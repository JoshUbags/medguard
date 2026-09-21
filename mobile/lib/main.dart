import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_startup.dart';
import 'firebase_options.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/privacy_policy_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/terms_conditions_screen.dart';
import 'screens/ai/ai_screen.dart';
import 'screens/dose/dose_screen.dart';
import 'screens/emergency/emergency_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/allergies/allergy_management_screen.dart';
import 'screens/foods/food_management_screen.dart';
import 'screens/safety/check_history_screen.dart';
import 'screens/security/app_lock_settings_screen.dart';
import 'screens/security/lock_screen.dart';
import 'services/api_service.dart';
import 'services/app_lock_service.dart';
import 'services/auth_profile_preferences.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/deep_link_service.dart';
import 'services/guest_mode_service.dart';
import 'services/interaction_checker.dart';
import 'services/lock_screen_widget_service.dart';
import 'services/login_activity_service.dart';
import 'services/notification_preferences.dart';
import 'services/session_service.dart';
import 'services/user_data_service.dart';
import 'screens/insights/insights_screen.dart';
import 'screens/loading/loading_screen.dart';
import 'screens/main_shell.dart';
import 'screens/medications/medications_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/onboarding/interaction_review_screen.dart';
import 'screens/onboarding/medication_context_screen.dart';
import 'screens/onboarding/safety_checks_overview_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/welcome/welcome_screen.dart';
import 'theme/app_theme.dart';
import 'theme/medguard_palette.dart';
import 'theme/theme_controller.dart';
import 'utils/keyboard.dart';
import 'widgets/common/connectivity_banner.dart';
import 'widgets/common/floating_nav_bar.dart';

/// Debug builds boot from a completely clean slate: every `flutter run`
/// clears all locally cached state (preferences, secrets, the encrypted user
/// database and its API caches) and signs out of Firebase, so the app always
/// starts from the very beginning — loading → welcome → onboarding → register.
///
/// Keep state across a run when needed:
///   flutter run --dart-define=MEDGUARD_KEEP_STATE=true
const bool _keepDevState = bool.fromEnvironment('MEDGUARD_KEEP_STATE');

bool get _freshStartEnabled => kDebugMode && !_keepDevState;

Future<void> _resetLocalStateForDev() async {
  // Preferences: onboarding progress, theme, notification + lock settings.
  // Login-consistency history is preserved across the reset — it is a real,
  // accumulating record of when the app was opened (the home "Welcome aboard"
  // streak), not sample state, so wiping it on every debug restart would erase
  // genuine prior logins (e.g. yesterday's) and the streak could never grow.
  try {
    final prefs = await SharedPreferences.getInstance();
    final preservedLogins = prefs.getStringList(
      LoginActivityService.storageKey,
    );
    await prefs.clear();
    if (preservedLogins != null && preservedLogins.isNotEmpty) {
      await prefs.setStringList(
        LoginActivityService.storageKey,
        preservedLogins,
      );
    }
  } catch (_) {}
  // Secrets: DB passphrase, app-lock PIN, cached tokens.
  try {
    await const FlutterSecureStorage().deleteAll();
  } catch (_) {}
  // Encrypted user DB: medications, allergies, schedules, dose logs, and the
  // ML/API prediction caches all live here — deleting the file clears them.
  if (!kIsWeb) {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final db = File(p.join(docs.path, 'medguard_user.db'));
      if (await db.exists()) await db.delete();
    } catch (_) {}
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_freshStartEnabled) {
    await _resetLocalStateForDev();
  }

  // Draw behind BOTH system bars. Without edge-to-edge the Android navigation
  // bar is an opaque strip the app cannot paint into, which is what clipped the
  // AI orb's glow in a hard line across the bottom of every screen.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Inter is bundled in the asset bundle (google_fonts/ directory), so fonts
  // load offline and no network fetch can ever stall or crash startup.
  GoogleFonts.config.allowRuntimeFetching = false;

  // ── The ONLY thing the first frame needs is the saved theme (paint colours).
  // It's a fast local-prefs read. Everything heavier — Firebase (which used to
  // block the loader from even appearing), app lock, fonts, the cached name —
  // now runs AFTER the first frame, WHILE the loader animates, so it overlaps
  // the splash instead of stacking in front of it.
  await ThemeController.instance.load();
  logStartupMilestone('theme ready → paint loader');

  runApp(const MedGuardApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    logStartupMilestone('first frame painted');
    unawaited(_initAfterFirstFrame());
  });
}

