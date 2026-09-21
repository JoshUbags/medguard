import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dose_schedule.dart';
import '../models/safety_report.dart';
import 'dose_service.dart';
import 'interaction_checker.dart';
import 'user_data_service.dart';

/// What kind of thing raised a notification. Drives the icon, the tint, and
/// the section the item is filed under.
enum NotificationKind {
  interaction,
  allergy,
  duplicate,
  dose,
  refill,
  conflict,
  setup,
  clear,
}

/// How urgently an item wants attention. Only [critical] and [attention] count
/// toward the badge — informational items never nag.
enum NotificationPriority { critical, attention, info }

/// A single notification, derived fresh from the user's own live data.
///
/// Every item carries a STABLE [id] built from what it is about (drug pair,
/// schedule + slot, …) rather than a timestamp, so "read" and "dismissed"
/// survive a rebuild of the feed: the same interaction flagged tomorrow is the
/// same notification, not a new one shouting again.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.priority,
    required this.title,
    required this.body,
    required this.when,
    this.actionLabel,
    this.actionRoute,
  });

  final String id;
  final NotificationKind kind;
  final NotificationPriority priority;
  final String title;
  final String body;

  /// When the item became relevant — used for ordering and the "Today /
  /// Earlier" grouping. Live checks stamp `now`.
  final DateTime when;

  /// Optional single action rendered on the card (e.g. "Review interactions").
  final String? actionLabel;
  final String? actionRoute;

  bool get demandsAttention => priority != NotificationPriority.info;
}

/// A notification paired with the local read/dismissed state the user has
/// applied to it.
@immutable
class NotificationEntry {
  const NotificationEntry({required this.notification, required this.read});

  final AppNotification notification;
  final bool read;

  bool get unread => !read;

  /// Badge-worthy: unread AND actually asking for something.
  bool get counts => unread && notification.demandsAttention;
}

/// Builds the notification feed from live app data and remembers what the user
/// has already read or dismissed.
///
/// Nothing here is canned. Items come from the same engines the rest of the app
/// uses — [InteractionChecker] for the safety report, [DoseService] for today's
/// doses, refills and timing conflicts — so the feed can never disagree with
/// the screens it points at. When there is genuinely nothing to say, the feed
/// is empty and the screen renders an honest all-caught-up state.
class NotificationCenter {
  NotificationCenter._();

  static final NotificationCenter instance = NotificationCenter._();

  static const String _readKey = 'medguard.notifications.read';
  static const String _dismissedKey = 'medguard.notifications.dismissed';

  /// Unread, attention-worthy count — what the home bell's badge shows.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Bumps whenever the feed or its read state changes.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Set<String> _read = <String>{};
  Set<String> _dismissed = <String>{};
  bool _loaded = false;

  List<NotificationEntry> _entries = const [];
  List<NotificationEntry> get entries => _entries;

