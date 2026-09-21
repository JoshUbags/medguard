/// Full record from the bundled DrugBank-derived DB used by the
/// [DrugMonographScreen]. Mirrors every column on the `drugs` table that
/// users would want to read when researching a medicine.
class DrugMonograph {
  const DrugMonograph({
    required this.id,
    required this.drugbankId,
    required this.name,
    this.genericName,
    this.drugType,
    this.description,
    this.indication,
    this.mechanismOfAction,
    this.absorption,
    this.halfLife,
    this.toxicity,
    this.atcCode,
    this.allAtcCodes,
    this.drugClass,
    this.casNumber,
    this.averageMass,
    this.groups,
    this.rxcui,
  });

  final int id;
  final String drugbankId;
  final String name;
  final String? genericName;
  final String? drugType;
  final String? description;
  final String? indication;
  final String? mechanismOfAction;
  final String? absorption;
  final String? halfLife;
  final String? toxicity;
  final String? atcCode;
  final String? allAtcCodes;
  final String? drugClass;
  final String? casNumber;
  final String? averageMass;
  final String? groups;
  final String? rxcui;

  bool get isApproved => groups?.toLowerCase().contains('approved') ?? false;

  factory DrugMonograph.fromMap(Map<String, dynamic> map) {
    String? str(String key) => map[key] as String?;
    return DrugMonograph(
      id: map['id'] as int,
      drugbankId: map['drugbank_id'] as String,
      name: map['name'] as String,
      genericName: str('generic_name'),
      drugType: str('drug_type'),
      description: str('description'),
      indication: str('indication'),
      mechanismOfAction: str('mechanism_of_action'),
      absorption: str('absorption'),
      halfLife: str('half_life'),
      toxicity: str('toxicity'),
      atcCode: str('atc_code'),
      allAtcCodes: str('all_atc_codes'),
      drugClass: str('drug_class'),
      casNumber: str('cas_number'),
      averageMass: str('average_mass'),
      groups: str('groups'),
      rxcui: str('rxcui'),
    );
  }
}
