/// A medication the user has added to their personal list.
///
/// Lives in the writable user database, separate from the read-only
/// clinical reference DB. [drugName] and [atcCode] are denormalised
/// from the `drugs` table at add time so the list renders instantly
/// without a join against the 280 MB reference DB.
class UserMedication {
  final int id;
  final String userId;
  final int drugId;
  final String drugName;
  final String? atcCode;

  /// User-defined label ("morning heart pill") shown instead of [drugName].
  final String? nickname;

  /// Optional ARGB colour value that overrides the deterministic drug-card
  /// visual signature. Stored as an integer (e.g. `0xFF2563EB`).
  final int? customColor;

  final DateTime addedAt;

  const UserMedication({
    required this.id,
    required this.userId,
    required this.drugId,
    required this.drugName,
    required this.atcCode,
    this.nickname,
    this.customColor,
    required this.addedAt,
  });

  /// The label shown in UI — [nickname] when set, else [drugName].
  String get displayName => nickname?.isNotEmpty == true ? nickname! : drugName;

  factory UserMedication.fromMap(Map<String, dynamic> map) {
    return UserMedication(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      drugId: map['drug_id'] as int,
      drugName: map['drug_name'] as String,
      atcCode: map['atc_code'] as String?,
      nickname: map['nickname'] as String?,
      customColor: map['custom_color'] as int?,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }

  Map<String, Object?> toInsertMap() => {
    'user_id': userId,
    'drug_id': drugId,
    'drug_name': drugName,
    'atc_code': atcCode,
    'nickname': nickname,
    'custom_color': customColor,
    'added_at': addedAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'UserMedication(#$id, $drugName, user=$userId)';
}
