import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_startup.dart';
import '../../services/guest_mode_service.dart';
import '../../services/onboarding_preferences.dart';
import '../../theme/medguard_palette.dart';
import '../auth/login_screen.dart';
import '../main_shell.dart';
import '../welcome/welcome_assets.dart';
import '../welcome/welcome_screen.dart';
import 'startup_animation.dart';

const bool _kResetOnboarding = bool.fromEnvironment(
  'RESET_ONBOARDING',
  defaultValue: false,
);

/// How long the loader is guaranteed to be visible: exactly as long as the
/// launch animation needs to play its intro through, so the sequence is never
/// cut off mid-stroke. It runs CONCURRENTLY with Firebase init (which used to
/// block the loader from appearing at all), so it overlaps the heavy startup
/// work instead of stacking on top of it — the splash lasts
/// `max(intro, startup work)`, capped by [kStartupCeiling], never
/// `intro + startup work`.
const Duration _minSplash = kStartupIntro;

/// Where a launch is allowed to begin.
enum StartupDestination { app, welcome, signIn }

/// The launch decision, as a pure function of the three things it depends on.
///
/// Extracted from the splash so the rule can be stated — and tested — without
/// booting the encrypted database, Firebase and every dashboard service that
/// the real destination widget pulls in behind it.
///
/// Order matters. An account wins over the local-only flag, so a guest who has
/// since signed in lands in their account even if the flag has not been cleared
/// yet. Local-only outranks first-launch, because someone who has already
/// chosen to work without an account has been through onboarding and must not
/// be walked back through it.
StartupDestination resolveStartupDestination({
  required bool signedIn,
  required bool guest,
  required bool firstLaunch,
}) {
  if (signedIn || guest) return StartupDestination.app;
  if (firstLaunch) return StartupDestination.welcome;
  return StartupDestination.signIn;
}

/// The launch gate: a single, quiet brand-teal surface carrying nothing but the
/// shared MedGuard loader. It decides where the session starts (signed-in or
/// local-only user → main shell, first launch → welcome, otherwise → sign in)
/// and hands over the moment the app is ready.
///
/// Signing in is one way in, not the only one. MedGuard's safety engine runs
/// entirely on this device, so a user who chose to continue without an account
/// goes straight into the app: nothing here may wait on the network to decide
/// where an offline-first app is allowed to start.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  static const String routeName = '/loading';

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        // Transparent so the launch backdrop's own gradient runs to the very
        // bottom of the screen, behind the navigation buttons, with no seam
        // where a painted bar colour would meet it.
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    _resolveAndGo();
  }

  Future<bool> _readFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (kDebugMode && _kResetOnboarding) {
      await prefs.remove(kIsFirstLaunchKey);
    }
    return prefs.getBool(kIsFirstLaunchKey) ?? true;
  }

  bool _isSignedIn() {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the destination while the launch animation plays, then crossfades
  /// into it. All three waits run in parallel, so the splash lasts
  /// `max(intro, first-launch read, auth state)` — never a fixed artificial
  /// delay, and never longer than [kStartupCeiling].
  Future<void> _resolveAndGo() async {
    // Latched as soon as the read lands, so the ceiling path below can use the
    // real answer if it arrived, without ever awaiting again on a read that may
    // be exactly what is hanging.
    bool? firstLaunch;
    final firstLaunchFuture = _readFirstLaunch().then((value) {
      firstLaunch = value;
      return value;
    });

    // Latched the same way: a local-only user must be routed into the app even
    // if the Firebase wait below times out, which is exactly the offline case
    // this path exists for.
    bool guest = false;
    final guestFuture = GuestModeService.instance.load().then((value) {
      guest = value;
      return value;
    });

    // Warm the welcome/onboarding photography ONLY when this launch is
    // actually heading into onboarding — returning users skip the decode work
    // (and the memory) entirely.
    unawaited(
      firstLaunchFuture.then((isFirst) {
        if (isFirst && mounted && !_isSignedIn()) {
          unawaited(precacheOnboardingMedia(context));
        }
      }),
    );

    // Everything the splash waits on, in parallel: the routing decision, a
    // reliable auth state, and the animation's own intro. Whichever finishes
    // last sets the splash length — and [kStartupCeiling] bounds the whole
    // thing, so a stalled service degrades into "route anyway" rather than an
    // indefinite loading screen.
    await Future.wait<Object?>([
      firstLaunchFuture,
      guestFuture,
      // Wait until Firebase has initialised so the signed-in check below is
      // reliable — otherwise a returning user could be mis-routed to sign-in.
      appStartupReady.future,
      Future<void>.delayed(_minSplash),
    ]).timeout(kStartupCeiling, onTimeout: () => const <Object?>[]).catchError(
      (_) => const <Object?>[],
    );

    // Default to first-launch only if the flag genuinely never arrived: showing
    // onboarding once more is recoverable, dropping a returning user into it
    // by mistake is the same outcome, and neither is worth a longer wait.
    final isFirstLaunch = firstLaunch ?? true;

    if (!mounted || _didNavigate) return;
    _didNavigate = true;

    final next = switch (resolveStartupDestination(
      signedIn: _isSignedIn(),
      guest: guest,
      firstLaunch: isFirstLaunch,
    )) {
      StartupDestination.app => const MainShell(),
      StartupDestination.welcome => const WelcomeScreen(),
      StartupDestination.signIn => const LoginScreen(),
    };
    logStartupMilestone('routing to ${next.runtimeType}');
    Navigator.of(context).pushReplacement(_splashFadeRoute(next));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // Matches the backdrop's darkest stop so the system bars blend into the
      // canvas with no seam at the very top and bottom of the launch screen.
      backgroundColor: MedGuardPalette.teal,
      body: StartupBackdrop(
        child: Center(child: MedGuardStartupAnimation()),
      ),
    );
  }
}

/// The hand-over into the first real screen: the launch lockup lifts and
/// dissolves while the destination fades up beneath it. Longer and softer than
/// a standard route fade, because this is the one transition the user watches
/// deliberately — a hard cut here undoes the calm the animation just built.
Route<T> _splashFadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 520),
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: eased,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.035, end: 1.0).animate(eased),
        child: child,
      ),
    );
  },
);