/// Heavy boot work, run once the loader is on screen so none of it delays the
/// first paint. Signals [appStartupReady] when auth state is resolved so the
/// loading screen can route correctly.
Future<void> _initAfterFirstFrame() async {
  // App lock, the cached display name, the local-only flag, and fonts are
  // independent — in parallel. The guest flag is a plain preferences read and
  // deliberately resolves before Firebase: it is what lets an offline launch
  // route into the app without ever waiting on the network.
  await Future.wait<void>([
    AppLockService.instance.load(),
    AuthProfilePreferences.loadCache(),
    GuestModeService.instance.load(),
    _loadFonts(),
  ]);
  if (AppLockService.instance.enabled) {
    AppLockService.instance.requireLock();
  }

  Object? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseError = e;
  }
  logStartupMilestone('firebase ready → auth state known');

  // Fresh-start builds also drop any persisted Firebase + Google session so the
  // run begins fully signed out, at the very first screen.
  if (_freshStartEnabled && firebaseError == null) {
    try {
      await AuthService.instance.signOut();
    } catch (_) {}
  }

  // Drop the SafetyReport cache whenever the user's medication list changes
  // so the next analysis reflects the new regimen. (Synchronous — free.)
  UserDataService.instance.medicationsRevision.addListener(
    InteractionChecker.invalidateCache,
  );

  // Surface a fatal Firebase error to the shell, and release the loading
  // screen to route now that auth state is known.
  firebaseInitError.value = firebaseError;
  if (!appStartupReady.isCompleted) appStartupReady.complete();

  // The remaining non-critical services can start now that the app is up.
  unawaited(_startDeferredServices());
}

/// Pre-loads the bundled Inter fonts to avoid FOUT on first render. Never
/// fatal: if a variant can't load, the app still boots with the platform
/// fallback font.
Future<void> _loadFonts() async {
  try {
    await GoogleFonts.pendingFonts([GoogleFonts.inter()]);
  } catch (_) {}
}

/// Background startup work, run once the first frame has painted:
///
///  * records today's app open for the home login-consistency streak
///    (idempotent per calendar day, and the home re-records on mount too);
///  * starts the remote-API connectivity listener that flushes queued
///    offline requests;
///  * warms the bundled clinical database — on first launch this performs the
///    ~100 MB asset copy, so doing it here (during the splash) means the first
///    real interaction check doesn't stall for seconds;
///  * resolves the active session identity (caregiver profiles), then
///    refreshes the Android lock-screen emergency widget that reads it.
Future<void> _startDeferredServices() async {
  unawaited(LoginActivityService.instance.recordToday());
  ApiService.instance.start();
  unawaited(DatabaseService.instance.warmUp());
  try {
    await SessionService.instance.start();
  } catch (_) {
    // Identity stays on the local-device fixture; screens listen and recover.
  }
  unawaited(_refreshEmergencyWidget());
}

Future<void> _refreshEmergencyWidget() async {
  try {
    final identity = SessionService.instance.identity.value;
    final user = FirebaseAuth.instance.currentUser;
    final fallbackLabel = user?.email?.trim().isNotEmpty == true
        ? user!.email!.trim()
        : identity.displayLabel;
    final displayName = AuthProfilePreferences.resolveDisplayName(
      firebaseDisplayName: user?.displayName,
      fallback: fallbackLabel,
    );
    final bloodType = await NotificationPreferences.bloodType();
    final contactName = await NotificationPreferences.emergencyContactName();
    final contactPhone = await NotificationPreferences.emergencyContactPhone();
    await LockScreenWidgetService.instance.publish(
      userId: identity.activeUserId,
      displayName: displayName,
      bloodType: bloodType,
      emergencyContactName: contactName,
      emergencyContactNumber: contactPhone,
    );
  } catch (_) {
    // Best-effort — failures here are logged inside the service.
  }
}

class MedGuardApp extends StatefulWidget {
  const MedGuardApp({super.key});

  @override
  State<MedGuardApp> createState() => _MedGuardAppState();
}

class _MedGuardAppState extends State<MedGuardApp> with WidgetsBindingObserver {
  static const String _startScreen = String.fromEnvironment(
    'MEDGUARD_START_SCREEN',
    defaultValue: '',
  );
  static final String _initialRoute = resolveInitialRouteForStartMode(
    _startScreen,
  );

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockService.instance.registerActivity();

