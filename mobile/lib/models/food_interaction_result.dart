/// Result of a drug-food interaction lookup.
class FoodInteractionResult {
  final int drugId;
  final String drugName;
  final String description;

  const FoodInteractionResult({
    required this.drugId,
    required this.drugName,
    required this.description,
  });

  factory FoodInteractionResult.fromMap(Map<String, dynamic> map) {
    return FoodInteractionResult(
      drugId: map['drug_id'] as int,
      drugName: map['drug_name'] as String,
      description: (map['description'] as String?) ?? '',
    );
  }
}
