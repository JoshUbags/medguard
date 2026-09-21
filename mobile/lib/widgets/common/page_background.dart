import 'package:flutter/material.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';

/// The character a page's canvas carries.
///
/// Every screen used the identical teal wash, which meant that at a glance —
/// before a single word is read — Home, Insights and Dose were the same picture.
/// Tone gives each destination its own light without letting any of them leave
/// the brand: the hues below are all within a step or two of the MedGuard teal,
/// and the shift is carried by *temperature and depth* rather than by a
/// different colour. You register that you have arrived somewhere new; you
/// could not name what changed.
enum PageTone {
  /// The brand teal. Home, and the default everywhere else.
  brand,

  /// Cooler and bluer — the analytical pages, where the content is a verdict.
  clinical,

  /// Warmer, with a deeper base — the editorial page, which is for reading
  /// rather than for checking.
  editorial,

  /// Greener and softer — the routine pages, which are about habit.
  routine,
}

extension _ToneColours on PageTone {
  /// The three ambient hues, in draw order. Kept deliberately low-alpha: this
  /// layer must read as atmosphere, never as decoration.
  List<Color> hues(MedGuardColors colors) => switch (this) {
    PageTone.brand => [
      colors.accentAlpha(0.075),
      MedGuardPalette.tealLight.withValues(alpha: 0.06),
      colors.accentAlpha(0.065),
    ],
    PageTone.clinical => [
      const Color(0xFF3E8EF0).withValues(alpha: 0.055),
      colors.accentAlpha(0.055),
      const Color(0xFF4C5BAC).withValues(alpha: 0.05),
    ],
    PageTone.editorial => [
      const Color(0xFFD98C2B).withValues(alpha: 0.07),
      colors.accentAlpha(0.07),
      const Color(0xFFB4643A).withValues(alpha: 0.055),
    ],
    PageTone.routine => [
      colors.accentAlpha(0.07),
      const Color(0xFF44786A).withValues(alpha: 0.065),
      MedGuardPalette.tealLight.withValues(alpha: 0.055),
    ],
  };

  /// A faint wash over the whole scaffold, so the page reads as tinted paper
  /// rather than as white with some blobs on it. This is what answers "no need
  /// to make everything so white" — the surface itself carries a temperature,
  /// while cards stay clean and therefore still lift off it.
  Color wash(MedGuardColors colors) => switch (this) {
    PageTone.brand => colors.accentAlpha(colors.isDark ? 0.0 : 0.014),
    PageTone.clinical => const Color(0xFF3E8EF0).withValues(
      alpha: colors.isDark ? 0.0 : 0.016,
    ),
    PageTone.editorial => const Color(0xFFD98C2B).withValues(
      alpha: colors.isDark ? 0.0 : 0.026,
    ),
    PageTone.routine => const Color(0xFF44786A).withValues(
      alpha: colors.isDark ? 0.0 : 0.020,
    ),
  };
}

/// THE app canvas: a few EXTREMELY large, very soft circular gradients in the
/// brand palette, widely spaced and mostly drawn off-screen so only their
/// gentlest edges bleed in.
///
/// Each carries a very low alpha and fades smoothly to transparent, so the
/// layer reads as almost-invisible atmosphere — the user senses depth and
/// richness, not the circles themselves. It is what stops white cards on a
/// near-white scaffold from having no edges and going flat.
///
/// Always wrap it in a [RepaintBoundary] (or use [PageBackground], which does)
/// so it rasterises once and never repaints while a feed scrolls over it.
class SoftPageBackground extends StatelessWidget {
  const SoftPageBackground({super.key, this.tone = PageTone.brand});

  final PageTone tone;

  Widget _orb({required double size, required Color color}) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            // A slow three-stop fade gives extra-soft, edgeless falloff.
            colors: [
              color,
              color.withValues(alpha: color.a * 0.4),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hues = tone.hues(colors);
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: tone.wash(colors))),
            Positioned(
              top: -340,
              right: -300,
              child: _orb(size: 860, color: hues[0]),
            ),
            Positioned(
              top: 380,
              left: -380,
              child: _orb(size: 760, color: hues[1]),
            ),
            Positioned(
              bottom: -400,
              right: -260,
              child: _orb(size: 900, color: hues[2]),
            ),
          ],
        ),
      ),
    );
  }
}

/// The canvas with content laid over it — the form every page actually uses.
///
/// Fills the scaffold colour first so the page is never transparent, paints the
/// atmosphere into its own repaint boundary, then puts [child] on top.
class PageBackground extends StatelessWidget {
  const PageBackground({
    super.key,
    required this.child,
    this.tone = PageTone.brand,
  });

  final Widget child;
  final PageTone tone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: context.colors.scaffold)),
        Positioned.fill(
          child: RepaintBoundary(child: SoftPageBackground(tone: tone)),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
