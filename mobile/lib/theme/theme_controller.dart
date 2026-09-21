import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modes the user can pick in Settings. [system] follows the OS appearance
/// setting; [oled] is a true-black dark mode for AMOLED screens.
enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark'),
  oled('oled');

  const AppThemeMode(this.wireValue);

  final String wireValue;

  ThemeMode get materialMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark || AppThemeMode.oled => ThemeMode.dark,
  };

  bool get isTrueBlack => this == AppThemeMode.oled;

  static AppThemeMode fromWire(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.wireValue == value) return mode;
    }
    return AppThemeMode.system;
  }
}

/// App-wide theme state. Listens via [ValueListenableBuilder] in main.dart so
/// the entire MaterialApp re-themes whenever the user changes mode.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'app_theme_mode';

  final ValueNotifier<AppThemeMode> mode = ValueNotifier(AppThemeMode.system);

  /// Loads the persisted choice. Safe to call before runApp; tolerates a
  /// missing platform store (returns the default).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = AppThemeMode.fromWire(prefs.getString(_key));
    } catch (_) {
      // Preferences unavailable — keep system default.
    }
  }

  Future<void> set(AppThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.wireValue);
    } catch (_) {
      // Best-effort; in-memory mode still applies for the session.
    }
  }
}
