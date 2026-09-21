import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/dose_log.dart';
import 'package:mobile/models/dose_schedule.dart';
import 'package:mobile/services/dose_service.dart';
import 'package:mobile/services/user_data_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const userId = 'local-device';
  final createdAt = DateTime(2026, 5, 1, 9);

  late Database db;
  late DoseService service;

  DoseSchedule schedule({
    int id = 0,
    int drugId = 1,
    String drugName = 'Metformin',
    double amount = 500,
    String unit = 'mg',
    DoseFrequency frequency = DoseFrequency.onceDaily,
    List<String> timeSlots = const ['08:00'],
    DateTime? startDate,
    DateTime? endDate,
    DateTime? refillDate,
    double? quantity,
  }) {
    return DoseSchedule(
      id: id,
      userId: userId,
      drugId: drugId,
      drugName: drugName,
      amount: amount,
      unit: unit,
      frequency: frequency,
      timeSlots: timeSlots,
      startDate: startDate ?? DateTime(2026, 5, 1),
      endDate: endDate,
      refillDate: refillDate,
      quantity: quantity,
      createdAt: createdAt,
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => UserDataService.createDoseSchema(db),
      ),
    );
    service = DoseService(databaseProvider: () async => db);
  });

  tearDown(() => db.close());

  test('adds and reads back a schedule with all fields intact', () async {
    final id = await service.addSchedule(
      schedule(
        frequency: DoseFrequency.twiceDaily,
        timeSlots: const ['08:00', '20:00'],
        refillDate: DateTime(2026, 5, 20),
        endDate: DateTime(2026, 6, 1),
      ),
    );
    expect(id, greaterThan(0));

    final schedules = await service.getSchedules(userId);
    expect(schedules, hasLength(1));
    final saved = schedules.single;
    expect(saved.drugName, 'Metformin');
    expect(saved.amount, 500);
    expect(saved.unit, 'mg');
    expect(saved.frequency, DoseFrequency.twiceDaily);
    expect(saved.timeSlots, ['08:00', '20:00']);
    expect(saved.startDate, DateTime(2026, 5, 1));
    expect(saved.endDate, DateTime(2026, 6, 1));
    expect(saved.refillDate, DateTime(2026, 5, 20));
    expect(saved.doseLabel, '500 mg');
  });

  test('occurrencesForDay expands active scheduled slots only', () async {
    await service.addSchedule(
      schedule(
        frequency: DoseFrequency.twiceDaily,
        timeSlots: const ['20:00', '08:00'],
        startDate: DateTime(2026, 5, 10),
        endDate: DateTime(2026, 5, 20),
      ),
    );
    await service.addSchedule(
      schedule(
        drugId: 2,
        drugName: 'PRN Painkiller',
        frequency: DoseFrequency.asNeeded,
        timeSlots: const [],
      ),
    );

    final onDay = await service.occurrencesForDay(userId, DateTime(2026, 5, 15));
    expect(onDay, hasLength(2), reason: 'as-needed contributes no occurrences');
    // Sorted by time of day.
    expect(onDay.first.scheduledTime, DateTime(2026, 5, 15, 8));
    expect(onDay.last.scheduledTime, DateTime(2026, 5, 15, 20));

    final beforeStart = await service.occurrencesForDay(
      userId,
      DateTime(2026, 5, 9),
    );
    expect(beforeStart, isEmpty);

    final afterEnd = await service.occurrencesForDay(
      userId,
      DateTime(2026, 5, 21),
    );
    expect(afterEnd, isEmpty);
  });

  test('logging a dose is reflected in occurrences and can be replaced',
      () async {
    final scheduleId = await service.addSchedule(schedule());
    final day = DateTime(2026, 5, 15);

    var occ = (await service.occurrencesForDay(userId, day)).single;
    expect(occ.isLogged, isFalse);
    expect(occ.status, isNull);

    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: occ.scheduledTime,
      status: DoseLogStatus.taken,
    );
    occ = (await service.occurrencesForDay(userId, day)).single;
    expect(occ.status, DoseLogStatus.taken);

    // Re-logging the same occurrence replaces rather than duplicates.
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: occ.scheduledTime,
      status: DoseLogStatus.skipped,
    );
    final logs = await db.query('dose_logs');
    expect(logs, hasLength(1));
    occ = (await service.occurrencesForDay(userId, day)).single;
    expect(occ.status, DoseLogStatus.skipped);

    await service.clearDoseLog(
      scheduleId: scheduleId,
      scheduledTime: occ.scheduledTime,
    );
    occ = (await service.occurrencesForDay(userId, day)).single;
    expect(occ.isLogged, isFalse);
  });

  test('adherence counts taken and late toward the percentage', () async {
    final scheduleId = await service.addSchedule(
      schedule(startDate: DateTime(2026, 5, 11)),
    );
    // Mon 11th taken, Tue 12th late, Wed 13th skipped, Thu 14th never logged.
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: DateTime(2026, 5, 11, 8),
      status: DoseLogStatus.taken,
    );
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: DateTime(2026, 5, 12, 8),
      status: DoseLogStatus.late,
    );
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: DateTime(2026, 5, 13, 8),
      status: DoseLogStatus.skipped,
    );

    final summary = await service.adherence(
      userId,
      from: DateTime(2026, 5, 11),
      to: DateTime(2026, 5, 14),
      asOf: DateTime(2026, 5, 14, 23, 59),
    );
    expect(summary.scheduled, 4);
    expect(summary.taken, 1);
    expect(summary.late, 1);
    expect(summary.skipped, 1);
    expect(summary.missed, 1); // the unlogged Thursday
    expect(summary.adhered, 2);
    expect(summary.percentRounded, 50);
  });

  test('adherence ignores doses not yet due today', () async {
    final scheduleId = await service.addSchedule(
      schedule(
        frequency: DoseFrequency.twiceDaily,
        timeSlots: const ['08:00', '20:00'],
        startDate: DateTime(2026, 5, 15),
      ),
    );
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: DateTime(2026, 5, 15, 8),
      status: DoseLogStatus.taken,
    );

    // It is 9am: only the 8am dose is due, and it was taken → 100%.
    final summary = await service.adherence(
      userId,
      from: DateTime(2026, 5, 15),
      to: DateTime(2026, 5, 15),
      asOf: DateTime(2026, 5, 15, 9),
    );
    expect(summary.scheduled, 1);
    expect(summary.percentRounded, 100);
  });

  test('currentStreak counts perfect days and breaks on a miss', () async {
    final scheduleId = await service.addSchedule(
      schedule(startDate: DateTime(2026, 5, 10)),
    );
    for (final day in [11, 12, 13, 14, 15]) {
      await service.logDose(
        scheduleId: scheduleId,
        scheduledTime: DateTime(2026, 5, day, 8),
        status: day == 13 ? DoseLogStatus.skipped : DoseLogStatus.taken,
      );
    }

    // As of the 15th: 14th and 15th taken, 13th skipped breaks it → streak 2.
    final streak = await service.currentStreak(
      userId,
      asOf: DateTime(2026, 5, 15, 23),
    );
    expect(streak, 2);
  });

  test('removing a schedule cascades its dose logs', () async {
    final scheduleId = await service.addSchedule(schedule());
    await service.logDose(
      scheduleId: scheduleId,
      scheduledTime: DateTime(2026, 5, 15, 8),
      status: DoseLogStatus.taken,
    );
    expect(await db.query('dose_logs'), hasLength(1));

    await service.removeSchedule(scheduleId);
    expect(await service.getSchedules(userId), isEmpty);
    expect(await db.query('dose_logs'), isEmpty);
  });

  test('detectConflicts flags interacting drugs sharing a slot', () {
    final metformin = schedule(id: 1, drugId: 1, timeSlots: const ['08:00']);
    final warfarin = schedule(
      id: 2,
      drugId: 2,
      drugName: 'Warfarin',
      timeSlots: const ['08:00', '20:00'],
    );
    final vitaminD = schedule(
      id: 3,
      drugId: 3,
      drugName: 'Vitamin D',
      timeSlots: const ['21:00'],
    );

    bool interacts(int a, int b) =>
        (a == 1 && b == 2) || (a == 2 && b == 1);

    final conflicts = DoseService.detectConflicts(
      schedules: [metformin, warfarin, vitaminD],
      interacts: interacts,
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.single.sharedSlot, '08:00');
    expect(conflicts.single.message, contains('2 hours'));

    // No shared slot → no conflict even when the drugs interact.
    final noOverlap = DoseService.detectConflicts(
      schedules: [
        metformin,
        warfarin.copyWith(timeSlots: const ['12:00']),
      ],
      interacts: interacts,
    );
    expect(noOverlap, isEmpty);
  });

  test('refill helpers measure days until the refill date', () {
    final withRefill = schedule(refillDate: DateTime(2026, 5, 20));
    expect(
      DoseService.daysUntilRefill(withRefill, asOf: DateTime(2026, 5, 15)),
      5,
    );
    expect(
      DoseService.isRefillDueSoon(withRefill, asOf: DateTime(2026, 5, 15)),
      isTrue,
    );
    expect(
      DoseService.isRefillDueSoon(withRefill, asOf: DateTime(2026, 5, 1)),
      isFalse,
    );
    expect(DoseService.daysUntilRefill(schedule()), isNull);
  });

  test('refill estimate is derived from quantity and dose rate', () {
    // 30 tablets, twice daily from May 1 → lasts 15 days → depletes May 16;
    // refill should surface 7 days before, on May 9.
    final twiceDaily = schedule(
      frequency: DoseFrequency.twiceDaily,
      timeSlots: const ['08:00', '20:00'],
      quantity: 30,
    );
    expect(
      DoseService.estimatedDepletionDate(twiceDaily),
      DateTime(2026, 5, 16),
    );
    expect(DoseService.effectiveRefillDate(twiceDaily), DateTime(2026, 5, 9));

    // An explicit refill date wins over the estimate.
    final explicit = twiceDaily.copyWith(refillDate: DateTime(2026, 5, 25));
    expect(DoseService.effectiveRefillDate(explicit), DateTime(2026, 5, 25));

    // No quantity and no refill date → nothing to surface.
    expect(DoseService.effectiveRefillDate(schedule()), isNull);
  });

  test('weeklySummary reports streak, totals and per-day flags', () async {
    final scheduleId = await service.addSchedule(
      schedule(startDate: DateTime(2026, 5, 9)),
    );
    for (final day in [13, 14, 15]) {
      await service.logDose(
        scheduleId: scheduleId,
        scheduledTime: DateTime(2026, 5, day, 8),
        status: DoseLogStatus.taken,
      );
    }

    final summary = await service.weeklySummary(
      userId,
      asOf: DateTime(2026, 5, 15, 23),
    );
    // Window is May 9..15 (7 active days): 3 taken, the rest due-but-missed.
    expect(summary.weeklyAdhered.length, 7);
    expect(summary.dosesScheduled, 7);
    expect(summary.dosesLogged, 3);
    expect(summary.streak, 3);
    expect(summary.weeklyAdhered.last, isTrue); // the 15th
    expect(summary.hasData, isTrue);
  });

  test('adherenceByDrug splits adherence per medicine', () async {
    final metforminId = await service.addSchedule(
      schedule(startDate: DateTime(2026, 5, 14)),
    );
    await service.addSchedule(
      schedule(
        drugId: 2,
        drugName: 'Amlodipine',
        startDate: DateTime(2026, 5, 14),
      ),
    );
    await service.logDose(
      scheduleId: metforminId,
      scheduledTime: DateTime(2026, 5, 14, 8),
      status: DoseLogStatus.taken,
    );
    await service.logDose(
      scheduleId: metforminId,
      scheduledTime: DateTime(2026, 5, 15, 8),
      status: DoseLogStatus.taken,
    );

    final rows = await service.adherenceByDrug(
      userId,
      from: DateTime(2026, 5, 14),
      to: DateTime(2026, 5, 15),
      asOf: DateTime(2026, 5, 15, 23),
    );
    expect(rows, hasLength(2));
    final metformin = rows.firstWhere((r) => r.schedule.drugId == 1);
    final amlodipine = rows.firstWhere((r) => r.schedule.drugId == 2);
    expect(metformin.summary.percentRounded, 100);
    expect(amlodipine.summary.percentRounded, 0);
    expect(amlodipine.summary.scheduled, 2);
  });
}