  String _userId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'local-device';
    } catch (_) {
      return 'local-device';
    }
  }

  Future<void> _loadState() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _read = (prefs.getStringList(_readKey) ?? const []).toSet();
      _dismissed = (prefs.getStringList(_dismissedKey) ?? const []).toSet();
    } catch (_) {
      // A prefs failure must never block the feed — it just means read state
      // starts empty for this run.
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readKey, _read.toList(growable: false));
      await prefs.setStringList(
        _dismissedKey,
        _dismissed.toList(growable: false),
      );
    } catch (_) {}
  }

  /// The in-flight rebuild, if any.
  ///
  /// The home screen listens to three separate revisions (medications,
  /// allergies, doses) and a single user action can bump more than one of
  /// them, so without this a "save" would kick off several full rebuilds at
  /// once — each re-running the interaction analysis. Callers that arrive
  /// while a rebuild is running simply await the one already in progress.
  Future<List<NotificationEntry>>? _inFlight;

  /// Rebuilds the feed from live data. Safe to call on every screen mount —
  /// the underlying services cache their own work, and concurrent calls share
  /// a single rebuild.
  Future<List<NotificationEntry>> refresh({DateTime? now}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _refresh(now: now);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<List<NotificationEntry>> _refresh({DateTime? now}) async {
    await _loadState();
    final at = now ?? DateTime.now();
    final userId = _userId();

    final items = <AppNotification>[];
    List<DoseSchedule> schedules = const [];
    SafetyReport? report;
    var medicationCount = 0;

    try {
      final medications = await UserDataService.instance.getUserMedications(
        userId,
      );
      medicationCount = medications.length;
      if (medications.length >= 2) {
        report = await InteractionChecker.analyze(
          medications.map((m) => m.drugId).toList(growable: false),
        );
      }
    } catch (_) {
      // Fresh install with no store yet — the rest of the feed still builds.
    }

    try {
      schedules = await DoseService.instance.getSchedules(userId);
    } catch (_) {}

    if (report != null) {
      items.addAll(_safetyItems(report, at));
    } else if (medicationCount < 2) {
      items.add(
        AppNotification(
          id: 'setup.pair-checks',
          kind: NotificationKind.setup,
          priority: NotificationPriority.info,
          title: 'Pair checks are not running yet',
          body:
              'Save at least two medicines and MedGuard screens every pair '
              'automatically, every time your regimen changes.',
          when: at,
          actionLabel: 'Add a medicine',
          actionRoute: '/add',
        ),
      );
    }

    items.addAll(_doseItems(schedules, at));
    items.addAll(_refillItems(schedules, at));
    items.addAll(_conflictItems(schedules, report, at));

    // Newest and most urgent first: priority is the primary key so a critical
    // interaction never sits below an informational note.
    items.sort((a, b) {
      final byPriority = a.priority.index.compareTo(b.priority.index);
      if (byPriority != 0) return byPriority;
      return b.when.compareTo(a.when);
    });

    final live = items
        .where((item) => !_dismissed.contains(item.id))
        .map(
          (item) =>
              NotificationEntry(notification: item, read: _read.contains(item.id)),
        )
        .toList(growable: false);

    // Drop remembered state for items that no longer exist, so the two sets
    // can't grow without bound across the life of the install.
    final liveIds = items.map((item) => item.id).toSet();
    final prunedRead = _read.intersection(liveIds);
    final prunedDismissed = _dismissed.intersection(liveIds);
    final changed =
        prunedRead.length != _read.length ||
        prunedDismissed.length != _dismissed.length;
    _read = prunedRead;
    _dismissed = prunedDismissed;
    if (changed) unawaited(_persist());

    _entries = live;
    _publish();
    return live;
  }

  void _publish() {
    unreadCount.value = _entries.where((entry) => entry.counts).length;
    revision.value = revision.value + 1;
  }

  /// Refreshes only the badge — cheap enough to call when a screen appears.
  Future<int> refreshBadge() async {
    await refresh();
    return unreadCount.value;
  }

  Future<void> markRead(String id) async {
    await _loadState();
    if (!_read.add(id)) return;
    _entries = _entries
        .map(
          (entry) => entry.notification.id == id
              ? NotificationEntry(notification: entry.notification, read: true)
              : entry,
        )
        .toList(growable: false);
    _publish();
    await _persist();
  }

  Future<void> markAllRead() async {
    await _loadState();
    _read.addAll(_entries.map((entry) => entry.notification.id));
    _entries = _entries
        .map(
          (entry) =>
              NotificationEntry(notification: entry.notification, read: true),
        )
        .toList(growable: false);
    _publish();
    await _persist();
  }

  Future<void> dismiss(String id) async {
    await _loadState();
    _dismissed.add(id);
    _entries = _entries
        .where((entry) => entry.notification.id != id)
        .toList(growable: false);
    _publish();
    await _persist();
  }

  /// Restores a dismissed item — the undo behind swipe-to-dismiss.
  Future<void> restore(String id) async {
    await _loadState();
    if (!_dismissed.remove(id)) return;
    await _persist();
    await refresh();
  }

  Future<void> clearAll() async {
    await _loadState();
    _dismissed.addAll(_entries.map((entry) => entry.notification.id));
    _entries = const [];
    _publish();
    await _persist();
  }

  // ── Feed builders ──────────────────────────────────────────────────────────

  List<AppNotification> _safetyItems(SafetyReport report, DateTime at) {
    final items = <AppNotification>[];

    for (final hit in report.allergyHits) {
      items.add(
        AppNotification(
          id: 'allergy.${hit.drugId}',
          kind: NotificationKind.allergy,
          priority: NotificationPriority.critical,
          title: 'Allergy conflict — ${hit.drugName}',
          body:
              '${hit.drugName} conflicts with a recorded allergy. Do not take '
              'it before speaking to a clinician or pharmacist.',
          when: at,
          actionLabel: 'Review allergies',
          actionRoute: '/allergies',
        ),
      );
    }

    final flagged = report.drugInteractions;
    if (flagged.isNotEmpty) {
      final first = flagged.first;
      final severe = report.hasHighRiskInteraction;
      items.add(
        AppNotification(
          id: 'interaction.count.${flagged.length}',
          kind: NotificationKind.interaction,
          priority: severe
              ? NotificationPriority.critical
              : NotificationPriority.attention,
          title: flagged.length == 1
              ? 'Interaction flagged'
              : '${flagged.length} interactions flagged',
          body:
              '${first.drugAName} + ${first.drugBName}'
              '${flagged.length > 1 ? ' and ${flagged.length - 1} more' : ''} — '
              'review before your next dose.',
          when: at,
          actionLabel: 'Review interactions',
          actionRoute: '/medications',
        ),
      );
    }

    final duplicates = report.duplicateTherapies.length;
    if (duplicates > 0) {
      items.add(
        AppNotification(
          id: 'duplicate.count.$duplicates',
          kind: NotificationKind.duplicate,
          priority: NotificationPriority.attention,
          title: duplicates == 1
              ? 'Possible duplicate therapy'
              : '$duplicates possible duplicate therapies',
          body:
              'Two of your saved medicines may repeat the same therapeutic '
              'effect. Ask a pharmacist whether both should stay.',
          when: at,
          actionLabel: 'Review interactions',
          actionRoute: '/medications',
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        AppNotification(
          id: 'clear.pair-check',
          kind: NotificationKind.clear,
          priority: NotificationPriority.info,
          title: 'Pair check clear',
          body: 'No flagged pairs across your saved medicines.',
          when: at,
        ),
      );
    }
    return items;
  }

  List<AppNotification> _doseItems(List<DoseSchedule> schedules, DateTime at) {
    if (schedules.isEmpty) return const [];
    final today = DateTime(at.year, at.month, at.day);
    final nowSlot =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';

    final upcoming = <({String slot, String name, int id})>[];
    final overdue = <({String slot, String name, int id})>[];
    for (final schedule in schedules) {
      for (final slot in schedule.slotsOn(today)) {
        final entry = (
          slot: slot,
          name: '${schedule.drugName} ${schedule.doseLabel ?? ''}'.trim(),
          id: schedule.id,
        );
        if (slot.compareTo(nowSlot) >= 0) {
          upcoming.add(entry);
        } else {
          overdue.add(entry);
        }
      }
    }

    final items = <AppNotification>[];
    if (overdue.isNotEmpty) {
      overdue.sort((a, b) => a.slot.compareTo(b.slot));
      final oldest = overdue.first;
      items.add(
        AppNotification(
          id: 'dose.overdue.${_dateKey(today)}',
          kind: NotificationKind.dose,
          priority: NotificationPriority.attention,
          title: overdue.length == 1
              ? 'A dose is waiting to be logged'
              : '${overdue.length} doses waiting to be logged',
          body:
              '${oldest.name} was due at ${formatSlot(oldest.slot)}. Mark it '
              'taken or skipped to keep your adherence accurate.',
          when: today,
          actionLabel: 'Open dose schedule',
          actionRoute: '/dose',
        ),
      );
    }
    if (upcoming.isNotEmpty) {
      upcoming.sort((a, b) => a.slot.compareTo(b.slot));
      final next = upcoming.first;
      items.add(
        AppNotification(
          id: 'dose.next.${_dateKey(today)}.${next.slot}',
          kind: NotificationKind.dose,
          priority: NotificationPriority.info,
          title: 'Next dose at ${formatSlot(next.slot)}',
          body: upcoming.length == 1
              ? '${next.name} is the last scheduled dose today.'
              : '${next.name} is up next — ${upcoming.length} doses left today.',
          when: today,
          actionLabel: 'Open dose schedule',
          actionRoute: '/dose',
        ),
      );
    }
    return items;
  }

  List<AppNotification> _refillItems(
    List<DoseSchedule> schedules,
    DateTime at,
  ) {
    final items = <AppNotification>[];
    for (final schedule in schedules) {
      final days = DoseService.daysUntilRefill(schedule, asOf: at);
      if (days == null || days > 7) continue;
      final overdue = days < 0;
      items.add(
        AppNotification(
          id: 'refill.${schedule.id}',
          kind: NotificationKind.refill,
          priority: overdue || days <= 2
              ? NotificationPriority.attention
              : NotificationPriority.info,
          title: overdue
              ? 'Refill overdue — ${schedule.drugName}'
              : days == 0
              ? 'Refill ${schedule.drugName} today'
              : 'Refill ${schedule.drugName} in $days day${days == 1 ? '' : 's'}',
          body: overdue
              ? 'Your estimated supply ran out ${-days} day'
                    '${days == -1 ? '' : 's'} ago.'
              : 'At ${schedule.dosesPerDay} dose'
                    '${schedule.dosesPerDay == 1 ? '' : 's'} a day, your '
                    'supply is running low.',
          when: at,
          actionLabel: 'Open dose schedule',
          actionRoute: '/dose',
        ),
      );
    }
    return items;
  }

  List<AppNotification> _conflictItems(
    List<DoseSchedule> schedules,
    SafetyReport? report,
    DateTime at,
  ) {
    if (report == null || schedules.length < 2) return const [];
    final interacting = <String>{
      for (final i in report.drugInteractions) _pairKey(i.drugAId, i.drugBId),
    };
    if (interacting.isEmpty) return const [];

    final suggestions = DoseService.detectConflicts(
      schedules: schedules,
      interacts: (a, b) => interacting.contains(_pairKey(a, b)),
    );
    return [
      for (final s in suggestions)
        AppNotification(
          id: 'conflict.${s.first.id}.${s.second.id}.${s.sharedSlot}',
          kind: NotificationKind.conflict,
          priority: NotificationPriority.attention,
          title: 'Two interacting medicines share a time',
          body: s.message,
          when: at,
          actionLabel: 'Open dose schedule',
          actionRoute: '/dose',
        ),
    ];
  }

  static String _pairKey(int a, int b) => a < b ? '$a:$b' : '$b:$a';

  static String _dateKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// `'08:00'` → `'8:00 AM'`. Shared with the dose screen so a slot reads the
  /// same wherever it appears.
  static String formatSlot(String slot) {
    final parts = slot.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final period = hour < 12 ? 'AM' : 'PM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Only used by tests to start from a known state.
  @visibleForTesting
  Future<void> resetForTest() async {
    _read = <String>{};
    _dismissed = <String>{};
    _entries = const [];
    _loaded = true;
    unreadCount.value = 0;
    revision.value = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_readKey);
      await prefs.remove(_dismissedKey);
    } catch (_) {}
  }
}
