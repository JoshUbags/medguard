import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connectivity_probe_stub.dart'
    if (dart.library.io) 'connectivity_probe_io.dart';

typedef ConnectivityProbe = Future<bool> Function();

/// Reachability of the outside world, polled on one shared timer.
///
/// Every consumer — the account avatar's status dot, the API queue's flush
/// trigger, the app-wide banner — reads the SAME [status]. That matters
/// practically: each `watch()` used to spin up its own periodic DNS lookup, so
/// three listeners meant three probes a minute and three chances to disagree
/// about whether the device was online. One poller, one answer.
///
/// [status] is `null` until the first probe resolves, which is what lets the
/// banner distinguish "we don't know yet" (say nothing) from "we checked and
/// you are offline" (say so).
class ConnectivityService {
  ConnectivityService({
    ConnectivityProbe? probe,
    this.interval = const Duration(seconds: 12),
  }) : _probe = probe ?? defaultConnectivityProbe;

  static final ConnectivityService instance = ConnectivityService();

  final ConnectivityProbe _probe;
  final Duration interval;

  final ValueNotifier<bool?> _status = ValueNotifier<bool?>(null);

  /// The live answer: `true` online, `false` offline, `null` not yet known.
  ValueListenable<bool?> get status => _status;

  /// True once at least one probe has completed.
  bool get isResolved => _status.value != null;

  Timer? _timer;
  bool _probing = false;
  int _leases = 0;

  /// Takes a lease on the shared poll, starting it if this is the first.
  ///
  /// Lease-counted rather than a bare `start()`, because a poll with nobody
  /// listening is a timer that runs for the life of the process: it wakes the
  /// device, performs a DNS lookup every interval, and — in a widget test —
  /// outlives the case that created it and fails the next one with a pending
  /// timer. Every caller of [acquire] must call [release]; [watch] does both
  /// for its subscribers automatically.
  void acquire() {
    _leases++;
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => _refresh());
    unawaited(_refresh());
  }

  /// Drops a lease taken by [acquire]. The poll stops when the last one goes.
  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases == 0) stop();
  }

  /// Forces an immediate probe, e.g. after the app returns to the foreground,
  /// where waiting up to a full interval to notice the network came back would
  /// leave a stale "offline" banner on screen.
  Future<bool> refreshNow() async {
    await _refresh();
    return _status.value ?? false;
  }

  Future<void> _refresh() async {
    // A probe can outlive its interval on a bad network; overlapping lookups
    // would let an old, slow answer land after a newer one.
    if (_probing) return;
    _probing = true;
    try {
      final online = await _safeCheck();
      if (_status.value == online) return;
      _status.value = online;
    } finally {
      _probing = false;
    }
  }

  /// A stream view of [status], for call sites that want one. Shares the single
  /// poller rather than starting another.
  ///
  /// Built by hand rather than as an `async*` generator, and the ordering
  /// inside [onListen] is the reason. A generator does not begin running until
  /// its first `await`, so `start()` could kick off a probe that RESOLVED
  /// before the generator reached its `yield*` — and a listener that is not yet
  /// attached misses the event entirely, leaving the caller stuck on stale
  /// state until the next poll. Here the listener is attached first, the
  /// current value is replayed, and only then is the poll started.
  Stream<bool> watch() {
    late final StreamController<bool> controller;

    void emit() {
      final value = _status.value;
      if (value != null && !controller.isClosed) controller.add(value);
    }

    controller = StreamController<bool>(
      onListen: () {
        _status.addListener(emit);
        emit();
        acquire();
      },
      // One controller per listener, so it is finished with the moment that
      // listener goes away — and its lease on the poll goes with it.
      onCancel: () {
        _status.removeListener(emit);
        release();
        return controller.close();
      },
    );
    return controller.stream;
  }

  Future<bool> _safeCheck() async {
    try {
      return await _probe();
    } catch (_) {
      return false;
    }
  }

  /// Stops the shared poll regardless of outstanding leases. [acquire] starts
  /// it again.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
