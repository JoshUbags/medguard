import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device-local answer to "is this person using MedGuard without an
/// account?".
///
/// MedGuard's safety engine is entirely on-device — the bundled rule database
/// and the TFLite predictor need no network at all — but until this existed the
/// app still put a Firebase sign-in between the user and every one of those
/// checks. An offline-first medication safety tool that cannot open its own
/// front door without internet is not offline-first, so the gate is now
/// optional: a guest gets the whole local app, and the account layer (the
/// record that outlives this phone) is what signing in adds.
///
/// The flag lives in [SharedPreferences] rather than memory so a guest who
/// closes the app comes back into the app, not back to the login wall. It is
/// deliberately independent of Firebase: reading it must never touch the
/// network, or it would reintroduce exactly the stall it exists to remove.
class GuestModeService {
  GuestModeService._();

  static final GuestModeService instance = GuestModeService._();

  @visibleForTesting
  static const String storageKey = 'guest_mode_enabled';

  /// Whether the app is currently running without an account.
  ///
  /// A [ValueNotifier] so the screens that change shape in guest mode (Profile,
  /// Settings, the account-gated pages) rebuild the moment the user signs in or
  /// chooses to continue locally, with no manual refresh.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  bool _loaded = false;

  /// Reads the persisted flag. Called once during startup, before the loading
  /// screen decides where to route. Safe to await repeatedly.
  Future<bool> load() async {
    if (_loaded) return enabled.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(storageKey) ?? false;
    } catch (_) {
      // Preferences unavailable (tests / a corrupt store): default to the
      // signed-out path rather than silently letting someone past the gate.
      enabled.value = false;
    }
    _loaded = true;
    return enabled.value;
  }

  /// Enters the local-only app. Persisted, so the next launch skips the wall.
  Future<void> enter() => _write(true);

  /// Leaves guest mode — called the moment an account takes over, so the app
  /// stops describing itself as local-only.
  Future<void> exit() => _write(false);

  Future<void> _write(bool value) async {
    enabled.value = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // The in-memory notifier is already updated, so this session behaves
      // correctly either way; only the persistence across relaunch is lost.
    }
  }

  /// Test seam: forget the cached read so the next [load] hits preferences.
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    enabled.value = false;
  }
}
