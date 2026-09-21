import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/safety_report.dart';
import 'package:mobile/models/severity.dart';
import 'package:mobile/services/interaction_checker.dart';

import '../helpers/real_database.dart';

void main() {
  if (realDatabaseSkip != null) {
    test('interaction checker', () {}, skip: realDatabaseSkip);
    return;
  }
  final database = createRealDatabaseService();
  final checker = InteractionChecker(database: database);

  tearDownAll(database.close);

  test('no drugs returns a safe empty report', () async {
    final report = await checker.run(const []);

    expect(report.overallRisk, OverallRisk.safe);
    expect(report.totalWarnings, 0);
    expect(report.drugInteractions, isEmpty);
    expect(report.foodInteractions, isEmpty);
    expect(report.duplicateTherapies, isEmpty);
  });

  test('one grapefruit-interacting drug returns food guidance only', () async {
    final cyclosporine = await findExactDrug(database, 'Cyclosporine');

    final report = await checker.run([cyclosporine.id]);

    expect(report.drugInteractions, isEmpty);
    expect(report.duplicateTherapies, isEmpty);
    expect(report.foodInteractions, isNotEmpty);
    expect(
      report.foodInteractions.first.description.toLowerCase(),
      contains('grapefruit'),
    );
    expect(report.overallRisk, OverallRisk.caution);
  });

  test('known Warfarin and Ibuprofen pair returns a major warning', () async {
    final warfarin = await findExactDrug(database, 'Warfarin');
    final ibuprofen = await findExactDrug(database, 'Ibuprofen');

    final report = await checker.run([warfarin.id, ibuprofen.id]);

    expect(report.drugInteractions, isNotEmpty);
    expect(report.drugInteractions.first.severityLevel, Severity.major);
    expect(report.drugInteractions.first.mechanism, isNotEmpty);
    expect(report.overallRisk, OverallRisk.danger);
  });

  test(
    'two proton pump inhibitors trigger duplicate therapy warning',
    () async {
      final omeprazole = await findExactDrug(database, 'Omeprazole');
      final pantoprazole = await findExactDrug(database, 'Pantoprazole');

      final report = await checker.run([omeprazole.id, pantoprazole.id]);

      expect(report.duplicateTherapies, isNotEmpty);
      // Duplicate therapy is keyed on a shared SPECIFIC therapeutic class;
      // proton pump inhibitors resolve to an "...Inhibitors" class label.
      expect(
        report.duplicateTherapies.map((item) => item.category),
        anyElement(contains('Inhibitors')),
      );
    },
  );
}
