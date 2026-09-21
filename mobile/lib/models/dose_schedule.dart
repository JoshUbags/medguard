import 'dart:convert';

/// How often a dose is taken. The [wireValue] is what we persist in SQLite so
/// the column stays human-readable; [defaultSlotCount] seeds the time-slot
/// editor when the user first picks a frequency.
enum DoseFrequency {
  onceDaily('once_daily', 'Once daily', 1),
  twiceDaily('twice_daily', 'Twice daily', 2),
  threeDaily('three_daily', 'Three times daily', 3),
  every8h('every_8h', 'Every 8 hours', 3),
  asNeeded('as_needed', 'As needed', 0);

  const DoseFrequency(this.wireValue, this.label, this.defaultSlotCount);

  final String wireValue;
  final String label;
  final int defaultSlotCount;

  /// `as_needed` doses are never auto-scheduled onto a calendar day.
  bool get isScheduled => this != DoseFrequency.asNeeded;

  static DoseFrequency fromWire(String value) {
    return DoseFrequency.values.firstWhere(
      (frequency) => frequency.wireValue == value,
      orElse: () => DoseFrequency.onceDaily,
    );
  }
}

/// A recurring medication schedule stored in the writable user database.
///
/// [timeSlots] holds the daily clock times (`HH:mm`, 24h) the dose is due.
/// [startDate], [endDate] and [refillDate] are day-granular (local midnight);
/// times of day live only in [timeSlots].
class DoseSchedule {
  final int id;
  final String userId;
  final int drugId;
  final String drugName;

  /// How much is taken each time. OPTIONAL — plenty of people know they take
  /// "one tablet, morning and night" without knowing or caring about the
  /// strength, and forcing a number there is a wall in front of the reminder
  /// they actually came to set.
  ///
  /// Stored as `0` rather than NULL so the existing NOT NULL column needs no
  /// migration; [hasAmount] is the check every reader should use.
  final double amount;
  final String unit;
  final DoseFrequency frequency;
  final List<String> timeSlots;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? refillDate;

  /// Units dispensed (tablets/mL/etc.) — drives the supply-depletion estimate.
  /// Null when the user did not record a quantity.
  final double? quantity;
  final DateTime createdAt;

  const DoseSchedule({
    required this.id,
    required this.userId,
    required this.drugId,
    required this.drugName,
    required this.amount,
    required this.unit,
    required this.frequency,
    required this.timeSlots,
    required this.startDate,
    this.endDate,
    this.refillDate,
    this.quantity,
    required this.createdAt,
  });

  /// Scheduled doses per active day (`as_needed` counts as one for estimates).
  int get dosesPerDay =>
      frequency.isScheduled && timeSlots.isNotEmpty ? timeSlots.length : 1;

  /// Whether a strength was actually recorded for this schedule.
  bool get hasAmount => amount > 0;

  /// `500 mg`, `1000 IU`, `2.5 mL` — trailing `.0` trimmed for whole numbers.
  /// Null when no amount was recorded, so callers must decide what to show
  /// instead rather than printing "0 mg".
  String? get doseLabel {
    if (!hasAmount) return null;
    final rounded = amount.roundToDouble();
    final amountText = amount == rounded
        ? rounded.toInt().toString()
        : amount.toString();
    return '$amountText $unit';
  }

  /// A never-null one-line descriptor: the strength when it is known, and how
  /// often the dose is taken when it isn't. For notification copy and report
  /// lines that must always say something.
  String get doseDescriptor => doseLabel ?? frequency.label;

  /// Whether this schedule is in its active window on [day] (date-only compare).
  bool isActiveOn(DateTime day) {
    final target = _dateOnly(day);
    final start = _dateOnly(startDate);
    if (target.isBefore(start)) return false;
    final end = endDate;
    if (end != null && target.isAfter(_dateOnly(end))) return false;
    return true;
  }

  /// The concrete `HH:mm` slots due on [day] — empty for inactive days or
  /// `as_needed` schedules that have no fixed clock time.
  List<String> slotsOn(DateTime day) {
    if (!frequency.isScheduled) return const [];
    if (!isActiveOn(day)) return const [];
    return timeSlots;
  }

  factory DoseSchedule.fromMap(Map<String, dynamic> map) {
    final rawSlots = map['time_slots'] as String? ?? '[]';
    final decoded = (jsonDecode(rawSlots) as List<dynamic>)
        .map((slot) => slot.toString())
        .toList(growable: false);
    return DoseSchedule(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      drugId: map['drug_id'] as int,
      drugName: map['drug_name'] as String,
      amount: (map['amount'] as num).toDouble(),
      unit: map['unit'] as String,
      frequency: DoseFrequency.fromWire(map['frequency'] as String),
      timeSlots: decoded,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: _parseNullableDate(map['end_date'] as String?),
      refillDate: _parseNullableDate(map['refill_date'] as String?),
      quantity: (map['quantity'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'user_id': userId,
    'drug_id': drugId,
    'drug_name': drugName,
    'amount': amount,
    'unit': unit,
    'frequency': frequency.wireValue,
    'time_slots': jsonEncode(timeSlots),
    'start_date': _dateKey(startDate),
    'end_date': endDate == null ? null : _dateKey(endDate!),
    'refill_date': refillDate == null ? null : _dateKey(refillDate!),
    'quantity': quantity,
    'created_at': createdAt.toIso8601String(),
  };

  DoseSchedule copyWith({
    int? id,
    String? drugName,
    double? amount,
    String? unit,
    DoseFrequency? frequency,
    List<String>? timeSlots,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? refillDate,
    double? quantity,
  }) {
    return DoseSchedule(
      id: id ?? this.id,
      userId: userId,
      drugId: drugId,
      drugName: drugName ?? this.drugName,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      frequency: frequency ?? this.frequency,
      timeSlots: timeSlots ?? this.timeSlots,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      refillDate: refillDate ?? this.refillDate,
      quantity: quantity ?? this.quantity,
      createdAt: createdAt,
    );
  }

  @override
  String toString() =>
      'DoseSchedule(#$id, $drugName $doseLabel, ${frequency.wireValue})';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseNullableDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.parse(value);
}
