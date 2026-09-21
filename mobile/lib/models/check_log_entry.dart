import '../models/safety_report.dart';

/// One row of the check-history audit trail. Persisted to `check_logs` by
/// [InteractionChecker] every time a SafetyReport is generated for the user.
class CheckLogEntry {
  const CheckLogEntry({
    required this.id,
    required this.userId,
    required this.drugIds,
    required this.drugNames,
    required this.overallRisk,
    required this.interactionCount,
    required this.foodCount,
    required this.duplicateCount,
    required this.allergyCount,
    required this.source,
    required this.createdAt,
  });

  final int id;
  final String userId;
  final List<int> drugIds;
  final List<String> drugNames;
  final OverallRisk overallRisk;
  final int interactionCount;
  final int foodCount;
  final int duplicateCount;
  final int allergyCount;

  /// Source of the analysis: `rule_based` today, `ml` when the TFLite
  /// predictor produces the call.
  final String source;
  final DateTime createdAt;

  int get totalFindings =>
      interactionCount + foodCount + duplicateCount + allergyCount;

  factory CheckLogEntry.fromMap(Map<String, dynamic> map) {
    final ids = (map['drug_ids'] as String? ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? -1)
        .toList(growable: false);
    final names = (map['drug_names'] as String? ?? '')
        .split('|')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final risk = OverallRisk.values.firstWhere(
      (r) => r.wireName == map['overall_risk'],
      orElse: () => OverallRisk.safe,
    );
    return CheckLogEntry(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      drugIds: ids,
      drugNames: names,
      overallRisk: risk,
      interactionCount: (map['interaction_count'] as int?) ?? 0,
      foodCount: (map['food_count'] as int?) ?? 0,
      duplicateCount: (map['duplicate_count'] as int?) ?? 0,
      allergyCount: (map['allergy_count'] as int?) ?? 0,
      source: (map['source'] as String?) ?? 'rule_based',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
