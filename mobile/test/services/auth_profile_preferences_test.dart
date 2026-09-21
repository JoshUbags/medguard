import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/auth_profile_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The display-name cache is a process-wide static; reset it before each test
  // so cases don't leak a name into one another.
  setUp(AuthProfilePreferences.clearCache);

  test('saves signup profile context locally for later profile use', () async {
    SharedPreferences.setMockInitialValues({});

    await AuthProfilePreferences.save(
      const SignupProfileContext(
        displayName: 'Ada',
        signUpMethod: 'google',
        accountType: 'Patient or caregiver',
        careTarget: 'Myself',
        medicationLoad: '2-5 medicines',
        safetyFocus: 'Interactions',
        healthDetails: 'Allergies, Kidney or liver concerns',
        reminderPreference: 'Dose-by-dose reminders',
      ),
    );

    final loaded = await AuthProfilePreferences.load();

    expect(loaded?.displayName, 'Ada');
    expect(loaded?.signUpMethod, 'google');
    expect(loaded?.accountType, 'Patient or caregiver');
    expect(loaded?.careTarget, 'Myself');
    expect(loaded?.medicationLoad, '2-5 medicines');
    expect(loaded?.safetyFocus, 'Interactions');
    expect(loaded?.healthDetails, 'Allergies, Kidney or liver concerns');
    expect(loaded?.reminderPreference, 'Dose-by-dose reminders');
  });

  test(
    'loads older signup profile context without new optional answers',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_profile_display_name': 'Ada',
        'auth_profile_sign_up_method': 'email',
        'auth_profile_account_type': 'Myself',
        'auth_profile_care_target': 'Myself',
        'auth_profile_medication_load': '1 medicine',
        'auth_profile_safety_focus': 'Interactions',
      });

      final loaded = await AuthProfilePreferences.load();

      expect(loaded?.healthDetails, '');
      expect(loaded?.reminderPreference, '');
    },
  );

  group('display name resolution (never "Guest" after a valid sign-in)', () {
    test('prefers the authenticated account name over everything else', () {
      AuthProfilePreferences.cacheDisplayName('Saved Name');
      expect(
        AuthProfilePreferences.resolveDisplayName(
          firebaseDisplayName: 'Ada Lovelace',
        ),
        'Ada Lovelace',
      );
    });

    test('falls back to the locally saved name when auth name is blank', () {
      AuthProfilePreferences.cacheDisplayName('Ada Lovelace');
      expect(
        AuthProfilePreferences.resolveDisplayName(firebaseDisplayName: '  '),
        'Ada Lovelace',
      );
      expect(
        AuthProfilePreferences.resolveDisplayName(firebaseDisplayName: null),
        'Ada Lovelace',
      );
    });

    test('uses the fallback only when no name exists anywhere', () {
      expect(
        AuthProfilePreferences.resolveDisplayName(firebaseDisplayName: null),
        'Guest',
      );
      expect(
        AuthProfilePreferences.resolveDisplayName(
          firebaseDisplayName: null,
          fallback: 'MedGuard user',
        ),
        'MedGuard user',
      );
    });

    test('saving a profile populates the cache for synchronous reads', () async {
      SharedPreferences.setMockInitialValues({});
      await AuthProfilePreferences.save(
        const SignupProfileContext(
          displayName: 'Grace Hopper',
          signUpMethod: 'google',
          accountType: 'Myself',
          careTarget: 'Myself',
          medicationLoad: '1 medicine',
          safetyFocus: 'Interactions',
        ),
      );
      expect(AuthProfilePreferences.cachedDisplayName, 'Grace Hopper');
      expect(
        AuthProfilePreferences.resolveDisplayName(firebaseDisplayName: null),
        'Grace Hopper',
      );
    });

    test('loadCache hydrates the saved name from disk', () async {
      SharedPreferences.setMockInitialValues({
        'auth_profile_display_name': 'Katherine Johnson',
      });
      await AuthProfilePreferences.loadCache();
      expect(AuthProfilePreferences.cachedDisplayName, 'Katherine Johnson');
    });

    test('clearCache drops the saved name (used on sign-out)', () {
      AuthProfilePreferences.cacheDisplayName('Ada Lovelace');
      AuthProfilePreferences.clearCache();
      expect(AuthProfilePreferences.cachedDisplayName, isNull);
      expect(
        AuthProfilePreferences.resolveDisplayName(firebaseDisplayName: ''),
        'Guest',
      );
    });

    test('blank names are normalised to no cached value', () {
      AuthProfilePreferences.cacheDisplayName('   ');
      expect(AuthProfilePreferences.cachedDisplayName, isNull);
    });
  });
}
