import 'package:flutter/material.dart';

import '../../theme/medguard_palette.dart';
import '../../widgets/common/morph_loader.dart';

/// How long the launch animation is guaranteed to stay on screen. Long enough
/// for the formation to complete a full rearrangement so it reads as
/// intentional, short enough never to feel like a wait.
const Duration kStartupIntro = Duration(milliseconds: 1700);

/// The hard ceiling on the splash. Even if startup work is still running, the
/// app routes on at this point rather than holding a loading screen forever.
const Duration kStartupCeiling = Duration(milliseconds: 4600);

/// The launch lockup: the app's [MorphLoader] at display size, on the brand
/// canvas, with a soft halo behind it.
///
/// It is deliberately the SAME mark the app shows whenever it is working, just
/// larger. The splash is where a user learns what "MedGuard is thinking" looks
/// like; showing them one animation at launch and a different one everywhere
/// after wastes that, and makes the app feel assembled from parts. Here it is
/// the whole screen; in a card it is 42 points wide; it is the same object.
///
/// No wordmark and no status text, on purpose. The motion carries the meaning:
/// parts visibly rearranging themselves is the universal read for *something is
/// being worked out*, which is exactly what is happening behind it.
class MedGuardStartupAnimation extends StatelessWidget {
  const MedGuardStartupAnimation({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final extent = (size.shortestSide * 0.34).clamp(120.0, 190.0).toDouble();

    return Semantics(
      label: 'Starting',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: extent * 1.9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // A wide, very soft halo so the mark sits in its own pool of
              // light rather than floating on a flat field. On the deep teal
              // canvas this is what gives the screen depth.
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      MedGuardPalette.whiteAlpha(0.13),
                      MedGuardPalette.whiteAlpha(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
                child: SizedBox.square(dimension: extent * 1.9),
              ),
              // Glow off: on a saturated canvas a coloured bloom under white
              // tiles muddies them rather than lifting them.
              MorphLoader(
                size: extent,
                color: MedGuardPalette.whiteAlpha(0.97),
                glow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The launch canvas: the brand teal, deepened toward the corners so the centre
/// reads as lit and the mark has somewhere to sit.
class StartupBackdrop extends StatelessWidget {
  const StartupBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.06),
          radius: 1.05,
          colors: [
            Color(0xFF0A7A6E),
            MedGuardPalette.teal,
            MedGuardPalette.tealDeep,
          ],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: child,
    );
  }
}
