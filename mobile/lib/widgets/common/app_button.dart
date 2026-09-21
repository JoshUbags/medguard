import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import 'morph_loader.dart';
import 'pressable.dart';

/// The visual style of an [AppButton].
enum AppButtonVariant {
  /// Solid teal fill with white label — the page's main action.
  primary,

  /// White fill with a thin teal outline and teal label — secondary action.
  secondary,

  /// Faint teal-tinted fill with a soft teal outline and teal label — a quieter
  /// action that still reads as on-brand (used inside cards / tinted surfaces).
  tonal,

  /// Solid ruby fill with a white label — for the one action on a screen that
  /// destroys something. Deliberately the same SHAPE as [primary]: a
  /// destructive action should be as easy to hit accurately as any other, it
  /// just needs to be impossible to mistake for a safe one.
  danger,
}

/// The single, shared pill button used for every filled / outlined / tonal
/// call-to-action across the app (welcome, onboarding, auth, home, and every
/// other page). One component, three variants, ONE standard height — so every
/// action looks and behaves the same everywhere: same shape, radius, icon size,
/// icon placement, text size, weight, and padding.
///
/// Text-only actions (no fill, no outline — e.g. "Skip", "Back", inline links)
/// intentionally do NOT use this widget and keep their bare-text styling.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final bool loading;

  /// Stretch to fill the available width (default). When false the button hugs
  /// its label, for inline / side-by-side placement.
  final bool expand;
  final IconData? icon;

  /// The one standard button height used everywhere in the app.
  static const double height = 48;

  // The single, shared spec — identical for every button in the app.
  static const double _fontSize = 13.2;
  static const double _iconSize = 18;
  static const double _spinnerSize = 20;
  static const double _hugPadding = 28;
  static const double _iconGap = 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPrimary = variant == AppButtonVariant.primary;
    final isDanger = variant == AppButtonVariant.danger;
    final isTonal = variant == AppButtonVariant.tonal;
    final isFilled = isPrimary || isDanger;
    final disabled = onTap == null || loading;

    // Filled buttons keep the BRAND colour in both themes — a teal primary is
    // teal at night too. Outlined and tonal ones take the theme-resolved accent,
    // because those read as text on the page and must clear contrast against a
    // dark surface.
    final foreground = isFilled ? MedGuardPalette.pureWhite : colors.accent;

    final Color fill = isDanger
        ? MedGuardPalette.ruby
        : isPrimary
        ? MedGuardPalette.teal
        : isTonal
        ? colors.accentAlpha(0.10)
        : colors.surface;
    final BorderSide side = isFilled
        ? BorderSide.none
        : BorderSide(color: colors.accentAlpha(isTonal ? 0.22 : 0.28));

    final content = loading
        ? SizedBox(
            width: _spinnerSize,
            height: _spinnerSize,
            // The app's own loading mark, so a button that is working looks
            // like every other part of the app that is working.
            child: Center(
              child: MorphLoader(
                size: _spinnerSize,
                color: foreground,
                glow: false,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: _iconSize, color: foreground),
                const SizedBox(width: _iconGap),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: foreground,
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );

    return Pressable(
      onTap: disabled ? null : onTap,
      disabled: disabled,
      semanticLabel: loading ? '$label, loading' : label,
      child: Opacity(
        opacity: disabled && !loading ? 0.55 : 1,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: expand
              ? null
              : const EdgeInsets.symmetric(horizontal: _hugPadding),
          decoration: ShapeDecoration(
            color: fill,
            shape: StadiumBorder(side: side),
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}
