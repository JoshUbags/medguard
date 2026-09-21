import 'severity.dart';

/// Where an interaction verdict came from. MedGuard is a hybrid engine, so the
/// UI surfaces provenance: a curated clinical pair vs. a model prediction.
enum InteractionSource {
  /// A known pair from the bundled DrugBank-derived rule database.
  clinicalDatabase('Clinical database'),

  /// Inferred by MedGuard's model (remote API or on-device TFLite) for a pair
  /// the rule database did not contain.
  aiPrediction('AI prediction');

  const InteractionSource(this.label);

  final String label;
}

/// A single drug-drug interaction between two medications.
///
/// Built from a joined SQL row in [DatabaseService], so it carries
/// denormalised drug names for display.
class InteractionResult {
  final int drugAId;
  final int drugBId;
  final String drugAName;
  final String drugBName;

  /// Raw severity string as stored in the DrugBank-derived database.
  /// Use [severityLevel] for the typed enum.
  final String severity;

  final String? mechanism;
  final String? effect;
  final String? description;

  /// Provenance of this verdict. Defaults to [InteractionSource.clinicalDatabase]
  /// because rows loaded from the rule database are, by definition, clinical.
  final InteractionSource source;

  /// Model confidence in [0, 1] for an [InteractionSource.aiPrediction]; null
  /// for clinical-database pairs (a curated fact has no probability).
  final double? confidence;

  const InteractionResult({
    required this.drugAId,
    required this.drugBId,
    required this.drugAName,
    required this.drugBName,
    required this.severity,
    this.mechanism,
    this.effect,
    this.description,
    this.source = InteractionSource.clinicalDatabase,
    this.confidence,
  });

  /// Typed severity derived from the wire string.
  Severity get severityLevel => Severity.fromString(severity);

  /// The three-tier risk level (Low / Moderate / High) this pair maps to — the
  /// canonical classification the UI renders.
  RiskLevel get riskLevel => severityLevel.riskLevel;

  /// Confidence as a rounded whole percent (e.g. 88), or null when unknown.
  int? get confidencePercent =>
      confidence == null ? null : (confidence! * 100).round();

  factory InteractionResult.fromMap(Map<String, dynamic> map) {
    return InteractionResult(
      drugAId: map['drug_a_id'] as int,
      drugBId: map['drug_b_id'] as int,
      drugAName: map['drug_a_name'] as String,
      drugBName: map['drug_b_name'] as String,
      severity: map['severity'] as String,
      mechanism: map['mechanism'] as String?,
      effect: map['effect'] as String?,
      description: map['description'] as String?,
    );
  }

  @override
  String toString() => 'InteractionResult($drugAName↔$drugBName, $severity)';
}
