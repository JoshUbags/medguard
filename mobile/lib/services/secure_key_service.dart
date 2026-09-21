import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the passphrase that encrypts the on-device health database.
///
/// The 256-bit key is generated once on first launch and stored in
/// platform-backed secure storage (Android Keystore / iOS Keychain) — never
/// in the app bundle, shared preferences, or the database itself. This is the
/// key-management half of encryption-at-rest for the sensitive medication,
/// allergy, and side-effect data (see docs/data-protection.md).
class SecureKeyService {
  SecureKeyService._();

  static final SecureKeyService instance = SecureKeyService._();

  static const _storage = FlutterSecureStorage();
  static const _dbKeyName = 'medguard_user_db_key_v1';

  String? _cached;

  /// Returns the database passphrase, generating and persisting one the first
  /// time it is requested.
  Future<String> databasePassphrase() async {
    final cached = _cached;
    if (cached != null) return cached;

    var key = await _storage.read(key: _dbKeyName);
    if (key == null || key.isEmpty) {
      key = _generateKey();
      await _storage.write(key: _dbKeyName, value: key);
    }
    _cached = key;
    return key;
  }

  static String _generateKey() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
