import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/dose_log.dart';
import '../models/dose_schedule.dart';
import 'user_data_service.dart';

/// A concrete dose instance on a calendar day — a [DoseSchedule] expanded to a
/// single clock time, paired with its [DoseLog] if the user has acted on it.
class DoseOccurrence {
  const DoseOccurrence({
    required this.schedule,
    required this.scheduledTime,
    this.log,
  });

  final DoseSchedule schedule;
  final DateTime scheduledTime;
  final DoseLog? log;

  bool get isLogged => log != null;
  DoseLogStatus? get status => log?.status;

  DoseOccurrence copyWith({DoseLog? log}) => DoseOccurrence(
    schedule: schedule,
    scheduledTime: scheduledTime,
    log: log ?? this.log,
  );
}

/// Aggregate adherence over a window. [percent] is `(taken + late) / scheduled`
/// expressed as 0..1; [scheduled] only counts occurrences already due.
class AdherenceSummary {
  const AdherenceSummary({
    required this.scheduled,
    required this.taken,
    required this.late,
    required this.skipped,
    required this.missed,
  });

  final int scheduled;
  final int taken;
  final int late;
  final int skipped;
  final int missed;

  int get adhered => taken + late;
  double get percent => scheduled == 0 ? 0 : adhered / scheduled;
  int get percentRounded => (percent * 100).round();

  static const empty = AdherenceSummary(
    scheduled: 0,
    taken: 0,
    late: 0,
    skipped: 0,
    missed: 0,
  );
}

/// Compact dose snapshot for the home dashboard: the current streak, last-7-day
/// adherence, and a per-day flag (oldest → today) for the week tracker strip.
class DoseSummary {
  const DoseSummary({
    required this.streak,
    required this.dosesLogged,
    required this.dosesScheduled,
    required this.weeklyAdhered,
    this.trend = 0,
  });

  final int streak;
  final int dosesLogged;
  final int dosesScheduled;
  final List<bool> weeklyAdhered;

  /// 1 = improving vs last week, -1 = declining, 0 = flat / no prior data.
  final int trend;

  double get percent => dosesScheduled == 0 ? 0 : dosesLogged / dosesScheduled;
  int get percentRounded => (percent * 100).round();
  bool get hasData => dosesScheduled > 0 || streak > 0;
}

/// Per-drug adherence row used by the dose tracker breakdown.
typedef DrugAdherence = ({DoseSchedule schedule, AdherenceSummary summary});

/// One calendar day's dose outcome, used to paint the day/week/month calendar
/// without re-querying per cell.
class DoseDayStat {
  const DoseDayStat({
    required this.day,
    required this.due,
    required this.adhered,
    required this.missed,
    required this.skipped,
    required this.pending,
  });

  final DateTime day;

  /// Occurrences scheduled on this day, whether or not they are due yet.
  final int due;
  final int adhered;
  final int missed;
  final int skipped;

  /// Scheduled but not yet reached (today's later slots, and future days).
  final int pending;

  bool get hasDoses => due > 0;

  /// Settled = everything that was due has an outcome recorded.
  bool get complete => due > 0 && pending == 0 && missed == 0 && skipped == 0;

  double get percent {
    final settled = due - pending;
    return settled <= 0 ? 0 : adhered / settled;
  }
}

/// Adherence within a part of the day — the "you miss your evening dose" read.
class PartOfDayAdherence {
  const PartOfDayAdherence({
    required this.label,
    required this.fromHour,
    required this.toHour,
    required this.due,
    required this.adhered,
  });

  final String label;
  final int fromHour;
  final int toHour;
  final int due;
  final int adhered;

  double get percent => due == 0 ? 0 : adhered / due;
  int get percentRounded => (percent * 100).round();
}

/// Supply status for one schedule — what the refill card renders.
class RefillStatus {
  const RefillStatus({
    required this.schedule,
    required this.daysRemaining,
    required this.depletionDate,
  });

  final DoseSchedule schedule;

  /// Days until the effective refill date. Negative when already passed.
  final int daysRemaining;
  final DateTime? depletionDate;

  bool get overdue => daysRemaining < 0;
  bool get urgent => daysRemaining <= 2;
}

