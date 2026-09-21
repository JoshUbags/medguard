import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'user_data_service.dart';

/// Publishes the user's emergency-card payload to the Android home-screen
/// widget so paramedics / bystanders can see allergies, blood type, and
/// emergency contact without unlocking the phone.
///
/// The matching Android receiver lives at
/// `android/app/src/main/kotlin/.../MedGuardEmergencyWidget.kt`. It reads the
/// values written here via [HomeWidget.saveWidgetData] and renders them in a
/// RemoteViews layout.
class LockScreenWidgetService {
  LockScreenWidgetService._();
  static final LockScreenWidgetService instance = LockScreenWidgetService._();

  static const _androidAppGroup = 'medguard.widget';
  static const _widgetProvider = 'MedGuardEmergencyWidget';

  /// Pushes the latest emergency card into the home-screen widget. Returns
  /// whether the update succeeded; failures are silently logged in debug
  /// mode (e.g. iOS without an extension, or Android < 6 where the widget
  /// is not supported).
  Future<bool> publish({
    required String userId,
    required String displayName,
    String? bloodType,
    String? emergencyContactName,
    String? emergencyContactNumber,
  }) async {
    try {
      await HomeWidget.setAppGroupId(_androidAppGroup);
      final users = UserDataService.instance;
      final allergies = await users.getUserAllergies(userId);
      final allergyLabels = allergies.map((a) => a.label).toSet().toList();

      await HomeWidget.saveWidgetData('mg_name', displayName);
      await HomeWidget.saveWidgetData(
        'mg_allergies',
        allergyLabels.isEmpty ? 'None recorded' : allergyLabels.join(', '),
      );
      await HomeWidget.saveWidgetData(
        'mg_blood',
        bloodType?.trim().isEmpty == true ? '—' : (bloodType ?? '—'),
      );
      await HomeWidget.saveWidgetData(
        'mg_contact',
        [emergencyContactName, emergencyContactNumber]
            .where((s) => s != null && s.trim().isNotEmpty)
            .join(' · '),
      );
      await HomeWidget.saveWidgetData(
        'mg_updated',
        DateTime.now().toIso8601String(),
      );

      await HomeWidget.updateWidget(
        name: _widgetProvider,
        androidName: _widgetProvider,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LockScreenWidgetService.publish failed: $e');
      }
      return false;
    }
  }

  /// Clears the widget when the user logs out / removes their emergency
  /// card so nothing sensitive is left on the home screen.
  Future<void> clear() async {
    try {
      await HomeWidget.saveWidgetData('mg_name', '');
      await HomeWidget.saveWidgetData('mg_allergies', '');
      await HomeWidget.saveWidgetData('mg_blood', '');
      await HomeWidget.saveWidgetData('mg_contact', '');
      await HomeWidget.updateWidget(
        name: _widgetProvider,
        androidName: _widgetProvider,
      );
    } catch (_) {
      // Best-effort.
    }
  }
}
