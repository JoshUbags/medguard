import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cross-file signals for the boot sequence.
///
/// The heavy startup work (Firebase, app lock, fonts) now runs *after* the
/// first frame so the loader paints immediately. These let the loading screen
/// wait for auth state to be known before it routes, and let the app shell
/// react to a fatal Firebase error that surfaces after construction.

/// Completes once the auth/session state is known well enough to choose a start
/// screen. The loading screen awaits this before routing, so a signed-in user
/// is never mis-routed to sign-in just because Firebase hadn't finished
/// initialising yet.
final Completer<void> appStartupReady = Completer<void>();

/// A fatal Firebase-init error, surfaced reactively (init now happens after the
/// first frame, so it can't be a constructor argument to the app shell).
final ValueNotifier<Object?> firebaseInitError = ValueNotifier<Object?>(null);

/// A single wall clock for the boot sequence. [logStartupMilestone] prints
/// elapsed milliseconds at each milestone so a slow launch can be measured
/// precisely instead of guessed at. Prints in BOTH debug and profile builds
/// (profile is where real, ship-like startup speed is measured — `kDebugMode`
/// is false there), and compiles to nothing in release.
final Stopwatch startupClock = Stopwatch()..start();

void logStartupMilestone(String label) {
  if (!kReleaseMode) {
    // debugPrint is throttled/stripped in release; print keeps the line in
    // profile builds where we actually want the measurement.
    // ignore: avoid_print
    print('[startup] $label @ ${startupClock.elapsedMilliseconds}ms');
  }
}
