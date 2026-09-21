import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/interaction_result.dart';
import 'package:mobile/models/safety_report.dart';
import 'package:mobile/models/severity.dart';
import 'package:mobile/models/user_medication.dart';
import 'package:mobile/screens/medications/medications_screen.dart';
import 'package:mobile/screens/safety/safety_report_screen.dart';
import 'package:mobile/services/regimen_review_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/common/floating_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserMedication _med(int id, String name) => UserMedication(
  id: id,
  userId: 'local-device',
  drugId: id,
  drugName: name,
  atcCode: null,
  addedAt: DateTime(2026, 1, 1),
);

SafetyReport _reportWith({int interactions = 0}) {
  return SafetyReport.fromAnalysis(
    drugInteractions: [
      for (var i = 0; i < interactions; i++)
        InteractionResult(
          drugAId: 1,
          drugBId: 2,
          drugAName: 'Warfarin',
          drugBName: 'Ibuprofen',
          severity: Severity.major.wireName,
          effect: 'Increased bleeding risk',
          source: InteractionSource.clinicalDatabase,
        ),
    ],
    foodInteractions: const [],
    duplicateTherapies: const [],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RegimenReviewService.instance.resetForTest();
  });

  Future<void> pumpMedicationsScreen(
    WidgetTester tester, {
    bool showNavigation = true,
    List<UserMedication> medications = const [],
    SafetyReport? report,
  }) async {
    // A tall surface, because this page is one long lazy list and the default
    // 800×600 test viewport simply never builds the sections below the fold.
    // Without this, an assertion about the sign-off block fails for the
    // uninteresting reason that the widget was never created — not because the
    // page is wrong.
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MedicationsScreen(
          showNavigation: showNavigation,
          loadMedications: () async => medications,
          runReview: (_) async => report ?? _reportWith(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the page names every medicine it could check', (tester) async {
    await pumpMedicationsScreen(
      tester,
      medications: [_med(1, 'Warfarin'), _med(2, 'Ibuprofen')],
    );

    expect(find.text('Interactions'), findsWidgets);
    expect(find.text('Your medicines'), findsOneWidget);
    // What WOULD be checked is always visible and always nameable, review or
    // no review.
    expect(find.text('Warfarin'), findsWidgets);
    expect(find.text('Ibuprofen'), findsWidgets);
    expect(find.byType(FloatingNavBar), findsOneWidget);
  });

  testWidgets('says nothing about risk until the review is run', (
    tester,
  ) async {
    await pumpMedicationsScreen(
      tester,
      medications: [_med(1, 'Warfarin'), _med(2, 'Ibuprofen')],
      report: _reportWith(interactions: 1),
    );

    // THE contract for this page. Every section is present — the user can see
    // what the page will tell them — but none of them assert a result, because
    // the user has not asked for one. A verdict rendered on arrival would be a
    // verdict about a regimen nobody confirmed was current.
    expect(find.text('Regimen risk'), findsOneWidget);
    expect(find.text('What gets checked'), findsOneWidget);
    expect(find.text('Findings'), findsOneWidget);

    expect(find.text('Not yet run'), findsOneWidget);
    expect(
      find.textContaining('nothing is assessed until you do'),
      findsOneWidget,
    );
    // The finding exists in the injected report, and must NOT be on screen.
    expect(find.textContaining('Warfarin + Ibuprofen'), findsNothing);
    // Every check reads "not yet known", not "clear".
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('running the review records it and opens the report', (
    tester,
  ) async {
    await pumpMedicationsScreen(
      tester,
      medications: [_med(1, 'Warfarin'), _med(2, 'Ibuprofen')],
      report: _reportWith(interactions: 1),
    );

    final run = find.byKey(const ValueKey('home-risk-review-action'));
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await tester.pumpAndSettle();

    // The acknowledgement is recorded, which is what activates the regimen's
    // verdicts everywhere else in the app…
    expect(
      RegimenReviewService.instance.isReviewed('local-device', const [1, 2]),
      isTrue,
    );
    // …and the user lands on the findings rather than being left on the page
    // they pressed the button from, hunting for a second control.
    expect(find.byType(SafetyReportScreen), findsOneWidget);
  });

  testWidgets('a single medicine cannot be checked, and the page says so', (
    tester,
  ) async {
    await pumpMedicationsScreen(tester, medications: [_med(1, 'Warfarin')]);

    expect(
      find.textContaining('at least two medicines'),
      findsWidgets,
      reason: 'One medicine cannot interact with anything, and the page has '
          'to explain that rather than simply showing nothing',
    );
  });

  testWidgets('changing the selection retracts what was already said', (
    tester,
  ) async {
    await pumpMedicationsScreen(
      tester,
      medications: [_med(1, 'Warfarin'), _med(2, 'Ibuprofen')],
      report: _reportWith(interactions: 1),
    );

    final run = find.byKey(const ValueKey('home-risk-review-action'));
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await tester.pumpAndSettle();

    // Back from the report to the page that produced it. DetailPage carries
    // its own back control rather than a platform one, so pageBack() has
    // nothing to find.
    await tester.tap(find.byKey(const ValueKey('detail-back')));
    await tester.pumpAndSettle();
    expect(find.text('Reviewed'), findsWidgets);

    // Untick one of the two: the findings described a pair that is no longer
    // the selection, so they must be withdrawn rather than left standing.
    await tester.tap(find.text('Ibuprofen').first);
    await tester.pumpAndSettle();

    expect(find.text('Not yet run'), findsOneWidget);
  });

  testWidgets('adding a medicine sends the regimen back behind the gate', (
    tester,
  ) async {
    await RegimenReviewService.instance.markReviewed('local-device', const [
      1,
      2,
    ]);

    // The acknowledged pair is still active…
    expect(
      RegimenReviewService.instance.isReviewed('local-device', const [1, 2]),
      isTrue,
    );
    // …but a third medicine makes it a different regimen, which was never
    // reviewed, so its sign-off must not carry over.
    expect(
      RegimenReviewService.instance.isReviewed('local-device', const [1, 2, 3]),
      isFalse,
    );

    await pumpMedicationsScreen(
      tester,
      medications: [
        _med(1, 'Warfarin'),
        _med(2, 'Ibuprofen'),
        _med(3, 'Aspirin'),
      ],
    );
    expect(find.text('Not yet run'), findsOneWidget);
  });

  testWidgets('embedded in the shell it hides its own nav bar', (tester) async {
    await pumpMedicationsScreen(tester, showNavigation: false);
    expect(find.byType(FloatingNavBar), findsNothing);
  });
}
