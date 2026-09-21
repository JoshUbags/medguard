/// Result of a duplicate-therapy check: two drugs in the same specific
/// therapeutic class (e.g. two proton-pump inhibitors), which may indicate
/// duplicate prescribing — an additive-dose risk. [category] holds that class
/// name (a filtered DrugBank category).
class DuplicateTherapyResult {
  final int drugAId;
  final int drugBId;
  final String drugAName;
  final String drugBName;
  final String category;

  const DuplicateTherapyResult({
    required this.drugAId,
    required this.drugBId,
    required this.drugAName,
    required this.drugBName,
    required this.category,
  });

  factory DuplicateTherapyResult.fromMap(Map<String, dynamic> map) {
    return DuplicateTherapyResult(
      drugAId: map['drug_a_id'] as int,
      drugBId: map['drug_b_id'] as int,
      drugAName: map['drug_a_name'] as String,
      drugBName: map['drug_b_name'] as String,
      category: map['category'] as String,
    );
  }
}
