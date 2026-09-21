import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/user_allergy.dart';
import 'package:mobile/services/allergy_checker.dart';

UserAllergy _drugAllergy(int id, String label, int drugId) => UserAllergy(
  id: id,
  userId: 'u1',
  drugId: drugId,
  label: label,
  addedAt: DateTime(2026, 1, 1),
);

UserAllergy _classAllergy(int id, String label) => UserAllergy(
  id: id,
  userId: 'u1',
  className: label,
  label: label,
  addedAt: DateTime(2026, 1, 1),
);

void main() {
  group('AllergyChecker.matchHits', () {
    test('direct drug allergy flags the same drug id', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_drugAllergy(1, 'Amoxicillin', 42)],
        drugId: 42,
        drugName: 'Amoxicillin',
        categories: const ['Penicillin Antibacterials'],
      );

      expect(hits, hasLength(1));
      expect(hits.first.kind, AllergyHitKind.direct);
      expect(hits.first.allergyLabel, 'Amoxicillin');
    });

    test('penicillin class allergy flags a cephalosporin', () {
      // Cefalexin shares the beta-lactam ring with penicillins; classic
      // cross-reactivity case from the dissertation plan.
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'Penicillin')],
        drugId: 99,
        drugName: 'Cefalexin',
        categories: const ['Cephalosporins', 'Beta-Lactam Antibacterials'],
      );

      expect(hits, isNotEmpty);
      expect(
        hits.map((h) => h.kind),
        contains(AllergyHitKind.crossReactivity),
      );
      expect(hits.first.allergyLabel, 'Penicillin');
    });

    test('sulfa allergy flags a sulfonamide', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'Sulfa')],
        drugId: 50,
        drugName: 'Sulfamethoxazole',
        categories: const ['Sulfonamide Antibacterials'],
      );

      expect(hits, isNotEmpty);
      expect(hits.first.kind, AllergyHitKind.crossReactivity);
    });

    test('NSAID allergy flags a COX inhibitor by alternate phrasing', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'NSAID')],
        drugId: 7,
        drugName: 'Naproxen',
        categories: const ['Cyclooxygenase Inhibitors'],
      );

      expect(hits, hasLength(1));
      expect(hits.first.matchedCategory, 'Cyclooxygenase Inhibitors');
    });

    test('unrelated drug does not trigger any hit', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'Penicillin')],
        drugId: 200,
        drugName: 'Metformin',
        categories: const ['Biguanides'],
      );

      expect(hits, isEmpty);
    });

    test('aspirin allergy still picks up salicylate categorisation', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'Aspirin')],
        drugId: 11,
        drugName: 'Diflunisal',
        categories: const ['Salicylates'],
      );

      expect(hits, isNotEmpty);
      expect(hits.first.kind, AllergyHitKind.crossReactivity);
    });

    test('multiple categories on a drug only produce one hit per allergy', () {
      final hits = AllergyChecker.matchHits(
        allergies: [_classAllergy(1, 'Penicillin')],
        drugId: 99,
        drugName: 'Cefalexin',
        categories: const [
          'Cephalosporins',
          'Beta-Lactam Antibacterials',
          'Antibacterials for Systemic Use',
        ],
      );

      // Two of the three categories overlap; we want one hit per unique
      // category, not one per token match.
      expect(hits.map((h) => h.matchedCategory).toSet(), {
        'Cephalosporins',
        'Beta-Lactam Antibacterials',
      });
    });

    test('summary text is human-readable for each kind', () {
      const direct = AllergyHit(
        drugId: 1,
        drugName: 'Amoxicillin',
        kind: AllergyHitKind.direct,
        allergyLabel: 'Amoxicillin',
        matchedCategory: 'Amoxicillin',
      );
      expect(direct.summary, contains('on your allergy list'));

      const cross = AllergyHit(
        drugId: 1,
        drugName: 'Cefalexin',
        kind: AllergyHitKind.crossReactivity,
        allergyLabel: 'Penicillin',
        matchedCategory: 'Cephalosporins',
      );
      expect(cross.summary, contains('cross-react'));
      expect(cross.summary, contains('Penicillin'));
    });
  });

  group('AllergyChecker.crossReactivityTokensFor', () {
    test('case-insensitive lookup returns the curated token list', () {
      final lower = AllergyChecker.crossReactivityTokensFor('penicillin');
      final mixed = AllergyChecker.crossReactivityTokensFor('Penicillin');
      expect(lower, equals(mixed));
      expect(lower, contains('cephalosporin'));
    });

    test('unknown label returns an empty list (fallback to literal match)', () {
      expect(AllergyChecker.crossReactivityTokensFor('Mango'), isEmpty);
    });
  });
}
