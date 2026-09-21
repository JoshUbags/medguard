# Google Sign-In — setup and device test script

Sign-in goes through the native account picker (`google_sign_in`), and the
returned ID token is exchanged for a Firebase credential. Everything funnels
through [`lib/services/auth_service.dart`](../lib/services/auth_service.dart).

Sign-in is optional: the app has a guest mode, and every safety check runs
on-device either way.

## How it works

1. The user taps **Continue with Google** on the login or register screen.
2. `AuthService.signInWithGoogle()` shows the native picker, gets an ID token,
   and calls `FirebaseAuth.signInWithCredential(...)`.
3. A **returning user** goes straight into the app. A **new user** goes
   through the register flow, which collects care context and consent while
   the user stays authenticated.
4. The display name comes from the Google profile. If Google supplies none,
   the register flow asks for one. The name is written to the Firebase user
   (`updateDisplayName`) and cached locally, so home and profile never read
   "Guest".
5. Sign-out (`AuthService.signOut()`) clears the Google and Firebase sessions
   and the cached name.

## Configuration

Firebase project: `medguard-fa943`.

### Android

- [`android/app/google-services.json`](../android/app/google-services.json)
  holds the web/server OAuth client (`client_type: 3`), which
  `AuthService._serverClientId` passes to `google_sign_in`, plus one Android
  client per registered signing key.
- Registered signing keys (Firebase console → Project settings → Android app):

  | Key | SHA-1 |
  | --- | --- |
  | Release | `1E:19:CC:E0:13:FB:67:A2:C4:7C:E1:83:36:D4:A5:08:60:CC:2E:4A` |
  | Debug (maintainer's machine) | `32:B8:8A:09:8F:9B:D8:DC:AB:E7:4F:56:8C:E1:09:70:03:E3:BA:9F` |

- The Android API key only accepts apps signed with those two keys. A build
  signed with any other key — another machine's debug key, for example — runs
  fully in guest mode, but every Firebase call is refused, so email and Google
  sign-in both fail (Google with `ApiException: 10`). To enable sign-in for
  your key, print its SHA-1:

  ```bash
  cd android && ./gradlew signingReport
  ```

  then add it in both places, and download `google-services.json` again:

  1. Firebase console → Project settings → the Android app → SHA certificate
     fingerprints.
  2. Google Cloud console → APIs & Services → Credentials → the Android key →
     Application restrictions → Android apps (package `com.medguard.app`).

- Firebase console → Authentication → Sign-in method → **Google** must be
  enabled.

### iOS

- Bundle id `com.medguard.app`, registered in Firebase as **MedGuard iOS**.
- Three values have to agree, and all come from that app's
  `GoogleService-Info.plist`:

  | Where | Value |
  | --- | --- |
  | `lib/firebase_options.dart` → `ios` / `macos` | `appId` |
  | `lib/services/auth_service.dart` → `_iosClientId` | `CLIENT_ID` |
  | `ios/Runner/Info.plist` → URL scheme | `REVERSED_CLIENT_ID` |

- `_serverClientId` is the web/server client and is not tied to a bundle id.
  Leave it alone when changing iOS settings.
- `GoogleService-Info.plist` itself is not needed: `AuthService` passes the
  client id explicitly. Add it if you adopt other Firebase iOS services.
- iOS builds need a Mac with Xcode and an Apple Developer Program membership.
  The configuration above is complete, but the iOS app has not been built or
  run on a device.

## Device test script

Use a **debug** build. Debug builds wipe local state and sign out on launch,
which suits the new-user cases. To keep state across restarts (returning-user
and persistence cases), add `--dart-define=MEDGUARD_KEEP_STATE=true`.

1. **New Google user**
   - `flutter run` → Welcome → Login → **Continue with Google** → pick an
     account never used with this app.
   - **Expected:** the native picker appears; after picking, the register flow
     opens (care context, then consent). Completing it lands on Home, greeting
     you by your Google name. Profile shows name, email and photo, if any.

2. **Returning user**
   - `flutter run --dart-define=MEDGUARD_KEEP_STATE=true` → Login →
     **Continue with Google** → the same account.
   - **Expected:** straight into the app with no register flow; name correct.

3. **Session persists across restart**
   - While signed in, close the app fully and relaunch with
     `--dart-define=MEDGUARD_KEEP_STATE=true`.
   - **Expected:** after the loading screen you are in the app, still signed
     in, name intact.

4. **Sign out, then sign in again**
   - Profile → Sign out.
   - **Expected:** back on Login. **Continue with Google** shows the account
     picker again, and any account can be chosen.

5. **Cancelled sign-in**
   - Tap **Continue with Google**, then dismiss the picker.
   - **Expected:** a "Sign-in was cancelled." notice; no crash; still on the
     login screen with the spinner cleared.

6. **Account with no display name**
   - Use a Google account whose profile has no name.
   - **Expected:** a "What should we call you?" step in the onboarding style;
     a name is required; afterwards the app greets you by it.

7. **No network**
   - Turn on airplane mode and try Google sign-in.
   - **Expected:** a readable error notice, and no partial entry into the app.

## Automated coverage

- `test/services/auth_profile_preferences_test.dart` — name resolution order
  (auth name, then saved name, then fallback), cache load and clear.
- `test/auth_register_social_name_test.dart` — the no-name prompt renders and
  blocks progress until filled.
- `test/widget_test.dart` — register requires a name before a social sign-up;
  the social flow still routes through care context and consent.