/// Everything the Dose screen renders, loaded in ONE pass.
///
/// The screen needs the schedule list, the selected day's occurrences, range
/// adherence, per-day stats for the calendar, per-drug and per-part-of-day
/// breakdowns, the streak, refills and timing conflicts. Fetching those
/// separately meant re-reading `dose_schedules` and `dose_logs` a dozen times
/// per rebuild; [DoseService.loadBoard] reads each table once and does the rest
/// in memory.
class DoseBoard {
  const DoseBoard({
    required this.schedules,
    required this.selectedDay,
    required this.dayOccurrences,
    required this.rangeSummary,
    required this.dayStats,
    required this.streak,
    required this.trend,
    required this.byDrug,
    required this.byPartOfDay,
    required this.refills,
    required this.conflicts,
  });

  final List<DoseSchedule> schedules;
  final DateTime selectedDay;
  final List<DoseOccurrence> dayOccurrences;
  final AdherenceSummary rangeSummary;

  /// Keyed `yyyy-MM-dd` so the calendar can look a cell up in O(1).
  final Map<String, DoseDayStat> dayStats;

  final int streak;

  /// 1 = improving vs the previous window, -1 = declining, 0 = flat.
  final int trend;

  final List<DrugAdherence> byDrug;
  final List<PartOfDayAdherence> byPartOfDay;
  final List<RefillStatus> refills;
  final List<DoseStaggerSuggestion> conflicts;

  bool get hasSchedules => schedules.isNotEmpty;

  /// A board with no data, for the moment before the first load resolves.
  factory DoseBoard.emptyFor(DateTime day) => DoseBoard(
    schedules: const [],
    selectedDay: DateTime(day.year, day.month, day.day),
    dayOccurrences: const [],
    rangeSummary: AdherenceSummary.empty,
    dayStats: const {},
    streak: 0,
    trend: 0,
    byDrug: const [],
    byPartOfDay: const [],
    refills: const [],
    conflicts: const [],
  );
}

/// A suggestion to stagger two interacting medicines that are scheduled at the
/// same clock time. Surfaced by [DoseService.detectConflicts].
class DoseStaggerSuggestion {
  const DoseStaggerSuggestion({
    required this.first,
    required this.second,
    required this.sharedSlot,
  });

  final DoseSchedule first;
  final DoseSchedule second;
  final String sharedSlot;

  String get message =>
      '${first.drugName} and ${second.drugName} are both scheduled at '
      '$sharedSlot and may interact. Consider taking ${first.drugName} about '
      '2 hours before ${second.drugName} to reduce absorption interference.';
}

