import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/drug.dart';
import '../models/drug_monograph.dart';
import '../models/duplicate_therapy_result.dart';
import '../models/food_interaction_result.dart';
import '../models/interaction_result.dart';
import '../models/regimen_analysis.dart';
import '../utils/lru_cache.dart';

/// Read-only access to the bundled MedGuard clinical reference database.
class DatabaseService {
  DatabaseService._({
    String dbAssetPath = _defaultDbAssetPath,
    String dbFileName = _defaultDbFileName,
    DatabaseFactory? databaseFactory,
    String? directDatabasePath,
    Future<Directory> Function()? directoryProvider,
  }) : _dbAssetPath = dbAssetPath,
       _dbFileName = dbFileName,
       _databaseFactory = databaseFactory,
       _directDatabasePath = directDatabasePath,
       _directoryProvider = directoryProvider;

  DatabaseService.fromDatabasePath(
    String databasePath, {
    required DatabaseFactory databaseFactory,
  }) : this._(
         databaseFactory: databaseFactory,
         directDatabasePath: databasePath,
       );

  static final DatabaseService instance = DatabaseService._();

  static const String _defaultDbAssetPath = 'assets/db/medguard.db';
  static const String _defaultDbFileName = 'medguard.db';

  final String _dbAssetPath;
  final String _dbFileName;
  final DatabaseFactory? _databaseFactory;
  final String? _directDatabasePath;
  final Future<Directory> Function()? _directoryProvider;

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final db = await _openBundledDatabase();
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

