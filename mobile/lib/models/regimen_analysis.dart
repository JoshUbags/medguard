/// Bands the cumulative risk score falls into. Drives the home gauge label
/// and the colour applied to the regimen summary.
enum RegimenRiskBand {
  calm('Calm regimen'),
  watch('Watch list'),
  elevated('Elevated risk'),
  critical('Critical risk');

  const RegimenRiskBand(this.label);

  final String label;
}

/// One metabolic interaction site where multiple of the user's medicines act
/// on the same CYP450 enzyme — e.g. drug A inhibits CYP3A4 while drug B is a
/// substrate of CYP3A4, so A may raise plasma levels of B.
class CypCascade {
  const CypCascade({
    required this.enzymeName,
    required this.shortName,
    required this.inhibitors,
    required this.substrates,
    required this.inducers,
  });

  final String enzymeName; // e.g. 'Cytochrome P450 3A4'
  final String shortName; // e.g. 'CYP3A4'
  final List<String> inhibitors;
  final List<String> substrates;
  final List<String> inducers;

  /// True when there is at least one inhibitor or inducer acting on at least
  /// one substrate the user also takes.
  bool get isCascade =>
      substrates.isNotEmpty &&
      (inhibitors.isNotEmpty || inducers.isNotEmpty);

  String get summary {
    final modulators = [...inhibitors, ...inducers];
    final modulatorWord = inhibitors.isNotEmpty
        ? (inducers.isNotEmpty ? 'modulates' : 'inhibits')
        : 'induces';
    return '${modulators.join(", ")} $modulatorWord $shortName · '
        'affects ${substrates.join(", ")}';
  }
}

/// Output of [RegimenAnalyser.analyze] — a regimen-wide safety snapshot.
class RegimenAnalysis {
  const RegimenAnalysis({
    required this.medicationCount,
    required this.flaggedPairs,
    required this.duplicateTherapies,
    required this.foodInteractions,
    required this.cascades,
    required this.cumulativeScore,
    required this.band,
    required this.contributors,
  });

  /// Number of medicines analysed.
  final int medicationCount;

  /// Drug-drug interaction pairs detected.
  final int flaggedPairs;

  /// Therapeutic duplicates detected.
  final int duplicateTherapies;

  /// Number of food-interaction warnings tied to the regimen.
  final int foodInteractions;

  /// CYP450 cascades (only includes those where [CypCascade.isCascade]).
  final List<CypCascade> cascades;

  /// Composite 0–100 score. Higher = more concerning.
  final int cumulativeScore;

  /// Banded interpretation of [cumulativeScore].
  final RegimenRiskBand band;

  /// Short human-readable bullets explaining what drove the score.
  final List<String> contributors;

  static const empty = RegimenAnalysis(
    medicationCount: 0,
    flaggedPairs: 0,
    duplicateTherapies: 0,
    foodInteractions: 0,
    cascades: [],
    cumulativeScore: 0,
    band: RegimenRiskBand.calm,
    contributors: [],
  );

  bool get hasFindings =>
      flaggedPairs > 0 ||
      duplicateTherapies > 0 ||
      cascades.isNotEmpty ||
      foodInteractions > 0;
}

/// One row from the bundled `drug_enzymes` table, filtered to metabolic
/// (CYP450) entries that the analyser cares about.
class DrugEnzymeRecord {
  const DrugEnzymeRecord({
    required this.drugId,
    required this.drugName,
    required this.enzymeName,
    required this.actions,
  });

  final int drugId;
  final String drugName;
  final String enzymeName;
  final Set<String> actions; // 'inhibitor', 'substrate', 'inducer'

  bool get isInhibitor => actions.contains('inhibitor');
  bool get isSubstrate => actions.contains('substrate');
  bool get isInducer => actions.contains('inducer');
}
