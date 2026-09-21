import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/drug.dart';

void main() {
  test('fromMap maps the database row into a Drug model', () {
    final drug = Drug.fromMap({
      'id': 295,
      'drugbank_id': 'DB00316',
      'name': 'Acetaminophen',
      'description': 'An analgesic and antipyretic medicine.',
      'indication': 'Used for pain and fever.',
      'atc_code': 'N02BE01',
      'rxcui': '161',
    });

    expect(drug.id, 295);
    expect(drug.drugbankId, 'DB00316');
    expect(drug.name, 'Acetaminophen');
    expect(drug.description, 'An analgesic and antipyretic medicine.');
    expect(drug.indication, 'Used for pain and fever.');
    expect(drug.atcCode, 'N02BE01');
    expect(drug.rxcui, '161');
  });

  test('fromMap preserves nullable clinical fields', () {
    final drug = Drug.fromMap({
      'id': 2562,
      'drugbank_id': 'DB10534',
      'name': 'Grapefruit',
      'description': null,
      'indication': null,
      'atc_code': null,
      'rxcui': null,
    });

    expect(drug.name, 'Grapefruit');
    expect(drug.description, isNull);
    expect(drug.indication, isNull);
    expect(drug.atcCode, isNull);
    expect(drug.rxcui, isNull);
  });
}
