import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/dose_schedule.dart';
import 'package:mobile/models/interaction_result.dart';
import 'package:mobile/models/safety_report.dart';
import 'package:mobile/models/user_medication.dart';
import 'package:mobile/screens/ai/ai_screen.dart';
import 'package:mobile/screens/dose/dose_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/screens/insights/insights_screen.dart';
import 'package:mobile/screens/main_shell.dart';
import 'package:mobile/screens/medications/medications_screen.dart';
import 'package:mobile/screens/profile/profile_screen.dart';
import 'package:mobile/screens/search/search_screen.dart';
import 'package:mobile/screens/settings/settings_screen.dart';
import 'package:mobile/services/auth_profile_preferences.dart';
import 'package:mobile/services/connectivity_service.dart';
import 'package:mobile/services/dose_service.dart';
import 'package:mobile/services/notification_preferences.dart';
import 'package:mobile/services/regimen_review_service.dart';
import 'package:mobile/services/user_data_service.dart';
import 'package:mobile/widgets/safety/regimen_risk.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/medguard_palette.dart';
import 'package:mobile/theme/page_transitions.dart';
import 'package:mobile/widgets/common/connectivity_banner.dart';
import 'package:mobile/widgets/common/detail_page.dart';
import 'package:mobile/widgets/common/floating_nav_bar.dart';
import 'package:mobile/widgets/common/glass_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  List<UserMedication> homeMedications(int count) {
    return List.generate(
      count,
      (index) => UserMedication(
        id: index + 1,
        userId: 'local-device',
        drugId: index + 1,
        drugName: 'Medicine ${index + 1}',
        atcCode: 'A${index + 1}',
        addedAt: DateTime.utc(2026, 5, index + 1),
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RegimenReviewService.instance.resetForTest();
  });

  /// Records a completed interaction review for the [count]-medicine regimen,
  /// so the home surfaces that sit behind the gate render their live analysis.
  /// Without this the dashboard correctly shows its "review required" state.
  Future<void> activateRegimen(int count) {
    return RegimenReviewService.instance.markReviewed(
      'local-device',
      homeMedications(count).map((medication) => medication.drugId),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: screen,
        routes: {
          HomeScreen.routeName: (_) => const HomeScreen(),
          SearchScreen.routeName: (_) => const SearchScreen(),
          MedicationsScreen.routeName: (_) => const MedicationsScreen(),
          DoseScreen.routeName: (_) => const DoseScreen(),
          InsightsScreen.routeName: (_) => const InsightsScreen(),
          ProfileScreen.routeName: (_) => const ProfileScreen(),
        },
      ),
    );
  }

  int visibleWordCount(String text) {
    return RegExp(r"[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?").allMatches(text).length;
  }

  testWidgets('bottom nav is a full-width faded wash with a centre orb', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final selectedTabs = <AppNavTab>[];

    await pumpScreen(
      tester,
      Scaffold(
        backgroundColor: MedGuardPalette.scaffold,
        body: const SizedBox.expand(),
        bottomNavigationBar: FloatingNavBar(
          current: AppNavTab.home,
          onTabSelected: selectedTabs.add,
        ),
      ),
    );

    // The bar rises from the bottom as a frosted fade: a real backdrop blur
    // under a scaffold-toned wash, with NO container or outline of its own.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-surface')),
        matching: find.byType(BackdropFilter),
      ),
      findsWidgets,
    );
    // The items live directly on the fade — the menu is a bare Row.
    expect(
      tester.widget<Row>(find.byKey(const ValueKey('bottom-nav-menu'))),
      isNotNull,
    );

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('bottom-nav-backdrop')),
    );
    final decoration = backdrop.decoration as BoxDecoration;
    expect(decoration.border, isNull, reason: 'No border, no defined shape');
    final wash = decoration.gradient! as LinearGradient;
    expect(wash.begin, Alignment.bottomCenter);
    expect(wash.end, Alignment.topCenter);
    expect(wash.colors.last.a, 0.0);
    for (var i = 1; i < wash.colors.length; i++) {
      expect(wash.colors[i].a, lessThanOrEqualTo(wash.colors[i - 1].a));
    }
    // A long, even dissolve rather than a block with an edge. The wash is
    // strong at the very bottom, but by three-quarters of the way up it has
    // nearly gone — that long ramp is what stops the bar reading as a slab.
    expect(wash.colors.length, greaterThanOrEqualTo(24));
    final threeQuarters = wash.colors[(wash.colors.length * 3) ~/ 4].a;
    expect(
      threeQuarters,
      lessThan(wash.colors.first.a * 0.3),
      reason: 'The fade must be nearly spent well before the top',
    );
    // And no single step may jump enough to read as a line — a visible step is
    // a visible edge, which is the banding this gradient exists to avoid.
    for (var i = 1; i < wash.colors.length; i++) {
      expect(
        wash.colors[i - 1].a - wash.colors[i].a,
        lessThan(0.09),
        reason: 'A visible step is a visible edge',
      );
    }

    // It spans the full width — no floating capsule inset from the edges.
    final surfaceRect = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-surface')),
    );
    expect(surfaceRect.left, 0);
    expect(surfaceRect.right, 390);

    // Each side item carries its page name beneath the icon; the orb never
    // carries a label, and Profile has left the nav.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Interaction'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Dose'), findsOneWidget);
    expect(find.text('AI'), findsNothing, reason: 'The orb IS the label');
    expect(find.text('Profile'), findsNothing, reason: 'Profile left the nav');

    // Every icon is centred in its own cell, and all four share one baseline.
    final iconCentres = <double>[];
    for (final name in ['home', 'interactions', 'insights', 'dose']) {
      final cell = tester.getRect(find.byKey(ValueKey('nav-hit-$name')));
      final pill = tester.getRect(find.byKey(ValueKey('nav-active-pill-$name')));
      expect(
        pill.center.dx,
        closeTo(cell.center.dx, 0.5),
        reason: '$name icon must be horizontally centred in its cell',
      );
      iconCentres.add(pill.center.dy);
    }
    for (final centre in iconCentres) {
      expect(
        centre,
        closeTo(iconCentres.first, 0.5),
        reason: 'All four icons sit on one vertical baseline',
      );
    }

    // Thin SF-style strokes; the active icon rests on a soft grey pill.
    final homeIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('nav-icon-home-true')),
    );
    expect(homeIcon.icon, Icons.grid_view_rounded);

    final interactionIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('nav-icon-interactions-false')),
    );
    expect(interactionIcon.icon, Icons.swap_horiz_rounded);

    final activePill = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('nav-active-pill-home')),
    );
    final activeDecoration = activePill.decoration! as BoxDecoration;
    expect(activeDecoration.color, isNot(Colors.transparent));
    expect(activeDecoration.border, isNull, reason: 'Pill is borderless');
    final inactivePill = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('nav-active-pill-dose')),
    );
    expect((inactivePill.decoration! as BoxDecoration).color,
        Colors.transparent);

    // Layout: five equally spaced items — Home + Interaction left of the
    // animated orb, Insights + Dose right of it, orb at the exact centre.
    final orbFinder = find.byKey(const ValueKey('nav-ai-orb'));
    expect(orbFinder, findsOneWidget);
    final orbCenter = tester.getCenter(orbFinder);
    final orbSize = tester.getSize(orbFinder);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(orbCenter.dx, closeTo(screenWidth / 2, 1.0));
    expect(orbSize.height, greaterThan(40));
    expect(
      tester.getCenter(find.byKey(const ValueKey('nav-hit-home'))).dx,
      lessThan(orbCenter.dx),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('nav-hit-interactions'))).dx,
      lessThan(orbCenter.dx),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('nav-hit-insights'))).dx,
      greaterThan(orbCenter.dx),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('nav-hit-dose'))).dx,
      greaterThan(orbCenter.dx),
    );

    // Selection callbacks fire for side tabs and the AI orb alike.
    await tester.tap(find.byKey(const ValueKey('nav-hit-insights')));
    expect(selectedTabs, [AppNavTab.insights]);

    await tester.tap(find.byKey(const ValueKey('nav-hit-ai')));
    expect(selectedTabs, [AppNavTab.insights, AppNavTab.ai]);
  });

  testWidgets('main shell keeps floating nav fixed across tab changes', (
    tester,
  ) async {
    await pumpScreen(tester, const MainShell(initialTab: AppNavTab.home));
    await tester.pump();

    expect(find.byType(FloatingNavBar), findsOneWidget);
    final shellScaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('main-shell-scaffold')),
    );
    expect(shellScaffold.extendBody, isTrue);
    expect(
      find.descendant(
        of: find.byType(Scrollable),
        matching: find.byType(FloatingNavBar),
      ),
      findsNothing,
    );

    final navTop = tester.getTopLeft(
      find.byKey(const ValueKey('bottom-nav-surface')),
    );

    await tester.tap(find.byKey(const ValueKey('nav-hit-dose')));
    await tester.pumpAndSettle();

    expect(find.byType(DoseScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-nav-surface'))),
      navTop,
    );

    await tester.tap(find.byKey(const ValueKey('nav-hit-interactions')));
    await tester.pumpAndSettle();

    expect(find.byType(MedicationsScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-nav-surface'))),
      navTop,
    );

    await tester.tap(find.byKey(const ValueKey('nav-hit-insights')));
    await tester.pumpAndSettle();

    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-nav-surface'))),
      navTop,
    );
  });

  testWidgets('main shell holds only the tab stack, no chrome of its own', (
    tester,
  ) async {
    await pumpScreen(tester, const MainShell(initialTab: AppNavTab.home));
    await tester.pump();

    final shellScaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('main-shell-scaffold')),
    );
    // The tab stack fades THROUGH on a switch, but it is still an IndexedStack
    // underneath — every tab stays mounted, so scroll positions and in-flight
    // loads survive a tab change.
    expect(shellScaffold.body, isA<FadeThroughIndexedStack>());

    // Connection state is NOT the shell's job. The banner is mounted once
    // around the whole app in `MaterialApp.builder`, so it rides above every
    // screen and survives navigation instead of re-animating on each push.
    expect(find.byType(ConnectivityBanner), findsNothing);
  });

  testWidgets('main shell AI orb opens the (empty) AI screen', (tester) async {
    await pumpScreen(tester, const MainShell(initialTab: AppNavTab.home));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('nav-hit-ai')));
    await tester.pumpAndSettle();

    expect(find.byType(AiScreen), findsOneWidget);
    expect(find.text('Ask anything'), findsOneWidget);
  });

  testWidgets('home screen exposes a useful safety dashboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // An empty in-memory dose store so the dose card resolves deterministically
    // to its "no reminders yet" setup state instead of touching a real DB.
    sqfliteFfiInit();
    final doseDb = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => UserDataService.createDoseSchema(db),
      ),
    );
    addTearDown(doseDb.close);
    await pumpScreen(
      tester,
      HomeScreen(
        showNavigation: false,
        loadMedications: () async => const [],
        doseService: DoseService(databaseProvider: () async => doseDb),
      ),
    );
    await tester.pump();

    // Greeting (+ wave) sits on top; the name is the larger line beneath it.
    expect(
      find.textContaining(RegExp(r'^Good (Morning|Afternoon|Evening)$')),
      findsOneWidget,
    );
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-scroll-view')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-header-search-action')),
      findsNothing,
    );
    // The bell + avatar share one glass capsule on the right; the avatar is
    // exactly as tall as the greeting + name text block beside it.
    expect(
      find.byKey(const ValueKey('home-header-glass-actions')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-header-bell')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-account-avatar')), findsOneWidget);
    final avatarSize = tester.getSize(
      find.byKey(const ValueKey('home-account-avatar')),
    );
    expect(avatarSize.width, avatarSize.height);
    final greetingSize = tester.getSize(
      find.textContaining(RegExp(r'^Good (Morning|Afternoon|Evening)$')),
    );
    final nameSize = tester.getSize(find.text('Guest'));
    final textGapSize = tester.getSize(
      find.byKey(const ValueKey('home-header-text-gap')),
    );
    expect(
      avatarSize.height,
      closeTo(
        greetingSize.height + textGapSize.height + nameSize.height,
        0.6,
      ),
    );
    final avatarStatus = tester.widget<Container>(
      find.byKey(const ValueKey('home-avatar-connection-dot')),
    );
    final avatarStatusDecoration = avatarStatus.decoration! as BoxDecoration;
    expect(avatarStatusDecoration.color, const Color(0xFF22C55E));
    // The connection indicator dot scales with the text-height avatar.
    final avatarDotSize = tester.getSize(
      find.byKey(const ValueKey('home-avatar-connection-dot')),
    );
    expect(avatarDotSize.height, inInclusiveRange(11, 18));
    final greetingFinder = find.textContaining(
      RegExp(r'^Good (Morning|Afternoon|Evening)$'),
    );
    final greetingText = tester.widget<Text>(greetingFinder);
    expect(greetingText.style?.fontWeight, FontWeight.w500);
    // The pinned chrome carries the section pills above the feed.
    expect(find.byKey(const ValueKey('home-pinned-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-section-filter-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-section-filter-quick-access')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-section-filter-risk')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-section-filter-dose')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-section-filter-alerts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-section-filter-insights')),
      findsOneWidget,
    );
    expect(find.text('Access'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);
    expect(find.text('Doses'), findsOneWidget);
    // "Alerts" labels both the pill and the section header at the end.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-filter-alerts')),
        matching: find.text('Alerts'),
      ),
      findsOneWidget,
    );
    // The Access pill is active (teal) on first appearance.
    final accessFilter = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('home-section-filter-quick-access')),
    );
    final accessFilterDecoration = accessFilter.decoration! as BoxDecoration;
    expect(accessFilterDecoration.color, MedGuardPalette.teal);
    final accessFilterIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-filter-quick-access')),
        matching: find.byIcon(Icons.bolt_rounded),
      ),
    );
    expect(accessFilterIcon.color, MedGuardPalette.pureWhite);
    // Pill order: Access · Risk · Insights · Doses · Alerts.
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey('home-section-filter-quick-access')),
          )
          .dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('home-section-filter-risk')))
            .dx,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-section-filter-risk')),
        matching: find.byIcon(Icons.monitor_heart_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.account_circle_rounded), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    // The Safety Pulse pill was removed (connectivity is shown only on the
    // avatar dot), and the Check-New-Medicine card moved to the Interactions
    // page.
    expect(find.byKey(const ValueKey('home-care-signal-pill')), findsNothing);
    expect(find.text('Safety Pulse'), findsNothing);
    expect(find.byKey(const ValueKey('home-live-pulse-badge')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-check-new-medicine-card')),
      findsNothing,
    );
    expect(find.text('Drug Library'), findsNothing);
    expect(find.text('Browse medicine records'), findsNothing);
    // The quietly-rotating caption and the login-consistency strip are present.
    expect(find.byKey(const ValueKey('home-app-caption')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-login-streak-section')),
      findsOneWidget,
    );
    // The consistency card greets a brand-new account (streak of 1).
    expect(find.text('Welcome aboard'), findsOneWidget);
    final headerContentGap = tester.getSize(
      find.byKey(const ValueKey('home-header-content-gap')),
    );
    final postLibraryGap = tester.getSize(
      find.byKey(const ValueKey('home-post-library-gap')),
    );
    // The caption's top spacing is one standardised section gap — the same gap
    // that divides every major section — sitting just below the pinned pills.
    expect(headerContentGap.height, postLibraryGap.height);
    expect(headerContentGap.height, inInclusiveRange(46, 54));
    expect(postLibraryGap.height, inInclusiveRange(46, 54));

    expect(find.text('Quick Access'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-section-title-accent')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('home-quick-access-heading-gap')))
          .height,
      inInclusiveRange(16, 18),
    );
    expect(find.byKey(const ValueKey('home-quick-access-row')), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('home-section-gap-after-quick-access')),
          )
          .height,
      inInclusiveRange(46, 54),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('home-section-gap-after-quick-access')),
          )
          .height,
      postLibraryGap.height,
    );
    expect(find.text('Drug library'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quick-access-card-library')),
        matching: find.text('Search'),
      ),
      findsOneWidget,
    );
    expect(find.text('Interaction map'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quick-access-card-interactions')),
        matching: find.text('Review'),
      ),
      findsOneWidget,
    );
    // Each Quick Access card links to a distinct page (no two shortcuts share a
    // destination): the old duplicate "Food warnings" → interactions card is now
    // "Allergy list" → allergy manager.
    expect(find.text('Allergy list'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Food warnings'), findsNothing);
    expect(find.text('Emergency card'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    final libraryCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('quick-access-card-library')),
    );
    final libraryCardDecoration = libraryCard.decoration! as BoxDecoration;
    final libraryCardPadding = libraryCard.padding! as EdgeInsets;
    final libraryCardSize = tester.getSize(
      find.byKey(const ValueKey('quick-access-card-library')),
    );
    expect(libraryCardDecoration.color, isNull);
    expect(libraryCardDecoration.gradient, isA<LinearGradient>());
    expect(libraryCardDecoration.borderRadius, isA<BorderRadius>());
    expect(libraryCardPadding.left, libraryCardPadding.top);
    expect(libraryCardPadding.right, libraryCardPadding.top);
    expect(libraryCardPadding.bottom, libraryCardPadding.top);
    expect(libraryCardSize.width, inInclusiveRange(132, 150));
    expect(libraryCardSize.height, inInclusiveRange(150, 170));
    final quickAccessHeading = tester.widget<Text>(find.text('Quick Access'));
    final searchValue = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('quick-access-card-library')),
        matching: find.text('Search'),
      ),
    );
    expect(quickAccessHeading.style?.fontWeight, FontWeight.w600);
    // Section titles are deliberately compact so content leads each block.
    expect(quickAccessHeading.style?.fontSize, inInclusiveRange(15.5, 18));
    expect(searchValue.style?.fontWeight, FontWeight.w600);

    final allergyCardDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('quick-access-card-allergies')),
                )
                .decoration!
            as BoxDecoration;
    expect(allergyCardDecoration.color, MedGuardPalette.pureWhite);

    await tester.drag(
      find.byKey(const ValueKey('home-quick-access-row')),
      const Offset(-900, 0),
    );
    await tester.pumpAndSettle();

    final libraryCardDecorationAfterScroll =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('quick-access-card-library')),
                )
                .decoration!
            as BoxDecoration;
    final focusedEmergencyDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('quick-access-card-emergency')),
                )
                .decoration!
            as BoxDecoration;
    expect(libraryCardDecorationAfterScroll.color, MedGuardPalette.pureWhite);
    expect(focusedEmergencyDecoration.color, isNull);
    expect(focusedEmergencyDecoration.gradient, isA<LinearGradient>());
    expect(greetingFinder, findsOneWidget);
    final regimenRiskHeading = tester.widget<Text>(find.text('Regimen Risk'));
    expect(
      regimenRiskHeading.style?.fontWeight,
      quickAccessHeading.style?.fontWeight,
    );
    expect(
      regimenRiskHeading.style?.fontSize,
      quickAccessHeading.style?.fontSize,
    );
    expect(find.byKey(const ValueKey('home-risk-section-body')), findsNothing);
    expect(
      find.text('Checks saved medicine pairs for interaction risk.'),
      findsNothing,
    );
    expect(find.text('Auto-checked'), findsOneWidget);
    // Home carries the meter itself — the SAME component Interactions renders,
    // in its compact form, against the same report. It is one widget rather
    // than a summary written twice, which is what stops the two screens
    // disagreeing about the verdict.
    expect(find.byKey(const ValueKey('home-risk-meter')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-risk-content-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-risk-trend-card')), findsOneWidget);
    expect(find.text('Interaction risk'), findsOneWidget);
    // Compact drops everything that invites a decision here: the pair-status
    // line, the context strip and the primary-driver breakdown all belong to
    // the full card on Interactions.
    expect(find.text('Pair status'), findsNothing);
    expect(find.byKey(const ValueKey('home-risk-context-strip')), findsNothing);
    expect(find.text('Live checks for risky combinations.'), findsOneWidget);
    // With nothing saved, the gauge states the reason it has no verdict
    // rather than showing a needle at zero — an "All clear" for a regimen that
    // does not exist would be the most misleading thing on the page.
    expect(
      find.textContaining('Add'),
      findsWidgets,
      reason: 'the empty gauge points at what would make it work',
    );
    expect(find.text('Dose timing'), findsNothing);
    expect(find.text('Saved medicines'), findsNothing);
    expect(find.text('Next dose due'), findsNothing);
    expect(find.text('Recent alerts'), findsNothing);
    expect(find.byKey(const ValueKey('home-break-before-doses')), findsNothing);
    expect(find.text('Dose rhythm'), findsNothing);
    expect(
      find.text('A steady week makes dose timing easier to trust.'),
      findsNothing,
    );
    expect(find.text('Weekly adherence'), findsNothing);
    expect(find.text('Care science'), findsNothing);
    expect(find.text('Why timing matters'), findsNothing);
    expect(
      find.text('A 30-minute window keeps medicine levels steady.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-doses-section')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-doses-section-panel')),
      findsOneWidget,
    );
    final doseSectionPanel = tester.widget<Container>(
      find.byKey(const ValueKey('home-doses-section-panel')),
    );
    final doseSectionDecoration = doseSectionPanel.decoration! as BoxDecoration;
    // The dose card is a white panel crowned by a dark premium header band; the
    // outer panel itself stays white with no gradient or colour fill (the dark
    // band is an inner container).
    expect(doseSectionDecoration.gradient, isNull);
    expect(doseSectionDecoration.color, MedGuardPalette.pureWhite);
    expect(find.text('Dose Schedule'), findsOneWidget);
    // With no schedules saved, the section's single action is the panel's "Add a
    // reminder" button; the "See all" link only appears once doses exist.
    expect(find.text('See all'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-dose-week-calendar')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-dose-week-calendar')),
        matching: find.text('W'),
      ),
      findsOneWidget,
    );
    expect(find.text('Mon'), findsNothing);
    expect(find.text('Up next today'), findsNothing);
    // With no schedules saved the dose card shows the setup prompt rather than
    // any demo doses.
    expect(find.byKey(const ValueKey('home-dose-setup-empty')), findsOneWidget);
    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('NEXT DOSE'), findsNothing);
    expect(find.text('Later today'), findsNothing);
    expect(find.text('Metformin 500 mg'), findsNothing);
    expect(find.text('Amlodipine 5 mg'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-did-you-know-section')),
      findsOneWidget,
    );
    expect(find.text('Did you know'), findsOneWidget);
    expect(
      find.text(
        'Taking doses at consistent times helps clinicians spot patterns.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Small changes are easier to review when your routine is steady.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-break-before-alerts')),
      findsNothing,
    );
    expect(find.text('Safety signal'), findsNothing);
    expect(
      find.text(
        'Warnings stay separate so real issues do not blend into routine care.',
      ),
      findsNothing,
    );
    expect(find.text('Cross-verified data sources'), findsNothing);
    expect(find.text('Pharmacist’s note'), findsNothing);
    expect(find.text('From a pharmacist'), findsNothing);
    expect(
      find.text('Most routines take about two weeks to feel natural.'),
      findsNothing,
    );
    // The "Finish setting up" mini was removed; the app-wide Alerts timeline at
    // the end of the feed now carries the profile/allergies/reminders state.
    expect(find.byKey(const ValueKey('home-action-center-mini')), findsNothing);
    expect(find.byKey(const ValueKey('home-alerts-section')), findsOneWidget);
    // The separate "Start your safety check" summary card was removed; the
    // regimen actions now live as buttons inside the risk gauge.
    expect(
      find.byKey(const ValueKey('home-regimen-safety-summary')),
      findsNothing,
    );
    expect(find.text('Action Center'), findsNothing);
    expect(find.text('Safety Alerts'), findsNothing);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Quick Check'), findsNothing);
    expect(find.text('Add Medicine'), findsNothing);
    expect(find.text('Set Dose'), findsNothing);
    expect(find.text('Share Report'), findsNothing);
    expect(find.text('Care Insights'), findsOneWidget);
    final careInsightsHeading = tester.widget<Text>(find.text('Care Insights'));
    expect(
      careInsightsHeading.style?.fontWeight,
      quickAccessHeading.style?.fontWeight,
    );
    expect(
      careInsightsHeading.style?.fontSize,
      quickAccessHeading.style?.fontSize,
    );
    // Care Insights now sits directly after Regimen Risk.
    expect(
      tester.getTopLeft(find.text('Quick Access')).dy,
      lessThan(tester.getTopLeft(find.text('Regimen Risk')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Regimen Risk')).dy,
      lessThan(tester.getTopLeft(find.text('Care Insights')).dy),
    );
    expect(find.byKey(const ValueKey('home-safety-brief-card')), findsNothing);
    expect(find.text('Safety Brief'), findsNothing);
    expect(find.text('Ready for today'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-medication-truth-section')),
      findsOneWidget,
    );
    expect(find.text('Medication truth'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-medication-truth-accent')),
      findsNothing,
    );
    const expectedTruths = [
      'Some medicines work differently when taken with certain everyday foods.',
      'Generic medicines must match brand drugs for active ingredients too.',
      'Supplements can change how prescriptions behave inside your body.',
      'Medicine cabinets near showers can shorten shelf life over time.',
      'Cold remedies may duplicate ingredients already in prescriptions at home.',
    ];
    expect(find.text(expectedTruths.first), findsOneWidget);
    for (final truth in expectedTruths) {
      expect(visibleWordCount(truth), inInclusiveRange(9, 10));
    }
    // Centre the section so it clears the floating header chrome before tapping.
    await Scrollable.ensureVisible(
      tester.element(
        find.byKey(const ValueKey('home-medication-truth-section')),
      ),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    for (final truth in expectedTruths.skip(1)) {
      await tester.tap(
        find.byKey(const ValueKey('home-medication-truth-section')),
      );
      await tester.pump(const Duration(milliseconds: 360));
      expect(find.text(truth), findsOneWidget);
    }
    final medicationTruthSection = tester.widget<Padding>(
      find.byKey(const ValueKey('home-medication-truth-section')),
    );
    expect(medicationTruthSection.padding, isA<EdgeInsets>());
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('home-medication-truth-section')),
          )
          .dy,
      greaterThan(tester.getTopLeft(find.text('Food-drug checks')).dy),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('home-medication-truth-section')),
          )
          .dy,
      lessThan(tester.getTopLeft(find.text('Dose Schedule')).dy),
    );
    expect(find.text('Medication safety updates to review'), findsOneWidget);
    expect(find.text('Medication safety'), findsOneWidget);
    expect(find.text('FDA update'), findsOneWidget);
    expect(find.text('Pill safety basics'), findsOneWidget);
    expect(find.text('Food-drug checks'), findsOneWidget);
    expect(find.text('Food + drug'), findsOneWidget);
    expect(
      find.text('Food timing can change how medicines work.'),
      findsOneWidget,
    );
    expect(
      find.text('Food timing can change how some medicines are taken.'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-pill-insight-arrow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-food-insight-arrow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-insight-cover-image')),
      findsOneWidget,
    );
    final homeInsightImage = tester.widget<Image>(
      find.byKey(const ValueKey('home-insight-cover-image')),
    );
    expect(
      (homeInsightImage.image as AssetImage).assetName,
      'assets/images/mainshell/03.jpg',
    );
    expect(find.byKey(const ValueKey('home-insight-arrow')), findsOneWidget);
    final insightDescription = tester.widget<Text>(
      find.text(
        'Verified drug safety notices help you spot label changes before they affect a daily routine.',
      ),
    );
    // The copy fits fully at standard sizes; ellipsis + a 3-line cap exist
    // purely as the guard rail for extreme accessibility text scales.
    expect(insightDescription.maxLines, greaterThanOrEqualTo(3));
    expect(
      tester.getTopLeft(find.text('Food-drug checks')).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('home-medication-truth-section')),
            )
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Regimen Risk')).dy,
      lessThan(tester.getTopLeft(find.text('Dose Schedule')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Dose Schedule')).dy,
      lessThan(tester.getTopLeft(find.text('Did you know')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Did you know')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('home-alerts-section'))).dy,
      ),
    );
    // Smart Reminders was removed from the Home feed.
    expect(
      find.byKey(const ValueKey('home-smart-reminders-section')),
      findsNothing,
    );
    expect(find.text('Smart Reminders'), findsNothing);
    expect(find.text('Interaction watchlist'), findsNothing);
    expect(find.text('Profile readiness'), findsNothing);
    expect(find.text('Next checks'), findsNothing);
    expect(find.text('2 open'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Dose Schedule')).dy,
      lessThan(tester.getTopLeft(find.text('Did you know')).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-alerts-section'))).dy,
      greaterThan(tester.getTopLeft(find.text('Did you know')).dy),
    );

    // The old "This Week" snapshot is gone — its data lives in the dose panel
    // strip (only when real dose data exists) and the slot now hosts the live
    // The supporting health tip replaces the old Recent Checks section.
    // state, never sample history.
    expect(
      find.byKey(const ValueKey('home-snapshot-section-panel')),
      findsNothing,
    );
    expect(find.text('This Week'), findsNothing);
    // Daily Health Tip and Recent Checks stay removed from the Home feed.
    expect(
      find.byKey(const ValueKey('home-daily-health-tip-section')),
      findsNothing,
    );
    expect(find.text('Daily Health Tip'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-recent-checks-section')),
      findsNothing,
    );
    expect(find.text('Recent checks'), findsNothing);
    expect(find.text('Recent Checks'), findsNothing);
    // No dose data → the dose panel renders without the weekly strip.
    expect(find.byKey(const ValueKey('home-dose-weekly-strip')), findsNothing);
    expect(find.text('Dose streak'), findsNothing);
    expect(find.text('Next check'), findsNothing);
    // Allergy Guard stays removed from the Home feed.
    expect(
      find.byKey(const ValueKey('home-allergy-guard-section')),
      findsNothing,
    );
    expect(find.text('Allergy guard'), findsNothing);

    // The feed scrolls beneath the pinned chrome. Dragging it moves the scroll
    // position.
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey('home-scroll-view')),
    );
    final scrollPosition = scrollView.controller!.position;
    scrollView.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(scrollPosition.pixels, 0);
    await tester.drag(
      find.byKey(const ValueKey('home-scroll-view')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    expect(scrollPosition.pixels, greaterThan(0));
  });

  testWidgets('the regimen gauge reads a major pair as the High tier', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var openedSafety = false;

    // The verdict only renders for a regimen whose interaction review is done.
    await activateRegimen(2);

    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: RegimenRiskCard(
            medications: homeMedications(2),
            loading: false,
            regimenReviewed: true,
            onReview: () => openedSafety = true,
            onLearnMore: () {},
            analyzeRegimenRisk: (_) async => SafetyReport.fromAnalysis(
              drugInteractions: const [
                InteractionResult(
                  drugAId: 1,
                  drugBId: 2,
                  drugAName: 'Medicine 1',
                  drugBName: 'Medicine 2',
                  severity: 'major',
                  effect: 'May increase adverse effects.',
                ),
              ],
              foodInteractions: const [],
              duplicateTherapies: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Interaction risk'), findsOneWidget);
    // The slot that used to hold the caption "Pair status" now carries the
    // canonical verdict instead. The old label was painted in a 12%-alpha
    // colour meant to be a background fill, so it rendered essentially
    // invisible — and it said nothing the headline beneath it did not.
    expect(find.text('Pair status'), findsNothing);
    expect(find.text('High risk'), findsWidgets);
    // Three-tier verdict: a major interaction is the HIGH tier.
    expect(find.text('High-Risk Pair Detected'), findsOneWidget);
    expect(find.text('Major Interaction Flagged'), findsNothing);
    expect(find.text('1 high-risk pair'), findsOneWidget);
    expect(find.text('1 flagged pair'), findsNothing);
    final valueStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.byKey(const ValueKey('risk-meter-value-style')),
    );
    expect(valueStyle.style.fontWeight, FontWeight.w700);
    expect(valueStyle.style.color, MedGuardPalette.rubyDeep);
    final statusText = tester.widget<Text>(
      find.byKey(const ValueKey('risk-status-text')),
    );
    expect(statusText.maxLines, 2);
    expect(statusText.overflow, isNot(TextOverflow.ellipsis));
    expect(statusText.style?.fontWeight, FontWeight.w700);
    expect(statusText.style?.fontSize, inInclusiveRange(18, 21));
    expect(find.byKey(const ValueKey('home-risk-meter-stage')), findsNothing);
    // The graded ring was replaced by a horizontal Low→Moderate→High meter.
    expect(find.byKey(const ValueKey('home-risk-meter')), findsOneWidget);
    expect(find.text('High'), findsWidgets);
    expect(find.byKey(const ValueKey('risk-endpoint-low')), findsNothing);
    expect(find.byKey(const ValueKey('risk-endpoint-high')), findsNothing);
    expect(
      find.byKey(const ValueKey('home-risk-context-strip')),
      findsOneWidget,
    );
    // The main concern now reads as a quiet label with the concern bold beneath.
    expect(find.text('Main concern'), findsOneWidget);
    // The combination appears both in the takeaway strip and as the primary risk
    // driver's title beneath the meter.
    expect(find.text('Medicine 1 + Medicine 2'), findsWidgets);
    // The old "what we screened" grid was replaced by the higher-value primary
    // risk driver: the single most concerning finding + a clinical next step.
    expect(find.byKey(const ValueKey('home-risk-driver')), findsOneWidget);
    expect(find.text('PRIMARY RISK DRIVER'), findsOneWidget);
    expect(find.text('Clinical priority'), findsOneWidget);
    expect(find.text('WHAT WE SCREENED'), findsNothing);
    expect(find.byKey(const ValueKey('home-risk-screened')), findsNothing);
    expect(find.text('Recommended action'), findsNothing);
    // The Next Step section (and its advice card) was removed.
    expect(find.text('NEXT STEP'), findsNothing);
    expect(find.byKey(const ValueKey('home-risk-advice-panel')), findsNothing);
    expect(find.text('Reason'), findsNothing);
    expect(find.text('Action'), findsNothing);
    expect(find.text('What this means'), findsNothing);
    expect(find.text('What to do'), findsNothing);
    expect(find.text('Dangerous'), findsNothing);
    expect(find.text('Major risk'), findsNothing);
    expect(find.byKey(const ValueKey('home-risk-advice-more')), findsNothing);
    expect(find.textContaining('Could cause:'), findsNothing);
    // The standalone safety-summary card was removed; the gauge itself carries
    // the verdict and the actions.
    expect(
      find.byKey(const ValueKey('home-regimen-safety-summary')),
      findsNothing,
    );
    expect(
      find.text('Call a pharmacist or clinician before the next dose.'),
      findsNothing,
    );
    // With a real (dangerous) verdict, the "Review" button appears in
    // the gauge's action row, below the verdict headline.
    expect(
      find.byKey(const ValueKey('home-risk-review-action')),
      findsOneWidget,
    );
    expect(
      tester.getBottomRight(find.text('High-Risk Pair Detected')).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('home-risk-review-action')))
            .dy,
      ),
    );

    // The gauge's own Review action hands off to the report.
    await tester.tap(find.byKey(const ValueKey('home-risk-review-action')));
    await tester.pumpAndSettle();

    expect(openedSafety, isTrue);
  });

  testWidgets('the regimen gauge reads moderate pairs as the Moderate tier', (
    tester,
  ) async {
    final interactions = List.generate(
      9,
      (index) => InteractionResult(
        drugAId: index + 1,
        drugBId: ((index + 1) % 9) + 1,
        drugAName: 'Medicine ${index + 1}',
        drugBName: 'Medicine ${((index + 1) % 9) + 1}',
        severity: 'moderate',
        effect: 'May need timing review.',
      ),
    );

    // The verdict only renders for a regimen whose interaction review is done.
    await activateRegimen(9);

    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: RegimenRiskCard(
            medications: homeMedications(9),
            loading: false,
            regimenReviewed: true,
            onReview: () {},
            onLearnMore: () {},
            analyzeRegimenRisk: (_) async => SafetyReport.fromAnalysis(
              drugInteractions: interactions,
              foodInteractions: const [],
              duplicateTherapies: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Three-tier verdict: moderate pairs are now their own MODERATE tier — not
    // folded into a binary "not dangerous", and not escalated to High.
    expect(find.text('Moderate-Risk Pairs Found'), findsOneWidget);
    expect(find.text('No Dangerous Findings'), findsNothing);
    expect(find.text('High-Risk Pairs Detected'), findsNothing);
    expect(find.text('9 moderate pairs'), findsOneWidget);
    expect(find.text('Use with care — worth monitoring'), findsOneWidget);
    // The meter value reads in the canonical Moderate amber tone
    // (SeverityColors.moderate), matching every other severity surface.
    final valueStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.byKey(const ValueKey('risk-meter-value-style')),
    );
    expect(valueStyle.style.color, const Color(0xFFB45309));
    // The primary risk driver panel replaces the old "what we screened" grid:
    // it names the single most concerning finding and the clinical next step.
    expect(find.byKey(const ValueKey('home-risk-driver')), findsOneWidget);
    expect(find.text('PRIMARY RISK DRIVER'), findsOneWidget);
    expect(find.text('Clinical priority'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-risk-screened')), findsNothing);
    expect(find.text('WHAT WE SCREENED'), findsNothing);
    expect(find.text("WHAT'S DRIVING THIS"), findsNothing);
    expect(find.text('RECOMMENDED ACTION'), findsNothing);
    expect(find.byKey(const ValueKey('home-risk-advice-panel')), findsNothing);
  });

  testWidgets('offline connection shows only on the avatar dot', (
    tester,
  ) async {
    final offlineService = ConnectivityService(probe: () async => false);

    await pumpScreen(
      tester,
      HomeScreen(
        showNavigation: false,
        loadMedications: () async => const [],
        connectivityService: offlineService,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // The Safety Pulse pill is gone — connection state lives only on the
    // profile avatar's status dot, which turns red when offline.
    expect(find.byKey(const ValueKey('home-care-signal-pill')), findsNothing);
    expect(find.text('Offline'), findsNothing);
    final avatarStatus = tester.widget<Container>(
      find.byKey(const ValueKey('home-avatar-connection-dot')),
    );
    final avatarStatusDecoration = avatarStatus.decoration! as BoxDecoration;
    expect(avatarStatusDecoration.color, const Color(0xFFFF6B6B));
  });

  testWidgets('insights is a news feed, and the AI tab is its own shell', (
    tester,
  ) async {
    await pumpScreen(tester, const InsightsScreen(showNavigation: false));
    await tester.pump();
    expect(find.text('Insights'), findsWidgets);
    // A real, attributed feed — not the old placeholder.
    expect(find.text('Fresh insights are coming'), findsNothing);
    expect(find.textContaining('min read'), findsWidgets);
    // The quiz and the fact break sit mid-feed, below the fold.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('insights-quiz')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('insights-quiz')), findsOneWidget);
    expect(find.text('QUICK CHECK'), findsOneWidget);

    await pumpScreen(tester, const AiScreen(showNavigation: false));
    await tester.pump();
    expect(find.text('Ask anything'), findsOneWidget);
    expect(find.byType(SiriOrb), findsOneWidget);
    // The input is the app's shared glass, not a one-off variant.
    expect(
      find.ancestor(
        of: find.text('Ask anything'),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dose page renders its full board before any schedule exists', (
    tester,
  ) async {
    await pumpScreen(tester, const DoseScreen(showNavigation: false));
    await tester.pump();

    // The page is designed to be useful from the very first launch: the
    // header, the range selector and every panel are present with no schedule
    // saved — it never hides behind an "add a medication first" wall.
    expect(find.text('Doses'), findsWidgets);
    expect(find.byType(FloatingNavBar), findsNothing);
    for (final label in ['Day', 'Week', 'Month']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Adherence'), findsOneWidget);
    expect(find.text('Timing'), findsOneWidget);
    expect(find.text('Supply & refills'), findsOneWidget);
  });

  testWidgets('dose range selector switches the body between views', (
    tester,
  ) async {
    await pumpScreen(tester, const DoseScreen(showNavigation: false));
    await tester.pump();

    // Day view: the selected day's timeline, and the calendar as a week row.
    // "Scheduled" is unique to the calendar legend, so it stands in for the
    // calendar being present.
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    // Per-medicine adherence is meaningless over one day, so it stays out.
    expect(find.text('By medicine'), findsNothing);

    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Week view ADDS the per-medicine breakdown. It does not take the day
    // timeline away: tapping a date must always be able to answer "what is due
    // on that date", whichever range is selected.
    expect(find.text('By medicine'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
  });

  testWidgets('top-level pages share the same standalone bottom spacing', (
    tester,
  ) async {
    Future<Size> pumpAndReadBottomSpacer(Widget screen, Key spacerKey) async {
      await pumpScreen(tester, screen);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(spacerKey));
    }

    final homeSpacer = await pumpAndReadBottomSpacer(
      const HomeScreen(showNavigation: false),
      const ValueKey('home-bottom-content-spacer'),
    );

    // Halved along with the nav-clearing variant above.
    expect(homeSpacer.height, inInclusiveRange(0.5, 3));
  });

  testWidgets('tab pages reserve enough space for the floating nav overlay', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Size> pumpAndReadBottomSpacer(Widget screen, Key spacerKey) async {
      await pumpScreen(tester, screen);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(spacerKey));
    }

    // Profile is no longer one of these: it moved off the tab bar and onto its
    // own route, so it has no floating nav to clear.
    final homeSpacer = await pumpAndReadBottomSpacer(
      const HomeScreen(
        showNavigation: false,
        bottomContentPadding: kFloatingNavReserveHeight,
      ),
      const ValueKey('home-bottom-content-spacer'),
    );

    // Half of what it used to reserve (was 12–18): the gap between the last
    // card and the floating nav was doubling the device's own bottom inset,
    // which the system already guarantees.
    expect(homeSpacer.height, inInclusiveRange(9, 13));
  });

  testWidgets('home quick action runs immediately without a colour flash', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var openedSearch = false;

    await pumpScreen(
      tester,
      HomeScreen(
        showNavigation: false,
        onOpenSearch: () => openedSearch = true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('quick-access-card-library')));
    await tester.pump();

    // The quick-access tile no longer flashes the app colour before navigating:
    // tapping runs its action immediately and the tile keeps its resting style.
    final tappedQuickAccess = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('quick-access-card-library')),
    );
    final tappedQuickAccessDecoration =
        tappedQuickAccess.decoration! as BoxDecoration;
    expect(tappedQuickAccessDecoration.color, isNot(MedGuardPalette.teal));
    expect(openedSearch, isTrue);

    await tester.pumpAndSettle();

    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey('home-scroll-view')),
    );
    final scrollPosition = scrollView.controller!.position;
    expect(scrollPosition.pixels, 0);

    // Tapping a section pill scrolls its section into view beneath the chrome.
    await tester.drag(
      find.byKey(const ValueKey('home-section-filter-row')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-section-filter-alerts')));
    await tester.pump();

    // The tapped pill turns teal and stays active (no flash-back).
    final armedFilter = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('home-section-filter-alerts')),
    );
    final armedFilterDecoration = armedFilter.decoration! as BoxDecoration;
    expect(armedFilterDecoration.color, MedGuardPalette.teal);

    await tester.pumpAndSettle();
    expect(scrollPosition.pixels, greaterThan(0));
  });

  testWidgets('the home risk card opens the Interactions screen', (
    tester,
  ) async {
    var openedSafety = false;

    // Home's risk block is a pointer, not a gauge: its whole job is to hand the
    // user off to the screen where the regimen can actually be worked on.
    await pumpScreen(
      tester,
      HomeScreen(
        showNavigation: false,
        loadMedications: () async => homeMedications(2),
        analyzeRegimenRisk: (_) async => SafetyReport.fromAnalysis(
          drugInteractions: const [],
          foodInteractions: const [],
          duplicateTherapies: const [],
        ),
        onOpenSafety: () => openedSafety = true,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Centre the card so it clears the floating header chrome before tapping.
    const card = ValueKey('home-risk-review-action');
    await Scrollable.ensureVisible(
      tester.element(find.byKey(card)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(card));
    await tester.pumpAndSettle();

    expect(openedSafety, isTrue);
  });

  testWidgets('home dose calendar reveals the selected day\'s schedule', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    sqfliteFfiInit();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => UserDataService.createDoseSchema(db),
      ),
    );
    addTearDown(db.close);
    final service = DoseService(databaseProvider: () async => db);
    // Three daily medicines that begin on different days of the visible week
    // (Sun 10 May … Sat 16 May), so each calendar day reveals a different set.
    await service.addSchedule(
      DoseSchedule(
        id: 0,
        userId: 'local-device',
        drugId: 1,
        drugName: 'Metformin',
        amount: 500,
        unit: 'mg',
        frequency: DoseFrequency.onceDaily,
        timeSlots: const ['08:00'],
        startDate: DateTime(2026, 5, 11),
        createdAt: DateTime(2026, 5, 11),
      ),
    );
    await service.addSchedule(
      DoseSchedule(
        id: 0,
        userId: 'local-device',
        drugId: 2,
        drugName: 'Lisinopril',
        amount: 10,
        unit: 'mg',
        frequency: DoseFrequency.onceDaily,
        timeSlots: const ['14:00'],
        startDate: DateTime(2026, 5, 13),
        createdAt: DateTime(2026, 5, 13),
      ),
    );
    await service.addSchedule(
      DoseSchedule(
        id: 0,
        userId: 'local-device',
        drugId: 3,
        drugName: 'Amlodipine',
        amount: 5,
        unit: 'mg',
        frequency: DoseFrequency.onceDaily,
        timeSlots: const ['21:00'],
        startDate: DateTime(2026, 5, 15),
        createdAt: DateTime(2026, 5, 15),
      ),
    );

    await pumpScreen(
      tester,
      HomeScreen(
        showNavigation: false,
        loadMedications: () async => const [],
        doseService: service,
        now: () => DateTime(2026, 5, 15),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final calendar = find.byKey(const ValueKey('home-dose-week-calendar'));
    final dosePanel = find.byKey(const ValueKey('home-doses-section-panel'));
    Finder inDosePanel(String text) =>
        find.descendant(of: dosePanel, matching: find.text(text));

    // Default selection is today (Friday 15 May) — all three are active.
    await tester.ensureVisible(calendar);
    await tester.pumpAndSettle();
    expect(find.text('Friday 15 May'), findsOneWidget);
    expect(inDosePanel('Today'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('Lisinopril 10 mg'), findsOneWidget);
    expect(find.text('Amlodipine 5 mg'), findsOneWidget);
    expect(find.text('No doses scheduled'), findsNothing);

    // A day before any schedule started (Sunday 10) shows the rest state.
    await tester.tap(find.descendant(of: calendar, matching: find.text('10')));
    await tester.pumpAndSettle();
    expect(find.text('Sunday 10 May'), findsOneWidget);
    expect(find.text('No doses scheduled'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsNothing);
    expect(inDosePanel('Today'), findsNothing);

    // Monday 11 — only Metformin has started by then.
    await tester.tap(find.descendant(of: calendar, matching: find.text('11')));
    await tester.pumpAndSettle();
    expect(find.text('Monday 11 May'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('Lisinopril 10 mg'), findsNothing);
    expect(find.text('Amlodipine 5 mg'), findsNothing);
  });

  testWidgets(
    'profile shows the record, and sends preferences to Settings',
    (tester) async {
      await pumpScreen(tester, const ProfileScreen());
      await tester.pumpAndSettle();

      // Profile is about what MedGuard KNOWS: identity, what is in the record
      // and how complete it is, what the user has been doing, and who else is
      // tracked.
      expect(find.text('Your record'), findsOneWidget);
      expect(find.text('Your activity'), findsOneWidget);
      expect(find.text('Care circle'), findsOneWidget);

      // "Your record" and "Safety picture" were two sections describing the
      // same four areas — one counting them, one listing what was missing from
      // them — with a "Jump to" pair of tiles below re-linking one of them a
      // third time. One section now carries the count, the completeness and the
      // way in for each area.
      expect(find.text('Safety picture'), findsNothing);
      expect(find.text('Jump to'), findsNothing);
      expect(find.text('Adherence'), findsNothing);

      // Each record area appears exactly once, and the emergency card is one of
      // them rather than a shortcut tile two sections further down.
      expect(find.text('Medicines'), findsOneWidget);
      expect(find.text('Allergies'), findsOneWidget);
      expect(find.text('Emergency card'), findsOneWidget);
      expect(find.text('Check history'), findsOneWidget);

      // …and NOT about preferences. Every one of these moved to Settings; a
      // profile page that still carried them is exactly the mixing this split
      // undid.
      expect(find.text('General settings'), findsNothing);
      expect(find.text('Account settings'), findsNothing);
      expect(find.text('Export my data'), findsNothing);
      expect(find.text('Dark mode'), findsNothing);
      expect(find.text('Report issue'), findsNothing);

      // The way through to them is one control, in the header.
      expect(
        find.descendant(
          of: find.byType(DetailPageAction),
          matching: find.byIcon(Icons.settings_rounded),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('settings screen carries every preference, grouped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await pumpScreen(tester, const SettingsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Dose reminders'), findsOneWidget);
    expect(find.text('Safety alerts'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Export my data'), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('Delete all my data'), findsOneWidget);

    // The summary is a cadence, not a switch — and it shows its current value
    // on the row so the setting is legible without opening it.
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text(SummaryInterval.off.label), findsOneWidget);
  });

  testWidgets('summary row opens a cadence picker and persists the choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await pumpScreen(tester, const SettingsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    // Every cadence is offered, each with the window it covers.
    for (final interval in SummaryInterval.values) {
      expect(find.text(interval.label), findsWidgets);
    }

    await tester.tap(find.text(SummaryInterval.monthly.label).last);
    await tester.pumpAndSettle();

    expect(await NotificationPreferences.summaryInterval(),
        SummaryInterval.monthly);
  });

  testWidgets('profile surfaces the care profile captured at sign-up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    await AuthProfilePreferences.save(
      const SignupProfileContext(
        displayName: 'Ada',
        signUpMethod: 'google',
        accountType: 'Patient or caregiver',
        careTarget: 'Patient or caregiver',
        medicationLoad: '2-5 medicines',
        safetyFocus: 'Interactions, Allergy alerts',
        healthDetails: 'Allergies, Kidney or liver concerns',
        reminderPreference: 'Dose-by-dose reminders',
      ),
    );

    await pumpScreen(tester, const ProfileScreen());
    await tester.pumpAndSettle();

    expect(find.text('Your care profile'), findsOneWidget);
    expect(find.text('Managing for'), findsOneWidget);
    expect(find.text('Medication load'), findsOneWidget);
    expect(find.text('Safety focus'), findsOneWidget);
    expect(find.text('Health details'), findsOneWidget);
    expect(find.text('Reminder style'), findsOneWidget);
    expect(find.text('2-5 medicines'), findsOneWidget);
    expect(find.text('Interactions, Allergy alerts'), findsOneWidget);
    expect(find.text('Allergies, Kidney or liver concerns'), findsOneWidget);
    expect(find.text('Dose-by-dose reminders'), findsOneWidget);
  });
}
