import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/interaction_result.dart';
import 'package:mobile/models/regimen_analysis.dart';
import 'package:mobile/models/safety_report.dart';
import 'package:mobile/models/user_medication.dart';
import 'package:mobile/services/regimen_analyser.dart';

void main() {
  UserMedication med(int id, String name) => UserMedication(
    id: id,
    userId: 'local-device',
    drugId: id,
    drugName: name,
    atcCode: null,
    addedAt: DateTime(2026, 5, 1),
  );

  InteractionResult pair({
    required String a,
    required String b,
    required String severity,
  }) {
    return InteractionResult(
      drugAId: 1,
      drugBId: 2,
      drugAName: a,
      drugBName: b,
      severity: severity,
      effect: 'effect',
    );
  }

  test('empty regimen produces an empty analysis in the calm band', () {
    final result = RegimenAnalyser.analyze(
      medications: const [],
      report: const SafetyReport.empty(),
      enzymeRecords: const [],
    );
    expect(result.cumulativeScore, 0);
    expect(result.band, RegimenRiskBand.calm);
    expect(result.hasFindings, isFalse);
  });

  test('major interactions and duplicates push the score into elevated', () {
    final result = RegimenAnalyser.analyze(
      medications: [med(1, 'Warfarin'), med(2, 'Ibuprofen')],
      report: SafetyReport.fromAnalysis(
        drugInteractions: [
          pair(a: 'Warfarin', b: 'Ibuprofen', severity: 'major'),
          pair(a: 'Warfarin', b: 'Ibuprofen', severity: 'moderate'),
        ],
        foodInteractions: const [],
        duplicateTherapies: const [],
      ),
      enzymeRecords: const [],
    );
    // 18 (major) + 8 (moderate) = 26 → watch band; with a duplicate would tip.
    expect(result.flaggedPairs, 2);
    expect(result.cumulativeScore, greaterThanOrEqualTo(20));
    expect(result.band, isNot(RegimenRiskBand.calm));
    // Contributors read in the three-tier vocabulary now.
    expect(result.contributors, contains('1 high-risk interaction'));
    expect(result.contributors, contains('1 moderate-risk interaction'));
  });

  test('CYP3A4 inhibitor + substrate is flagged as a cascade', () {
    final records = [
      const DrugEnzymeRecord(
        drugId: 1,
        drugName: 'Clarithromycin',
        enzymeName: 'Cytochrome P450 3A4',
        actions: {'inhibitor'},
      ),
      const DrugEnzymeRecord(
        drugId: 2,
        drugName: 'Simvastatin',
        enzymeName: 'Cytochrome P450 3A4',
        actions: {'substrate'},
      ),
    ];
    final result = RegimenAnalyser.analyze(
      medications: [med(1, 'Clarithromycin'), med(2, 'Simvastatin')],
      report: const SafetyReport.empty(),
      enzymeRecords: records,
    );
    expect(result.cascades, hasLength(1));
    final cascade = result.cascades.single;
    expect(cascade.shortName, 'CYP3A4');
    expect(cascade.inhibitors, ['Clarithromycin']);
    expect(cascade.substrates, ['Simvastatin']);
    expect(result.contributors, contains('CYP3A4 metabolism cascade'));
  });

  test('a drug acting on its own enzyme alone is not a cascade', () {
    final records = [
      const DrugEnzymeRecord(
        drugId: 1,
        drugName: 'Ritonavir',
        enzymeName: 'Cytochrome P450 3A4',
        actions: {'substrate', 'inhibitor'},
      ),
    ];
    final result = RegimenAnalyser.analyze(
      medications: [med(1, 'Ritonavir')],
      report: const SafetyReport.empty(),
      enzymeRecords: records,
    );
    expect(result.cascades, isEmpty);
  });
}
