import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_profile_preferences.dart';

/// Single entry point for every authentication action in the app.
///
/// Before this existed, the login and register screens each inlined their own
/// `_authProviderFor` switch and called `FirebaseAuth.signInWithProvider`
/// directly — duplicated logic, and for Google it used the web/Custom-Tab OAuth
/// flow that users reported as "loads briefly then enters without finishing".
///
/// Google now goes through the native [GoogleSignIn] account picker and we
/// exchange its ID token for a Firebase credential. Microsoft and Apple keep
/// the Firebase OAuth-provider flow (no dedicated native SDK is bundled for
/// them). Everything funnels through here so sign-in, sign-out and display-name
/// persistence behave identically wherever they're triggered.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// OAuth web/server client (google-services.json `client_type: 3`). On
  /// Android this is required for [GoogleSignIn] to return an ID token whose
  /// audience Firebase will accept.
  static const String _serverClientId =
      '745899760331-5282oa56qbt372k2au8jkthern4dpbre.apps.googleusercontent.com';

  /// OAuth iOS client (google-services.json `client_type: 2`). Used to drive the
  /// native sheet on iOS/macOS. The matching reversed-client-id URL scheme must
  /// be present in ios/Runner/Info.plist.
  static const String _iosClientId =
      '745899760331-dit1grkfcvvat6qv72lt55239injovvi.apps.googleusercontent.com';

  bool _googleInitialized = false;

  /// [GoogleSignIn] v7 requires a one-time [GoogleSignIn.initialize] before any
  /// sign-in call. Safe to await repeatedly — it only runs once.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
          ? _iosClientId
          : null,
      serverClientId: _serverClientId,
    );
    _googleInitialized = true;
  }

  /// Interactive Google sign-in via the native picker, exchanged for a Firebase
  /// session. Throws [GoogleSignInException] (e.g. `canceled`) on failure and
  /// [FirebaseAuthException] if the credential is rejected — both are rendered
  /// by `authErrorMessage`.
  Future<UserCredential> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      // No ID token means we can't build a Firebase credential — surface it as a
      // normal auth failure rather than entering the app half-authenticated.
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google did not return the information needed to sign in.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithMicrosoft() {
    return FirebaseAuth.instance.signInWithProvider(MicrosoftAuthProvider());
  }

  Future<UserCredential> signInWithApple() {
    return FirebaseAuth.instance.signInWithProvider(
      AppleAuthProvider()
        ..addScope('email')
        ..addScope('name'),
    );
  }

  /// Persist [name] as the account's display name so every screen that reads
  /// `currentUser.displayName` (home header, profile, emergency widget) shows it
  /// immediately and after a relaunch. No-op when the name is blank or already
  /// current. Also refreshes the local fallback cache.
  Future<void> persistDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.displayName?.trim() == trimmed) {
      AuthProfilePreferences.cacheDisplayName(trimmed);
      return;
    }
    await user.updateDisplayName(trimmed);
    await user.reload();
    AuthProfilePreferences.cacheDisplayName(trimmed);
  }

  /// Full sign-out: clears the Google session (so the next sign-in shows the
  /// account picker and a different account can be chosen) and the Firebase
  /// session, then drops the cached display name. Every step is best-effort so a
  /// missing/uninitialised provider never blocks logout.
  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google not initialised / not the active provider — nothing to clear.
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Firebase may be unavailable (tests / offline desktop).
    }
    AuthProfilePreferences.clearCache();
  }
}
