import '../services/allergy_checker.dart' show AllergyHit;
import 'duplicate_therapy_result.dart';
import 'food_interaction_result.dart';
import 'interaction_result.dart';
import 'severity.dart';

enum OverallRisk {
  safe('safe'),
  caution('caution'),
  warning('warning'),
  danger('danger');

  const OverallRisk(this.wireName);
  final String wireName;
}

/// One axis the regimen verdict weighs. Used both by the rules layer (to decide
/// the verdict) and by the UI (to show *everything* that was considered, even
/// the axes that came back clear).
enum SafetyFactorKind { interactions, duplicates, allergies, food }

/// A single considered safety axis: how many hits it found, and whether — under
/// the rules layer — it is severe enough to escalate the regimen to the HIGH tier.
class SafetyFactor {
  const SafetyFactor({
    required this.kind,
    required this.count,
    required this.escalates,
  });

  final SafetyFactorKind kind;
  final int count;

  /// True when this axis, on its own, escalates the regimen to the HIGH tier.
  final bool escalates;

  bool get triggered => count > 0;
}

/// Aggregated output of MedGuard's interaction, food, duplication, and
/// allergy checks. Allergy hits always escalate the overall risk to at least
/// [OverallRisk.warning] because they directly affect prescribing safety.
class SafetyReport {
  final List<InteractionResult> drugInteractions;
  final List<FoodInteractionResult> foodInteractions;
  final List<DuplicateTherapyResult> duplicateTherapies;
  final List<AllergyHit> allergyHits;
  final OverallRisk overallRisk;

  const SafetyReport({
    required this.drugInteractions,
    required this.foodInteractions,
    required this.duplicateTherapies,
    this.allergyHits = const [],
    required this.overallRisk,
  });

  const SafetyReport.empty()
    : drugInteractions = const [],
      foodInteractions = const [],
      duplicateTherapies = const [],
      allergyHits = const [],
      overallRisk = OverallRisk.safe;

  int get totalWarnings =>
      drugInteractions.length +
      foodInteractions.length +
      duplicateTherapies.length +
      allergyHits.length;

  String get overallRiskWire => overallRisk.wireName;

  // ── Rules layer ────────────────────────────────────────────────────────--
  // The ML model grades drug–drug risk (Low / Moderate / High); these
  // deterministic rules sit on top so therapeutic duplication and allergy
  // conflicts also escalate the regimen to the HIGH tier, while food cues remain
  // advisory cautions. Centralised here so every surface (home dial, critical
  // banner, status board, safety report) reads the exact same verdict.

  /// Whether any screened drug–drug pair sits in the HIGH risk tier
  /// (major / contraindicated).
  bool get hasHighRiskInteraction =>
      drugInteractions.any((i) => i.riskLevel.isHigh);

  /// The highest drug–drug risk tier present among the screened pairs, or null
  /// when no pair was found. Drives the graded risk dial and the verdict copy.
  RiskLevel? get highestInteractionRiskLevel {
    RiskLevel? highest;
    for (final i in drugInteractions) {
      final level = i.riskLevel;
      if (highest == null || level.rank > highest.rank) highest = level;
    }
    return highest;
  }

  /// The single tier the whole regimen reads as, across every screened axis.
  /// HIGH when a high-risk pair or an allergy conflict is present; MODERATE when
  /// a moderate pair OR a therapeutic duplication is present (an additive-dose
  /// risk); LOW otherwise. Food cues stay advisory and never raise the tier on
  /// their own.
  RiskLevel get regimenRiskLevel {
    if (isRegimenHighRisk) return RiskLevel.high;
    final highest = highestInteractionRiskLevel;
    if ((highest != null && highest.rank >= RiskLevel.moderate.rank) ||
        hasDuplication) {
      return RiskLevel.moderate;
    }
    return RiskLevel.low;
  }

  /// True when at least one axis found something — of any severity.
  ///
  /// This is what separates "we checked and there is genuinely nothing" from
  /// "we found only minor things". Both sit in the LOW tier, but they are not
  /// the same message to a patient, and [verdictLabel] tells them apart.
  bool get hasAnyFinding => totalWarnings > 0;