  /// Opens the database, performing the one-time ~100 MB asset copy on first
  /// launch. Call (via [warmUp]) from a background moment — e.g. right after
  /// the first frame — so the first real query never pays for the copy.
  Future<Database> _openBundledDatabase() async {
    if (_directDatabasePath != null) {
      return _openDatabase(_directDatabasePath);
    }

    final docs =
        await (_directoryProvider ?? getApplicationDocumentsDirectory)();
    final dbPath = p.join(docs.path, _dbFileName);

    final file = File(dbPath);
    if (!await file.exists()) {
      final data = await rootBundle.load(_dbAssetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      // Copy via a temp file + atomic rename: if the app is killed mid-copy,
      // no half-written medguard.db is left behind to satisfy the exists()
      // check above and permanently corrupt every future query.
      final tmp = File('$dbPath.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(dbPath);
    }

    return _openDatabase(dbPath);
  }

  /// Kicks off the open (and the first-launch asset copy) in the background.
  /// Never throws — a genuine failure will surface on the first real query,
  /// where callers already handle errors.
  Future<void> warmUp() async {
    try {
      await database;
    } catch (_) {}
  }

  Future<Database> _openDatabase(String dbPath) {
    final factory = _databaseFactory;
    if (factory != null) {
      return factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: true),
      );
    }
    return openDatabase(dbPath, readOnly: true, singleInstance: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // Search results are stable for a given (query, limit) on the bundled
  // read-only DB. A small LRU keeps the common keystroke prefixes hot so
  // repeated typing doesn't re-run the same SQL.
  final LruCache<String, List<Drug>> _searchCache = LruCache(capacity: 64);
  bool? _supportsFts;

  /// One-time probe: can we use the FTS5 query path? Requires both that the
  /// bundled DB carries the `drugs_fts` virtual table AND that this SQLite build
  /// actually has the fts5 module. The module check matters because some builds
  /// (notably `winsqlite3`, used by the desktop/test FFI) ship without fts5 — in
  /// that case we silently fall back to the LIKE path so search still works.
  Future<bool> _hasFts5() async {
    final cached = _supportsFts;
    if (cached != null) return cached;
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT name FROM sqlite_master '
      "WHERE type='table' AND name='drugs_fts' LIMIT 1",
    );
    var result = rows.isNotEmpty;
    if (result) {
      try {
        await db.rawQuery(
          "SELECT rowid FROM drugs_fts WHERE drugs_fts MATCH 'a' LIMIT 1",
        );
      } catch (_) {
        // Table present but the fts5 module isn't loaded — use LIKE instead.
        result = false;
      }
    }
    _supportsFts = result;
    return result;
  }

  Future<List<Drug>> searchDrugs(String query, {int limit = 25}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final cacheKey = '${trimmed.toLowerCase()}|$limit';
    final cached = _searchCache.get(cacheKey);
    if (cached != null) return cached;

    final db = await database;
    final List<Map<String, Object?>> rows;
    if (await _hasFts5()) {
      // FTS5 path — prefix search (`token*`) gives autocomplete-fast results.
      // We escape any FTS reserved characters by quoting the term.
      final ftsTerm = '"${trimmed.replaceAll('"', '""')}"*';
      rows = await db.rawQuery(
        '''
        SELECT DISTINCT
          d.id, d.drugbank_id, d.name, d.description,
          d.indication, d.atc_code, d.rxcui
        FROM drugs d
        WHERE d.id IN (SELECT rowid FROM drugs_fts WHERE drugs_fts MATCH ?)
           OR d.id IN (
             SELECT s.drug_id
             FROM drug_synonyms s
             JOIN drug_synonyms_fts fs ON fs.rowid = s.id
             WHERE drug_synonyms_fts MATCH ?
           )
        ORDER BY
          CASE WHEN d.name LIKE ? COLLATE NOCASE THEN 0 ELSE 1 END,
          LENGTH(d.name),
          d.name COLLATE NOCASE
        LIMIT ?
        ''',
        [ftsTerm, ftsTerm, '$trimmed%', limit],
      );
    } else {
      // Legacy LIKE path — used until the bundled DB is rebuilt with FTS5.
      final like = '$trimmed%';
      final contains = '%$trimmed%';
      rows = await db.rawQuery(
        '''
        SELECT DISTINCT
          d.id, d.drugbank_id, d.name, d.description,
          d.indication, d.atc_code, d.rxcui
        FROM drugs d
        LEFT JOIN drug_synonyms s ON s.drug_id = d.id
        WHERE d.name LIKE ? COLLATE NOCASE
           OR s.synonym LIKE ? COLLATE NOCASE
        ORDER BY
          CASE WHEN d.name LIKE ? COLLATE NOCASE THEN 0 ELSE 1 END,
          LENGTH(d.name),
          d.name COLLATE NOCASE
        LIMIT ?
        ''',
        [like, contains, like, limit],
      );
    }

    final results = rows.map(Drug.fromMap).toList(growable: false);
    _searchCache.put(cacheKey, results);
    return results;
  }

  /// All synonyms (brands, products, secondary IDs) for the given drug —
  /// powers the "Also known as" section on the monograph.
  Future<List<({String synonym, String? source})>> getDrugSynonyms(
    int drugId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'drug_synonyms',
      columns: ['synonym', 'source'],
      where: 'drug_id = ?',
      whereArgs: [drugId],
      orderBy: 'synonym COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => (
            synonym: r['synonym'] as String,
            source: r['source'] as String?,
          ),
        )
        .toList(growable: false);
  }

  /// Severity breakdown of all interactions involving [drugId] — used in the
  /// monograph's "Known interactions" summary chip row.
  Future<Map<String, int>> getInteractionSummaryForDrug(int drugId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT severity, COUNT(*) AS c FROM interactions
      WHERE drug_a_id = ? OR drug_b_id = ?
      GROUP BY severity
      ''',
      [drugId, drugId],
    );
    return {
      for (final row in rows)
        (row['severity'] as String): (row['c'] as int?) ?? 0,
    };
  }

  /// Loads the full drug record — every column on the `drugs` table — for the
  /// monograph screen. Returns null when the drug id isn't found.
  Future<DrugMonograph?> getDrugMonograph(int id) async {
    final db = await database;
    final rows = await db.query('drugs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DrugMonograph.fromMap(rows.first);
  }

  Future<Drug?> getDrugById(int id) async {
    final db = await database;
    final rows = await db.query(
      'drugs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Drug.fromMap(rows.first);
  }

  Future<Drug?> findByDrugbankId(String drugbankId) async {
    final db = await database;
    final rows = await db.query(
      'drugs',
      where: 'drugbank_id = ?',
      whereArgs: [drugbankId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Drug.fromMap(rows.first);
  }

  Future<Drug?> findByRxcui(String rxcui) async {
    final db = await database;
    final rows = await db.query(
      'drugs',
      where: 'rxcui = ?',
      whereArgs: [rxcui],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Drug.fromMap(rows.first);
  }

  Future<List<InteractionResult>> getInteractions(
    int drugAId,
    int drugBId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        i.drug_a_id, i.drug_b_id,
        da.name AS drug_a_name,
        dbx.name AS drug_b_name,
        i.severity, i.mechanism, i.clinical_effect AS effect, i.description
      FROM interactions i
      JOIN drugs da  ON da.id  = i.drug_a_id
      JOIN drugs dbx ON dbx.id = i.drug_b_id
      WHERE (i.drug_a_id = ? AND i.drug_b_id = ?)
         OR (i.drug_a_id = ? AND i.drug_b_id = ?)
      ''',
      [drugAId, drugBId, drugBId, drugAId],
    );
    return rows.map(InteractionResult.fromMap).toList(growable: false);
  }

  Future<List<InteractionResult>> checkAllInteractions(
    List<int> drugIds,
  ) async {
    if (drugIds.length < 2) return const [];
    final db = await database;
    final placeholders = List.filled(drugIds.length, '?').join(',');

    final rows = await db.rawQuery(
      '''
      SELECT
        MIN(i.drug_a_id, i.drug_b_id) AS drug_a_id,
        MAX(i.drug_a_id, i.drug_b_id) AS drug_b_id,
        da.name AS drug_a_name,
        dbx.name AS drug_b_name,
        i.severity, i.mechanism, i.clinical_effect AS effect, i.description
      FROM interactions i
      JOIN drugs da  ON da.id  = MIN(i.drug_a_id, i.drug_b_id)
      JOIN drugs dbx ON dbx.id = MAX(i.drug_a_id, i.drug_b_id)
      WHERE i.drug_a_id IN ($placeholders)
        AND i.drug_b_id IN ($placeholders)
      GROUP BY
        MIN(i.drug_a_id, i.drug_b_id),
        MAX(i.drug_a_id, i.drug_b_id),
        i.severity, i.mechanism, i.clinical_effect, i.description
      ''',
      [...drugIds, ...drugIds],
    );

    return rows.map(InteractionResult.fromMap).toList(growable: false);
  }

  Future<List<FoodInteractionResult>> getFoodInteractions(int drugId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT fi.drug_id, d.name AS drug_name, fi.description
      FROM food_interactions fi
      JOIN drugs d ON d.id = fi.drug_id
      WHERE fi.drug_id = ?
      ''',
      [drugId],
    );
    return rows.map(FoodInteractionResult.fromMap).toList(growable: false);
  }

  Future<List<FoodInteractionResult>> getAllFoodInteractions(
    List<int> drugIds,
  ) async {
    if (drugIds.isEmpty) return const [];
    final db = await database;
    final placeholders = List.filled(drugIds.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT fi.drug_id, d.name AS drug_name, fi.description
      FROM food_interactions fi
      JOIN drugs d ON d.id = fi.drug_id
      WHERE fi.drug_id IN ($placeholders)
      ORDER BY d.name COLLATE NOCASE
      ''', drugIds);
    return rows.map(FoodInteractionResult.fromMap).toList(growable: false);
  }

  /// Returns the CYP450 metabolism rows for the supplied drugs. Filters to
  /// `enzyme_type='enzymes'` and CYP-named entries so non-metabolic targets
  /// (receptors, carriers, transporters) are ignored.
  Future<List<DrugEnzymeRecord>> getDrugEnzymes(List<int> drugIds) async {
    if (drugIds.isEmpty) return const [];
    final db = await database;
    final placeholders = List.filled(drugIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT de.drug_id, d.name AS drug_name, de.enzyme_name, de.actions
      FROM drug_enzymes de
      JOIN drugs d ON d.id = de.drug_id
      WHERE de.drug_id IN ($placeholders)
        AND de.enzyme_type = 'enzymes'
        AND de.enzyme_name LIKE 'Cytochrome P450 %'
      ''',
      drugIds,
    );
    return rows
        .map(
          (row) => DrugEnzymeRecord(
            drugId: row['drug_id'] as int,
            drugName: row['drug_name'] as String,
            enzymeName: row['enzyme_name'] as String,
            actions: (row['actions'] as String? ?? '')
                .split('|')
                .map((s) => s.trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet(),
          ),
        )
        .toList(growable: false);
  }

  /// Returns ALL metabolic-enzyme rows (`enzyme_type='enzymes'`), not just
  /// CYP450 — used by the ML feature builder, whose enzyme index also covers
  /// UGTs, cholinesterase, etc. Keyed by `enzyme_name` to match the trained
  /// model's `enzyme_index.json`.
  Future<List<DrugEnzymeRecord>> getMetabolicEnzymes(List<int> drugIds) async {
    if (drugIds.isEmpty) return const [];
    final db = await database;
    final placeholders = List.filled(drugIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT de.drug_id, d.name AS drug_name, de.enzyme_name, de.actions
      FROM drug_enzymes de
      JOIN drugs d ON d.id = de.drug_id
      WHERE de.drug_id IN ($placeholders)
        AND de.enzyme_type = 'enzymes'
      ''',
      drugIds,
    );
    return rows
        .map(
          (row) => DrugEnzymeRecord(
            drugId: row['drug_id'] as int,
            drugName: row['drug_name'] as String,
            enzymeName: row['enzyme_name'] as String,
            actions: (row['actions'] as String? ?? '')
                .split('|')
                .map((s) => s.trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<String>> getDrugCategories(int drugId) async {
    final db = await database;
    final rows = await db.query(
      'drug_categories',
      columns: ['category'],
      where: 'drug_id = ?',
      whereArgs: [drugId],
    );
    return rows.map((r) => r['category'] as String).toList(growable: false);
  }

  /// A DrugBank category broader than this many drugs is treated as a generic
  /// metabolic/chemical grouping (not a specific therapeutic class) and ignored
  /// for duplicate-therapy detection. Tuned so real classes (statins ~30, PPIs
  /// ~15) qualify while broad noise (CYP substrates ~1,000) does not.
  static const int _duplicateCategoryMaxMembers = 40;

  Future<List<DuplicateTherapyResult>> checkDuplicateTherapy(
    List<int> drugIds,
  ) async {
    if (drugIds.length < 2) return const [];
    final db = await database;
    final placeholders = List.filled(drugIds.length, '?').join(',');

    // A genuine duplicate therapy is two drugs in the same SPECIFIC therapeutic
    // class (e.g. two proton-pump inhibitors, two statins). We match on shared
    // DrugBank `drug_categories`, but only on *specific* classes: a category is
    // ignored when it is too broad (more than [_duplicateCategoryMaxMembers]
    // drugs — e.g. "Cytochrome P-450 Substrates" spans ~1,000) or is a
    // combination category (name containing " and " / "combination", e.g. "ACE
    // Inhibitors and Calcium Channel Blockers"). The previous query matched on
    // ANY shared category, so the broad metabolic/chemical ones flagged ~47% of
    // arbitrary pairs as duplicates and wrongly escalated almost every regimen
    // to High. This filter drops the false-positive rate to ~1% while still
    // catching real same-class duplicates.
    final rows = await db.rawQuery(
      '''
      SELECT dc.drug_id AS drug_id, d.name AS name, dc.category AS category,
             cs.n AS n
      FROM drug_categories dc
      JOIN drugs d ON d.id = dc.drug_id
      JOIN (
        SELECT category, COUNT(*) AS n FROM drug_categories GROUP BY category
      ) cs ON cs.category = dc.category
      WHERE dc.drug_id IN ($placeholders)
      ''',
      drugIds,
    );

    final names = <int, String>{};
    final drugCategories = <int, Set<String>>{};
    final categorySize = <String, int>{};
    for (final row in rows) {
      final id = row['drug_id'] as int;
      final category = row['category'] as String;
      names[id] = row['name'] as String;
      categorySize[category] = row['n'] as int;
      drugCategories.putIfAbsent(id, () => <String>{}).add(category);
    }

    // Exclude broad metabolic / pharmacokinetic groupings (CYP enzymes, drug
    // transporters, substrate/inducer lists) and combination categories — these
    // are not therapeutic classes and would create false duplicate matches.
    const excludedFragments = [
      ' and ',
      'combination',
      'cytochrome',
      'cyp',
      'p-glycoprotein',
      'glycoprotein',
      'substrate',
      'inducer',
      'transporter',
    ];
    bool isSpecificClass(String category) {
      if ((categorySize[category] ?? 1 << 30) > _duplicateCategoryMaxMembers) {
        return false;
      }
      final lower = category.toLowerCase();
      return !excludedFragments.any(lower.contains);
    }

    // Prefer a recognisable class name for display (e.g. "Proton Pump
    // Inhibitors") over an obscure chemical synonym.
    const classKeywords = [
      'inhibitor',
      'blocker',
      'antagonist',
      'agonist',
      'reuptake',
      'statin',
      'reductase',
      'diuretic',
      'steroid',
    ];

    final ids = drugCategories.keys.toList()..sort();
    final results = <DuplicateTherapyResult>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i];
        final b = ids[j];
        final shared =
            drugCategories[a]!.intersection(drugCategories[b]!).where(
              isSpecificClass,
            ).toList()..sort(
              (x, y) => categorySize[x]!.compareTo(categorySize[y]!),
            );
        if (shared.isEmpty) continue;
        final label = shared.firstWhere(
          (category) =>
              classKeywords.any(category.toLowerCase().contains),
          orElse: () => shared.last,
        );
        results.add(
          DuplicateTherapyResult(
            drugAId: a,
            drugBId: b,
            drugAName: names[a]!,
            drugBName: names[b]!,
            category: label,
          ),
        );
      }
    }
    return results;
  }

  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;

    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as int?) ?? 0;
    }

    // `interactions` is a VIEW over the physical `interactions_data` table
    // (a 1:1 projection, so both report the same row count). COUNT(*) through
    // the view forces a full scan of every row's text payload — tens of
    // seconds over ~850k rows — while counting the physical table lets SQLite
    // use its indexed fast-count and returns in milliseconds. Falls back to
    // the view if a future database build drops the physical table.
    Future<int> countInteractions() async {
      try {
        return await count('interactions_data');
      } catch (_) {
        return count('interactions');
      }
    }

    final counts = await Future.wait<int>([
      count('drugs'),
      countInteractions(),
      count('food_interactions'),
      count('drug_categories'),
      count('drug_synonyms'),
      count('drug_enzymes'),
    ]);
    return {
      'drugs': counts[0],
      'interactions': counts[1],
      'food_interactions': counts[2],
      'drug_categories': counts[3],
      'drug_synonyms': counts[4],
      'enzymes': counts[5],
    };
  }
}
