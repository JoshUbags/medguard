import '../models/user_allergy.dart';
import 'database_service.dart';
import 'user_data_service.dart';

/// One reason a drug was flagged for the user — either a direct allergy match
/// (the drug itself is on the list) or a cross-reactivity hit (a class the
/// user is allergic to that this drug belongs to).
enum AllergyHitKind { direct, classMatch, crossReactivity }

class AllergyHit {
  const AllergyHit({
    required this.drugId,
    required this.drugName,
    required this.kind,
    required this.allergyLabel,
    required this.matchedCategory,
    this.note,
  });

  final int drugId;
  final String drugName;
  final AllergyHitKind kind;

  /// The user's allergy that triggered the flag (e.g. "Penicillin",
  /// "Sulfonamides").
  final String allergyLabel;

  /// The clinical category the drug shares with the allergy. For direct hits
  /// this is the drug name; for class/cross-reactivity it's the ATC or DrugBank
  /// category whose name overlaps the allergy.
  final String matchedCategory;

  final String? note;

  String get summary {
    switch (kind) {
      case AllergyHitKind.direct:
        return '$drugName is on your allergy list.';
      case AllergyHitKind.classMatch:
        return '$drugName belongs to "$matchedCategory" — '
            'you are allergic to "$allergyLabel".';
      case AllergyHitKind.crossReactivity:
        return '$drugName may cross-react with "$allergyLabel" '
            '(shared category: $matchedCategory).';
    }
  }
}

/// Known cross-reactivity groups. The keys are the *allergy labels* a user
/// would record (typically class names); each value is the list of DrugBank
/// `category` substrings (case-insensitive contains match) that should also
/// trigger a flag. Curated against the dissertation plan's list.
const Map<String, List<String>> _crossReactivityGroups = {
  'Penicillin': [
    'penicillin',
    'cephalosporin',
    'beta-lactam',
    'carbapenem',
  ],
  'Penicillins': [
    'penicillin',
    'cephalosporin',
    'beta-lactam',
    'carbapenem',
  ],
  'Cephalosporin': [
    'cephalosporin',
    'penicillin',
    'beta-lactam',
  ],
  'Sulfa': ['sulfonamide', 'sulfa'],
  'Sulfonamide': ['sulfonamide', 'sulfa'],
  'Sulfonamides': ['sulfonamide', 'sulfa'],
  'NSAID': [
    'non-steroidal anti-inflammatory',
    'nsaid',
    'cyclooxygenase inhibitor',
  ],
  'NSAIDs': [
    'non-steroidal anti-inflammatory',
    'nsaid',
    'cyclooxygenase inhibitor',
  ],
  'Aspirin': [
    'salicylate',
    'non-steroidal anti-inflammatory',
    'cyclooxygenase inhibitor',
  ],
  'Statin': [
    'hmg-coa reductase inhibitor',
    'statin',
  ],
  'Statins': [
    'hmg-coa reductase inhibitor',
    'statin',
  ],
};

/// Detects when a drug the user is about to take (or already saved) conflicts
/// with one of their recorded allergies. Direct matches are an exact drug-id
/// hit; class / cross-reactivity matches consult [DatabaseService.getDrugCategories]
/// so we can flag e.g. cephalosporins when the user is allergic to penicillin.
class AllergyChecker {
  AllergyChecker({DatabaseService? database, UserDataService? userData})
    : _db = database ?? DatabaseService.instance,
      _users = userData ?? UserDataService.instance;

  final DatabaseService _db;
  final UserDataService _users;

  /// Returns the canonical cross-reactivity tokens for [allergyLabel] — the
  /// substrings used to match against drug categories. Empty when the label
  /// has no known group (we fall back to a literal contains check).
  static List<String> crossReactivityTokensFor(String allergyLabel) {
    final entry = _crossReactivityGroups.entries.firstWhere(
      (e) => e.key.toLowerCase() == allergyLabel.toLowerCase(),
      orElse: () => const MapEntry('', []),
    );
    return entry.value;
  }

