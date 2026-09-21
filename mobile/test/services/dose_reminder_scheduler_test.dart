import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/dose_schedule.dart';
import 'package:mobile/services/dose_reminder_scheduler.dart';

void main() {
  DoseSchedule schedule({
    int id = 7,
    DoseFrequency frequency = DoseFrequency.onceDaily,
    List<String> timeSlots = const ['08:00'],
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return DoseSchedule(
      id: id,
      userId: 'local-device',
      drugId: 1,
      drugName: 'Metformin',
      amount: 500,
      unit: 'mg',
      frequency: frequency,
      timeSlots: timeSlots,
      startDate: startDate ?? DateTime(2026, 5, 1),
      endDate: endDate,
      createdAt: DateTime(2026, 5, 1),
    );
  }

  test('plans a primary alert + 30-minute follow-up per future occurrence', () {
    final reminders = planDoseReminders(
      schedule(),
      now: DateTime(2026, 5, 15, 6),
      horizonDays: 2,
    );

    // Days 15, 16, 17 each have one future 08:00 dose.
    final primaries = reminders.where((r) => !r.isFollowUp).toList();
    final followUps = reminders.where((r) => r.isFollowUp).toList();
    expect(primaries, hasLength(3));
    expect(followUps, hasLength(3));
    expect(primaries.first.fireTime, DateTime(2026, 5, 15, 8));
    expect(followUps.first.fireTime, DateTime(2026, 5, 15, 8, 30));
    expect(
      primaries.first.payload,
      '7|${DateTime(2026, 5, 15, 8).toIso8601String()}|0',
    );
    // Distinct, stable notification ids per alert.
    expect(
      reminders.map((r) => r.notificationId).toSet(),
      hasLength(reminders.length),
    );
  });

  test('skips occurrences already past for today', () {
    final reminders = planDoseReminders(
      schedule(),
      now: DateTime(2026, 5, 15, 9), // after the 08:00 slot
      horizonDays: 2,
    );
    final primaries = reminders.where((r) => !r.isFollowUp).toList();
    expect(primaries, hasLength(2)); // only the 16th and 17th
    expect(primaries.first.fireTime, DateTime(2026, 5, 16, 8));
  });

  test('respects the schedule end date and as-needed frequency', () {
    final ended = planDoseReminders(
      schedule(endDate: DateTime(2026, 5, 15)),
      now: DateTime(2026, 5, 15, 6),
      horizonDays: 5,
    );
    expect(ended.where((r) => !r.isFollowUp), hasLength(1)); // only the 15th

    final asNeeded = planDoseReminders(
      schedule(frequency: DoseFrequency.asNeeded, timeSlots: const []),
      now: DateTime(2026, 5, 15, 6),
      horizonDays: 5,
    );
    expect(asNeeded, isEmpty);
  });

  test('no-op scheduler is safe to call', () async {
    const scheduler = NoopDoseReminderScheduler();
    await scheduler.initialize();
    expect(await scheduler.requestPermission(), isFalse);
    await scheduler.syncSchedule(schedule());
    await scheduler.cancelForSchedule(7);
    await scheduler.cancelOccurrence(
      scheduleId: 7,
      scheduledTime: DateTime(2026, 5, 15, 8),
    );
  });
}
