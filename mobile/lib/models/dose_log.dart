/// Outcome recorded against a single scheduled dose occurrence.
enum DoseLogStatus {
  taken('taken', 'Taken'),
  skipped('skipped', 'Skipped'),
  late('late', 'Taken late'),
  missed('missed', 'Missed');

  const DoseLogStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Both [taken] and [late] count as the dose having been taken, so they
  /// count toward adherence; [skipped] and [missed] do not.
  bool get countsAsTaken =>
      this == DoseLogStatus.taken || this == DoseLogStatus.late;

  static DoseLogStatus fromWire(String value) {
    return DoseLogStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse: () => DoseLogStatus.taken,
    );
  }
}

/// A logged dose event tied to a [DoseSchedule] occurrence at [scheduledTime].
///
/// Uniqueness is enforced on `(schedule_id, scheduled_time)` so re-logging the
/// same occurrence updates the existing row rather than duplicating it.
class DoseLog {
  final int id;
  final int scheduleId;
  final DateTime scheduledTime;
  final DoseLogStatus status;
  final DateTime loggedAt;

  const DoseLog({
    required this.id,
    required this.scheduleId,
    required this.scheduledTime,
    required this.status,
    required this.loggedAt,
  });

  factory DoseLog.fromMap(Map<String, dynamic> map) {
    return DoseLog(
      id: map['id'] as int,
      scheduleId: map['schedule_id'] as int,
      scheduledTime: DateTime.parse(map['scheduled_time'] as String),
      status: DoseLogStatus.fromWire(map['status'] as String),
      loggedAt: DateTime.parse(map['logged_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'schedule_id': scheduleId,
    'scheduled_time': scheduledTime.toIso8601String(),
    'status': status.wireValue,
    'logged_at': loggedAt.toIso8601String(),
  };

  @override
  String toString() =>
      'DoseLog(schedule=$scheduleId, ${status.wireValue} @ $scheduledTime)';
}
