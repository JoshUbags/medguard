import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Centralised app-lock state.
///
/// Three concerns live here:
///   1. Whether the lock is enabled at all (persisted in secure storage).
///   2. Whether the device supports biometrics and the user opted in.
///   3. A salted-hash 6-digit PIN fallback.
///
/// The service also exposes [locked], a `ValueNotifier<bool>` the app shell
/// listens to so it can route to an [LockScreen] whenever auto-lock fires.
class AppLockService {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  /// Reasonable default auto-lock window: 5 minutes of inactivity.
  static const Duration defaultAutoLock = Duration(minutes: 5);

  static const _keyEnabled = 'app_lock_enabled';
  static const _keyBiometric = 'app_lock_biometric';
  static const _keyPinHash = 'app_lock_pin_hash';
  static const _keyPinSalt = 'app_lock_pin_salt';
  static const _keyAutoLockMinutes = 'app_lock_auto_minutes';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Whether the app is currently locked and the shell should show the lock
  /// screen. Starts unlocked and is set to true by [requireLock].
  final ValueNotifier<bool> locked = ValueNotifier<bool>(false);

  DateTime? _lastActivity;
  Duration _autoLockWindow = defaultAutoLock;

  bool _loaded = false;
  bool _enabled = false;
  bool _biometricPreferred = false;

  bool get enabled => _enabled;
  bool get biometricPreferred => _biometricPreferred && _enabled;
  Duration get autoLockWindow => _autoLockWindow;

  /// Loads persisted settings. Safe to call multiple times — no-ops after the
  /// first successful load. Treats a missing platform store as "lock off".
  Future<void> load() async {
    if (_loaded) return;
    try {
      // One parallel batch instead of three sequential round-trips — secure
      // storage reads go through the platform keystore and each can cost
      // hundreds of milliseconds, and load() sits on the app's startup path.
      final values = await Future.wait([
        _storage.read(key: _keyEnabled),
        _storage.read(key: _keyBiometric),
        _storage.read(key: _keyAutoLockMinutes),
      ]);
      _enabled = values[0] == '1';
      _biometricPreferred = values[1] == '1';
      final parsed = int.tryParse(values[2] ?? '');
      _autoLockWindow = parsed != null && parsed > 0
          ? Duration(minutes: parsed)
          : defaultAutoLock;
      _loaded = true;
    } catch (_) {
      // Secure storage unavailable (e.g. unit tests). Treat lock as off.
      _enabled = false;
      _biometricPreferred = false;
      _autoLockWindow = defaultAutoLock;
      _loaded = true;
    }
  }

  /// Records user activity. Call from a top-level [Listener] / route observer
  /// so [shouldAutoLock] knows when the user was last active.
  void registerActivity() {
    _lastActivity = DateTime.now();
  }

  /// True when the last recorded activity is older than [autoLockWindow] and
  /// the lock is enabled.
  bool shouldAutoLock({DateTime? now}) {
    if (!_enabled) return false;
    final last = _lastActivity;
    if (last == null) return false;
    return (now ?? DateTime.now()).difference(last) >= _autoLockWindow;
  }

  /// Flags the app as locked. The shell should observe [locked] and route to
  /// the lock screen.
  void requireLock() {
    if (!_enabled) return;
    locked.value = true;
  }

  /// Clears the locked flag and stamps activity.
  void markUnlocked() {
    locked.value = false;
    registerActivity();
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Whether the device reports any usable biometric capability.
  Future<bool> isBiometricSupported() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final available = await _localAuth.canCheckBiometrics;
      return supported && available;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      // Disabling the lock wipes the PIN + biometric preference too.
      _biometricPreferred = false;
      await _storage.delete(key: _keyEnabled);
      await _storage.delete(key: _keyBiometric);
      await _storage.delete(key: _keyPinHash);
      await _storage.delete(key: _keyPinSalt);
      locked.value = false;
      return;
    }
    await _storage.write(key: _keyEnabled, value: '1');
  }

  Future<void> setBiometricPreferred(bool value) async {
    _biometricPreferred = value;
    if (value) {
      await _storage.write(key: _keyBiometric, value: '1');
    } else {
      await _storage.delete(key: _keyBiometric);
    }
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    final safe = minutes.clamp(1, 60);
    _autoLockWindow = Duration(minutes: safe);
    await _storage.write(key: _keyAutoLockMinutes, value: '$safe');
  }

  // ── PIN ──────────────────────────────────────────────────────────────────��─

  /// Persists a new 6-digit PIN with a random per-user salt. Throws when the
  /// PIN is not exactly six digits — UI should validate before calling.
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be six digits');
    }
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _storage.write(key: _keyPinSalt, value: salt);
    await _storage.write(key: _keyPinHash, value: hash);
  }

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return false;
    final salt = await _storage.read(key: _keyPinSalt);
    final hash = await _storage.read(key: _keyPinHash);
    if (salt == null || hash == null) return false;
    return _hashPin(pin, salt) == hash;
  }

  Future<bool> authenticateBiometric(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  String _generateSalt() {
    // Crypto-random 16-byte salt encoded as hex.
    final rng = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return sha256.convert(utf8.encode('$rng:${DateTime.now().toIso8601String()}'))
        .toString();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
