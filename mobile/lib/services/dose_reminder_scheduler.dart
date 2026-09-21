import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/dose_schedule.dart';
import 'notification_preferences.dart';

/// One concrete reminder to fire for a dose: the primary "dose due" alert at
/// the scheduled time, or the single follow-up nudge 30 minutes later.
class DoseReminder {
  const DoseReminder({
    required this.scheduleId,
    required this.scheduledTime,
    required this.fireTime,
    required this.isFollowUp,
    required this.title,
    required this.body,
  });

  final int scheduleId;
  final DateTime scheduledTime;
  final DateTime fireTime;
  final bool isFollowUp;
  final String title;
  final String body;

  /// Stable cancellation key: schedule + occurrence + which alert.
  String get payload =>
      '$scheduleId|${scheduledTime.toIso8601String()}|${isFollowUp ? 1 : 0}';

  /// Deterministic 31-bit notification id derived from [payload].
  int get notificationId => payload.hashCode & 0x7fffffff;
}

/// Plans the reminders for a schedule over a rolling horizon. Pure and
/// dependency-free so it can be unit-tested without the notification plugin.
///
/// Each due, future occurrence yields a primary alert at the dose time plus a
/// single follow-up [followUpDelay] later (cancelled once the dose is logged).
List<DoseReminder> planDoseReminders(
  DoseSchedule schedule, {
  required DateTime now,
  int horizonDays = 14,
  Duration followUpDelay = const Duration(minutes: 30),
}) {
  if (!schedule.frequency.isScheduled) return const [];
  final reminders = <DoseReminder>[];
  final startDay = DateTime(now.year, now.month, now.day);
  for (var offset = 0; offset <= horizonDays; offset++) {
    final day = startDay.add(Duration(days: offset));
    for (final slot in schedule.slotsOn(day)) {
      final time = _slotDateTime(day, slot);
      if (!time.isAfter(now)) continue;
      reminders.add(
        DoseReminder(
          scheduleId: schedule.id,
          scheduledTime: time,
          fireTime: time,
          isFollowUp: false,
          title: 'Dose due — ${schedule.drugName}',
          body: '${schedule.doseDescriptor} scheduled for $slot.',
        ),
      );
      reminders.add(
        DoseReminder(
          scheduleId: schedule.id,
          scheduledTime: time,
          fireTime: time.add(followUpDelay),
          isFollowUp: true,
          title: 'Reminder — ${schedule.drugName}',
          body: 'Have you taken your ${schedule.doseDescriptor} dose yet?',
        ),
      );
    }
  }
  return reminders;
}

/// Schedules and cancels offline dose reminders. Implementations must tolerate
/// being called on platforms without notification support (no-op, never throw).
abstract class DoseReminderScheduler {
  Future<void> initialize();

  /// Requests OS notification permission (Android 13+/iOS). Returns false when
  /// unavailable or denied.
  Future<bool> requestPermission();

  /// Re-plans all reminders for a single schedule (cancels its old ones first).
  Future<void> syncSchedule(DoseSchedule schedule);

  /// Re-plans reminders for every schedule — call on app start.
  Future<void> syncAll(List<DoseSchedule> schedules);

  /// Cancels every reminder belonging to a schedule (e.g. when it is deleted).
  Future<void> cancelForSchedule(int scheduleId);

  /// Cancels the alert + follow-up for one occurrence — call when a dose is
  /// marked taken or skipped so the follow-up nudge does not fire.
  Future<void> cancelOccurrence({
    required int scheduleId,
    required DateTime scheduledTime,
  });

  /// Schedules the opt-in adherence summary at the chosen cadence, or cancels
  /// it for [SummaryInterval.off]. Always fires at 20:00 local time.
  Future<void> setSummaryInterval(SummaryInterval interval);

  /// Active scheduler. Defaults to the real plugin on mobile and a no-op
  /// elsewhere (desktop, web, tests). Override in tests with a fake.
  static DoseReminderScheduler instance = _defaultScheduler();

  static DoseReminderScheduler _defaultScheduler() {
    if (kIsWeb) return const NoopDoseReminderScheduler();
    final platform = defaultTargetPlatform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return mobile
        ? LocalDoseReminderScheduler()
        : const NoopDoseReminderScheduler();
  }
}

/// Does nothing — used in tests, on desktop/web, and as a safe fallback.
class NoopDoseReminderScheduler implements DoseReminderScheduler {
  const NoopDoseReminderScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> syncSchedule(DoseSchedule schedule) async {}

  @override
  Future<void> syncAll(List<DoseSchedule> schedules) async {}

  @override
  Future<void> cancelForSchedule(int scheduleId) async {}

  @override
  Future<void> cancelOccurrence({
    required int scheduleId,
    required DateTime scheduledTime,
  }) async {}

  @override
  Future<void> setSummaryInterval(SummaryInterval interval) async {}
}

