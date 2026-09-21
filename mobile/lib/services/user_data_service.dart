import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/check_log_entry.dart';
import '../models/managed_profile.dart';
import '../models/safety_report.dart';
import '../models/user_allergy.dart';
import '../models/user_food.dart';
import '../models/user_medication.dart';
import 'secure_key_service.dart';

/// Writable per-user store for medication and allergy data.
class UserDataService {
  UserDataService._();

  static final UserDataService instance = UserDataService._();

  /// Bumps every time the medication list mutates. Screens that mirror
  /// the list (home, medications) can listen and re-fetch on change.
  final ValueNotifier<int> medicationsRevision = ValueNotifier<int>(0);

  /// Bumps every time the allergy list mutates.
  final ValueNotifier<int> allergiesRevision = ValueNotifier<int>(0);

  /// Bumps every time the food list mutates.
  final ValueNotifier<int> foodsRevision = ValueNotifier<int>(0);

  /// Announces that the rows behind EVERY area just changed owner — the
  /// guest-to-account hand-over re-keys medications, allergies, foods, dose
  /// schedules and check history in one pass, so each list must re-read against
  /// the new id rather than keep showing what it loaded for the old one.
  void notifyRecordAdopted() {
    _bumpMedicationsRevision();
    _bumpAllergiesRevision();
    _bumpFoodsRevision();
    checkHistoryRevision.value = checkHistoryRevision.value + 1;
    profilesRevision.value = profilesRevision.value + 1;
  }

