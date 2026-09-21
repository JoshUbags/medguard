import 'package:sqflite_sqlcipher/sqflite.dart';

import 'session_service.dart';
import 'user_data_service.dart';

/// What a guest built up on this device before they had an account.
///
/// Used to decide whether the hand-over is even worth mentioning (an empty
/// record needs no sheet) and to say out loud what is about to move — a safety
/// record should never be relocated behind a generic "continue".
class GuestRecordSummary {
  const GuestRecordSummary({
    required this.medications,
    required this.allergies,
    required this.foods,
    required this.schedules,
    required this.checks,
  });

  static const GuestRecordSummary empty = GuestRecordSummary(
    medications: 0,
    allergies: 0,
    foods: 0,
    schedules: 0,
    checks: 0,
  );

  final int medications;
  final int allergies;
  final int foods;
  final int schedules;
  final int checks;

  bool get isEmpty =>
      medications == 0 &&
      allergies == 0 &&
      foods == 0 &&
      schedules == 0 &&
      checks == 0;

  bool get isNotEmpty => !isEmpty;

  /// A plain-English list of what is on the device, longest-lived items first:
  /// "4 medicines, 2 allergies and 3 safety checks". Returns an empty string
  /// when there is nothing, so callers can treat it as "nothing to say".
  String describe() {
    final parts = <String>[
      if (medications > 0) _plural(medications, 'medicine', 'medicines'),
      if (allergies > 0) _plural(allergies, 'allergy', 'allergies'),
      if (foods > 0) _plural(foods, 'food or drink', 'foods and drinks'),
      if (schedules > 0) _plural(schedules, 'dose schedule', 'dose schedules'),
      if (checks > 0) _plural(checks, 'safety check', 'safety checks'),
    ];
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';
}

/// Moves everything a guest recorded on this device into the account they have
/// just signed into.
///
/// Every user-owned table is keyed by a plain `user_id` string, and an
/// unauthenticated run writes under the `'local-device'` fixture, so the
/// hand-over is a re-key rather than a copy: no rows are read into memory, no
/// clinical data is rewritten, and a failure part-way leaves the untouched
/// tables exactly where they were.
///
/// Conflicts are resolved in favour of the account. `UPDATE OR IGNORE` skips
/// any row whose move would collide with a `UNIQUE(user_id, …)` row the account
/// already has — the same medicine, or the same food label — and the follow-up
/// delete clears the guest copy that was left behind. Nothing the account did
/// not already know is discarded.
class GuestDataMigration {
  GuestDataMigration({
    Future<Database> Function()? databaseProvider,
    void Function()? onRecordChanged,
  }) : _databaseProvider =
           databaseProvider ?? (() => UserDataService.instance.database),
       _onRecordChanged =
           onRecordChanged ?? UserDataService.instance.notifyRecordAdopted;

  static final GuestDataMigration instance = GuestDataMigration();

  static const String localUserId = 'local-device';

  final Future<Database> Function() _databaseProvider;
  final void Function() _onRecordChanged;

  /// Tables re-keyed by the hand-over, with whether a `UNIQUE(user_id, …)`
  /// constraint can make a row collide with one the account already holds.
  ///
  /// `managed_profiles` is deliberately absent: caregiver profiles are part of
  /// the account layer and cannot be created without one, so there is never a
  /// guest-owned row to move — and its `profile_id` embeds the owner id, which
  /// a blind re-key would leave pointing at the fixture.
  static const List<({String table, bool canCollide})> _tables = [
    (table: 'user_medications', canCollide: true),
    (table: 'user_allergies', canCollide: false),
    (table: 'user_foods', canCollide: true),
    (table: 'dose_schedules', canCollide: false),
    (table: 'check_logs', canCollide: false),
  ];

  /// What is currently sitting under the local-device fixture.
  ///
  /// Best-effort per table: a missing table (an older database that has not
  /// upgraded yet) contributes zero rather than failing the whole count, so a
  /// partial schema can never block sign-in.
  Future<GuestRecordSummary> summarise() async {
    try {
      final db = await _databaseProvider();
      return GuestRecordSummary(
        medications: await _count(db, 'user_medications'),
        allergies: await _count(db, 'user_allergies'),
        foods: await _count(db, 'user_foods'),
        schedules: await _count(db, 'dose_schedules'),
        checks: await _count(db, 'check_logs'),
      );
    } catch (_) {
      return GuestRecordSummary.empty;
    }
  }

  /// Re-keys every guest row to [userId] and returns the number of rows moved.
  ///
  /// A no-op when [userId] is empty or is itself the fixture — re-keying
  /// `local-device` to `local-device` would delete the whole record on the
  /// cleanup pass.
  Future<int> adopt(String userId) async {
    if (userId.isEmpty || userId == localUserId) return 0;
    final db = await _databaseProvider();

    var moved = 0;
    for (final entry in _tables) {
      try {
        moved += await db.rawUpdate(
          'UPDATE OR IGNORE ${entry.table} SET user_id = ? WHERE user_id = ?',
          [userId, localUserId],
        );
        if (entry.canCollide) {
          // Whatever OR IGNORE refused to move is a duplicate of something the
          // account already has. Dropping the guest copy is what makes the
          // hand-over complete rather than half-done.
          await db.delete(
            entry.table,
            where: 'user_id = ?',
            whereArgs: [localUserId],
          );
        }
      } catch (_) {
        // One missing table must not strand the rest of the record.
      }
    }

    if (moved > 0) _onRecordChanged();
    return moved;
  }

  /// Permanently removes the guest record instead of adopting it — the "start
  /// fresh" branch of the hand-over. Returns the number of rows removed.
  Future<int> discard() async {
    var removed = 0;
    try {
      final db = await _databaseProvider();
      for (final entry in _tables) {
        try {
          removed += await db.delete(
            entry.table,
            where: 'user_id = ?',
            whereArgs: [localUserId],
          );
        } catch (_) {
          // Missing table — nothing there to remove.
        }
      }
    } catch (_) {
      return removed;
    }
    if (removed > 0) _onRecordChanged();
    return removed;
  }

  /// The id the hand-over should target: the account that has just taken over.
  static String currentAccountId() => SessionService.instance.ownerUserId;

  Future<int> _count(Database db, String table) async {
    try {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table WHERE user_id = ?',
        [localUserId],
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
