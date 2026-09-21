/// A food or drink the user regularly consumes. Stored per-user in the writable
/// user database so MedGuard can flag drug–food interactions (e.g. grapefruit,
/// dairy, alcohol) against what the person actually eats — not just against the
/// drug's generic food list.
class UserFood {
  final int id;
  final String userId;

  /// User-facing food name, e.g. "Grapefruit", "Milk", "Alcohol". Always
  /// non-empty and stored title-cased for display.
  final String label;

  /// Optional free-form note ("with breakfast", "every evening").
  final String? note;

  final DateTime addedAt;

  const UserFood({
    required this.id,
    required this.userId,
    required this.label,
    this.note,
    required this.addedAt,
  });

  factory UserFood.fromMap(Map<String, dynamic> map) {
    return UserFood(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      label: map['label'] as String,
      note: map['note'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'user_id': userId,
    'label': label,
    'note': note,
    'added_at': addedAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'UserFood(#$id, $label, user=$userId)';
}