  static const String _dbFileName = 'medguard_user.db';
  static const int _schemaVersion = 10;

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final db = await _open();
      _db = db;
      completer.complete(db);
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _opening = null;
    }
    return completer.future;
  }

  Future<Database> _open() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, _dbFileName);
    // Sensitive health data (medications, allergies, side effects) is stored
    // in a SQLCipher-encrypted database. The AES-256 passphrase lives in
    // platform secure storage (Android Keystore / iOS Keychain), never on
    // disk in the clear. See docs/data-protection.md.
    final passphrase = await SecureKeyService.instance.databasePassphrase();

    // Builds before encryption-at-rest stored this database in plaintext.
    // Opening such a file with a SQLCipher key throws "file is not a database",
    // which previously broke every user-data feature (adding medications,
    // interaction analysis, dose logs) after an in-place app update. Migrate
    // the legacy file to an encrypted copy — non-destructively — before the
    // real open below.
    if (await File(path).exists()) {
      await _ensureEncryptedDatabase(path, passphrase);
    }

    return openDatabase(
      path,
      password: passphrase,
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Guarantees the file at [path] can be opened with [passphrase]. If it is
  /// already encrypted with our key, this is a no-op. If it is a pre-encryption
  /// plaintext database, its contents are exported into an encrypted copy via
  /// SQLCipher's `sqlcipher_export`, verified, then swapped in (the original is
  /// kept as a `.pre-encrypt.bak` sidecar). If the file is unreadable or
  /// migration fails, it is moved aside so a fresh encrypted database can be
  /// created — the feature works again and the old bytes remain recoverable.
  Future<void> _ensureEncryptedDatabase(String path, String passphrase) async {
    // 1. Already encrypted with our key? Probe and bail out early.
    try {
      final probe = await openDatabase(
        path,
        password: passphrase,
        readOnly: true,
        singleInstance: false,
      );
      await probe.close();
      return;
    } catch (_) {
      // Not openable with the key — fall through to migration.
    }

    final escapedKey = passphrase.replaceAll("'", "''");
    final migratedPath = '$path.migrated';
    await _deleteIfExists(migratedPath);

    // 2. Try to read it as a legacy plaintext database and export it encrypted.
    var migrated = false;
    Database? plain;
    try {
      plain = await openDatabase(path, singleInstance: false);
      // Touching sqlite_master confirms it really is a readable SQLite file.
      await plain.rawQuery('SELECT count(*) FROM sqlite_master');
      // sqlcipher_export copies schema + data but NOT the user_version pragma,
      // so we read the source version and stamp it on the encrypted copy. Without
      // this the copy opens at version 0, sqflite treats it as brand-new, and
      // onCreate runs against already-populated tables.
      final versionRows = await plain.rawQuery('PRAGMA user_version');
      final sourceVersion = Sqflite.firstIntValue(versionRows) ?? 0;
      final escapedPath = migratedPath.replaceAll("'", "''");
      await plain.execute(
        "ATTACH DATABASE '$escapedPath' AS encrypted KEY '$escapedKey'",
      );
      await plain.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plain.execute('PRAGMA encrypted.user_version = $sourceVersion');
      await plain.execute('DETACH DATABASE encrypted');
      migrated = true;
    } catch (_) {
      migrated = false;
    } finally {
      await plain?.close();
    }

    // 3. Verify the migrated copy opens with the key before trusting it.
    if (migrated) {
      try {
        final verify = await openDatabase(
          migratedPath,
          password: passphrase,
          readOnly: true,
          singleInstance: false,
        );
        await verify.close();
        await File(path).rename('$path.pre-encrypt.bak');
        await File(migratedPath).rename(path);
        return;
      } catch (_) {
        await _deleteIfExists(migratedPath);
      }
    }

    // 4. Couldn't migrate. Move the unreadable file aside (never delete) so a
    // fresh encrypted database is created and the feature recovers.
    await _deleteIfExists(migratedPath);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await File(path).rename('$path.unreadable-$stamp');
    } catch (_) {
      // Last resort only: if we cannot even rename it, leave it — the open
      // below will surface the original error rather than hide a problem.
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  // Every statement uses `IF NOT EXISTS` so onCreate is idempotent. This makes
  // the schema self-healing: if a database ever opens at version 0 while the
  // tables already exist (e.g. a SQLCipher-migrated file whose user_version
  // wasn't carried over), onCreate runs harmlessly and sqflite stamps the
  // current version instead of crashing on a duplicate-table error.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id      TEXT    NOT NULL,
        drug_id      INTEGER NOT NULL,
        drug_name    TEXT    NOT NULL,
        atc_code     TEXT,
        nickname     TEXT,
        custom_color INTEGER,
        added_at     TEXT    NOT NULL,
        UNIQUE(user_id, drug_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_medications_user
        ON user_medications(user_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_allergies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     TEXT NOT NULL,
        drug_id     INTEGER,
        class_name  TEXT,
        label       TEXT NOT NULL,
        note        TEXT,
        added_at    TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_allergies_user
        ON user_allergies(user_id)
    ''');

    await _createFoodsTable(db);
    await createDoseSchema(db);
    await _createCheckLogsTable(db);
    await _createMlCacheTables(db);
    await _createProfilesTable(db);
  }

  /// Foods/drinks the user regularly consumes, for drug–food interaction checks.
  static Future<void> _createFoodsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_foods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id  TEXT NOT NULL,
        label    TEXT NOT NULL,
        note     TEXT,
        added_at TEXT NOT NULL,
        UNIQUE(user_id, label)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_user_foods_user
        ON user_foods(user_id)
    ''');
  }

  /// Drops the tables behind features that have been removed from the app.
  ///
  /// Installs that predate the removal still carry `user_pharmacogenomics`,
  /// `side_effect_reports` and `side_effect_alerts`. Nothing reads them any
  /// more, so they are pure weight in an encrypted database the user carries on
  /// their phone — and, for the side-effect tables, weight made of health data
  /// we no longer have a reason to hold.
  static Future<void> _dropRetiredTables(Database db) async {
    for (final table in const [
      'user_pharmacogenomics',
      'side_effect_reports',
      'side_effect_alerts',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  /// Multi-profile / caregiver mode. The "owner" account stays in
  /// the existing `user_id` columns; dependents are managed here and the UI
  /// switches the active profile when the caregiver picks one.
  static Future<void> _createProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS managed_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_id    TEXT    NOT NULL,
        profile_id  TEXT    NOT NULL,
        name        TEXT    NOT NULL,
        relation    TEXT,
        date_of_birth TEXT,
        notes       TEXT,
        created_at  TEXT    NOT NULL,
        UNIQUE(owner_id, profile_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_managed_profiles_owner
        ON managed_profiles(owner_id)
    ''');
  }

  /// ML prediction cache + offline request queue.
  static Future<void> _createMlCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ml_predictions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        drug_a_drugbank_id TEXT    NOT NULL,
        drug_b_drugbank_id TEXT    NOT NULL,
        severity           TEXT    NOT NULL,
        severity_int       INTEGER NOT NULL,
        confidence         REAL    NOT NULL,
        source             TEXT    NOT NULL,
        features_json      TEXT,
        explanation_json   TEXT,
        cached_at          TEXT    NOT NULL,
        UNIQUE(drug_a_drugbank_id, drug_b_drugbank_id, source)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ml_predictions_pair
        ON ml_predictions(drug_a_drugbank_id, drug_b_drugbank_id)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_api_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint     TEXT    NOT NULL,
        payload_json TEXT    NOT NULL,
        attempts     INTEGER NOT NULL DEFAULT 0,
        last_error   TEXT,
        queued_at    TEXT    NOT NULL
      )
    ''');
  }

  /// Audit trail for every InteractionChecker run.
  static Future<void> _createCheckLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS check_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id            TEXT    NOT NULL,
        drug_ids           TEXT    NOT NULL,
        drug_names         TEXT    NOT NULL,
        overall_risk       TEXT    NOT NULL,
        interaction_count  INTEGER NOT NULL DEFAULT 0,
        food_count         INTEGER NOT NULL DEFAULT 0,
        duplicate_count    INTEGER NOT NULL DEFAULT 0,
        allergy_count      INTEGER NOT NULL DEFAULT 0,
        source             TEXT    NOT NULL DEFAULT 'rule_based',
        created_at         TEXT    NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_check_logs_user
        ON check_logs(user_id, created_at DESC)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await createDoseSchema(db);
    } else if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE dose_schedules ADD COLUMN quantity REAL',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE user_medications ADD COLUMN nickname TEXT',
      );
      await db.execute(
        'ALTER TABLE user_medications ADD COLUMN custom_color INTEGER',
      );
    }
    if (oldVersion < 6) {
      await _createCheckLogsTable(db);
    }
    if (oldVersion < 7) {
      await _createMlCacheTables(db);
    }
    if (oldVersion < 8) {
      await _createProfilesTable(db);
    }
    if (oldVersion < 9) {
      await _createFoodsTable(db);
    }
    if (oldVersion < 10) {
      // Pharmacogenomics and side-effect logging were removed from the app.
      await _dropRetiredTables(db);
    }
    if (oldVersion < 5) {
      // The v1 user_allergies schema was drug-only. Rebuild it so class-level
      // allergies and richer labels are supported without losing existing rows.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_allergies_v5 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id     TEXT NOT NULL,
          drug_id     INTEGER,
          class_name  TEXT,
          label       TEXT NOT NULL,
          note        TEXT,
          added_at    TEXT NOT NULL
        )
      ''');
      // Copy existing rows: drug_name maps to label, drug_id stays.
      try {
        await db.execute('''
          INSERT INTO user_allergies_v5 (id, user_id, drug_id, label, note, added_at)
          SELECT id, user_id, drug_id, drug_name, note, added_at
          FROM user_allergies
        ''');
      } catch (_) {
        // No prior data — table may have been empty.
      }
      await db.execute('DROP TABLE IF EXISTS user_allergies');
      await db.execute(
        'ALTER TABLE user_allergies_v5 RENAME TO user_allergies',
      );
    }
  }

  /// Creates the dose-tracking tables. Shared by [_onCreate], [_onUpgrade] and
  /// tests so the schema lives in exactly one place. Relies on
  /// `PRAGMA foreign_keys = ON` (set in [_open]) for the cascade delete.
  static Future<void> createDoseSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dose_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    TEXT    NOT NULL,
        drug_id    INTEGER NOT NULL,
        drug_name  TEXT    NOT NULL,
        amount     REAL    NOT NULL,
        unit       TEXT    NOT NULL,
        frequency  TEXT    NOT NULL,
        time_slots TEXT    NOT NULL,
        start_date TEXT    NOT NULL,
        end_date   TEXT,
        refill_date TEXT,
        quantity   REAL,
        created_at TEXT    NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dose_schedules_user
        ON dose_schedules(user_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dose_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id    INTEGER  NOT NULL,
        scheduled_time TEXT     NOT NULL,
        status         TEXT     NOT NULL,
        logged_at      TEXT     NOT NULL,
        UNIQUE(schedule_id, scheduled_time),
        FOREIGN KEY (schedule_id) REFERENCES dose_schedules(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dose_logs_schedule
        ON dose_logs(schedule_id)
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<int> addMedication({
    required String userId,
    required int drugId,
    required String drugName,
    String? atcCode,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('user_medications', {
      'user_id': userId,
      'drug_id': drugId,
      'drug_name': drugName,
      'atc_code': atcCode,
      'added_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    if (id != 0) {
      _bumpMedicationsRevision();
      return id;
    }

    final rows = await db.query(
      'user_medications',
      columns: ['id'],
      where: 'user_id = ? AND drug_id = ?',
      whereArgs: [userId, drugId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['id'] as int;
  }

  Future<int> updateMedicationPersonalisation({
    required int id,
    String? nickname,
    int? customColor,
  }) async {
    final db = await database;
    final count = await db.update(
      'user_medications',
      {'nickname': nickname, 'custom_color': customColor},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) _bumpMedicationsRevision();
    return count;
  }

  Future<int> removeMedication(int id) async {
    final db = await database;
    final removed = await db.delete(
      'user_medications',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (removed > 0) _bumpMedicationsRevision();
    return removed;
  }

  Future<int> removeMedicationByDrug({
    required String userId,
    required int drugId,
  }) async {
    final db = await database;
    final removed = await db.delete(
      'user_medications',
      where: 'user_id = ? AND drug_id = ?',
      whereArgs: [userId, drugId],
    );
    if (removed > 0) _bumpMedicationsRevision();
    return removed;
  }

  Future<List<UserMedication>> getUserMedications(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_medications',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'added_at DESC',
    );
    return rows.map(UserMedication.fromMap).toList(growable: false);
  }

  Future<List<int>> getUserMedicationIds(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_medications',
      columns: ['drug_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((r) => r['drug_id'] as int).toList(growable: false);
  }

  Future<bool> hasMedication({
    required String userId,
    required int drugId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'user_medications',
      columns: ['id'],
      where: 'user_id = ? AND drug_id = ?',
      whereArgs: [userId, drugId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> clearMedications(String userId) async {
    final db = await database;
    final removed = await db.delete(
      'user_medications',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    if (removed > 0) _bumpMedicationsRevision();
    return removed;
  }

  void _bumpMedicationsRevision() {
    medicationsRevision.value = medicationsRevision.value + 1;
  }

  Future<int> countMedications(String userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_medications WHERE user_id = ?',
      [userId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // ── Allergies ──────────────────────────────────────────────────────────────

  Future<int> addDrugAllergy({
    required String userId,
    required int drugId,
    required String drugName,
    String? note,
  }) async {
    final db = await database;
    final id = await db.insert('user_allergies', {
      'user_id': userId,
      'drug_id': drugId,
      'class_name': null,
      'label': drugName,
      'note': note,
      'added_at': DateTime.now().toUtc().toIso8601String(),
    });
    _bumpAllergiesRevision();
    return id;
  }

  Future<int> addClassAllergy({
    required String userId,
    required String className,
    String? note,
  }) async {
    final db = await database;
    final id = await db.insert('user_allergies', {
      'user_id': userId,
      'drug_id': null,
      'class_name': className,
      'label': className,
      'note': note,
      'added_at': DateTime.now().toUtc().toIso8601String(),
    });
    _bumpAllergiesRevision();
    return id;
  }

  Future<int> removeAllergy(int id) async {
    final db = await database;
    final removed = await db.delete(
      'user_allergies',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (removed > 0) _bumpAllergiesRevision();
    return removed;
  }

  Future<List<UserAllergy>> getUserAllergies(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_allergies',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'added_at DESC',
    );
    return rows.map(UserAllergy.fromMap).toList(growable: false);
  }

  Future<int> countAllergies(String userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_allergies WHERE user_id = ?',
      [userId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  void _bumpAllergiesRevision() {
    allergiesRevision.value = allergiesRevision.value + 1;
  }

  // ── Foods ─────────────────────────────────────────────────────────────────

  /// Adds a food/drink to the user's list. Idempotent on (user, label): adding
  /// a food already present is a no-op and returns its existing id.
  Future<int> addFood({
    required String userId,
    required String label,
    String? note,
  }) async {
    final db = await database;
    final clean = label.trim();
    if (clean.isEmpty) return 0;
    final id = await db.insert('user_foods', {
      'user_id': userId,
      'label': clean,
      'note': note,
      'added_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) {
      _bumpFoodsRevision();
      return id;
    }
    final rows = await db.query(
      'user_foods',
      columns: ['id'],
      where: 'user_id = ? AND label = ?',
      whereArgs: [userId, clean],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['id'] as int;
  }

  Future<int> removeFood(int id) async {
    final db = await database;
    final removed = await db.delete(
      'user_foods',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (removed > 0) _bumpFoodsRevision();
    return removed;
  }

  Future<List<UserFood>> getUserFoods(String userId) async {
    final db = await database;
    final rows = await db.query(
      'user_foods',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'added_at DESC',
    );
    return rows.map(UserFood.fromMap).toList(growable: false);
  }

  Future<int> countFoods(String userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM user_foods WHERE user_id = ?',
      [userId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  void _bumpFoodsRevision() {
    foodsRevision.value = foodsRevision.value + 1;
  }

  // ── Check history ───────────────────────────────────────────────────────

  /// Bumps every time a new SafetyReport is recorded.
  final ValueNotifier<int> checkHistoryRevision = ValueNotifier<int>(0);

  Future<int> recordCheck({
    required String userId,
    required List<({int id, String name})> drugs,
    required SafetyReport report,
    String source = 'rule_based',
  }) async {
    final db = await database;
    final id = await db.insert('check_logs', {
      'user_id': userId,
      'drug_ids': drugs.map((d) => d.id).join(','),
      'drug_names': drugs.map((d) => d.name).join('|'),
      'overall_risk': report.overallRiskWire,
      'interaction_count': report.drugInteractions.length,
      'food_count': report.foodInteractions.length,
      'duplicate_count': report.duplicateTherapies.length,
      'allergy_count': report.allergyHits.length,
      'source': source,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    checkHistoryRevision.value = checkHistoryRevision.value + 1;
    return id;
  }

  Future<List<CheckLogEntry>> getCheckHistory(
    String userId, {
    int limit = 50,
  }) async {
    final db = await database;
    final rows = await db.query(
      'check_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(CheckLogEntry.fromMap).toList(growable: false);
  }

  Future<int> clearCheckHistory(String userId) async {
    final db = await database;
    final removed = await db.delete(
      'check_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    if (removed > 0) {
      checkHistoryRevision.value = checkHistoryRevision.value + 1;
    }
    return removed;
  }

  // ── Managed profiles (caregiver mode) ─────────────────────────────────────

  final ValueNotifier<int> profilesRevision = ValueNotifier<int>(0);

  Future<int> addManagedProfile({
    required String ownerId,
    required String name,
    String? relation,
    DateTime? dateOfBirth,
    String? notes,
  }) async {
    final db = await database;
    final created = DateTime.now().toUtc();
    final profileId = _slugProfileId(ownerId, name, created);
    final id = await db.insert(
      'managed_profiles',
      {
        'owner_id': ownerId,
        'profile_id': profileId,
        'name': name,
        'relation': relation,
        'date_of_birth': dateOfBirth?.toUtc().toIso8601String(),
        'notes': notes,
        'created_at': created.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    profilesRevision.value = profilesRevision.value + 1;
    return id;
  }

  Future<List<ManagedProfile>> getManagedProfiles(String ownerId) async {
    final db = await database;
    final rows = await db.query(
      'managed_profiles',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ManagedProfile.fromMap).toList(growable: false);
  }

  Future<int> removeManagedProfile({
    required String ownerId,
    required String profileId,
  }) async {
    final db = await database;
    // Cascade delete the dependent's data so we don't leak medications /
    // allergies belonging to a profile the caregiver has removed.
    await db.delete('user_medications', where: 'user_id = ?', whereArgs: [profileId]);
    await db.delete('user_allergies', where: 'user_id = ?', whereArgs: [profileId]);
    await db.delete('user_foods', where: 'user_id = ?', whereArgs: [profileId]);
    await db.delete('dose_schedules', where: 'user_id = ?', whereArgs: [profileId]);
    final n = await db.delete(
      'managed_profiles',
      where: 'owner_id = ? AND profile_id = ?',
      whereArgs: [ownerId, profileId],
    );
    if (n > 0) profilesRevision.value = profilesRevision.value + 1;
    return n;
  }

  static String _slugProfileId(String ownerId, String name, DateTime created) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '$ownerId::$slug::${created.millisecondsSinceEpoch}';
  }
}