  /// Hits found for [drugId] against the user's allergy list. Empty when the
  /// drug is safe. Used at medication-add time to block / warn and on the
  /// safety report to surface lingering allergy conflicts.
  Future<List<AllergyHit>> checkDrug({
    required String userId,
    required int drugId,
    required String drugName,
  }) async {
    final allergies = await _users.getUserAllergies(userId);
    if (allergies.isEmpty) return const [];
    final categories = await _db.getDrugCategories(drugId);
    return _matchHits(
      allergies: allergies,
      drugId: drugId,
      drugName: drugName,
      categories: categories,
    );
  }

  /// Hits across an entire drug list — used by [InteractionChecker] when
  /// assembling the regimen-wide SafetyReport.
  Future<List<AllergyHit>> checkDrugs({
    required String userId,
    required List<({int id, String name})> drugs,
  }) async {
    final allergies = await _users.getUserAllergies(userId);
    if (allergies.isEmpty || drugs.isEmpty) return const [];
    final hits = <AllergyHit>[];
    for (final drug in drugs) {
      final categories = await _db.getDrugCategories(drug.id);
      hits.addAll(
        _matchHits(
          allergies: allergies,
          drugId: drug.id,
          drugName: drug.name,
          categories: categories,
        ),
      );
    }
    return hits;
  }

  /// Pure matching pass — exposed for unit tests that supply allergies +
  /// categories directly.
  static List<AllergyHit> matchHits({
    required List<UserAllergy> allergies,
    required int drugId,
    required String drugName,
    required List<String> categories,
  }) {
    return _matchHits(
      allergies: allergies,
      drugId: drugId,
      drugName: drugName,
      categories: categories,
    );
  }

  static List<AllergyHit> _matchHits({
    required List<UserAllergy> allergies,
    required int drugId,
    required String drugName,
    required List<String> categories,
  }) {
    final lowerCats = categories.map((c) => c.toLowerCase()).toList();
    final hits = <AllergyHit>[];
    final seen = <String>{}; // (allergyId, drugId) — one hit per allergy pair.

    for (final allergy in allergies) {
      // Direct drug match.
      if (allergy.drugId != null && allergy.drugId == drugId) {
        final key = '${allergy.id}@$drugId@direct';
        if (seen.add(key)) {
          hits.add(
            AllergyHit(
              drugId: drugId,
              drugName: drugName,
              kind: AllergyHitKind.direct,
              allergyLabel: allergy.label,
              matchedCategory: drugName,
              note: allergy.note,
            ),
          );
        }
        continue;
      }

      // Class / cross-reactivity match.
      final crossTokens = crossReactivityTokensFor(allergy.label)
          .map((t) => t.toLowerCase())
          .toList();
      final literalTokens = [allergy.label.toLowerCase()];

      for (final category in lowerCats) {
        if (crossTokens.any(category.contains)) {
          final original = categories[lowerCats.indexOf(category)];
          final key = '${allergy.id}@$drugId@cross@$original';
          if (seen.add(key)) {
            hits.add(
              AllergyHit(
                drugId: drugId,
                drugName: drugName,
                kind: AllergyHitKind.crossReactivity,
                allergyLabel: allergy.label,
                matchedCategory: original,
                note: allergy.note,
              ),
            );
          }
        } else if (literalTokens.any(category.contains)) {
          final original = categories[lowerCats.indexOf(category)];
          final key = '${allergy.id}@$drugId@class@$original';
          if (seen.add(key)) {
            hits.add(
              AllergyHit(
                drugId: drugId,
                drugName: drugName,
                kind: AllergyHitKind.classMatch,
                allergyLabel: allergy.label,
                matchedCategory: original,
                note: allergy.note,
              ),
            );
          }
        }
      }
    }

    return hits;
  }
}
