import 'dart:io';

import 'package:mobile/models/drug.dart';
import 'package:mobile/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _realDatabasePath = 'assets/db/medguard.db';

/// Null when the bundled clinical database is present; otherwise the reason
/// every test that reads real clinical data is skipped.
///
/// The database ships in the repository, so this only trips when it has been
/// removed or replaced by a stub. A real database is tens of megabytes, so
/// anything smaller counts as missing, and those tests skip with a reason that
/// says so rather than failing with one that says nothing about the code.
final String? realDatabaseSkip = _hasRealDatabase()
    ? null
    : 'Bundled clinical database ($_realDatabasePath) is missing or a stub; '
          'restore it, or rebuild it with data_pipeline, to run these tests.';

bool _hasRealDatabase() {
  final file = File(_realDatabasePath);
  return file.existsSync() && file.lengthSync() > 1024 * 1024;
}

DatabaseService createRealDatabaseService() {
  sqfliteFfiInit();
  return DatabaseService.fromDatabasePath(
    File(_realDatabasePath).absolute.path,
    databaseFactory: databaseFactoryFfi,
  );
}

Future<Drug> findExactDrug(DatabaseService database, String name) async {
  final results = await database.searchDrugs(name, limit: 50);
  return results.firstWhere(
    (drug) => drug.name.toLowerCase() == name.toLowerCase(),
  );
}
