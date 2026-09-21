import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/dose/dose_screen.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The medication input modal, driven the way a user drives it.
///
/// The interesting behaviour here is not that a schedule saves — that is the
/// service's job — but that the form tells the user what is wrong, where, and
/// gives them an obvious way out without saving.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Opens the editor over a host screen, exactly as the Dose page does, on a
  /// real phone viewport — the default 800x600 test surface makes the sheet so
  /// short that the lower fields are culled before they are ever built.
  Future<void> openEditor(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDoseScheduleEditor(
                  context,
                  userId: 'local-device',
                  now: DateTime(2026, 7, 26, 9),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the modal opens with labelled fields in a logical order', (
    tester,
  ) async {
    await openEditor(tester);

    expect(find.text('New dose schedule'), findsOneWidget);
    // The form is three numbered panels, not one long column of fields, so a
    // user can see how much there is to do before they start.
    for (final group in ['The medicine', 'The timing']) {
      expect(find.text(group), findsOneWidget, reason: '$group is a panel');
    }
    // What → how much → how often → when → optional supply.
    for (final label in ['MEDICINE', 'STRENGTH', 'HOW OFTEN', 'TIMES']) {
      expect(find.text(label), findsOneWidget, reason: '$label is labelled');
    }
    // Strength is optional, and says so on the label rather than only in a
    // hint the user reads after tapping in.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('STRENGTH'),
          matching: find.byType(Row),
        ).first,
        matching: find.text('optional'),
      ),
      findsOneWidget,
    );
    // The remaining sections sit below the fold. Scrolled to rather than
    // dragged by a fixed distance, so the assertion survives the form growing
    // or shrinking by a card.
    for (final below in ['DATES', 'The supply', 'QUANTITY']) {
      await tester.scrollUntilVisible(
        find.text(below),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(below), findsOneWidget, reason: '$below is reachable');
    }
    // The last thing above the Save button is the schedule restated in plain
    // English — incomplete here, and honest about being incomplete.
    await tester.scrollUntilVisible(
      find.text('Not ready yet'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Not ready yet'), findsOneWidget);
    // Both a primary and a secondary action are present and obvious.
    expect(find.text('Create schedule'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // …plus an explicit close, so a drag-down is never the only way out.
    expect(find.bySemanticsLabel('Close without saving'), findsOneWidget);
  });

  testWidgets('an empty strength is accepted — only the medicine is required', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.ensureVisible(find.text('Create schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create schedule'));
    await tester.pumpAndSettle();

    // The medicine is genuinely required, and the error sits against it.
    expect(
      find.text('Choose which medicine this schedule is for.'),
      findsOneWidget,
    );
    // The strength is NOT: leaving it blank must never block the reminder.
    expect(find.textContaining('how much you take'), findsNothing);
    expect(find.textContaining('must be greater than zero'), findsNothing);
    // The sheet stays open so the real problem can be fixed in place.
    expect(find.text('New dose schedule'), findsOneWidget);
  });

  testWidgets('a non-numeric strength is explained, then clears as you type', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.enterText(find.widgetWithText(TextField, 'e.g. 500'), 'abc');
    await tester.ensureVisible(find.text('Create schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create schedule'));
    await tester.pumpAndSettle();

    expect(find.text('Use numbers only, for example 500.'), findsOneWidget);

    // Editing the field clears its error immediately — the message never
    // lingers over input the user has already corrected.
    await tester.enterText(find.widgetWithText(TextField, 'e.g. 500'), '500');
    await tester.pumpAndSettle();
    expect(find.text('Use numbers only, for example 500.'), findsNothing);
  });

  testWidgets('cancel closes the modal without saving', (tester) async {
    await openEditor(tester);
    expect(find.text('New dose schedule'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('New dose schedule'), findsNothing);
  });
}
