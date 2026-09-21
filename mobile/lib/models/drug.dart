/// A medication record from the bundled DrugBank-derived SQLite DB.
class Drug {
  final int id;
  final String drugbankId;
  final String name;
  final String? description;
  final String? indication;
  final String? atcCode;
  final String? rxcui;
  final String? drugType;
  final String? halfLife;
  final String? allAtcCodes;

  const Drug({
    required this.id,
    required this.drugbankId,
    required this.name,
    this.description,
    this.indication,
    this.atcCode,
    this.rxcui,
    this.drugType,
    this.halfLife,
    this.allAtcCodes,
  });

  factory Drug.fromMap(Map<String, dynamic> map) {
    return Drug(
      id: map['id'] as int,
      drugbankId: map['drugbank_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      indication: map['indication'] as String?,
      atcCode: map['atc_code'] as String?,
      rxcui: map['rxcui'] as String?,
      drugType: map['drug_type'] as String?,
      halfLife: map['half_life'] as String?,
      allAtcCodes: map['all_atc_codes'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is Drug && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Drug(#$id, $name)';
}
