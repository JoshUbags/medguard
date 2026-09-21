import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/guest_data_migration.dart';
import 'package:mobile/services/user_data_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The guest-to-account hand-over, exercised against a real SQLite schema
/// rather than a mock: every guarantee it makes is a SQL guarantee (OR IGNORE
/// on a UNIQUE constraint, a scoped delete), so a fake database would test the
/// wrong thing.
void main() {
  const local = GuestDataMigration.localUserId;
  const account = 'firebase-uid-123';

  late Database db;
  late GuestDataMigration migration;
  late int changeNotifications;

  Future<void> createSchema() async {
    await db.execute('''
      CREATE TABLE user_medications (
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
      CREATE TABLE user_allergies (
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
      CREATE TABLE user_foods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id  TEXT NOT NULL,
        label    TEXT NOT NULL,
        note     TEXT,
        added_at TEXT NOT NULL,
        UNIQUE(user_id, label)
      )
    ''');
    await db.execute('''
      CREATE TABLE check_logs (
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
    await UserDataService.createDoseSchema(db);
  }

  Future<void> addMedication(String userId, int drugId, String name) {
    return db.insert('user_medications', {
      'user_id': userId,
      'drug_id': drugId,
      'drug_name': name,
      'added_at': DateTime(2026, 5, 1).toIso8601String(),
    });
  }

  Future<void> addAllergy(String userId, String label) {
    return db.insert('user_allergies', {
      'user_id': userId,
      'label': label,
      'added_at': DateTime(2026, 5, 1).toIso8601String(),
    });
  }

  Future<void> addFood(String userId, String label) {
    return db.insert('user_foods', {
      'user_id': userId,
      'label': label,
      'added_at': DateTime(2026, 5, 1).toIso8601String(),
    });
  }

  Future<void> addCheck(String userId) {
    return db.insert('check_logs', {
      'user_id': userId,
      'drug_ids': '1,2',
      'drug_names': 'Warfarin,Aspirin',
      'overall_risk': 'major',
      'created_at': DateTime(2026, 5, 1).toIso8601String(),
    });
  }

  Future<void> addSchedule(String userId, int drugId) {
    return db.insert('dose_schedules', {
      'user_id': userId,
      'drug_id': drugId,
      'drug_name': 'Metformin',
      'amount': 500.0,
      'unit': 'mg',
      'frequency': 'onceDaily',
      'time_slots': '08:00',
      'start_date': DateTime(2026, 5, 1).toIso8601String(),
      'created_at': DateTime(2026, 5, 1).toIso8601String(),
    });
  }

  Future<List<String>> owners(String table) async {
    final rows = await db.query(table, columns: ['user_id'], orderBy: 'id');
    return rows.map((r) => r['user_id'] as String).toList();
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createSchema();
    changeNotifications = 0;
    migration = GuestDataMigration(
      databaseProvider: () async => db,
      onRecordChanged: () => changeNotifications++,
    );
  });

  tearDown(() async => db.close());

  group('summarise', () {
    test('an untouched device has nothing to hand over', () async {
      final summary = await migration.summarise();

      expect(summary.isEmpty, isTrue);
      expect(summary.describe(), isEmpty);
    });

    test('counts only the local fixture, never the account', () async {
      await addMedication(local, 1, 'Warfarin');
      await addMedication(local, 2, 'Aspirin');
      await addMedication(account, 3, 'Ibuprofen');
      await addAllergy(local, 'Penicillin');
      await addCheck(local);

      final summary = await migration.summarise();

      expect(summary.medications, 2);
      expect(summary.allergies, 1);
      expect(summary.checks, 1);
      expect(summary.foods, 0);
      expect(summary.isNotEmpty, isTrue);
    });

    test('describes the record in plain English', () async {
      await addMedication(local, 1, 'Warfarin');
      await addAllergy(local, 'Penicillin');
      await addCheck(local);
      await addCheck(local);

      expect(
        (await migration.summarise()).describe(),
        '1 medicine, 1 allergy and 2 safety checks',
      );
    });

    test('singular and plural are both correct', () async {
      await addMedication(local, 1, 'Warfarin');
      expect((await migration.summarise()).describe(), '1 medicine');

      await addMedication(local, 2, 'Aspirin');
      expect((await migration.summarise()).describe(), '2 medicines');
    });
  });

  group('adopt', () {
    test('re-keys every table to the account', () async {
      await addMedication(local, 1, 'Warfarin');
      await addAllergy(local, 'Penicillin');
      await addFood(local, 'Grapefruit');
      await addSchedule(local, 1);
      await addCheck(local);

      final moved = await migration.adopt(account);

      expect(moved, 5);
      expect(await owners('user_medications'), [account]);
      expect(await owners('user_allergies'), [account]);
      expect(await owners('user_foods'), [account]);
      expect(await owners('dose_schedules'), [account]);
      expect(await owners('check_logs'), [account]);
      expect(changeNotifications, 1);
    });

    test('leaves rows that already belong to the account alone', () async {
      await addMedication(account, 3, 'Ibuprofen');
      await addMedication(local, 1, 'Warfarin');

      await migration.adopt(account);

      final rows = await db.query('user_medications', orderBy: 'drug_id');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['user_id'] == account), isTrue);
    });

    test(
      'a medicine the account already has is de-duplicated, not duplicated',
      () async {
        // The UNIQUE(user_id, drug_id) collision case: both sides know
        // Warfarin. The account's row is authoritative and the guest copy is
        // dropped, so the regimen does not end up listing it twice.
        await addMedication(account, 1, 'Warfarin');
        await addMedication(local, 1, 'Warfarin');
        await addMedication(local, 2, 'Aspirin');

        await migration.adopt(account);

        final rows = await db.query('user_medications', orderBy: 'drug_id');
        expect(rows.map((r) => r['drug_id']), [1, 2]);
        expect(rows.every((r) => r['user_id'] == account), isTrue);
        // Nothing is left stranded under the fixture.
        expect((await migration.summarise()).isEmpty, isTrue);
      },
    );

    test('a food label the account already has is de-duplicated', () async {
      await addFood(account, 'Grapefruit');
      await addFood(local, 'Grapefruit');
      await addFood(local, 'Green tea');

      await migration.adopt(account);

      final rows = await db.query('user_foods', orderBy: 'label');
      expect(rows.map((r) => r['label']), ['Grapefruit', 'Green tea']);
      expect(rows.every((r) => r['user_id'] == account), isTrue);
    });

    test('duplicate allergy notes survive — they are not unique', () async {
      await addAllergy(account, 'Penicillin');
      await addAllergy(local, 'Penicillin');

      await migration.adopt(account);

      final rows = await db.query('user_allergies');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['user_id'] == account), isTrue);
    });

    test('refuses to re-key onto the fixture itself', () async {
      // Guarding this matters: the cleanup delete that follows a re-key would
      // otherwise wipe the very record it was asked to keep.
      await addMedication(local, 1, 'Warfarin');

      expect(await migration.adopt(local), 0);
      expect(await owners('user_medications'), [local]);
      expect(changeNotifications, 0);
    });

    test('refuses an empty account id', () async {
      await addMedication(local, 1, 'Warfarin');

      expect(await migration.adopt(''), 0);
      expect(await owners('user_medications'), [local]);
    });

    test('with nothing to move, it changes and announces nothing', () async {
      expect(await migration.adopt(account), 0);
      expect(changeNotifications, 0);
    });

    test('a missing table does not strand the rest of the record', () async {
      await addMedication(local, 1, 'Warfarin');
      await addCheck(local);
      await db.execute('DROP TABLE user_foods');

      expect(await migration.adopt(account), 2);
      expect(await owners('user_medications'), [account]);
      expect(await owners('check_logs'), [account]);
    });
  });

  group('discard', () {
    test('removes the local record and nothing else', () async {
      await addMedication(account, 3, 'Ibuprofen');
      await addMedication(local, 1, 'Warfarin');
      await addAllergy(local, 'Penicillin');
      await addCheck(local);

      final removed = await migration.discard();

      expect(removed, 3);
      expect(await owners('user_medications'), [account]);
      expect(await owners('user_allergies'), isEmpty);
      expect(await owners('check_logs'), isEmpty);
      expect(changeNotifications, 1);
    });

    test('is silent when there is nothing to remove', () async {
      expect(await migration.discard(), 0);
      expect(changeNotifications, 0);
    });
  });
}