/// Business logic for dose scheduling, logging and adherence. Persists into the
/// shared writable user database owned by [UserDataService]; the database
/// handle is injectable so tests can run against an in-memory store.
class DoseService {
  DoseService({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => UserDataService.instance.database);

  static final DoseService instance = DoseService();

  final Future<Database> Function() _databaseProvider;

  /// Bumps whenever schedules or logs change so dependent screens can refetch.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<Database> get _db => _databaseProvider();

  void _bump() => revision.value = revision.value + 1;

  // ── Schedule CRUD ──────────────────────────────────────────────────────────

  Future<int> addSchedule(DoseSchedule schedule) async {
    final db = await _db;
    final id = await db.insert('dose_schedules', schedule.toInsertMap());
    _bump();
    return id;
  }

  Future<int> updateSchedule(DoseSchedule schedule) async {
    final db = await _db;
    final count = await db.update(
      'dose_schedules',
      schedule.toInsertMap(),
      where: 'id = ?',
      whereArgs: [schedule.id],
    );
    if (count > 0) _bump();
    return count;
  }

  Future<int> removeSchedule(int id) async {
    final db = await _db;
    // dose_logs cascade via the foreign key (foreign_keys pragma is ON).
    final count = await db.delete(
      'dose_schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) _bump();
    return count;
  }

  Future<List<DoseSchedule>> getSchedules(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'dose_schedules',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(DoseSchedule.fromMap).toList(growable: false);
  }

  // ── Dose logging ───────────────────────────────────────────────────────────

  /// Records (or replaces) the outcome for one scheduled occurrence.
  Future<DoseLog> logDose({
    required int scheduleId,
    required DateTime scheduledTime,
    required DoseLogStatus status,
    DateTime? loggedAt,
  }) async {
    final db = await _db;
    final log = DoseLog(
      id: 0,
      scheduleId: scheduleId,
      scheduledTime: scheduledTime,
      status: status,
      loggedAt: loggedAt ?? DateTime.now(),
    );
    final id = await db.insert(
      'dose_logs',
      log.toInsertMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _bump();
    return DoseLog(
      id: id,
      scheduleId: scheduleId,
      scheduledTime: scheduledTime,
      status: status,
      loggedAt: log.loggedAt,
    );
  }

  /// Removes any logged outcome for an occurrence, returning it to "pending".
  Future<int> clearDoseLog({
    required int scheduleId,
    required DateTime scheduledTime,
  }) async {
    final db = await _db;
    final count = await db.delete(
      'dose_logs',
      where: 'schedule_id = ? AND scheduled_time = ?',
      whereArgs: [scheduleId, scheduledTime.toIso8601String()],
    );
    if (count > 0) _bump();
    return count;
  }

  // ── Occurrence expansion ─────────────────────────────────────────────────��─

  /// Expands every active schedule into the concrete doses due on [day],
  /// joined with any logged outcome, sorted by time of day.
  Future<List<DoseOccurrence>> occurrencesForDay(
    String userId,
    DateTime day,
  ) async {
    final schedules = await getSchedules(userId);
    final logs = await _logsByKey(schedules.map((s) => s.id).toList());
    final occurrences = <DoseOccurrence>[];
    for (final schedule in schedules) {
      for (final slot in schedule.slotsOn(day)) {
        final time = _slotDateTime(day, slot);
        occurrences.add(
          DoseOccurrence(
            schedule: schedule,
            scheduledTime: time,
            log: logs[_logKey(schedule.id, time)],
          ),
        );
      }
    }
    occurrences.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return occurrences;
  }

  // ── Adherence & streaks ──────────────────────────────────────────────────��─

  /// Adherence across the inclusive day range [from]..[to]. Only occurrences
  /// already due (scheduled at or before [asOf], default now) are counted, so
  /// doses still upcoming today never read as missed.
  Future<AdherenceSummary> adherence(
    String userId, {
    required DateTime from,
    required DateTime to,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final schedules = await getSchedules(userId);
    if (schedules.isEmpty) return AdherenceSummary.empty;
    final logs = await _logsByKey(schedules.map((s) => s.id).toList());

    var scheduled = 0, taken = 0, late = 0, skipped = 0, missed = 0;
    for (final occ in _expandRange(schedules, from, to, asOf: now)) {
      scheduled++;
      final status = logs[_logKey(occ.scheduleId, occ.time)]?.status;
      switch (status) {
        case DoseLogStatus.taken:
          taken++;
        case DoseLogStatus.late:
          late++;
        case DoseLogStatus.skipped:
          skipped++;
        case DoseLogStatus.missed:
          missed++;
        case null:
          missed++; // due but never logged
      }
    }
    return AdherenceSummary(
      scheduled: scheduled,
      taken: taken,
      late: late,
      skipped: skipped,
      missed: missed,
    );
  }

  /// Consecutive days, walking back from [asOf], on which every due dose was
  /// taken (or taken late). Days with no due dose are skipped; the first day
  /// with a missed/unlogged due dose ends the streak.
  Future<int> currentStreak(String userId, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final schedules = await getSchedules(userId);
    if (schedules.isEmpty) return 0;
    final logs = await _logsByKey(schedules.map((s) => s.id).toList());
    final earliest = schedules
        .map((s) => _dateOnly(s.startDate))
        .reduce((a, b) => a.isBefore(b) ? a : b);

    var streak = 0;
    var day = _dateOnly(now);
    var guard = 0;
    while (!day.isBefore(earliest) && guard < 800) {
      guard++;
      final due = _dueOccurrences(schedules, day, now);
      if (due.isNotEmpty) {
        final allTaken = due.every(
          (occ) =>
              logs[_logKey(occ.scheduleId, occ.time)]?.status.countsAsTaken ??
              false,
        );
        if (!allTaken) break;
        streak++;
      }
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Last-7-day snapshot for the home dashboard.
  Future<DoseSummary> weeklySummary(String userId, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 6));
    final overall = await adherence(userId, from: from, to: today, asOf: now);

    final schedules = await getSchedules(userId);
    final logs = await _logsByKey(schedules.map((s) => s.id).toList());
    final weekly = <bool>[];
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final due = _dueOccurrences(schedules, day, now);
      final adhered =
          due.isNotEmpty &&
          due.every(
            (occ) =>
                logs[_logKey(occ.scheduleId, occ.time)]?.status.countsAsTaken ??
                false,
          );
      weekly.add(adhered);
    }

    final streak = await currentStreak(userId, asOf: now);
    final trend = await weeklyTrend(userId, asOf: now);
    return DoseSummary(
      streak: streak,
      dosesLogged: overall.adhered,
      dosesScheduled: overall.scheduled,
      weeklyAdhered: weekly,
      trend: trend.trend,
    );
  }

  /// Per-drug adherence over [from]..[to], one row per scheduled medicine.
  Future<List<DrugAdherence>> adherenceByDrug(
    String userId, {
    required DateTime from,
    required DateTime to,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final schedules = await getSchedules(userId);
    final logs = await _logsByKey(schedules.map((s) => s.id).toList());
    final rows = <DrugAdherence>[];
    for (final schedule in schedules.where((s) => s.frequency.isScheduled)) {
      var scheduled = 0, taken = 0, late = 0, skipped = 0, missed = 0;
      for (final occ in _expandRange([schedule], from, to, asOf: now)) {
        scheduled++;
        switch (logs[_logKey(occ.scheduleId, occ.time)]?.status) {
          case DoseLogStatus.taken:
            taken++;
          case DoseLogStatus.late:
            late++;
          case DoseLogStatus.skipped:
            skipped++;
          case DoseLogStatus.missed:
            missed++;
          case null:
            missed++;
        }
      }
      rows.add((
        schedule: schedule,
        summary: AdherenceSummary(
          scheduled: scheduled,
          taken: taken,
          late: late,
          skipped: skipped,
          missed: missed,
        ),
      ));
    }
    return rows;
  }

  /// Compares this week's adherence to last week's. Returns a record with
  /// both percents and a directional indicator: 1 = improving, -1 = declining,
  /// 0 = flat (or no data).
  Future<({double thisWeek, double lastWeek, int trend})> weeklyTrend(
    String userId, {
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisFrom = today.subtract(const Duration(days: 6));
    final lastTo = thisFrom.subtract(const Duration(days: 1));
    final lastFrom = lastTo.subtract(const Duration(days: 6));

    final thisSummary = await adherence(
      userId,
      from: thisFrom,
      to: today,
      asOf: now,
    );
    final lastSummary = await adherence(
      userId,
      from: lastFrom,
      to: lastTo,
      asOf: now,
    );

    final tw = thisSummary.percent;
    final lw = lastSummary.percent;
    final direction = thisSummary.scheduled == 0 || lastSummary.scheduled == 0
        ? 0
        : tw > lw + 0.01
        ? 1
        : tw < lw - 0.01
        ? -1
        : 0;
    return (thisWeek: tw, lastWeek: lw, trend: direction);
  }

  /// Returns the milestone the user just reached at [streak] days, or null.
  /// Milestones: 7, 30, 90, 365. Only fires on exact match so the UI can
  /// celebrate once.
  static int? milestoneAt(int streak) {
    const milestones = [7, 30, 90, 365];
    return milestones.contains(streak) ? streak : null;
  }

  /// User-facing label for a milestone: "1 week", "1 month", "3 months", etc.
  static String milestoneLabel(int days) {
    return switch (days) {
      7 => '1 week',
      30 => '1 month',
      90 => '3 months',
      365 => '1 year',
      _ => '$days days',
    };
  }

  // ── The Dose screen's single-pass load ─────────────────────────────────────

  /// Loads everything the Dose screen renders in one pass over the two dose
  /// tables. [from]..[to] is the inclusive calendar window the stats and the
  /// calendar cover; [selectedDay] is the day whose timeline is shown.
  ///
  /// [interacts] lets the caller supply interaction knowledge (normally from
  /// [InteractionChecker]) so timing conflicts can be detected without this
  /// service depending on the interaction engine. Omit it to skip conflicts.
  Future<DoseBoard> loadBoard(
    String userId, {
    required DateTime from,
    required DateTime to,
    required DateTime selectedDay,
    DateTime? asOf,
    bool Function(int drugA, int drugB)? interacts,
  }) async {
    final now = asOf ?? DateTime.now();
    final day = _dateOnly(selectedDay);
    final schedules = await getSchedules(userId);

    if (schedules.isEmpty) {
      return DoseBoard.emptyFor(day);
    }

    final logs = await _logsByKey(schedules.map((s) => s.id).toList());

    // ── Per-day walk across the window. Every downstream figure — the range
    // summary, the calendar cells, the per-drug and per-part-of-day splits —
    // is accumulated in this single loop.
    final dayStats = <String, DoseDayStat>{};
    var scheduled = 0, taken = 0, late = 0, skipped = 0, missed = 0;
    final perDrug = <int, List<int>>{}; // drugId -> [scheduled, adhered, skipped, missed]
    final perPart = List<List<int>>.generate(4, (_) => [0, 0]); // [due, adhered]

    var cursor = _dateOnly(from);
    final last = _dateOnly(to);
    var guard = 0;
    while (!cursor.isAfter(last) && guard < 800) {
      guard++;
      var dueCount = 0, dayAdhered = 0, dayMissed = 0, daySkipped = 0;
      var dayPending = 0;

      for (final schedule in schedules) {
        for (final slot in schedule.slotsOn(cursor)) {
          final time = _slotDateTime(cursor, slot);
          dueCount++;
          final status = logs[_logKey(schedule.id, time)]?.status;
          final drugBucket = perDrug.putIfAbsent(
            schedule.id,
            () => [0, 0, 0, 0],
          );

          if (status == null && time.isAfter(now)) {
            dayPending++;
            continue; // not yet due — never counts as missed
          }

          scheduled++;
          drugBucket[0]++;
          final part = _partIndex(time.hour);
          perPart[part][0]++;

          switch (status) {
            case DoseLogStatus.taken:
              taken++;
              dayAdhered++;
              drugBucket[1]++;
              perPart[part][1]++;
            case DoseLogStatus.late:
              late++;
              dayAdhered++;
              drugBucket[1]++;
              perPart[part][1]++;
            case DoseLogStatus.skipped:
              skipped++;
              daySkipped++;
              drugBucket[2]++;
            case DoseLogStatus.missed:
            case null:
              missed++;
              dayMissed++;
              drugBucket[3]++;
          }
        }
      }

      if (dueCount > 0) {
        dayStats[_dateKeyOf(cursor)] = DoseDayStat(
          day: cursor,
          due: dueCount,
          adhered: dayAdhered,
          missed: dayMissed,
          skipped: daySkipped,
          pending: dayPending,
        );
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    final rangeSummary = AdherenceSummary(
      scheduled: scheduled,
      taken: taken,
      late: late,
      skipped: skipped,
      missed: missed,
    );

    // ── The selected day's timeline ─────────────────────────────────────────
    final dayOccurrences = <DoseOccurrence>[];
    for (final schedule in schedules) {
      for (final slot in schedule.slotsOn(day)) {
        final time = _slotDateTime(day, slot);
        dayOccurrences.add(
          DoseOccurrence(
            schedule: schedule,
            scheduledTime: time,
            log: logs[_logKey(schedule.id, time)],
          ),
        );
      }
    }
    dayOccurrences.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    // ── Breakdowns ──────────────────────────────────────────────────────────
    final byDrug = <DrugAdherence>[];
    for (final schedule in schedules.where((s) => s.frequency.isScheduled)) {
      final bucket = perDrug[schedule.id] ?? const [0, 0, 0, 0];
      byDrug.add((
        schedule: schedule,
        summary: AdherenceSummary(
          scheduled: bucket[0],
          taken: bucket[1],
          late: 0,
          skipped: bucket[2],
          missed: bucket[3],
        ),
      ));
    }
    byDrug.sort((a, b) => a.summary.percent.compareTo(b.summary.percent));

    final byPartOfDay = <PartOfDayAdherence>[
      for (var i = 0; i < _partLabels.length; i++)
        PartOfDayAdherence(
          label: _partLabels[i],
          fromHour: _partBounds[i].$1,
          toHour: _partBounds[i].$2,
          due: perPart[i][0],
          adhered: perPart[i][1],
        ),
    ];

    final refills = <RefillStatus>[];
    for (final schedule in schedules) {
      final days = daysUntilRefill(schedule, asOf: now);
      if (days == null) continue;
      refills.add(
        RefillStatus(
          schedule: schedule,
          daysRemaining: days,
          depletionDate: estimatedDepletionDate(schedule),
        ),
      );
    }
    refills.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    final conflicts = interacts == null
        ? const <DoseStaggerSuggestion>[]
        : detectConflicts(schedules: schedules, interacts: interacts);

    return DoseBoard(
      schedules: schedules,
      selectedDay: day,
      dayOccurrences: dayOccurrences,
      rangeSummary: rangeSummary,
      dayStats: dayStats,
      streak: _streakFrom(schedules, logs, now),
      trend: _trendFrom(schedules, logs, now),
      byDrug: byDrug,
      byPartOfDay: byPartOfDay,
      refills: refills,
      conflicts: conflicts,
    );
  }

  /// Records the same outcome for every occurrence on [day] that has none yet.
  /// Returns how many rows were written.
  Future<int> logRemainingForDay({
    required String userId,
    required DateTime day,
    required DoseLogStatus status,
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final occurrences = await occurrencesForDay(userId, day);
    var written = 0;
    for (final occ in occurrences) {
      if (occ.isLogged) continue;
      if (occ.scheduledTime.isAfter(now)) continue; // don't pre-log the future
      await logDose(
        scheduleId: occ.schedule.id,
        scheduledTime: occ.scheduledTime,
        status: status,
        loggedAt: now,
      );
      written++;
    }
    return written;
  }

  static const List<String> _partLabels = [
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
  ];
  static const List<(int, int)> _partBounds = [(5, 12), (12, 17), (17, 21), (21, 5)];

  /// 0 = morning (05–12), 1 = afternoon (12–17), 2 = evening (17–21),
  /// 3 = night (21–05).
  static int _partIndex(int hour) {
    if (hour >= 5 && hour < 12) return 0;
    if (hour >= 12 && hour < 17) return 1;
    if (hour >= 17 && hour < 21) return 2;
    return 3;
  }

  /// The part-of-day label for a `HH:mm` slot — shared with the UI so a slot is
  /// filed under the same heading everywhere.
  static String partOfDayLabel(int hour) => _partLabels[_partIndex(hour)];

  /// `'08:00'` → `'8:00 AM'`, for showing a stored 24h slot to the user.
  static String formatSlotForDisplay(String slot) {
    final parts = slot.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final period = hour < 12 ? 'AM' : 'PM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  int _streakFrom(
    List<DoseSchedule> schedules,
    Map<String, DoseLog> logs,
    DateTime now,
  ) {
    if (schedules.isEmpty) return 0;
    final earliest = schedules
        .map((s) => _dateOnly(s.startDate))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    var streak = 0;
    var day = _dateOnly(now);
    var guard = 0;
    while (!day.isBefore(earliest) && guard < 800) {
      guard++;
      final due = _dueOccurrences(schedules, day, now);
      if (due.isNotEmpty) {
        final allTaken = due.every(
          (occ) =>
              logs[_logKey(occ.scheduleId, occ.time)]?.status.countsAsTaken ??
              false,
        );
        if (!allTaken) break;
        streak++;
      }
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int _trendFrom(
    List<DoseSchedule> schedules,
    Map<String, DoseLog> logs,
    DateTime now,
  ) {
    double windowPercent(DateTime from, DateTime to) {
      var due = 0, adhered = 0;
      for (final occ in _expandRange(schedules, from, to, asOf: now)) {
        due++;
        if (logs[_logKey(occ.scheduleId, occ.time)]?.status.countsAsTaken ??
            false) {
          adhered++;
        }
      }
      return due == 0 ? -1 : adhered / due;
    }

    final today = _dateOnly(now);
    final thisFrom = today.subtract(const Duration(days: 6));
    final lastTo = thisFrom.subtract(const Duration(days: 1));
    final lastFrom = lastTo.subtract(const Duration(days: 6));

    final tw = windowPercent(thisFrom, today);
    final lw = windowPercent(lastFrom, lastTo);
    if (tw < 0 || lw < 0) return 0;
    if (tw > lw + 0.01) return 1;
    if (tw < lw - 0.01) return -1;
    return 0;
  }

  static String _dateKeyOf(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// The `yyyy-MM-dd` key the calendar looks [DoseBoard.dayStats] up by.
  static String dayKey(DateTime day) => _dateKeyOf(day);

  // ── Conflict detection & refills (pure helpers) ─────────────────────────────

  /// Finds interacting medicines scheduled at the same clock time. [interacts]
  /// reports whether two drug ids have a known interaction (typically backed by
  /// [InteractionChecker] results).
  static List<DoseStaggerSuggestion> detectConflicts({
    required List<DoseSchedule> schedules,
    required bool Function(int drugA, int drugB) interacts,
  }) {
    final scheduled = schedules
        .where((s) => s.frequency.isScheduled && s.timeSlots.isNotEmpty)
        .toList();
    final suggestions = <DoseStaggerSuggestion>[];
    for (var i = 0; i < scheduled.length; i++) {
      for (var j = i + 1; j < scheduled.length; j++) {
        final a = scheduled[i];
        final b = scheduled[j];
        if (a.drugId == b.drugId) continue;
        if (!interacts(a.drugId, b.drugId)) continue;
        final shared = a.timeSlots.toSet().intersection(b.timeSlots.toSet());
        if (shared.isEmpty) continue;
        final sortedSlots = shared.toList()..sort();
        suggestions.add(
          DoseStaggerSuggestion(first: a, second: b, sharedSlot: sortedSlots.first),
        );
      }
    }
    return suggestions;
  }

  /// Estimated date the supply runs out: [DoseSchedule.startDate] plus the
  /// number of whole days the dispensed [DoseSchedule.quantity] lasts at the
  /// schedule's daily rate. Null when no quantity was recorded.
  static DateTime? estimatedDepletionDate(DoseSchedule schedule) {
    final quantity = schedule.quantity;
    if (quantity == null || quantity <= 0) return null;
    if (!schedule.frequency.isScheduled) return null;
    final days = (quantity / schedule.dosesPerDay).floor();
    final start = _dateOnly(schedule.startDate);
    return start.add(Duration(days: days));
  }

  /// The date a refill should be surfaced: an explicit [DoseSchedule.refillDate]
  /// if set, otherwise 7 days before estimated supply depletion.
  static DateTime? effectiveRefillDate(DoseSchedule schedule) {
    if (schedule.refillDate != null) return schedule.refillDate;
    final depletion = estimatedDepletionDate(schedule);
    if (depletion == null) return null;
    return depletion.subtract(const Duration(days: 7));
  }

  /// Days from [asOf] until the schedule's effective refill date, or null when
  /// neither a refill date nor a quantity estimate is available. Negative when
  /// the date has already passed.
  static int? daysUntilRefill(DoseSchedule schedule, {DateTime? asOf}) {
    final refill = effectiveRefillDate(schedule);
    if (refill == null) return null;
    final from = _dateOnly(asOf ?? DateTime.now());
    return _dateOnly(refill).difference(from).inDays;
  }

  /// Whether a refill falls within [withinDays] (and is not already overdue
  /// further back than that window flags either way).
  static bool isRefillDueSoon(
    DoseSchedule schedule, {
    DateTime? asOf,
    int withinDays = 7,
  }) {
    final days = daysUntilRefill(schedule, asOf: asOf);
    if (days == null) return false;
    return days <= withinDays;
  }

  // ── Internals ───────────────────────────────────────────────────────────��──

  Future<Map<String, DoseLog>> _logsByKey(List<int> scheduleIds) async {
    if (scheduleIds.isEmpty) return const {};
    final db = await _db;
    final placeholders = List.filled(scheduleIds.length, '?').join(',');
    final rows = await db.query(
      'dose_logs',
      where: 'schedule_id IN ($placeholders)',
      whereArgs: scheduleIds,
    );
    final map = <String, DoseLog>{};
    for (final row in rows) {
      final log = DoseLog.fromMap(row);
      map[_logKey(log.scheduleId, log.scheduledTime)] = log;
    }
    return map;
  }

  /// Lightweight occurrence reference used by the in-memory range/streak math.
  Iterable<({int scheduleId, DateTime time})> _expandRange(
    List<DoseSchedule> schedules,
    DateTime from,
    DateTime to, {
    required DateTime asOf,
  }) sync* {
    var day = _dateOnly(from);
    final last = _dateOnly(to);
    var guard = 0;
    while (!day.isAfter(last) && guard < 800) {
      guard++;
      yield* _dueOccurrences(schedules, day, asOf);
      day = day.add(const Duration(days: 1));
    }
  }

  List<({int scheduleId, DateTime time})> _dueOccurrences(
    List<DoseSchedule> schedules,
    DateTime day,
    DateTime asOf,
  ) {
    final result = <({int scheduleId, DateTime time})>[];
    for (final schedule in schedules) {
      for (final slot in schedule.slotsOn(day)) {
        final time = _slotDateTime(day, slot);
        if (time.isAfter(asOf)) continue; // not yet due
        result.add((scheduleId: schedule.id, time: time));
      }
    }
    return result;
  }

  static String _logKey(int scheduleId, DateTime time) =>
      '$scheduleId@${time.toIso8601String()}';

  static DateTime _slotDateTime(DateTime day, String slot) {
    final parts = slot.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
