import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';

/// The default glass tint strength — calibrated to the home header's
/// notification + avatar capsule, which is THE reference glass for the app.
/// Every other pane is that same material, so nothing has to be matched by eye.
///
/// Deliberately LOW: this is the single value that decides whether a pane reads
/// as glass or as a frosted slab. Above roughly 0.5 light stops passing through
/// and the surface becomes opaque plastic; real glass earns its legibility from
/// the blur and the saturation lift underneath, not from hiding what is behind
/// it.
const double kGlassTint = 0.22;

/// The reference blur, again taken from the home header capsule.
const double kGlassBlur = 22;

/// How much the backdrop's colour is amplified before the tint goes over it.
/// This is the detail that separates convincing glass from a grey wash: real
/// glass concentrates the colour behind it, so a teal card passing under the
/// pane should visibly bloom teal through it.
const double kGlassSaturation = 1.7;

/// THE glass material. Every frosted surface in MedGuard is this one widget, so
/// the app has a single glass rather than a family of lookalikes.
///
/// It is built from five layers, and all five matter — drop any one and the
/// illusion collapses into "a translucent rectangle":
///
///  1. a real [BackdropFilter] blur, so content behind is genuinely diffused;
///  2. a **saturation lift** on that same backdrop, so colour blooms through
///     the pane instead of going muddy grey;
///  3. a low-opacity tint that is brighter at the top than the bottom — glass
///     lit from above, which is what gives a flat pane its curvature;
///  4. a **gradient rim**: bright along the top-left edge where light catches,
///     fading to nearly nothing at the bottom-right. A uniform 1px border is
///     the single most common tell of fake glass;
///  5. an inner highlight just inside the top edge, reading as the pane's
///     thickness catching light.
///
/// Optionally a specular sheen sweeps the top half ([gloss]) for interactive
/// panes, and a soft shadow lifts it off the page.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint = kGlassTint,
    this.blur = kGlassBlur,
    this.gloss = false,
    this.shadow = false,
    this.padding = EdgeInsets.zero,
    this.height,
    this.tintColor,
  });

  /// A stadium-shaped pane — the shape used by the AI input. Resolves its own
  /// radius from [height].
  const GlassSurface.pill({
    Key? key,
    required Widget child,
    required double height,
    double tint = kGlassTint,
    double blur = kGlassBlur,
    bool gloss = false,
    bool shadow = false,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    Color? tintColor,
  }) : this(
         key: key,
         borderRadius: null,
         height: height,
         tint: tint,
         blur: blur,
         gloss: gloss,
         shadow: shadow,
         padding: padding,
         tintColor: tintColor,
         child: child,
       );

  final Widget child;

  /// The pane's corner radius. Null means "fully rounded", resolved from
  /// [height] — the [GlassSurface.pill] shape.
  final BorderRadius? borderRadius;

  /// Strength of the glass tint. See [kGlassTint] — keep it low.
  final double tint;

  /// Backdrop blur sigma. Higher diffuses busy content more completely.
  final double blur;

  /// Adds a specular highlight across the top half — the "glossy" read used on
  /// interactive panes rather than passive chrome.
  final bool gloss;

  /// The soft drop shadow that lifts the pane off the page.
  final bool shadow;

  final EdgeInsetsGeometry padding;

  /// Fixes the pane's height. Required for [GlassSurface.pill].
  final double? height;

  /// Overrides the colour the tint is mixed from. Defaults to the surface
  /// colour in light and white in dark — i.e. the pane takes the theme's own
  /// material. Pass white here for a pane that must read as WHITE glass in both
  /// modes (the AI composer), rather than as a pane of the dark canvas.
  final Color? tintColor;

  BorderRadius _radius() =>
      borderRadius ?? BorderRadius.circular((height ?? 0) / 2);

  /// Blur + saturation in one filter, so the backdrop is sampled once.
  static ImageFilter _backdrop(double blur) {
    return ImageFilter.compose(
      outer: ColorFilter.matrix(_saturate(kGlassSaturation)),
      inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
    );
  }

  /// A standard saturation matrix around the luminance axis.
  static List<double> _saturate(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
    return <double>[
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0, //
      ir, ig, ib + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = colors.isDark;
    final radius = _radius();

    // Dark glass takes a lighter hand: the same tint over a dark canvas reads
    // far heavier than it does over a light one.
    final top = isDark ? tint * 0.62 : tint;
    final bottom = isDark ? tint * 0.34 : tint * 0.62;
    final paneTint =
        tintColor ?? (isDark ? MedGuardPalette.pureWhite : colors.surface);

    final pane = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: _backdrop(blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // Lit from above.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                paneTint.withValues(alpha: top.clamp(0.0, 1.0)),
                paneTint.withValues(alpha: bottom.clamp(0.0, 1.0)),
              ],
            ),
          ),
          child: SizedBox(
            height: height,
            child: Stack(
              // passthrough hands the pane's own constraints straight to the
              // content, so a fixed-height pane gives its child a TIGHT height
              // and the child fills it. Without this the stack falls back to
              // loose constraints aligned top-start, which is what pinned the
              // AI input's text and send button to the top of the pill instead
              // of centring them.
              fit: StackFit.passthrough,
              children: [
                // The content is the Stack's ONLY non-positioned child, so it
                // is what sizes the pane when no height is given. Without this
                // the stack has no intrinsic size and blows up the moment the
                // surface is placed somewhere horizontally unbounded — a
                // header row, say.
                Padding(padding: padding, child: child),
                // ── The specular sheen, on the top half of the pane. ──────
                if (gloss)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              MedGuardPalette.whiteAlpha(isDark ? 0.14 : 0.40),
                              MedGuardPalette.whiteAlpha(0.0),
                            ],
                            stops: const [0.0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                // ── The rim: bright top-left, fading to almost nothing at the
                // bottom-right. A uniform border is the giveaway of fake
                // glass; a raking one reads as a lit edge. ─────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GlassRimPainter(radius: radius, isDark: isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!shadow) return pane;

    return DecoratedBox(
      // The shadow lives on an outer box so the clip above can't cut it off.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.blackAlpha(isDark ? 0.38 : 0.12),
            blurRadius: 26,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: pane,
    );
  }
}

/// Paints the pane's lit edge: ONE raking rim, bright where the light falls on
/// the top-left and fading to almost nothing at the bottom-right.
///
/// Deliberately a single stroke. An earlier version added a second inner
/// catch-light just under the top edge; on a small pane the two sit only a
/// pixel or two apart and read as a double border rather than as one piece of
/// lit glass. The gradient along a single rim does the same job honestly.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.isDark});

  final BorderRadius radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);

    canvas.drawRRect(
      rrect.deflate(0.55),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MedGuardPalette.whiteAlpha(isDark ? 0.32 : 0.88),
            MedGuardPalette.whiteAlpha(isDark ? 0.11 : 0.40),
            MedGuardPalette.whiteAlpha(isDark ? 0.03 : 0.08),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter old) =>
      old.radius != radius || old.isDark != isDark;
}
