import 'package:flutter/services.dart';

import '../screens/emergency/emergency_screen.dart';

/// Bridge to Android's `medguard://…` intent filter (declared in
/// [AndroidManifest.xml]) so deep links from the lock-screen emergency
/// widget land on the right route inside Flutter rather than dropping the
/// user on the home tab.
///
/// We deliberately keep the surface tiny: one Future at start-up for the
/// initial launch URI, one Stream for live deep links arriving while the
/// app is already running. Future deep-link sources (Firebase Dynamic
/// Links, magic-link auth, share intents) plug into the same channel.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const _channel = MethodChannel('medguard.app/intents');

  /// Resolves the URI the activity was launched with, if any. Safe to call
  /// on every platform — non-Android platforms return null because the
  /// channel doesn't exist there.
  Future<Uri?> initialLink() async {
    try {
      final raw = await _channel.invokeMethod<String?>('getInitialLink');
      if (raw == null || raw.isEmpty) return null;
      return Uri.tryParse(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Listen for deep links that arrive while the app is already in the
  /// foreground (Android `onNewIntent`).
  void listen(void Function(Uri uri) onLink) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final raw = call.arguments as String?;
        if (raw == null) return null;
        final uri = Uri.tryParse(raw);
        if (uri != null) onLink(uri);
      }
      return null;
    });
  }

  /// Resolves the in-app route name for a given deep link, or null when we
  /// don't recognise the URI shape.
  static String? routeFor(Uri uri) {
    if (uri.scheme != 'medguard') return null;
    switch (uri.host) {
      case 'emergency':
        return EmergencyScreen.routeName;
      default:
        return null;
    }
  }
}
