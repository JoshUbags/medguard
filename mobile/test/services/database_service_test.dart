import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/severity.dart';

import '../helpers/real_database.dart';

void main() {
  if (realDatabaseSkip != null) {
    test('bundled database', () {}, skip: realDatabaseSkip);
    return;
  }
  final database = createRealDatabaseService();

  tearDownAll(database.close);

  test('opens the bundled database and reports core table counts', () async {
    final stats = await database.getDatabaseStats();

    expect(stats['drugs'], 4955);
    expect(stats['interactions'], greaterThan(800000));
    expect(stats['food_interactions'], greaterThan(2000));
    // The regenerated bundled database (2026-07) carries ~252k synonyms —
    // the pre-cleanup figure of 700k+ no longer reflects the shipped asset.
    expect(stats['drug_synonyms'], greaterThan(200000));
  });

  test('search finds Acetaminophen through Tylenol synonyms', () async {
    final results = await database.searchDrugs('Tylenol', limit: 25);

    expect(results.map((drug) => drug.name), contains('Acetaminophen'));
  });

  test('empty search returns no results without opening a query', () async {
    final results = await database.searchDrugs('   ');

    expect(results, isEmpty);
  });

  test('searching ibu prioritizes Ibuprofen in autocomplete', () async {
    final results = await database.searchDrugs('ibu', limit: 10);

    expect(results, isNotEmpty);
    expect(results.first.name, 'Ibuprofen');
  });

  test(
    'Warfarin and Ibuprofen interaction comes from SQLite with severity',
    () async {
      final warfarin = await findExactDrug(database, 'Warfarin');
      final ibuprofen = await findExactDrug(database, 'Ibuprofen');

      final interactions = await database.getInteractions(
        warfarin.id,
        ibuprofen.id,
      );

      expect(interactions, isNotEmpty);
      expect(interactions.first.severityLevel, Severity.major);
      expect(interactions.first.mechanism, isNotEmpty);
      expect(interactions.first.effect, isNotEmpty);
    },
  );
}
