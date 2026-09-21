/// A dependent profile managed by a caregiver — e.g. a parent looking
/// after a child's medication or an adult tracking an elderly relative.
///
/// Each profile has its own opaque [profileId] used as the `user_id` foreign
/// key in [user_medications], [user_allergies], [dose_schedules], etc., so
/// the existing per-user storage layer can stay unchanged. The
/// [ActiveProfileService] switches what id is current at runtime.
class ManagedProfile {
  const ManagedProfile({
    required this.id,
    required this.ownerId,
    required this.profileId,
    required this.name,
    this.relation,
    this.dateOfBirth,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final String ownerId;

  /// Opaque id used as the `user_id` for this profile's medications etc.
  /// Generated as `${ownerId}::${slug(name)}::${createdAt.millisecondsSinceEpoch}`
  /// so it's stable, deterministic from human input, and never collides with
  /// the owner's own user_id.
  final String profileId;

  final String name;
  final String? relation;
  final DateTime? dateOfBirth;
  final String? notes;
  final DateTime createdAt;

  factory ManagedProfile.fromMap(Map<String, Object?> map) {
    return ManagedProfile(
      id: map['id'] as int,
      ownerId: map['owner_id'] as String,
      profileId: map['profile_id'] as String,
      name: map['name'] as String,
      relation: map['relation'] as String?,
      dateOfBirth: map['date_of_birth'] == null
          ? null
          : DateTime.parse(map['date_of_birth'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