/// Real implementation backed by `flutter_local_notifications`. Every plugin
/// call is guarded so a missing platform channel (e.g. in a widget test that
/// reports as Android) degrades to a no-op rather than throwing.
class LocalDoseReminderScheduler implements DoseReminderScheduler {
  LocalDoseReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const _channelId = 'dose_reminders';
  static const _channelName = 'Dose reminders';
  static const _channelDescription =
      'Reminders to take your medication on time.';
  static const _horizonDays = 14;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));
    } catch (_) {
      // Timezone lookup unavailable — fall back to whatever tz.local resolves
      // to. Scheduling is still attempted below.
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
      );
      _initialized = true;
    } catch (_) {
      // No platform channel (tests/unsupported) — leave uninitialised so the
      // guarded calls below short-circuit.
    }
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (!_initialized) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {
      // Permission flow unavailable.
    }
    return false;
  }

  @override
  Future<void> syncSchedule(DoseSchedule schedule) async {
    await initialize();
    if (!_initialized) return;
    await cancelForSchedule(schedule.id);
    final reminders = planDoseReminders(
      schedule,
      now: DateTime.now(),
      horizonDays: _horizonDays,
    );
    for (final reminder in reminders) {
      await _schedule(reminder);
    }
  }

  @override
  Future<void> syncAll(List<DoseSchedule> schedules) async {
    for (final schedule in schedules) {
      await syncSchedule(schedule);
    }
  }

  @override
  Future<void> cancelForSchedule(int scheduleId) async {
    await initialize();
    if (!_initialized) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload?.startsWith('$scheduleId|') ?? false) {
          await _plugin.cancel(id: request.id);
        }
      }
    } catch (_) {
      // Cancellation unavailable.
    }
  }

  @override
  Future<void> cancelOccurrence({
    required int scheduleId,
    required DateTime scheduledTime,
  }) async {
    await initialize();
    if (!_initialized) return;
    final iso = scheduledTime.toIso8601String();
    try {
      for (final isFollowUp in [false, true]) {
        final id = '$scheduleId|$iso|${isFollowUp ? 1 : 0}'.hashCode &
            0x7fffffff;
        await _plugin.cancel(id: id);
      }
    } catch (_) {
      // Cancellation unavailable.
    }
  }

  static const int _summaryId = 0x55EEAA; // stable, unlikely to collide

  /// The hour the summary lands. Evening on purpose: a recap of the day's doses
  /// is meaningless at 9am, when none of them have happened yet.
  static const int _summaryHour = 20;

  @override
  Future<void> setSummaryInterval(SummaryInterval interval) async {
    await initialize();
    if (!_initialized) return;
    try {
      // Always cancel first: changing cadence must not leave the previous
      // schedule running alongside the new one.
      await _plugin.cancel(id: _summaryId);
      if (!interval.isOn) return;

      final now = tz.TZDateTime.now(tz.local);
      final (next, repeat) = _summarySchedule(interval, now);

      await _plugin.zonedSchedule(
        id: _summaryId,
        title: _summaryTitle(interval),
        body: _summaryBody(interval),
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'medguard_summary',
            'Adherence summary',
            channelDescription:
                'A recap of doses taken and any safety updates.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repeat,
        payload: 'summary',
      );
    } catch (_) {
      // Plugin unavailable — silently skip.
    }
  }

  /// The first firing time and the recurrence rule for [interval].
  ///
  /// The plugin repeats by matching date components, so the recurrence is
  /// expressed by WHICH components are held fixed: the time alone repeats
  /// daily, time-plus-weekday repeats weekly, and so on.
  static (tz.TZDateTime, DateTimeComponents) _summarySchedule(
    SummaryInterval interval,
    tz.TZDateTime now,
  ) {
    final todayAtHour = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _summaryHour,
    );

    switch (interval) {
      case SummaryInterval.daily:
        final next = todayAtHour.isAfter(now)
            ? todayAtHour
            : todayAtHour.add(const Duration(days: 1));
        return (next, DateTimeComponents.time);

      case SummaryInterval.weekly:
        // The coming Sunday, or the one after if this Sunday's slot has passed.
        var next = todayAtHour.add(
          Duration(days: (DateTime.sunday - todayAtHour.weekday) % 7),
        );
        if (!next.isAfter(now)) next = next.add(const Duration(days: 7));
        return (next, DateTimeComponents.dayOfWeekAndTime);

      case SummaryInterval.monthly:
        // The 1st of the month. Rolls the year over correctly in December
        // because DateTime normalises month 13 to January of the next year.
        var next = tz.TZDateTime(tz.local, now.year, now.month, 1, _summaryHour);
        if (!next.isAfter(now)) {
          next = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, _summaryHour);
        }
        return (next, DateTimeComponents.dayOfMonthAndTime);

      case SummaryInterval.yearly:
        var next = tz.TZDateTime(tz.local, now.year, 1, 1, _summaryHour);
        if (!next.isAfter(now)) {
          next = tz.TZDateTime(tz.local, now.year + 1, 1, 1, _summaryHour);
        }
        return (next, DateTimeComponents.dateAndTime);

      case SummaryInterval.off:
        // Unreachable — guarded by `interval.isOn` above.
        return (todayAtHour, DateTimeComponents.time);
    }
  }

  static String _summaryTitle(SummaryInterval interval) {
    return switch (interval) {
      SummaryInterval.daily => 'Today in MedGuard',
      SummaryInterval.weekly => 'This week in MedGuard',
      SummaryInterval.monthly => 'This month in MedGuard',
      SummaryInterval.yearly => 'Your year in MedGuard',
      SummaryInterval.off => 'MedGuard',
    };
  }

  static String _summaryBody(SummaryInterval interval) {
    final window = switch (interval) {
      SummaryInterval.daily => 'today',
      SummaryInterval.weekly => 'the past 7 days',
      SummaryInterval.monthly => 'the past month',
      SummaryInterval.yearly => 'the past year',
      SummaryInterval.off => 'recently',
    };
    return 'Review your adherence and any safety updates from $window.';
  }

  Future<void> _schedule(DoseReminder reminder) async {
    try {
      final when = tz.TZDateTime.from(reminder.fireTime, tz.local);
      await _plugin.zonedSchedule(
        id: reminder.notificationId,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.payload,
      );
    } catch (_) {
      // A single failed schedule should never break the batch.
    }
  }
}

DateTime _slotDateTime(DateTime day, String slot) {
  final parts = slot.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(day.year, day.month, day.day, hour, minute);
}
