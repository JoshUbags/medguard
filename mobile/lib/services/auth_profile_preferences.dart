import 'package:shared_preferences/shared_preferences.dart';

class SignupProfileContext {
  const SignupProfileContext({
    required this.displayName,
    required this.signUpMethod,
    required this.accountType,
    required this.careTarget,
    required this.medicationLoad,
    required this.safetyFocus,
    this.healthDetails = '',
    this.reminderPreference = '',
  });

  final String displayName;
  final String signUpMethod;
  final String accountType;
  final String careTarget;
  final String medicationLoad;
  final String safetyFocus;
  final String healthDetails;
  final String reminderPreference;
}

class AuthProfilePreferences {
  const AuthProfilePreferences._();

  /// In-memory copy of the saved display name, kept so synchronous UI builds
  /// (the home header, the profile card) can fall back to it the instant
  /// `FirebaseAuth.currentUser.displayName` is momentarily empty — e.g. right
  /// after a fallback-name sign-up, before the auth user has refreshed. Loaded
  /// once at startup by [loadCache] and kept current by [save] / [signOut].
  static String? _cachedDisplayName;

  static String? get cachedDisplayName => _cachedDisplayName;

  static void cacheDisplayName(String? name) {
    final trimmed = name?.trim();
    _cachedDisplayName = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void clearCache() => _cachedDisplayName = null;

  /// Hydrate [cachedDisplayName] from disk. Call once during app startup.
  static Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      cacheDisplayName(prefs.getString(_displayNameKey));
    } catch (_) {
      // Preferences unavailable — leave the cache empty.
    }
  }

  /// The name to greet the user by, in priority order: the authenticated
  /// account's display name, then the locally saved name, then [fallback]. A
  /// valid Google (or any) sign-in therefore never reads as the fallback.
  static String resolveDisplayName({
    required String? firebaseDisplayName,
    String fallback = 'Guest',
  }) {
    final fromAuth = firebaseDisplayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;
    final cached = _cachedDisplayName;
    if (cached != null && cached.isNotEmpty) return cached;
    return fallback;
  }

  static const _displayNameKey = 'auth_profile_display_name';
  static const _signUpMethodKey = 'auth_profile_sign_up_method';
  static const _accountTypeKey = 'auth_profile_account_type';
  static const _careTargetKey = 'auth_profile_care_target';
  static const _medicationLoadKey = 'auth_profile_medication_load';
  static const _safetyFocusKey = 'auth_profile_safety_focus';
  static const _healthDetailsKey = 'auth_profile_health_details';
  static const _reminderPreferenceKey = 'auth_profile_reminder_preference';

  static Future<void> save(SignupProfileContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, context.displayName);
    cacheDisplayName(context.displayName);
    await prefs.setString(_signUpMethodKey, context.signUpMethod);
    await prefs.setString(_accountTypeKey, context.accountType);
    await prefs.setString(_careTargetKey, context.careTarget);
    await prefs.setString(_medicationLoadKey, context.medicationLoad);
    await prefs.setString(_safetyFocusKey, context.safetyFocus);
    await prefs.setString(_healthDetailsKey, context.healthDetails);
    await prefs.setString(_reminderPreferenceKey, context.reminderPreference);
  }

  static Future<SignupProfileContext?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final accountType = prefs.getString(_accountTypeKey);
    final careTarget = prefs.getString(_careTargetKey);
    final medicationLoad = prefs.getString(_medicationLoadKey);
    final safetyFocus = prefs.getString(_safetyFocusKey);
    if (accountType == null ||
        careTarget == null ||
        medicationLoad == null ||
        safetyFocus == null) {
      return null;
    }

    return SignupProfileContext(
      displayName: prefs.getString(_displayNameKey) ?? '',
      signUpMethod: prefs.getString(_signUpMethodKey) ?? 'email',
      accountType: accountType,
      careTarget: careTarget,
      medicationLoad: medicationLoad,
      safetyFocus: safetyFocus,
      healthDetails: prefs.getString(_healthDetailsKey) ?? '',
      reminderPreference: prefs.getString(_reminderPreferenceKey) ?? '',
    );
  }
}
