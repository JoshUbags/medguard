/// A drug or drug-class the user is allergic to. Stored per-user in the
/// writable user database; surfaced by [AllergyChecker] as a hard block at
/// medication-add time and as a section on the safety report.
class UserAllergy {
  final int id;
  final String userId;

  /// Set when the allergy is to a specific drug (e.g. amoxicillin).
  final int? drugId;

  /// Set when the allergy is to a whole therapeutic class (e.g. "penicillins"
  /// or "sulfonamides"). For class-level allergies [drugId] is null and the
  /// label is matched against `drug_categories.category` via [AllergyChecker].
  final String? className;

  /// User-facing label — drug name for drug allergies, class label for
  /// class-level allergies. Always non-empty.
  final String label;

  /// Optional free-form note ("anaphylaxis 2018", "mild rash").
  final String? note;

  final DateTime addedAt;

  const UserAllergy({
    required this.id,
    required this.userId,
    this.drugId,
    this.className,
    required this.label,
    this.note,
    required this.addedAt,
  });

  bool get isClassLevel => drugId == null && className != null;

  factory UserAllergy.fromMap(Map<String, dynamic> map) {
    return UserAllergy(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      drugId: map['drug_id'] as int?,
      className: map['class_name'] as String?,
      label: map['label'] as String,
      note: map['note'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'user_id': userId,
    'drug_id': drugId,
    'class_name': className,
    'label': label,
    'note': note,
    'added_at': addedAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'UserAllergy(#$id, $label, user=$userId)';
}
