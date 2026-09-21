import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import 'floating_nav_bar.dart';

/// What KIND of thing a notice is saying. Drives its whole treatment — see
/// [_NoticeStyle].
enum AppNoticeType {
  /// Something the user asked for worked.
  success,

  /// Something failed and they need to know.
  error,

  /// Neutral information. The quietest treatment in the set.
  info,

  /// A caution — true, not fatal, worth reading.
  warning,

  /// A destructive action with a way back. Always carries an action.
  undo,

  /// The device lost the network. Persistent: the state persists, so the
  /// message does too.
  offline,

  /// The network came back.
  online,
}

/// The design each category carries.
///
/// Every notice has the SAME structure — a capsule anchored to the bottom of
/// the interface, a leading glyph, the message, an optional trailing action —
/// because a message that moves or changes shape between categories makes the
/// user re-find it every time. What changes is the treatment *within* that
/// structure, so a category is recognisable before a word of it is read:
///
///  * **Severity rises through the glyph.** Information gets a flat tinted
///    disc; a caution gets a filled gradient disc; an error gets that plus a
///    coloured bloom under it. The eye picks up "how much does this matter"
///    from the weight of one 32px circle.
///  * **Only the ones that matter tint the capsule.** Errors and warnings wash
///    the surface faintly in their own colour so the whole pill reads as
///    coloured at a glance; success and information stay on clean surface,
///    because a confirmation should not shout.
///  * **The rim tracks the same scale**, from a barely-there hairline on
///    information to a definite edge on an error.
///  * **Connectivity states carry a second line**, because "No connection" on
///    its own prompts the question the detail line answers.
class _NoticeStyle {
  const _NoticeStyle({
    required this.accent,
    required this.icon,
    required this.emphasis,
    this.tintsSurface = false,
    this.persistent = false,
    this.detail,
  });

  final Color accent;
  final IconData icon;

  /// 0 = quiet (flat tinted disc), 1 = filled gradient disc, 2 = filled disc
  /// with a coloured bloom beneath it.
  final int emphasis;

  /// Whether the capsule itself takes a faint wash of [accent].
  final bool tintsSurface;

  /// Whether the notice stays until something replaces it.
  final bool persistent;

  /// The second line, for categories that need one.
  final String? detail;

  static _NoticeStyle of(AppNoticeType type, MedGuardColors colors) {
    return switch (type) {
      AppNoticeType.success => _NoticeStyle(
        accent: colors.accent,
        icon: Icons.check_rounded,
        emphasis: 1,
      ),
      AppNoticeType.error => _NoticeStyle(
        accent: colors.danger,
        icon: Icons.priority_high_rounded,
        emphasis: 2,
        tintsSurface: true,
      ),
      AppNoticeType.warning => _NoticeStyle(
        accent: colors.warning,
        icon: Icons.warning_amber_rounded,
        emphasis: 1,
        tintsSurface: true,
      ),
      AppNoticeType.info => _NoticeStyle(
        accent: colors.accent,
        icon: Icons.info_outline_rounded,
        emphasis: 0,
      ),
      AppNoticeType.undo => _NoticeStyle(
        accent: colors.inkSoft,
        icon: Icons.delete_sweep_rounded,
        emphasis: 0,
      ),
      AppNoticeType.offline => _NoticeStyle(
        accent: colors.warning,
        icon: Icons.wifi_off_rounded,
        emphasis: 1,
        tintsSurface: true,
        persistent: true,
        detail: 'Your saved medicines and reminders still work.',
      ),
      AppNoticeType.online => _NoticeStyle(
        accent: colors.accent,
        icon: Icons.wifi_rounded,
        emphasis: 1,
        detail: 'Syncing anything that was waiting.',
      ),
    };
  }
}

/// The live notice, so a new one replaces the old instead of stacking.
OverlayEntry? _activeNotice;
_AppNoticeHandle? _activeHandle;

/// A way to take a notice down again — needed by persistent ones, which have no
/// timer of their own.
class _AppNoticeHandle {
  _AppNoticeHandle(this._dismiss);
  final Future<void> Function() _dismiss;
  Future<void> dismiss() => _dismiss();
}

