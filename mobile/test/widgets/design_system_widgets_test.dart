import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/severity.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/common/empty_state.dart';
import 'package:mobile/widgets/common/severity_colors.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }

  group('SeverityColors', () {
    test('maps every severity onto the three-tier palette', () {
      for (final severity in Severity.values) {
        // Should not throw and should return defined values.
        expect(SeverityColors.colorFor(severity), isA<Color>());
        expect(SeverityColors.iconFor(severity), isA<IconData>());
      }
      // Three-tier mapping: minor → Low (teal), moderate → Moderate (amber),
      // major/contraindicated → High (ruby).
      expect(SeverityColors.colorFor(Severity.minor), SeverityColors.low);
      expect(
        SeverityColors.colorFor(Severity.moderate),
        SeverityColors.moderate,
      );
      expect(SeverityColors.colorFor(Severity.major), SeverityColors.high);
      expect(
        SeverityColors.colorFor(Severity.contraindicated),
        SeverityColors.high,
      );
    });
  });


  group('EmptyState', () {
    testWidgets('renders icon, title, message and optional action', (
      tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        EmptyState(
          icon: Icons.medication_rounded,
          title: 'No medications yet',
          message: 'Add a medicine to start.',
          actionLabel: 'Add',
          onAction: () => retried++,
        ),
      );

      expect(find.text('No medications yet'), findsOneWidget);
      expect(find.text('Add a medicine to start.'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(retried, 1);
    });
  });
}
