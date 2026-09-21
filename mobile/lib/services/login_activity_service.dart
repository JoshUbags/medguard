import 'package:shared_preferences/shared_preferences.dart';

/// Records which calendar days the app was opened, so the home screen can show
/// a real login-consistency streak. Honest by construction: a day is only
/// "active" if the app was actually opened on it — nothing is back-filled.
class LoginActivityService {
  LoginActivityService._();

  static final LoginActivityService instance = LoginActivityService._();

  static const String _key = 'login_activity_days';
  static const int _maxStored = 60;

  /// The SharedPreferences key the active-day set is stored under. Exposed so
  /// the dev-only "fresh start" reset can preserve real login history across a
  /// debug restart (a genuine record, not sample state, so the streak survives).
  static const String storageKey = _key;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Marks today as an active login day and returns the full active-day set.
  Future<Set<String>> recordToday({DateTime? now}) async {
    final today = dayKey(now ?? DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      final days = (prefs.getStringList(_key) ?? const <String>[]).toSet();
      if (days.add(today)) {
        final sorted = days.toList()..sort();
        final trimmed = sorted.length > _maxStored
            ? sorted.sublist(sorted.length - _maxStored)
            : sorted;
        await prefs.setStringList(_key, trimmed);
        return trimmed.toSet();
      }
      return days;
    } catch (_) {
      // No writable store (fresh install / tests) — today still counts.
      return {today};
    }
  }

  /// The set of recorded active-day keys.
  Future<Set<String>> activeDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Current consecutive-day streak ending today, given an active-day set.
  static int streakFrom(Set<String> activeDays, {DateTime? now}) {
    var day = now ?? DateTime.now();
    day = DateTime(day.year, day.month, day.day);
    var streak = 0;
    while (activeDays.contains(dayKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
