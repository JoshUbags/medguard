import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'active_profile_service.dart';
import 'guest_mode_service.dart';

/// The "who am I reading and writing data for" question lives here.
///
/// With caregiver mode (one signed-in account that can switch between
/// dependents) the answer is: "the active managed profile, falling back to
/// the signed-in account, falling back to the local-only fixture for
/// unauthenticated runs".
///
/// [SessionService] resolves all three sources in one place and exposes a
/// [ValueNotifier] every screen can listen to so swapping the active
/// profile in the caregiver picker re-renders the rest of the app
/// automatically.
class SessionIdentity {
  const SessionIdentity({
    required this.ownerUserId,
    required this.activeUserId,
    required this.displayLabel,
    required this.isOwner,
  });

  /// The signed-in account's id (Firebase UID or the `'local-device'`
  /// fixture). This is what reads/writes that belong to "the device owner"
  /// — managed_profiles, pharmacogenomics inherited across profiles, etc.
  /// — should use.
  final String ownerUserId;

  /// The id every other table is scoped to. Equals [ownerUserId] when the
  /// caregiver has picked themselves; equals a profile slug when they've
  /// switched to a dependent.
  final String activeUserId;

  final String displayLabel;
  final bool isOwner;
}

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const String _localFallback = 'local-device';

  final ValueNotifier<SessionIdentity> identity =
      ValueNotifier<SessionIdentity>(const SessionIdentity(
    ownerUserId: _localFallback,
    activeUserId: _localFallback,
    displayLabel: 'Myself',
    isOwner: true,
  ));

  bool _started = false;

  /// Wire up auth + active-profile listeners. Safe to call multiple times.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        final owner = user?.uid ?? _localFallback;
        // An account taking over ends guest mode wherever the sign-in came
        // from — email, a social provider, or registration — so no screen has
        // to remember to clear the flag itself. Signing OUT deliberately does
        // not set it: that path lands on sign-in, which offers local-only as a
        // choice rather than making it for the user.
        if (user != null) {
          unawaited(GuestModeService.instance.exit());
        }
        unawaited(ActiveProfileService.instance.load(ownerUserId: owner));
        _publish(owner: owner, fromActive: ActiveProfileService.instance.current.value);
      });
      await ActiveProfileService.instance.load(
        ownerUserId: FirebaseAuth.instance.currentUser?.uid ?? _localFallback,
      );
    } catch (_) {
      // Firebase isn't initialised in tests / lock-only flows — fall back
      // to the local-device fixture and continue.
      await ActiveProfileService.instance.load(ownerUserId: _localFallback);
    }

    ActiveProfileService.instance.current.addListener(_onActiveChanged);
    _publish(
      owner: identity.value.ownerUserId,
      fromActive: ActiveProfileService.instance.current.value,
    );
  }

  void _onActiveChanged() {
    _publish(
      owner: identity.value.ownerUserId,
      fromActive: ActiveProfileService.instance.current.value,
    );
  }

  void _publish({
    required String owner,
    required ActiveProfile fromActive,
  }) {
    identity.value = SessionIdentity(
      ownerUserId: owner,
      activeUserId: fromActive.activeUserId == 'local-device' ||
              fromActive.activeUserId == fromActive.ownerUserId
          ? owner
          : fromActive.activeUserId,
      displayLabel: fromActive.label,
      isOwner: fromActive.isOwner,
    );
  }

  /// Convenience for non-listening callers — typically `initState` reads
  /// or one-shot operations like exporting data.
  String get activeUserId => identity.value.activeUserId;

  /// The owner id even when looking at a dependent — needed when listing
  /// managed profiles or syncing owner-level settings.
  String get ownerUserId => identity.value.ownerUserId;
}
