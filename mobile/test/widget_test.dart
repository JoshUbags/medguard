import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app_startup.dart';
import 'package:mobile/main.dart' as medguard_app;
import 'package:mobile/screens/auth/forgot_password_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/privacy_policy_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/auth/terms_conditions_screen.dart';
import 'package:mobile/screens/loading/loading_screen.dart';
import 'package:mobile/screens/loading/startup_animation.dart';
import 'package:mobile/screens/main_shell.dart';
import 'package:mobile/screens/onboarding/interaction_review_screen.dart';
import 'package:mobile/screens/onboarding/medication_context_screen.dart';
import 'package:mobile/screens/onboarding/onboarding_chrome.dart';
import 'package:mobile/screens/onboarding/safety_checks_overview_screen.dart';
import 'package:mobile/screens/welcome/welcome_screen.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/widgets/common/continue_button.dart';
import 'package:mobile/widgets/common/morph_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: screen,
        routes: {
          WelcomeScreen.routeName: (_) => const WelcomeScreen(),
          '/interaction-review': (_) => const InteractionReviewScreen(),
          LoginScreen.routeName: (_) => const LoginScreen(),
          RegisterScreen.routeName: (_) => const RegisterScreen(),
          ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
          PrivacyPolicyScreen.routeName: (_) => const PrivacyPolicyScreen(),
          TermsConditionsScreen.routeName: (_) => const TermsConditionsScreen(),
        },
      ),
    );
  }

  testWidgets('onboarding screens render without error', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const viewportSizes = [Size(360, 780), Size(390, 844), Size(430, 932)];

    for (final size in viewportSizes) {
      tester.view.physicalSize = size;

      await pumpScreen(tester, const WelcomeScreen());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      // The welcome screen has a single bottom tap-to-continue button (the
      // old slide gesture was removed); no top-right action, no "Log In".
      expect(find.byType(ContinueButton), findsOneWidget);
      expect(find.text('Tap to Continue'), findsOneWidget);
      expect(find.text('Slide to continue'), findsNothing);
      expect(find.text('Log In'), findsNothing);

      await pumpScreen(tester, const InteractionReviewScreen());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.textContaining('Review Drug'), findsOneWidget);
      expect(
        find.text(
          'MedGuard turns drug-pair warnings into clear risk, action, and monitoring cues.',
        ),
        findsOneWidget,
      );
      final interactionBody = tester.widget<Text>(
        find.text(
          'MedGuard turns drug-pair warnings into clear risk, action, and monitoring cues.',
        ),
      );
      expect(interactionBody.style?.fontStyle, isNot(FontStyle.italic));
      expect(find.text('Tap a step to update Case 024.'), findsOneWidget);
      expect(find.text('Severity Signal'), findsOneWidget);
      expect(find.text('Decision Ready'), findsOneWidget);
      expect(find.text('Major bleeding signal'), findsOneWidget);
      expect(
        find.text('Warfarin with ibuprofen may increase bleeding risk.'),
        findsOneWidget,
      );
      expect(find.text('Monitor'), findsOneWidget);
      // Step 2 advances with the original Next button, not the welcome CTA.
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(ContinueButton), findsNothing);

      await pumpScreen(tester, const MedicationContextScreen());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Context Linked'), findsOneWidget);
      final medicationBody = tester.widget<Text>(
        find.text(
          'Keep medicine pairs, timing notes, and counselling context together.',
        ),
      );
      expect(medicationBody.style?.fontStyle, isNot(FontStyle.italic));

      await pumpScreen(tester, const SafetyChecksOverviewScreen());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Five Risk Areas'), findsOneWidget);
      final safetyBody = tester.widget<Text>(
        find.text(
          'MedGuard checks interactions, food conflicts, duplication, dosing, and patient flags.',
        ),
      );
      expect(safetyBody.style?.fontStyle, isNot(FontStyle.italic));
      expect(find.text('Profile Flags'), findsOneWidget);
      // Onboarding steps 2–4 advance with the original Next button; the
      // tap-to-continue CTA lives only on the Welcome screen.
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(ContinueButton), findsNothing);
    }
  });

  testWidgets('splash plays the brand launch animation, then hands over', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // In the real app main() completes this once Firebase init finishes; the
    // loading screen waits for it before routing. Simulate that here so the
    // gate can resolve. (Guarded — the global completes at most once.)
    if (!appStartupReady.isCompleted) appStartupReady.complete();

    await pumpScreen(tester, const LoadingScreen());
    await tester.pump();

    // The launch gate is the branded lockup on the brand backdrop — and the
    // mark inside it is the app's OWN loader at display size, not a generic
    // spinner. The splash and every in-app loading state are deliberately the
    // same object, so a user learns one "MedGuard is working" animation.
    expect(find.byType(MedGuardStartupAnimation), findsOneWidget);
    expect(find.byType(StartupBackdrop), findsOneWidget);
    expect(find.byType(MorphLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // It holds while the intro plays rather than cutting away mid-sequence…
    await tester.pump(kStartupIntro ~/ 2);
    expect(find.byType(WelcomeScreen), findsNothing);

    // …then, first launch + signed out, the fade route lands on Welcome.
    await tester.pump(kStartupIntro);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await pumpScreen(tester, const SizedBox.shrink());
  });

  test('the launch sequence stays inside its budget', () {
    // The brief: a few seconds at most, never an open-ended wait. The intro is
    // what the user watches; the ceiling is the hard bound on a slow cold boot.
    expect(kStartupIntro.inMilliseconds, lessThanOrEqualTo(2500));
    expect(kStartupCeiling.inSeconds, lessThanOrEqualTo(5));
    expect(kStartupCeiling, greaterThan(kStartupIntro));
  });

  test('welcome is no longer counted as onboarding', () {
    expect(kOnboardingPageCount, 3);
  });

  test('onboarding route uses visible slide timing', () {
    final route =
        onboardingSlideRoute<void>(const Placeholder()) as PageRoute<void>;
    expect(route.transitionDuration, const Duration(milliseconds: 360));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 280));
  });

  test('debug start modes resolve only to onboarding or main app', () {
    expect(
      medguard_app.resolveInitialRouteForStartMode('onboarding'),
      WelcomeScreen.routeName,
    );
    expect(
      medguard_app.resolveInitialRouteForStartMode('main'),
      MainShell.routeName,
    );
    expect(
      medguard_app.resolveInitialRouteForStartMode('/search'),
      LoadingScreen.routeName,
    );
    expect(
      medguard_app.resolveInitialRouteForStartMode('/medications'),
      LoadingScreen.routeName,
    );
    expect(
      medguard_app.resolveInitialRouteForStartMode(''),
      LoadingScreen.routeName,
    );
  });

  testWidgets('onboarding chrome exposes consistent navigation actions', (
    tester,
  ) async {
    await pumpScreen(tester, const InteractionReviewScreen());

    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    // The onboarding footer advances with the original Next button; the
    // tap-to-continue CTA is reserved for the Welcome screen.
    expect(find.text('Next'), findsOneWidget);
    expect(find.byType(ContinueButton), findsNothing);
  });

  testWidgets('login back returns to the previous route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-login'),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).push(onboardingSlideRoute(const LoginScreen()));
                  },
                  child: const Text('Open Login'),
                ),
              ),
            );
          },
        ),
        routes: {
          RegisterScreen.routeName: (_) => const RegisterScreen(),
          ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));
    expect(find.text('Open Login'), findsOneWidget);
  });

  testWidgets('auth screens expose core account actions', (tester) async {
    await pumpScreen(tester, const LoginScreen());

    final panelSize = tester.getSize(
      find.byKey(const ValueKey('login-white-panel')),
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(panelSize.height, greaterThanOrEqualTo(screenHeight * 0.78));
    expect(panelSize.height, lessThanOrEqualTo(screenHeight * 0.84));

    // Pumped as the root route (like right after a sign-out) there is nowhere
    // to go back to — so no dead Back control is shown at all.
    expect(find.text('Back'), findsNothing);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(
      find.text('Enter your details to pick up your medication safety review.'),
      findsOneWidget,
    );
    expect(find.text('Your safety workspace is ready.'), findsNothing);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Sign in with'), findsOneWidget);
    expect(find.textContaining('Sign Up'), findsOneWidget);
    expect(find.byKey(const ValueKey('google-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('microsoft-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('apple-login')), findsOneWidget);

    await pumpScreen(tester, const ForgotPasswordScreen());

    expect(find.text('Forgot password'), findsOneWidget);
    expect(find.text('Your account stays protected.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('register uses a three-step dot navigation flow', (tester) async {
    await pumpScreen(tester, const RegisterScreen());

    expect(find.text('Create Your Account'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('register-step-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('register-step-dot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('register-step-dot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('register-step-dot-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('register-step-account')), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Or sign up with'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('register-name')),
        matching: find.byType(TextFormField),
      ),
      'Ada',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('register-email')),
        matching: find.byType(TextFormField),
      ),
      'ada@example.com',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('register-password')),
        matching: find.byType(TextFormField),
      ),
      'StrongPass123!',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('register-confirm-password')),
        matching: find.byType(TextFormField),
      ),
      'StrongPass123!',
    );

    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('register-step-context')), findsOneWidget);
    expect(find.text('Your Care Context'), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);

    // Step 2 now presents one question at a time. Question 1 is shown; later
    // questions are not in the tree until you advance to them.
    expect(find.text('Question 1 of 5'), findsOneWidget);
    expect(find.text('Who are you caring for?'), findsOneWidget);
    expect(
      find.text('Choose the closest match so MedGuard can label your profile.'),
      findsOneWidget,
    );
    expect(find.text('How many medicines do you track?'), findsNothing);

    // Q1 — care target via a typed "Other" answer, then advance manually.
    await tester.ensureVisible(
      find.byKey(const ValueKey('care-question-care-target-other-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('care-question-care-target-other-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('care-question-care-target-other-field')),
      'elderly parent',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q2 — single select now also requires an explicit Next (no auto-advance).
    expect(find.text('How many medicines do you track?'), findsOneWidget);
    await tester.ensureVisible(find.text('2-5 medicines'));
    await tester.tap(find.text('2-5 medicines'));
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q3 — multi select needs an explicit Next.
    expect(find.text('What matters most to you?'), findsOneWidget);
    await tester.ensureVisible(find.text('Interactions'));
    await tester.tap(find.text('Interactions'));
    await tester.pump();
    await tester.ensureVisible(find.text('Allergy alerts'));
    await tester.tap(find.text('Allergy alerts'));
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q4 — multi select with a typed "Other" answer.
    expect(
      find.text('Which health details should MedGuard consider?'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Allergies'));
    await tester.tap(find.text('Allergies'));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('care-question-health-details-other-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('care-question-health-details-other-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('care-question-health-details-other-field')),
      'needs weekly blood pressure checks at home',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q5 — final single select; an explicit Continue moves to the review step.
    expect(
      find.text('How do you prefer medication reminders?'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Every dose'));
    await tester.tap(find.text('Every dose'));
    await tester.pump();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('register-step-consent')), findsOneWidget);
    expect(find.text('Review & Consent'), findsOneWidget);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Elderly Parent'), findsOneWidget);
    expect(find.text('2-5 medicines'), findsOneWidget);
    expect(find.text('Interactions, Allergy alerts'), findsOneWidget);
    expect(
      find.text('Allergies, Needs weekly blood pressure checks at home'),
      findsOneWidget,
    );
    expect(find.text('Every dose'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Password strength: strong'), findsOneWidget);
    expect(find.text('Terms & Conditions'), findsWidgets);
    expect(find.text('Privacy Policy'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('register-step-dot-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('register-step-account')), findsOneWidget);
  });

  testWidgets('social register still requires context and consent steps', (
    tester,
  ) async {
    await pumpScreen(tester, const RegisterScreen());

    // Choosing Google moves straight to the care-context step; the name is the
    // first question there (pre-filled from anything already typed), not a
    // requirement on the first screen.
    await tester.enterText(
      find.byKey(const ValueKey('register-name')),
      'Ada',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('google-register')));
    await tester.tap(find.byKey(const ValueKey('google-register')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('register-step-context')), findsOneWidget);
    expect(find.text('Connected with Google'), findsOneWidget);
    expect(find.text('Email address'), findsNothing);
    expect(find.text('Question 1 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('register-social-name')), findsOneWidget);

    // Past the (pre-filled) name question, the rest of the context is optional.
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('register-step-consent')), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(
      find.text('Please agree to the Terms & Conditions and Privacy Policy.'),
      findsOneWidget,
    );
  });

  testWidgets('social sign-up asks the name in the care-context step', (
    tester,
  ) async {
    await pumpScreen(tester, const RegisterScreen());

    // Tapping a provider with no name entered does NOT ask for it on the first
    // screen — it advances into the care-context step where the name is the
    // first (required) question.
    await tester.ensureVisible(find.byKey(const ValueKey('google-register')));
    await tester.tap(find.byKey(const ValueKey('google-register')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('register-step-account')), findsNothing);
    expect(find.byKey(const ValueKey('register-step-context')), findsOneWidget);
    expect(find.text('Question 1 of 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('register-social-name')), findsOneWidget);
  });

  testWidgets('onboarding completes into Sign In, and Back returns', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester, const SafetyChecksOverviewScreen());
    expect(find.byType(SafetyChecksOverviewScreen), findsOneWidget);

    // Finishing onboarding lands on Sign In — not Sign Up.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);

    // The top-left Back returns to the actual previous screen (onboarding),
    // because the onboarding stack is preserved rather than wiped.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SafetyChecksOverviewScreen), findsOneWidget);
  });

  testWidgets('Sign Up from Sign In returns to onboarding on back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester, const SafetyChecksOverviewScreen());

    // Onboarding → Sign In.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // Sign In → Create Account is a PUSH, so Back walks the stack honestly:
    // register → sign in → onboarding, with no dead ends after a sign-out.
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Create Your Account'), findsOneWidget);

    // Back from Create Account returns to Sign In…
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // …and Back from Sign In returns to the onboarding screen we came from.
    // (The card kept its scroll position from tapping Sign Up, so bring the
    // Back control into view first.)
    await tester.ensureVisible(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SafetyChecksOverviewScreen), findsOneWidget);
  });
}
