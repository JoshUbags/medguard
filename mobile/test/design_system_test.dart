import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/ai/ai_screen.dart';
import 'package:mobile/screens/dose/dose_screen.dart';
import 'package:mobile/screens/insights/insights_screen.dart';
import 'package:mobile/screens/medications/medications_screen.dart';
import 'package:mobile/services/regimen_review_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/medguard_palette.dart';
import 'package:mobile/theme/medguard_responsive.dart';
import 'package:mobile/theme/medguard_spacing.dart';
import 'package:mobile/widgets/common/glass_surface.dart';
import 'package:mobile/widgets/common/page_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A status-bar inset every screen must clear before its own top gap begins.
const _statusBar = EdgeInsets.only(top: 47);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RegimenReviewService.instance.resetForTest();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: _statusBar,
            viewPadding: _statusBar,
          ),
          child: screen,
        ),
      ),
    );
    await tester.pump();
  }

  /// Resolves [MedGuardResponsive] for a given viewport through a real
  /// element, since the helpers read from an inherited [MediaQuery].
  Future<MedGuardResponsive> responsiveFor(
    WidgetTester tester,
    Size size,
  ) async {
    late MedGuardResponsive resolved;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            resolved = MedGuardResponsive.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return resolved;
  }

  group('global top spacing', () {
    testWidgets('the universal top gap is one value, scaled once', (
      tester,
    ) async {
      final responsive = await responsiveFor(tester, const Size(390, 844));
      // screenTop is screenTopGap already scaled — the pair exists so no call
      // site can accidentally scale the raw value twice.
      expect(
        MedGuardSpacing.screenTop(responsive),
        responsive.s(MedGuardSpacing.screenTopGap(responsive)),
      );
    });

    testWidgets('every top-level page starts at the same height', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tops = <String, double>{};

      // Dose only joined this rule when its full-bleed teal masthead was
      // replaced by the shared page header — before that it began a good 40
      // points higher than every other tab, and in a different colour.
      await pumpScreen(tester, const DoseScreen(showNavigation: false));
      tops['dose'] = tester.getTopLeft(find.text('Doses').first).dy;

      await pumpScreen(tester, const MedicationsScreen(showNavigation: false));
      tops['interactions'] = tester
          .getTopLeft(find.text('Interactions').first)
          .dy;

      await pumpScreen(tester, const InsightsScreen(showNavigation: false));
      tops['insights'] = tester.getTopLeft(find.text('Insights').first).dy;

      final reference = tops.values.first;
      for (final entry in tops.entries) {
        expect(
          entry.value,
          closeTo(reference, 1.0),
          reason: '${entry.key} must begin at the shared top height',
        );
      }

      // And that height clears the status bar by a genuinely noticeable gap
      // rather than hugging it.
      expect(reference, greaterThan(_statusBar.top + 24));
    });

    testWidgets('tablets get a larger top gap than compact phones', (
      tester,
    ) async {
      final compact = MedGuardSpacing.screenTopGap(
        await responsiveFor(tester, const Size(320, 568)),
      );
      final phone = MedGuardSpacing.screenTopGap(
        await responsiveFor(tester, const Size(390, 844)),
      );
      final tablet = MedGuardSpacing.screenTopGap(
        await responsiveFor(tester, const Size(800, 1280)),
      );
      expect(compact, lessThan(phone));
      expect(phone, lessThan(tablet));
    });
  });

  group('shared glass', () {
    testWidgets('every primary tab carries the identical header cluster', (
      tester,
    ) async {
      // The profile control must be the SAME widget, at the same size, in the
      // same slot, on every page — this is the consistency that kept slipping.
      for (final screen in <String, Widget>{
        'dose': const DoseScreen(showNavigation: false),
        'interactions': const MedicationsScreen(showNavigation: false),
        'insights': const InsightsScreen(showNavigation: false),
      }.entries) {
        await pumpScreen(tester, screen.value);
        expect(
          find.byType(HeaderGlassActions),
          findsOneWidget,
          reason: '${screen.key} must use the shared header cluster',
        );
        expect(
          find.byKey(const ValueKey('page-header-avatar')),
          findsOneWidget,
          reason: '${screen.key} must carry the shared avatar',
        );
      }

      // Dose adds its action INSIDE that same capsule rather than beside it.
      await pumpScreen(tester, const DoseScreen(showNavigation: false));
      expect(find.byKey(const ValueKey('dose-header-add')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('dose-header-add')),
          matching: find.byType(HeaderGlassActions),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the AI top bar uses the same capsule as every other page', (
      tester,
    ) async {
      await pumpScreen(tester, const AiScreen(showNavigation: false));
      expect(find.byType(HeaderGlassActions), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-header-avatar')), findsOneWidget);
    });

    testWidgets('the AI composer is WHITE glass, still the shared surface', (
      tester,
    ) async {
      await pumpScreen(tester, const AiScreen(showNavigation: false));

      final input = tester.widget<GlassSurface>(
        find
            .ancestor(
              of: find.text('Ask anything'),
              matching: find.byType(GlassSurface),
            )
            .first,
      );
      // Still the app's one glass component — the composer must never grow a
      // bespoke frosted container of its own.
      expect(input, isA<GlassSurface>());
      // But deliberately tuned, and in exactly one direction: the tint is
      // WHITE in both themes rather than the theme's surface, so the pane
      // reads as a lit pane of glass over the AI page's teal bloom instead of
      // dissolving into a dark canvas.
      expect(input.tintColor, MedGuardPalette.pureWhite);
      // Carried MUCH heavier than the reference tint, and for a reason that is
      // about legibility rather than taste: this is the one pane in the app
      // that holds an editable text field over a dark, saturated canvas. At the
      // reference tint the pane was barely brighter than the page and the
      // placeholder became the lowest-contrast text in the app. It stays short
      // of opaque so the blur and saturation lift still read through it.
      expect(input.tint, greaterThan(0.6));
      expect(input.tint, lessThan(0.85));
    });

    testWidgets('the AI composer inks are fixed light-theme, not themed', (
      tester,
    ) async {
      // The pane is white in BOTH themes, so its contents must take the
      // light-theme inks in both themes. Reading `context.colors.ink` here is
      // what previously put near-white text on a white pane in dark mode.
      await pumpScreen(tester, const AiScreen(showNavigation: false));

      final field = tester.widget<TextField>(
        find
            .ancestor(
              of: find.text('Ask anything'),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(field.style?.color, MedGuardPalette.ink);
      expect(
        field.decoration?.hintStyle?.color,
        MedGuardPalette.inkSoft,
      );
    });

    testWidgets('the glass default stays in the see-through range', (
      tester,
    ) async {
      // Guards the one value that decides whether the app's glass looks like
      // glass. Raising it past ~0.45 is what turned the panes into slabs.
      expect(kGlassTint, inExclusiveRange(0.12, 0.45));
      expect(kGlassSaturation, greaterThan(1.0));
    });
  });

  group('Dose date picking', () {
    /// The calendar card, identified by its paging control — the one thing
    /// only that card has.
    Finder calendar() => find.bySemanticsLabel('Previous period');

    testWidgets('exactly one date picker is on screen in every range', (
      tester,
    ) async {
      await pumpScreen(tester, const DoseScreen(showNavigation: false));
      await tester.pumpAndSettle();

      // ONE picker, present in all three ranges. The range changes the
      // calendar's SHAPE (week row or month grid), never whether it exists.
      //
      // Day view used to have no calendar at all, because the page's pinned
      // masthead carried a day rail instead. When the masthead was replaced by
      // the standard page header, that left Day view with no way to change the
      // date — tapping "Day" simply removed the date picker from the screen.
      expect(calendar(), findsOneWidget, reason: 'Day view has a calendar');

      await tester.tap(find.bySemanticsLabel('Week view'));
      await tester.pumpAndSettle();
      expect(calendar(), findsOneWidget, reason: 'Week view has a calendar');

      await tester.tap(find.bySemanticsLabel('Month view'));
      await tester.pumpAndSettle();
      expect(calendar(), findsOneWidget, reason: 'Month view has a calendar');
    });

    testWidgets('picking a date shows what is due on it, in every range', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(tester, const DoseScreen(showNavigation: false));
      await tester.pumpAndSettle();

      // The day timeline answers "what is due on the selected date". It must
      // survive a range change: Week and Month used to REPLACE it with the
      // per-medicine breakdown, so tapping a date on the month grid moved the
      // selection and then showed nothing at all about that date — the one
      // thing someone taps a calendar date to find out.
      expect(find.text('Schedule'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Month view'));
      await tester.pumpAndSettle();
      expect(find.text('Schedule'), findsOneWidget);
      // …and the breakdown is now additional rather than a substitute.
      expect(find.text('By medicine'), findsOneWidget);
    });
  });

  group('AI side navigation', () {
    testWidgets(
      'search is a labelled destination and the profile block is gone',
      (tester) async {
        await pumpScreen(tester, const AiScreen(showNavigation: false));

        await tester.tap(find.bySemanticsLabel('Open menu'));
        await tester.pumpAndSettle();

        // Search says what it searches, inside the navigation group.
        expect(find.text('Search medicines'), findsOneWidget);
        expect(find.text('Go to'.toUpperCase()), findsOneWidget);
        // The account block at the foot of the menu has been removed.
        expect(find.text('View profile'), findsNothing);
        expect(find.text('Your account'), findsNothing);
      },
    );
  });
}
