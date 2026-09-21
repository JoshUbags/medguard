import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_palette.dart';
import 'app_button.dart';
import 'pressable.dart';

/// The Welcome screen's tap-to-continue action — the single entry point into
/// onboarding, replacing the old slide gesture.
///
/// It shares [AppButton.height] with every other primary action (the Sign In /
/// Create Account buttons), so the flagship CTA and the auth CTAs read as one
/// component family: same height, same stadium shape, same teal fill, same
/// label type. What distinguishes it is the trailing mark — a pure-white disc
/// (deliberately contrasting the teal track) carrying the brand's upper-right
/// arrow, pinned to the right end of the button.
class ContinueButton extends StatelessWidget {
  const ContinueButton({
    super.key,
    required this.onPressed,
    this.label = 'Tap to Continue',
  });

  final VoidCallback onPressed;
  final String label;

  // Shares the app-wide primary action height (the Sign In button's height).
  static const double _height = AppButton.height;
  static const double _inset = 5;
  static const double _discSize = _height - _inset * 2;

  void _handleTap() {
    HapticFeedback.lightImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: _handleTap,
      pressScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: _height,
        width: double.infinity,
        decoration: ShapeDecoration(
          color: MedGuardPalette.teal,
          shape: const StadiumBorder(),
          shadows: [
            BoxShadow(
              color: MedGuardPalette.tealDeep.withValues(alpha: 0.28),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: MedGuardPalette.tealAlpha(0.20),
              blurRadius: 10,
              spreadRadius: -6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              style: GoogleFonts.inter(
                color: MedGuardPalette.pureWhite,
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            // The trailing arrow disc — white on teal for crisp contrast,
            // pinned to the right end of the track.
            Positioned(
              right: _inset,
              child: Container(
                width: _discSize,
                height: _discSize,
                alignment: Alignment.center,
                decoration: const ShapeDecoration(
                  color: MedGuardPalette.pureWhite,
                  shape: CircleBorder(),
                  shadows: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.north_east_rounded,
                  color: MedGuardPalette.teal,
                  size: _discSize * 0.44,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
