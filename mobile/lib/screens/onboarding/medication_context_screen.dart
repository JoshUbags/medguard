import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../welcome/welcome_assets.dart';
import 'onboarding_chrome.dart';
import 'safety_checks_overview_screen.dart';

class MedicationContextScreen extends StatefulWidget {
  const MedicationContextScreen({super.key});

  @override
  State<MedicationContextScreen> createState() =>
      _MedicationContextScreenState();
}

class _MedicationContextScreenState extends State<MedicationContextScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _next() {
    Navigator.of(
      context,
    ).push(onboardingSlideRoute(const SafetyChecksOverviewScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: context.colors.scaffold,
        body: SafeArea(
          child: Column(
            children: [
              const OnboardingSkipAction(),
              const SizedBox(height: 6),
              // ── Image-driven editorial hero: one dominant central image
              // anchored by supporting tiles of varying sizes around it. ──────
              Expanded(child: _MedicationImageComposition(animation: _float)),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Column(
                  children: [
                    Text.rich(
                      textAlign: TextAlign.center,
                      TextSpan(
                        style: GoogleFonts.inter(
                          color: context.colors.ink,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          height: 1.02,
                          letterSpacing: -0.4,
                        ),
                        children: const [
                          TextSpan(text: 'See Medication\n'),
                          TextSpan(
                            text: 'Context',
                            style: TextStyle(color: MedGuardPalette.teal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const OnboardingTag(
                      icon: Icons.link_rounded,
                      label: 'Context Linked',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Keep medicine pairs, timing notes, and counselling context together.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: context.colors.inkSoft,
                        fontSize: 13.2,
                        height: 1.46,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
              OnboardingFooter(
                activeIndex: 1,
                onBack: () => Navigator.of(context).pop(),
                onNext: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tile in the composition: a bundled photograph, its size and position
/// expressed against a reference frame (see [_MedicationImageComposition]).
class _Tile {
  const _Tile({
    required this.asset,
    required this.w,
    required this.h,
    required this.dx,
    required this.dy,
    required this.angle,
    required this.drift,
    this.radius = 18,
    this.dominant = false,
  });

  final String asset;
  final double w;
  final double h;
  final double dx;
  final double dy;
  final double angle;
  final double drift;
  final double radius;
  final bool dominant;
}

class _MedicationImageComposition extends StatelessWidget {
  const _MedicationImageComposition({required this.animation});

  final Animation<double> animation;

  // A curated layered cluster: one clearly dominant focal image with four
  // supporting tiles tucked behind its corners. Positions are authored against
  // this reference frame (then scaled to the available space) so each support
  // peeks out from a corner and overlaps only the focal — never another
  // support — reading as one cohesive, layered stack rather than a scattered
  // ring. Every image is bundled (no network), so the whole composition paints
  // instantly, and each tile pops when tapped.
  static const double _refW = 372;
  static const double _refH = 388;

  // The supporting tiles — drawn behind the focal image, each tucking one inner
  // corner under it for depth. Clockwise from top-left.
  static const List<_Tile> _backTiles = [
    _Tile(
      asset: 'assets/images/onboarding/02.jpg', // hand + pills — top-left
      w: 106,
      h: 128,
      dx: -120,
      dy: -94,
      angle: -0.06,
      drift: -4,
      radius: 20,
    ),
    _Tile(
      asset:
          'assets/images/onboarding/01.jpg', // plate + thermometer — top-right
      w: 110,
      h: 132,
      dx: 120,
      dy: -86,
      angle: 0.06,
      drift: 4,
      radius: 20,
    ),
    _Tile(
      asset:
          'assets/images/onboarding/05.jpg', // pill on tongue (wide) — bottom-right
      w: 128,
      h: 92,
      dx: 108,
      dy: 114,
      angle: -0.04,
      drift: 4,
      radius: 18,
    ),
    _Tile(
      asset:
          'assets/images/onboarding/08.jpg', // citrus + blister — bottom-left
      w: 110,
      h: 128,
      dx: -118,
      dy: 106,
      angle: 0.05,
      drift: -4,
      radius: 20,
    ),
  ];

  // The focal image — emphatically the largest, centred and on top so the eye
  // lands on it first; the supports stay clearly secondary around its corners.
  static const _Tile _dominant = _Tile(
    asset: 'assets/images/onboarding/03.jpg', // clinician with two pill types
    w: 188,
    h: 234,
    dx: 0,
    dy: -2,
    angle: 0,
    drift: 2,
    radius: 28,
    dominant: true,
  );

  // (Supports only ever overlap the focal, so nothing is drawn in front of it.)
  static const List<_Tile> _frontTiles = [];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // A slow, gentle drift gives the supporting tiles editorial life.
        final lift = (Curves.easeInOut.transform(animation.value) - 0.5) * 2;
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final scale = math
                .min(w / _refW, h / _refH)
                .clamp(0.5, 1.05)
                .toDouble();

            Widget place(_Tile t) {
              return Transform.translate(
                offset: Offset(t.dx * scale, t.dy * scale + t.drift * lift),
                child: _CompositionTile(
                  asset: t.asset,
                  width: t.w * scale,
                  height: t.h * scale,
                  angle: t.angle,
                  radius: t.radius,
                  dominant: t.dominant,
                ),
              );
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final t in _backTiles) place(t),
                place(_dominant),
                for (final t in _frontTiles) place(t),
              ],
            );
          },
        );
      },
    );
  }
}

class _CompositionTile extends StatefulWidget {
  const _CompositionTile({
    required this.asset,
    required this.width,
    required this.height,
    required this.angle,
    this.radius = 18,
    this.dominant = false,
  });

  final String asset;
  final double width;
  final double height;
  final double angle;
  final double radius;
  final bool dominant;

  @override
  State<_CompositionTile> createState() => _CompositionTileState();
}

class _CompositionTileState extends State<_CompositionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    // A quick swell to ~1.10 then a soft over-spring back to rest.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.10,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.10,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 58,
      ),
    ]).animate(_pop);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.selectionClick();
    _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.dominant ? 5.0 : 3.0;
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _pop,
          // The image is built once and passed as [child]; only the cheap
          // transforms rebuild as the tap animation plays.
          child: _frame(frame),
          builder: (context, child) {
            // A short triangular pulse (0 → 1 → 0) lifts the tile slightly so
            // the tap reads as a physical pop without disturbing layout.
            final pulse = 1 - (_pop.value * 2 - 1).abs();
            return Transform.translate(
              offset: Offset(0, -7 * pulse),
              child: Transform.scale(
                scale: _scale.value,
                child: Transform.rotate(angle: widget.angle, child: child),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _frame(double frame) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: context.colors.surface, width: frame),
        boxShadow: [
          // Light, sophisticated lift — depth comes from scale and layering,
          // not from heavy shadows.
          BoxShadow(
            color: context.colors.accent.withValues(
              alpha: widget.dominant ? 0.17 : 0.08,
            ),
            blurRadius: widget.dominant ? 30 : 14,
            spreadRadius: -8,
            offset: Offset(0, widget.dominant ? 15 : 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius - frame),
        child: Image.asset(
          widget.asset,
          fit: BoxFit.cover,
          width: widget.width,
          height: widget.height,
          // Bundled + downsampled to ~2× display width — instant paint, no
          // memory bloat, no network.
          cacheWidth: kMedicationTileCacheWidth,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