    // Handle deep links from the lock-screen emergency widget. The
    // initial-link case (cold start) is read here; the live
    // case (warm app already running) is handled by [DeepLinkService.listen]
    // which the next line registers.
    _resolveInitialDeepLink();
    DeepLinkService.instance.listen(_navigateToDeepLink);
  }

  Future<void> _resolveInitialDeepLink() async {
    final uri = await DeepLinkService.instance.initialLink();
    if (uri == null) return;
    _navigateToDeepLink(uri);
  }

  void _navigateToDeepLink(Uri uri) {
    final route = DeepLinkService.routeFor(uri);
    if (route == null) return;
    // pushNamed instead of replace so back navigation lands on whichever
    // tab the user was on before the widget tap.
    _navigatorKey.currentState?.pushNamed(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AppLockService.instance.shouldAutoLock()) {
        AppLockService.instance.requireLock();
      }
      AppLockService.instance.registerActivity();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Stamp activity at the moment of backgrounding so the auto-lock window
      // is measured from then.
      AppLockService.instance.registerActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firebase now initialises after the first frame, so a fatal init error is
    // surfaced reactively: if it becomes non-null the shell swaps to the error
    // screen; until then the normal app (loader → routes) renders.
    return ValueListenableBuilder<Object?>(
      valueListenable: firebaseInitError,
      builder: (context, firebaseError, _) {
        if (firebaseError != null) {
          return MaterialApp(
            title: 'MedGuard',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: _FirebaseErrorScreen(error: firebaseError),
          );
        }
        return _buildApp(context);
      },
    );
  }

  Widget _buildApp(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'MedGuard',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme(trueBlack: mode.isTrueBlack),
          themeMode: mode.materialMode,
          builder: (context, child) {
            // Wrap every routed view in a lock overlay + an activity listener
            // so any touch resets the auto-lock timer.
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => AppLockService.instance.registerActivity(),
              // A tap on anything that is NOT itself interactive drops text
              // focus and closes the keyboard. Deeper recognisers (buttons,
              // fields, the Pressable wrapper) win the gesture arena, so this
              // only fires on genuine "tapped somewhere else" taps.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismissTextInput,
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppLockService.instance.locked,
                  builder: (context, locked, _) {
                    return Stack(
                      children: [
                        // The connection banner wraps the ROUTED content only,
                        // so it rides above every screen and survives
                        // navigation — but stays beneath the lock screen, which
                        // must be the only thing visible when the app is
                        // locked.
                        ConnectivityBanner(
                          child: child ?? const SizedBox.shrink(),
                        ),
                        if (locked)
                          Positioned.fill(
                            child: LockScreen(
                              onUnlock: AppLockService.instance.markUnlocked,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
          initialRoute: _initialRoute,
          routes: {
            LoadingScreen.routeName: (_) => const LoadingScreen(),
            WelcomeScreen.routeName: (_) => const WelcomeScreen(),
            MainShell.routeName: (_) => const MainShell(),
            HomeScreen.routeName: (_) =>
                const MainShell(initialTab: AppNavTab.home),
            SearchScreen.routeName: (_) => const SearchScreen(),
            MedicationsScreen.routeName: (_) =>
                const MainShell(initialTab: AppNavTab.interactions),
            DoseScreen.routeName: (_) =>
                const MainShell(initialTab: AppNavTab.dose),
            AiScreen.routeName: (_) =>
                const MainShell(initialTab: AppNavTab.ai),
            InsightsScreen.routeName: (_) =>
                const MainShell(initialTab: AppNavTab.insights),
            ProfileScreen.routeName: (_) => const ProfileScreen(),
            NotificationsScreen.routeName: (_) => const NotificationsScreen(),
            EmergencyScreen.routeName: (_) => const EmergencyScreen(),
            AppLockSettingsScreen.routeName: (_) =>
                const AppLockSettingsScreen(),
            SettingsScreen.routeName: (_) => const SettingsScreen(),
            AllergyManagementScreen.routeName: (_) =>
                const AllergyManagementScreen(),
            FoodManagementScreen.routeName: (_) => const FoodManagementScreen(),
            CheckHistoryScreen.routeName: (_) => const CheckHistoryScreen(),
            '/interaction-review': (_) => const InteractionReviewScreen(),
            '/medication-context': (_) => const MedicationContextScreen(),
            '/safety-checks': (_) => const SafetyChecksOverviewScreen(),
            LoginScreen.routeName: (_) => const LoginScreen(),
            RegisterScreen.routeName: (_) => const RegisterScreen(),
            ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
            PrivacyPolicyScreen.routeName: (_) => const PrivacyPolicyScreen(),
            TermsConditionsScreen.routeName: (_) =>
                const TermsConditionsScreen(),
          },
          // Fallback when an unknown route name is requested (e.g. a typo'd
          // initialRoute). Without this, MaterialApp throws and the resulting
          // navigator failure cascades into framework element-tree assertions.
          onUnknownRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const LoadingScreen(),
          ),
        );
      },
    );
  }
}

String resolveInitialRouteForStartMode(String startScreen) {
  return switch (startScreen.trim().toLowerCase()) {
    'onboarding' => WelcomeScreen.routeName,
    'main' => MainShell.routeName,
    _ => LoadingScreen.routeName,
  };
}

class _FirebaseErrorScreen extends StatelessWidget {
  const _FirebaseErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MedGuardPalette.teal,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_rounded,
                  size: 48,
                  color: MedGuardPalette.ruby,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not start MedGuard',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: MedGuardPalette.pureWhite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: MedGuardPalette.whiteAlpha(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
