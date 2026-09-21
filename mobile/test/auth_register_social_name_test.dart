import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/theme/app_theme.dart';

/// For social sign-up the name is collected as the FIRST care-context question
/// (pre-filled from the provider when available) — never on the first
/// "Create Your Account" screen — and it is required so an account is never
/// nameless ("Guest").
///
/// These run without Firebase initialised, which is the "no provider name"
/// condition: RegisterScreen swallows the lookup and routes a pre-auth social
/// user straight to the care-context step with an empty, required name question.
void main() {
  Future<void> pumpRegister(WidgetTester tester, SignupMethod method) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: RegisterScreen(preAuthSocialMethod: method),
      ),
    );
  }

  void sizePhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('name is the first care-context question, not the first screen', (
    tester,
  ) async {
    sizePhone(tester);
    await pumpRegister(tester, SignupMethod.google);
    await tester.pump();

    expect(find.text('Your Care Context'), findsOneWidget);
    expect(find.text('Question 1 of 6'), findsOneWidget);
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.byKey(const ValueKey('register-social-name')), findsOneWidget);
    // Not the credential screen.
    expect(find.byKey(const ValueKey('register-step-account')), findsNothing);
    expect(find.byKey(const ValueKey('register-email')), findsNothing);
  });

  testWidgets('an empty name blocks leaving the first question', (tester) async {
    sizePhone(tester);
    await pumpRegister(tester, SignupMethod.google);
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Question 1 of 6'), findsOneWidget);
    expect(find.text('Question 2 of 6'), findsNothing);
  });

  testWidgets('entering the name advances to the next question', (tester) async {
    sizePhone(tester);
    await pumpRegister(tester, SignupMethod.google);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('register-social-name')),
      'Ada Lovelace',
    );
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Question 2 of 6'), findsOneWidget);
    expect(find.text('Who are you caring for?'), findsOneWidget);
  });
}