  /// **THE** verdict wording, for every surface that states one.
  ///
  /// This exists because there used to be two: the risk gauge read the
  /// three-tier [regimenRiskLevel], while the safety report read the four-level
  /// [overallRisk] through its own label map. On a regimen whose only finding
  /// was a minor pair or a food note, the gauge said "All Clear" and the report
  /// said "Low risk" — about the same medicines, at the same moment, from the
  /// same object. For a safety tool that is not a cosmetic inconsistency; it is
  /// the app contradicting itself about whether the user is safe.
  ///
  /// [overallRisk] remains the persisted wire format for check history (it
  /// distinguishes four states and is already written to the database). It is
  /// no longer allowed to produce user-facing words.
  String get verdictLabel => switch (regimenRiskLevel) {
    RiskLevel.high => 'High risk',
    RiskLevel.moderate => 'Moderate risk',
    RiskLevel.low => hasAnyFinding ? 'Low risk' : 'All clear',
  };

  /// The user is taking a drug they're allergic to (directly or by class /
  /// cross-reactivity). Always escalates the regimen to the HIGH tier.
  bool get hasAllergyConflict => allergyHits.isNotEmpty;

  /// Two drugs duplicate the same therapeutic class — an additive-dose risk
  /// surfaced as a MODERATE concern. (A genuinely dangerous same-class combo —
  /// e.g. two anticoagulants — is independently caught as a major interaction,
  /// so it still reaches HIGH via [hasHighRiskInteraction].)
  bool get hasDuplication => duplicateTherapies.isNotEmpty;

  /// A drug–food cue exists. Considered and surfaced, but advisory: it does not
  /// by itself raise the regimen tier.
  bool get hasFoodConsideration => foodInteractions.isNotEmpty;

  /// Whether the regimen reaches the HIGH tier overall: a high-risk pair or an
  /// allergy conflict. (Therapeutic duplication is a MODERATE concern — see
  /// [regimenRiskLevel] — so it does not by itself make the regimen HIGH.)
  bool get isRegimenHighRisk => hasHighRiskInteraction || hasAllergyConflict;

  /// Every axis the verdict weighed — including the ones that came back clear —
  /// in display order, so the UI can show the full "what we checked" picture.
  List<SafetyFactor> get consideredFactors => [
    SafetyFactor(
      kind: SafetyFactorKind.interactions,
      count: drugInteractions.length,
      escalates: hasHighRiskInteraction,
    ),
    SafetyFactor(
      kind: SafetyFactorKind.duplicates,
      count: duplicateTherapies.length,
      // Duplication is a MODERATE concern, so it does not escalate to HIGH.
      escalates: false,
    ),
    SafetyFactor(
      kind: SafetyFactorKind.allergies,
      count: allergyHits.length,
      escalates: hasAllergyConflict,
    ),
    SafetyFactor(
      kind: SafetyFactorKind.food,
      count: foodInteractions.length,
      escalates: false,
    ),
  ];

  factory SafetyReport.fromAnalysis({
    required List<InteractionResult> drugInteractions,
    required List<FoodInteractionResult> foodInteractions,
    required List<DuplicateTherapyResult> duplicateTherapies,
    List<AllergyHit> allergyHits = const [],
  }) {
    final sortedDdi = [...drugInteractions]
      ..sort((a, b) => b.severityLevel.rank.compareTo(a.severityLevel.rank));

    return SafetyReport(
      drugInteractions: List.unmodifiable(sortedDdi),
      foodInteractions: List.unmodifiable(foodInteractions),
      duplicateTherapies: List.unmodifiable(duplicateTherapies),
      allergyHits: List.unmodifiable(allergyHits),
      overallRisk: _computeOverallRisk(
        sortedDdi,
        foodInteractions,
        duplicateTherapies,
        allergyHits,
      ),
    );
  }

  static OverallRisk _computeOverallRisk(
    List<InteractionResult> ddis,
    List<FoodInteractionResult> food,
    List<DuplicateTherapyResult> duplicates,
    List<AllergyHit> allergies,
  ) {
    if (ddis.isEmpty &&
        food.isEmpty &&
        duplicates.isEmpty &&
        allergies.isEmpty) {
      return OverallRisk.safe;
    }

    var highest = 0;
    for (final ddi in ddis) {
      if (ddi.severityLevel.rank > highest) highest = ddi.severityLevel.rank;
    }

    // Rules layer: a high-risk pair or an allergy conflict escalates the regimen
    // to the HIGH tier (danger). Therapeutic duplication and moderate pairs read
    // as a warning (MODERATE); lone food/minor cues are a calm caution.
    if (highest >= Severity.major.rank || allergies.isNotEmpty) {
      return OverallRisk.danger;
    }
    if (highest >= Severity.moderate.rank || duplicates.isNotEmpty) {
      return OverallRisk.warning;
    }
    return OverallRisk.caution;
  }
}
