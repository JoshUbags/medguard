import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/connectivity_service.dart';
import 'app_notice.dart';

/// Watches the connection and speaks through the app's ONE notification
/// system.
///
/// It used to render its own capsule dropping from the top of the screen. That
/// meant the app had two notification mechanisms — one at the top for
/// connectivity, one at the bottom for everything else — in two shapes, with
/// two sets of behaviour, for the same job. This now raises an [showAppNotice]
/// like every other message in the app: same position, same structure, same
/// entrance. The *category* differs ([AppNoticeType.offline] /
/// [AppNoticeType.online]), which is what gives it its own colour, glyph and
/// second line.
///
/// Mounted ONCE, around the whole app. Connection state belongs to the session,
/// not to a page: mounting it per screen would re-announce the state on every
/// navigation.
///
/// Two rules about when it speaks:
///
///  * It says NOTHING on a normal, connected launch. A banner that greets every
///    cold start with "you are online" is noise; the absence of one already
///    carries that message.
///  * "Back online" is transient and self-dismisses; "No connection" persists,
///    because that state persists.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child, this.service});

  final Widget child;

  /// Injectable for tests; defaults to the shared singleton.
  final ConnectivityService? service;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with WidgetsBindingObserver {
  ConnectivityService get _service =>
      widget.service ?? ConnectivityService.instance;

  /// The last resolved state, so a *transition* can be told from a repeated
  /// reading of the same state.
  bool? _lastOnline;

  /// True while an offline notice of ours is on screen, so we only take one
  /// down if we were the one that put it up.
  bool _showingOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.status.addListener(_onStatusChanged);
    // Lease-counted: the poll runs while this is mounted and stops with it, so
    // a torn-down app (or a finished widget test) leaves no periodic DNS lookup
    // behind.
    _service.acquire();
    _lastOnline = _service.status.value;
    // A launch that is ALREADY known to be offline still deserves the notice —
    // the "stay quiet on launch" rule is about not announcing success. Deferred
    // to after the first frame, because there is no Overlay to insert into
    // until the app has built one.
    if (_lastOnline == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announceOffline());
    }
  }

  @override
  void dispose() {
    _service.status.removeListener(_onStatusChanged);
    _service.release();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the background is the most likely moment for the
    // connection to have silently changed — the user may have walked out of
    // range or turned off flight mode. Waiting up to a full poll interval to
    // notice would leave a message on screen that is simply wrong.
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.refreshNow());
    }
  }

  void _announceOffline() {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _showingOffline = true;
    showAppNotice(
      context,
      'No connection',
      type: AppNoticeType.offline,
    );
  }

  void _onStatusChanged() {
    final online = _service.status.value;
    if (online == null || !mounted) return;

    final previous = _lastOnline;
    _lastOnline = online;
    if (previous == online) return;

    if (!online) {
      _announceOffline();
      return;
    }

    // Came back online. Only worth announcing if the user was actually told it
    // had dropped — otherwise this is the first successful probe of the session
    // and there is nothing to reassure them about.
    if (previous == null) {
      if (_showingOffline) {
        _showingOffline = false;
        unawaited(dismissAppNotice());
      }
      return;
    }
    _showingOffline = false;
    HapticFeedback.lightImpact();
    showAppNotice(context, 'Back online', type: AppNoticeType.online);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