/// The single, app-wide popup message: a compact capsule that rides up from the
/// bottom and rests just above the floating navigation — anchored to the bottom
/// of the interface so it reads as a reply to what just happened, never
/// detached or floating.
///
/// EVERY transient message in the app goes through here, including the
/// connection banner, which used to drop from the top of the screen as its own
/// bespoke component. Two notification systems in one app means two positions,
/// two shapes and two sets of behaviour for the same job.
///
/// It renders into the root [Overlay] (not a SnackBar), so it appears at the
/// same place regardless of whether the host screen has a bottom nav, its
/// shadow fades smoothly with no clipped edge, and it auto-dismisses — unless
/// its category is persistent, in which case it waits to be replaced.
void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeType type = AppNoticeType.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // Replace any notice already on screen so they never stack.
  if (_activeNotice?.mounted ?? false) _activeNotice!.remove();
  _activeNotice = null;
  _activeHandle = null;

  final key = GlobalKey<_AppNoticeOverlayState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppNoticeOverlay(
      key: key,
      message: message,
      type: type,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismissed: () {
        if (_activeNotice == entry) {
          _activeNotice = null;
          _activeHandle = null;
        }
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _activeNotice = entry;
  _activeHandle = _AppNoticeHandle(() async {
    await key.currentState?.dismiss();
  });
  overlay.insert(entry);
}

/// Takes down whatever notice is on screen. Used when the condition a
/// persistent notice describes stops being true.
Future<void> dismissAppNotice() async {
  await _activeHandle?.dismiss();
}

/// Drives the toast's entrance, timed hold, and exit, then removes its entry.
class _AppNoticeOverlay extends StatefulWidget {
  const _AppNoticeOverlay({
    super.key,
    required this.message,
    required this.type,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppNoticeType type;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_AppNoticeOverlay> createState() => _AppNoticeOverlayState();
}

class _AppNoticeOverlayState extends State<_AppNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _timer;
  bool _leaving = false;

  /// How long the pill rests fully visible before it eases back out. Null means
  /// it does not leave on its own — see [_NoticeStyle.persistent].
  Duration? get _hold {
    if (_persistent) return null;
    if (widget.actionLabel != null) return const Duration(milliseconds: 5000);
    if (widget.type == AppNoticeType.error) {
      return const Duration(milliseconds: 4600);
    }
    return const Duration(milliseconds: 3200);
  }

  bool get _persistent => switch (widget.type) {
    AppNoticeType.offline => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _controller.forward();
    final hold = _hold;
    if (hold != null) _timer = Timer(hold, dismiss);
  }

  Future<void> dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      // Sits just above the floating navigation with a small, safe-area-aware
      // gap, so the toast feels anchored to the bottom of the interface rather
      // than detached.
      bottom: bottomInset + kFloatingNavReserveHeight + 4,
      left: 14,
      right: 14,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final t = _curve.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 18),
              child: child,
            ),
          );
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: dismiss,
            child: _AppNoticePill(
              message: widget.message,
              type: widget.type,
              actionLabel: widget.actionLabel,
              onAction: widget.onAction == null
                  ? null
                  : () {
                      widget.onAction!();
                      dismiss();
                    },
            ),
          ),
        ),
      ),
    );
  }
}

class _AppNoticePill extends StatelessWidget {
  const _AppNoticePill({
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppNoticeType type;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = _NoticeStyle.of(type, colors);
    final action = actionLabel;
    final detail = style.detail;

    // Only the categories that matter tint the capsule; the rest stay on clean
    // surface so a confirmation never shouts as loudly as a failure.
    final surface = style.tintsSurface
        ? Color.alphaBlend(
            style.accent.withValues(alpha: colors.isDark ? 0.14 : 0.05),
            colors.surface,
          )
        : colors.surface;

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 8, action == null ? 18 : 8, 8),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(detail == null ? 100 : 22),
            border: Border.all(
              // The rim tracks the emphasis scale, from a hairline on
              // information to a definite edge on an error.
              color: style.accent.withValues(
                alpha: switch (style.emphasis) {
                  2 => 0.34,
                  1 => 0.22,
                  _ => 0.14,
                },
              ),
            ),
            // Two stacked, low-opacity shadows — a wide diffuse lift and a
            // tight contact shadow — so the pill reads as elevated and fades
            // off with no hard edge.
            boxShadow: [
              BoxShadow(
                color: MedGuardPalette.blackAlpha(0.10),
                blurRadius: 30,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: MedGuardPalette.blackAlpha(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: detail == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _NoticeGlyph(style: style),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: colors.inkSoft,
                          fontSize: 11.6,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentAlpha(0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      action,
                      style: GoogleFonts.inter(
                        color: colors.accent,
                        fontSize: 12.4,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The leading glyph — the element that carries "how much does this matter".
class _NoticeGlyph extends StatelessWidget {
  const _NoticeGlyph({required this.style});

  final _NoticeStyle style;

  @override
  Widget build(BuildContext context) {
    final accent = style.accent;
    final quiet = style.emphasis == 0;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Quiet categories get a flat tinted disc with a coloured glyph;
        // everything above gets a filled gradient with a white glyph.
        color: quiet ? accent.withValues(alpha: 0.12) : null,
        gradient: quiet
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, Colors.black, 0.16) ?? accent,
                ],
              ),
        // Only the top of the scale gets a bloom beneath it.
        boxShadow: style.emphasis >= 2
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.34),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Icon(
        style.icon,
        color: quiet ? accent : MedGuardPalette.pureWhite,
        size: 18,
      ),
    );
  }
}
