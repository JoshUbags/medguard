import 'package:shared_preferences/shared_preferences.dart';

/// How often the adherence-and-safety summary is delivered, and how far back it
/// looks.
///
/// The two are deliberately the same setting. A "monthly" summary that only
/// recaps the last seven days is a lie the user has to work out for themselves;
/// picking the cadence should pick the window it covers.
enum SummaryInterval {
  off('Off', 'No summary', 0),
  daily('Daily', 'Every evening, covering that day', 1),
  weekly('Weekly', 'Sunday evenings, covering 7 days', 7),
  monthly('Monthly', 'First of the month, covering 30 days', 30),
  yearly('Yearly', 'Each January, covering 12 months', 365);

  const SummaryInterval(this.label, this.detail, this.lookbackDays);

  final String label;
  final String detail;

  /// How many days of history the report covers.
  final int lookbackDays;

  bool get isOn => this != SummaryInterval.off;

  static SummaryInterval fromWire(String? wire) {
    for (final v in SummaryInterval.values) {
      if (v.name == wire) return v;
    }
    return SummaryInterval.off;
  }
}

/// Persisted per-type notification toggles. Each setting controls whether that
/// notification category fires at all; the scheduler and safety checks consult
/// these before scheduling or surfacing alerts.
class NotificationPreferences {
  NotificationPreferences._();

  static const _keyDoseReminders = 'notif_dose_reminders';
  static const _keySafetyAlerts = 'notif_safety_alerts';
  static const _keySummaryInterval = 'notif_summary_interval';

  /// The pre-[SummaryInterval] boolean. Read once, to carry an existing opt-in
  /// forward as a weekly summary rather than silently switching it off.
  static const _legacyKeyWeeklySummary = 'notif_weekly_summary';

  /// Whether offline dose reminders are enabled (primary + follow-up).
  static Future<bool> doseReminders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDoseReminders) ?? true;
  }

  static Future<void> setDoseReminders(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDoseReminders, value);
  }

  /// Whether in-app safety alerts fire when the user adds an interacting drug.
  static Future<bool> safetyAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySafetyAlerts) ?? true;
  }

  static Future<void> setSafetyAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySafetyAlerts, value);
  }

  /// The summary cadence. Defaults to off, so nobody is opted into a recurring
  /// notification they never asked for.
  static Future<SummaryInterval> summaryInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keySummaryInterval);
    if (stored != null) return SummaryInterval.fromWire(stored);
    // Migrate the old boolean: someone who had opted in keeps a summary.
    final legacy = prefs.getBool(_legacyKeyWeeklySummary);
    return legacy == true ? SummaryInterval.weekly : SummaryInterval.off;
  }

  static Future<void> setSummaryInterval(SummaryInterval value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySummaryInterval, value.name);
    await prefs.remove(_legacyKeyWeeklySummary);
  }

  // ── Reminder behaviour ─────────────────────────────────────────────────────

  static const _keySnoozeDuration = 'pref_snooze_duration_minutes';

  /// Snooze duration in minutes (default 15).
  static Future<int> snoozeDuration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySnoozeDuration) ?? 15;
  }

  static Future<void> setSnoozeDuration(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySnoozeDuration, minutes);
  }

  // ── Emergency profile ──────────────────────────────────────────────────────

  static const _keyEmergencyName = 'emergency_contact_name';
  static const _keyEmergencyPhone = 'emergency_contact_phone';
  static const _keyBloodType = 'emergency_blood_type';

  static Future<String?> emergencyContactName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmergencyName);
  }

  static Future<String?> emergencyContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmergencyPhone);
  }

  static Future<String?> bloodType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBloodType);
  }

  static Future<void> setEmergencyContact({
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmergencyName, name);
    await prefs.setString(_keyEmergencyPhone, phone);
  }

  static Future<void> setBloodType(String? bloodType) async {
    final prefs = await SharedPreferences.getInstance();
    if (bloodType == null || bloodType.isEmpty) {
      await prefs.remove(_keyBloodType);
    } else {
      await prefs.setString(_keyBloodType, bloodType);
    }
  }
}
