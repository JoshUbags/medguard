import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/ai/ai_screen.dart';
import 'package:mobile/screens/auth/forgot_password_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/dose/dose_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/screens/insights/insights_screen.dart';
import 'package:mobile/screens/medications/medications_screen.dart';
import 'package:mobile/screens/onboarding/interaction_review_screen.dart';
import 'package:mobile/screens/onboarding/medication_context_screen.dart';
import 'package:mobile/screens/onboarding/safety_checks_overview_screen.dart';
import 'package:mobile/screens/profile/profile_screen.dart';
import 'package:mobile/screens/welcome/welcome_screen.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every phone/tablet footprint the app must lay out cleanly on — from the
/// smallest supported phone through big Androids to a 10" tablet. Any
/// RenderFlex overflow at any of these sizes fails the sweep.
const _viewports = <Size>[
  Size(320, 568), // smallest supported phone
  Size(360, 640), // compact Android
  Size(390, 844), // iPhone baseline
  Size(412, 915), // Pixel-class Android
  Size(480, 1067), // big-screen Android
  Size(800, 1280), // tablet
];

void main() {
  SharedPreferences.setMockInitialValues({});

  final screens = <String, Widget Function()>{
    'welcome': () => const WelcomeScreen(),
    'onboarding-interaction': () => const InteractionReviewScreen(),
    'onboarding-context': () => const MedicationContextScreen(),
    'onboarding-safety': () => const SafetyChecksOverviewScreen(),
    'login': () => const LoginScreen(),
    'register': () => const RegisterScreen(),
    'forgot-password': () => const ForgotPasswordScreen(),
    'home': () =>
        HomeScreen(showNavigation: true, loadMedications: () async => const []),
    'interactions-tab': () => const MedicationsScreen(),
    'dose-tab': () => const DoseScreen(),
    'insights-tab': () => const InsightsScreen(),
    'ai-tab': () => const AiScreen(),
    'profile': () => const ProfileScreen(),
  };

  Future<void> sweep(
    WidgetTester tester, {
    required ThemeData theme,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in _viewports) {
      tester.view.physicalSize = size;
      for (final entry in screens.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: entry.value(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final exception = tester.takeException();
        expect(
          exception,
          isNull,
          reason:
              '${entry.key} threw at ${size.width.toInt()}x'
              '${size.height.toInt()} (textScale $textScale): $exception',
        );
      }
      // Reset the tree between viewport sizes so stale render state from the
      // previous size can never mask or fabricate an overflow.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }

  testWidgets('no screen overflows at any supported size (light)', (
    tester,
  ) async {
    await sweep(tester, theme: AppTheme.lightTheme);
  });

  testWidgets('no screen overflows at any supported size (dark)', (
    tester,
  ) async {
    await sweep(tester, theme: AppTheme.darkTheme());
  });

  testWidgets('no screen overflows with large accessibility text', (
    tester,
  ) async {
    await sweep(tester, theme: AppTheme.lightTheme, textScale: 1.3);
  });
}
