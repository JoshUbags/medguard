import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/managed_profile.dart';
import 'user_data_service.dart';

/// Identity of whichever person the user is currently looking at — either
/// themselves (`ownerUserId`) or one of their managed [ManagedProfile]s.
///
/// Existing screens already read a `userId` string from a route argument or
/// constant ("local-device"). This service lets the caregiver swap which
/// id is "active" so the rest of the app — medications list, dose
/// scheduler, allergy checks, safety reports — automatically scopes to the
/// right person without touching every screen.
class ActiveProfile {
  const ActiveProfile({
    required this.ownerUserId,
    required this.activeUserId,
    required this.label,
    required this.isOwner,
  });

  final String ownerUserId;
  final String activeUserId;
  final String label;
  final bool isOwner;
}

class ActiveProfileService {
  ActiveProfileService._();
  static final ActiveProfileService instance = ActiveProfileService._();

  static const _prefsKey = 'medguard.active_profile_id';
  static const _ownerKey = 'medguard.owner_user_id';

  final ValueNotifier<ActiveProfile> current = ValueNotifier<ActiveProfile>(
    const ActiveProfile(
      ownerUserId: 'local-device',
      activeUserId: 'local-device',
      label: 'Myself',
      isOwner: true,
    ),
  );

  Future<void> load({String ownerUserId = 'local-device'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, ownerUserId);
    final saved = prefs.getString(_prefsKey);
    if (saved == null || saved == ownerUserId) {
      current.value = ActiveProfile(
        ownerUserId: ownerUserId,
        activeUserId: ownerUserId,
        label: 'Myself',
        isOwner: true,
      );
      return;
    }
    final profiles =
        await UserDataService.instance.getManagedProfiles(ownerUserId);
    final match =
        profiles.where((p) => p.profileId == saved).firstOrNull;
    if (match == null) {
      current.value = ActiveProfile(
        ownerUserId: ownerUserId,
        activeUserId: ownerUserId,
        label: 'Myself',
        isOwner: true,
      );
      await prefs.remove(_prefsKey);
    } else {
      current.value = ActiveProfile(
        ownerUserId: ownerUserId,
        activeUserId: match.profileId,
        label: match.name,
        isOwner: false,
      );
    }
  }

  Future<void> switchToOwner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    current.value = ActiveProfile(
      ownerUserId: current.value.ownerUserId,
      activeUserId: current.value.ownerUserId,
      label: 'Myself',
      isOwner: true,
    );
  }

  Future<void> switchTo(ManagedProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, profile.profileId);
    current.value = ActiveProfile(
      ownerUserId: current.value.ownerUserId,
      activeUserId: profile.profileId,
      label: profile.name,
      isOwner: false,
    );
  }
}
