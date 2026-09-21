import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user_allergy.dart';
import 'package:mobile/services/allergy_checker.dart';

import '../helpers/real_database.dart';

/// End-to-end allergy flow:
///   user records a penicillin allergy → adds a cephalosporin → the safety
///   report should surface a cross-reactivity hit.
///
/// We exercise the real bundled DrugBank database (categories come straight
/// from `drug_categories`) and the pure matching layer of [AllergyChecker]
/// so the test reflects what end users actually see, without needing to
/// stand up the SQLite-on-documents-dir user store inside a unit test.
void main() {
  if (realDatabaseSkip != null) {
    test('allergy integration', () {}, skip: realDatabaseSkip);
    return;
  }
  final database = createRealDatabaseService();

  tearDownAll(database.close);

  UserAllergy classAllergy(String label) => UserAllergy(
    id: 1,
    userId: 'u1',
    className: label,
    label: label,
    addedAt: DateTime(2026, 1, 1),
  );

  test('penicillin allergy + Cephalexin → cross-reactivity hit', () async {
    final cefalexin = await findExactDrug(database, 'Cephalexin');
    final categories = await database.getDrugCategories(cefalexin.id);
    expect(categories, isNotEmpty,
        reason: 'Cephalexin should have DrugBank categories');

    final hits = AllergyChecker.matchHits(
      allergies: [classAllergy('Penicillin')],
      drugId: cefalexin.id,
      drugName: cefalexin.name,
      categories: categories,
    );

    expect(hits, isNotEmpty);
    expect(
      hits.map((h) => h.kind),
      contains(AllergyHitKind.crossReactivity),
    );
  });

  test('sulfa allergy + Sulfamethoxazole → cross-reactivity hit', () async {
    final smx = await findExactDrug(database, 'Sulfamethoxazole');
    final categories = await database.getDrugCategories(smx.id);

    final hits = AllergyChecker.matchHits(
      allergies: [classAllergy('Sulfa')],
      drugId: smx.id,
      drugName: smx.name,
      categories: categories,
    );

    expect(hits, isNotEmpty);
  });

  test('NSAID allergy + Naproxen → flagged', () async {
    final naproxen = await findExactDrug(database, 'Naproxen');
    final categories = await database.getDrugCategories(naproxen.id);

    final hits = AllergyChecker.matchHits(
      allergies: [classAllergy('NSAID')],
      drugId: naproxen.id,
      drugName: naproxen.name,
      categories: categories,
    );

    expect(hits, isNotEmpty);
  });

  test('penicillin allergy does NOT flag Metformin', () async {
    final metformin = await findExactDrug(database, 'Metformin');
    final categories = await database.getDrugCategories(metformin.id);

    final hits = AllergyChecker.matchHits(
      allergies: [classAllergy('Penicillin')],
      drugId: metformin.id,
      drugName: metformin.name,
      categories: categories,
    );

    expect(hits, isEmpty);
  });
}
