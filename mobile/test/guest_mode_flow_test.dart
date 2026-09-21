import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app_startup.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/loading/loading_screen.dart';
import 'package:mobile/screens/loading/startup_animation.dart';
import 'package:mobile/screens/main_shell.dart';
import 'package:mobile/screens/onboarding/onboarding_chrome.dart';
import 'package:mobile/screens/onboarding/safety_checks_overview_screen.dart';
import 'package:mobile/screens/profile/profile_screen.dart';
import 'package:mobile/screens/safety/check_history_screen.dart';
import 'package:mobile/screens/welcome/welcome_screen.dart';
import 'package:mobile/services/guest_mode_service.dart';
import 'package:mobile/services/onboarding_preferences.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/common/sign_in_wall.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MedGuard's safety engine is entirely on-device, so the app must be usable
/// with no account and no network. These tests pin the two halves of that
/// promise: that there is always a way past the sign-in wall, and that what
/// sign-in still gates says so rather than simply failing.
void main() {
  /// A stand-in for the real main shell. The genuine one boots the encrypted
  /// database and every dashboard service, which a widget test has no business
  /// starting — the routing decision is what is under test here.
  Widget shellStub() => const Scaffold(body: Text('main-shell-stub'));

  Future<void> pumpScreen(WidgetTester tester, Widget screen) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: screen,
        routes: {
          WelcomeScreen.routeName: (_) => const WelcomeScreen(),
          LoginScreen.routeName: (_) => const LoginScreen(),
          RegisterScreen.routeName: (_) => const RegisterScreen(),
          MainShell.routeName: (_) => shellStub(),
        },
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GuestModeService.instance.resetForTest();
  });

  group('the way in without an account', () {
    testWidgets('onboarding offers it, and taking it enters the app', (
      tester,
    ) async {
      await pumpScreen(tester, const SafetyChecksOverviewScreen());

      final action = find.byType(ContinueWithoutAccountAction);
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      // Straight into the app — not into the sign-in screen it sits beside.
      expect(find.text('main-shell-stub'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('the choice is remembered for the next launch', (tester) async {
      await pumpScreen(tester, const SafetyChecksOverviewScreen());
      await tester.tap(find.byType(ContinueWithoutAccountAction));
      await tester.pumpAndSettle();

      expect(GuestModeService.instance.enabled.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(GuestModeService.storageKey), isTrue);
      // Onboarding is finished too — it must not replay on the way back in.
      expect(prefs.getBool(kIsFirstLaunchKey), isFalse);
    });

    testWidgets('entering the app leaves no route back to the wall', (
      tester,
    ) async {
      await pumpScreen(tester, const SafetyChecksOverviewScreen());
      await tester.tap(find.byType(ContinueWithoutAccountAction));
      await tester.pumpAndSettle();

      // The stack is wiped: this is an arrival, so Back exits the app rather
      // than walking back through onboarding into the screen just declined.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('sign-in is no longer a dead end', (tester) async {
      await pumpScreen(tester, const LoginScreen());

      final action = find.byType(ContinueWithoutAccountAction);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('main-shell-stub'), findsOneWidget);
      expect(GuestModeService.instance.enabled.value, isTrue);
    });

    testWidgets('signing in stays the primary path', (tester) async {
      await pumpScreen(tester, const LoginScreen());

      // The local-only route is an alternative offered below the account
      // options, not a competing call to action above them.
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      final signInY = tester.getTopLeft(find.text('Sign In')).dy;
      final guestY = tester
          .getTopLeft(find.byType(ContinueWithoutAccountAction))
          .dy;
      expect(guestY, greaterThan(signInY));
    });
  });

  group('launch routing', () {
    test('a local-only user launches into the app, not the wall', () {
      // The whole point: no account, no network, and the app still opens.
      expect(
        resolveStartupDestination(
          signedIn: false,
          guest: true,
          firstLaunch: false,
        ),
        StartupDestination.app,
      );
    });

    test('a returning user with no account still lands on sign-in', () {
      expect(
        resolveStartupDestination(
          signedIn: false,
          guest: false,
          firstLaunch: false,
        ),
        StartupDestination.signIn,
      );
    });

    test('a first launch still gets the welcome and onboarding', () {
      expect(
        resolveStartupDestination(
          signedIn: false,
          guest: false,
          firstLaunch: true,
        ),
        StartupDestination.welcome,
      );
    });

    test('an account outranks a stale local-only flag', () {
      // Signing in clears the flag asynchronously; a launch that catches the
      // gap must still land the user in their account.
      expect(
        resolveStartupDestination(
          signedIn: true,
          guest: true,
          firstLaunch: false,
        ),
        StartupDestination.app,
      );
    });

    test('local-only outranks first launch — onboarding never replays', () {
      expect(
        resolveStartupDestination(
          signedIn: false,
          guest: true,
          firstLaunch: true,
        ),
        StartupDestination.app,
      );
    });

    testWidgets('the splash routes a local-only launch into the app', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GuestModeService.storageKey: true,
        kIsFirstLaunchKey: false,
      });
      GuestModeService.instance.resetForTest();
      if (!appStartupReady.isCompleted) appStartupReady.complete();

      await pumpScreen(tester, const LoadingScreen());
      await tester.pump();
      expect(find.byType(MedGuardStartupAnimation), findsOneWidget);

      await tester.pump(kStartupIntro);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // The real shell, not a stub: the splash hands over to a widget instance
      // rather than a named route, so this is the only honest assertion that
      // the gate actually opened.
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await pumpScreen(tester, const SizedBox.shrink());
    });
  });

  group('what an account still gates', () {
    testWidgets('check history explains itself rather than failing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GuestModeService.storageKey: true,
      });
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const CheckHistoryScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SignInWall), findsOneWidget);
      // The wall must not imply that running checks is switched off — only
      // that the trail they build up belongs to an account.
      expect(
        find.text('Checks you run are saved here and open when you sign in.'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('the wall opens sign-in without losing the page', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GuestModeService.storageKey: true,
      });
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const CheckHistoryScreen());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      // Pushed, not replaced: changing your mind returns you to the page you
      // were on, with the app still underneath.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
    });

    testWidgets('history is open once there is an account', (tester) async {
      SharedPreferences.setMockInitialValues({});
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const CheckHistoryScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SignInWall), findsNothing);
    });

    testWidgets('the care circle says why, instead of disappearing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GuestModeService.storageKey: true,
      });
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 100));

      // Still present, still named — a caregiver must not conclude MedGuard
      // cannot do this at all.
      expect(find.text('Care circle'), findsOneWidget);
      expect(find.text('Needs an account'), findsOneWidget);
    });
  });

  group('profile, without an account', () {
    testWidgets('states what is already working before what is missing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GuestModeService.storageKey: true,
      });
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No account'), findsOneWidget);
      expect(
        find.text('Every safety check runs offline, on this device.'),
        findsOneWidget,
      );
      // The offer is a description of what an account adds, not a nag.
      expect(find.text('Your check history opens up'), findsOneWidget);
      expect(
        find.text('Your record survives losing this phone'),
        findsOneWidget,
      );
    });

    testWidgets('the section is absent once there is an account', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      GuestModeService.instance.resetForTest();
      await GuestModeService.instance.load();

      await pumpScreen(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No account'), findsNothing);
    });
  });
}
