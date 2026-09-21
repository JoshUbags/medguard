import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';

/// THE MedGuard loading mark — four tiles that continuously rearrange.
///
/// Four rounded tiles orbit a shared centre. As they travel they morph between
/// a circle and a squircle, and the whole formation gathers inward and disperses
/// outward twice per cycle, so the mark reads as *shapes rearranging themselves*
/// rather than as a spinner going round.
///
/// Why this instead of a ring: a rotating arc says "wait". A set of parts
/// visibly re-ordering says "something is being worked out" — which is what the
/// app is actually doing at every point it shows this (resolving a regimen,
/// scoring interactions, assembling a report). It is the same idea the launch
/// screen carries, reduced to a mark small enough to sit inside a card.
///
/// **The loop is mathematically seamless.** Every tile's morph and scale are
/// driven by its *angular position*, not by its index, and the formation turns
/// exactly 90° per cycle. Because the arrangement has four-fold symmetry, at the
/// end of a cycle each tile has landed precisely where its neighbour began — in
/// that neighbour's exact shape and size. There is no jump to hide, and so no
/// fade or restart is needed.
class MorphLoader extends StatefulWidget {
  const MorphLoader({super.key, this.size = 42, this.color, this.glow = true});

  /// Outer extent of the mark. Tiles are sized from this, so the loader keeps
  /// its proportions at any scale.
  final double size;

  /// Tile colour. Defaults to the theme accent; the launch screen passes white.
  final Color? color;

  /// A soft coloured bloom under each tile. Reads beautifully on a light canvas
  /// and is wasted on a saturated one, so the splash turns it off.
  final bool glow;

  @override
  State<MorphLoader> createState() => _MorphLoaderState();
}

class _MorphLoaderState extends State<MorphLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle;

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(
      vsync: this,
      // Slow enough to be watched without impatience, quick enough that a tile
      // visibly moves between two glances.
      duration: const Duration(milliseconds: 2200),
    );
    // An endlessly repeating controller makes `pumpAndSettle` spin forever, so
    // under widget tests the mark holds its (fully composed) first frame — the
    // same guard the orb and the launch animation use.
    final underTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    if (!underTest) _cycle.repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.accent;
    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _cycle,
            builder: (context, _) => CustomPaint(
              painter: _MorphPainter(
                t: _cycle.value,
                color: color,
                glow: widget.glow,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.t,
    required this.color,
    required this.glow,
  });

  /// 0→1, looping.
  final double t;
  final Color color;
  final bool glow;

  /// Four tiles: the smallest count that still reads as a *formation* with a
  /// centre, and the count whose rotational symmetry makes the loop seamless.
  static const int _tiles = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final extent = math.min(size.width, size.height);

    // The formation turns exactly a quarter turn per cycle. With four-fold
    // symmetry that is a full period — this is what makes the loop seamless.
    final spin = t * math.pi / 2;

    // Gather and disperse: the ring draws in tight and opens out twice per
    // cycle. Integer frequency, so it closes its own loop.
    final breath = math.sin(t * 2 * math.pi * 2);
    final orbit = extent * (0.235 + 0.055 * breath);

    // Tiles shrink a little as the ring opens, so the mark holds a constant
    // visual weight instead of appearing to swell.
    final tileBase = extent * (0.275 - 0.022 * breath);

    for (var i = 0; i < _tiles; i++) {
      // Position on the ring. EVERY per-tile quantity below is derived from
      // this angle rather than from `i`, which is precisely why a tile arriving
      // at its neighbour's position also arrives in its neighbour's shape.
      final angle = spin + i * (2 * math.pi / _tiles);

      final cx = centre.dx + math.cos(angle) * orbit;
      final cy = centre.dy + math.sin(angle) * orbit;

      // Corner morph: fully round at one side of the ring, squircle at the
      // other, travelling continuously between the two.
      final round = 0.5 + 0.5 * math.sin(angle);
      // 0.30 of the half-extent is a crisp squircle; 0.5 is a circle.
      final cornerFactor = 0.30 + 0.20 * round;

      // A travelling swell — a wave running around the ring, a quarter turn
      // out of phase with the morph, so no two tiles peak together.
      final swell = 1.0 + 0.10 * math.sin(angle - math.pi / 2);
      final tile = tileBase * swell;
      final half = tile / 2;

      // The leading tile is fullest; the trailing one recedes slightly. Enough
      // to give the ring a direction of travel, never enough to look faulty.
      final alpha = 0.62 + 0.38 * round;

      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: tile,
        height: tile,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(half * cornerFactor * 2),
      );

      if (glow) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.30)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, extent * 0.055),
        );
      }

      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(covariant _MorphPainter old) =>
      old.t != t || old.color != color || old.glow != glow;
}

/// THE in-content loading state: the morph mark over an optional line of text,
/// centred in whatever space it is given.
///
/// Every "we are fetching this" moment in the app uses this, so a wait looks the
/// same whether it happens inside a card, on a tab, or behind a routed screen.
/// Pass [message] when the wait is long enough that the user deserves to know
/// what is being done; leave it off for short, obvious ones.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.size = 46, this.padding});

  final String? message;
  final double size;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final label = message;

    return Padding(
      padding: padding ?? EdgeInsets.symmetric(vertical: responsive.s(34)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphLoader(size: responsive.s(size)),
            if (label != null) ...[
              SizedBox(height: responsive.s(16)),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(12.8),
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Runs [action] behind a blocking wait — the modal form of [LoadingView], for
/// operations the user must not interrupt (assembling a PDF, wiping data).
///
/// The overlay cannot be dismissed by tapping away or by the back gesture,
/// because every use of it would leave state half-written if abandoned. It is
/// always torn down, including when [action] throws, and the error is rethrown
/// for the caller to surface.
Future<T> withBlockingLoader<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? message,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final barrier = context.colors.scaffold.withValues(alpha: 0.72);

  // Deliberately NOT awaited: this future completes only when the route is
  // popped, which is what the `finally` below does once the work is finished.
  final dismissed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: barrier,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: LoadingView(message: message, padding: EdgeInsets.zero),
      ),
    ),
  );

  var open = true;
  // If the route is torn down by something else (the whole screen being
  // popped), don't try to pop it a second time.
  unawaited(dismissed.whenComplete(() => open = false));

  try {
    return await action();
  } finally {
    if (open) navigator.pop();
  }
}
