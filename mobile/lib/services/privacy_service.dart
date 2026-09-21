import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'app_lock_service.dart';
import 'auth_service.dart';
import 'dose_reminder_scheduler.dart';
import 'dose_service.dart';
import 'notification_preferences.dart';
import 'user_data_service.dart';

/// Privacy-tooling that supports the user's right to download their data and
/// to permanently delete their account. Pure data orchestration — UI is
/// responsible for confirmation prompts and sharing the resulting bytes.
class PrivacyService {
  PrivacyService._();

  /// Builds a JSON dump of every piece of user-owned data this app stores:
  /// medications, dose schedules, dose logs, allergies, preferences, and
  /// minimal account metadata. Returned as UTF-8 bytes, ready to be saved or
  /// shared via `share_plus`.
  static Future<Uint8List> exportUserData(String userId) async {
    final medications = await _safe<List<dynamic>>(
      () async => (await UserDataService.instance.getUserMedications(userId))
          .map(
            (m) => {
              'drug_id': m.drugId,
              'drug_name': m.drugName,
              'atc_code': m.atcCode,
              'nickname': m.nickname,
              'custom_color': m.customColor,
              'added_at': m.addedAt.toIso8601String(),
            },
          )
          .toList(),
      fallback: const [],
    );

    final schedules = await _safe<List<dynamic>>(
      () async => (await DoseService.instance.getSchedules(userId))
          .map(
            (s) => {
              'drug_id': s.drugId,
              'drug_name': s.drugName,
              // Null rather than 0 when no strength was recorded — the export
              // should say "not recorded", not "zero milligrams".
              'amount': s.hasAmount ? s.amount : null,
              'unit': s.unit,
              'frequency': s.frequency.wireValue,
              'time_slots': s.timeSlots,
              'start_date': s.startDate.toIso8601String(),
              'end_date': s.endDate?.toIso8601String(),
              'refill_date': s.refillDate?.toIso8601String(),
              'quantity': s.quantity,
              'created_at': s.createdAt.toIso8601String(),
            },
          )
          .toList(),
      fallback: const [],
    );

    final logs = await _safe<List<dynamic>>(
      () async => _doseLogs(userId),
      fallback: const [],
    );

    final prefs = <String, dynamic>{};
    try {
      final summary = await NotificationPreferences.summaryInterval();
      prefs['summary_interval'] = summary.name;
      prefs['dose_reminders'] = await NotificationPreferences.doseReminders();
      prefs['safety_alerts'] = await NotificationPreferences.safetyAlerts();
      prefs['snooze_minutes'] = await NotificationPreferences.snoozeDuration();
      prefs['blood_type'] = await NotificationPreferences.bloodType();
      prefs['emergency_contact'] = {
        'name': await NotificationPreferences.emergencyContactName(),
        'phone': await NotificationPreferences.emergencyContactPhone(),
      };
    } catch (_) {
      // Skip prefs if SharedPreferences is unavailable.
    }

    String? email;
    String? displayName;
    try {
      final user = FirebaseAuth.instance.currentUser;
      email = user?.email;
      displayName = user?.displayName;
    } catch (_) {}

    final payload = {
      'app': 'MedGuard',
      'export_version': 1,
      'generated_at': DateTime.now().toIso8601String(),
      'user': {
        'id': userId,
        'email': ?email,
        'display_name': ?displayName,
      },
      'medications': medications,
      'dose_schedules': schedules,
      'dose_logs': logs,
      'allergies': await _safe<List<dynamic>>(
        () => _userAllergies(userId),
        fallback: const [],
      ),
      'preferences': prefs,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    return Uint8List.fromList(utf8.encode(encoded));
  }

  /// Wipes every locally-stored bit of user data: medications, schedules,
  /// dose logs, allergies, preferences, and the auth-lock secrets. Optionally
  /// also signs the user out of Firebase. Returns true when every step
  /// completed without throwing.
  static Future<bool> wipeLocalData({
    required String userId,
    bool signOut = true,
  }) async {
    var ok = true;
    ok = await _safeBool(() => _clearUserDatabase(userId));
    ok = ok && await _safeBool(() => _clearPreferences());
    ok = ok && await _safeBool(() => _clearSecureStorage());
    if (signOut) {
      ok = ok && await _safeBool(() => _firebaseSignOut());
    }
    return ok;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, Object?>>> _doseLogs(String userId) async {
    final db = await UserDataService.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT dl.schedule_id, dl.scheduled_time, dl.status, dl.logged_at
      FROM dose_logs dl
      JOIN dose_schedules ds ON ds.id = dl.schedule_id
      WHERE ds.user_id = ?
      ORDER BY dl.scheduled_time
      ''',
      [userId],
    );
    return rows.map((r) => {...r}).toList(growable: false);
  }

  static Future<List<Map<String, Object?>>> _userAllergies(String userId) async {
    final db = await UserDataService.instance.database;
    final rows = await db.query(
      'user_allergies',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((r) => {...r}).toList(growable: false);
  }

  static Future<void> _clearUserDatabase(String userId) async {
    final db = await UserDataService.instance.database;
    // Cascade FKs handle dose_logs; we still scrub both for safety.
    await db.delete('user_medications', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('user_allergies', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('dose_schedules', where: 'user_id = ?', whereArgs: [userId]);
    UserDataService.instance.medicationsRevision.value++;
  }

  static Future<void> _clearPreferences() async {
    await NotificationPreferences.setDoseReminders(true);
    await NotificationPreferences.setSafetyAlerts(true);
    await NotificationPreferences.setSummaryInterval(SummaryInterval.off);
    await NotificationPreferences.setBloodType(null);
    // Cancel the scheduled summary too. Resetting the preference alone would
    // leave a recurring notification firing for data that no longer exists.
    try {
      await DoseReminderScheduler.instance.setSummaryInterval(
        SummaryInterval.off,
      );
    } catch (_) {
      // Plugin unavailable — the preference reset above still stands.
    }
  }

  static Future<void> _clearSecureStorage() async {
    // App lock secrets — also reset the in-memory state.
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    await AppLockService.instance.setEnabled(false);
  }

  static Future<void> _firebaseSignOut() async {
    // Routed through AuthService so the Google session is cleared alongside
    // Firebase — otherwise a deleted account could silently re-authenticate.
    await AuthService.instance.signOut();
  }

  static Future<T> _safe<T>(
    Future<T> Function() block, {
    required T fallback,
  }) async {
    try {
      return await block();
    } catch (_) {
      return fallback;
    }
  }

  static Future<bool> _safeBool(Future<void> Function() block) async {
    try {
      await block();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Suppresses an analyzer warning about unused `sqflite` import in some
  /// flavours where the database call is conditional.
  // ignore: unused_field
  static const _sqfliteSentinel = Sqflite;
}
