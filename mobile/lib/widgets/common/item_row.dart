import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';
import 'surface_card.dart';

/// One record in a list the user curates — an allergy, a food, a care profile —
/// as a card of its own: a tinted glyph, a label, an optional detail line and
/// a single trailing control.
///
/// Allergies, foods and care profiles each used to build this row by hand, at
/// three radii, two glyph shapes and two title weights, with a Material
/// [IconButton] on one screen and a bordered disc on another. They are the same
/// object, so they are now the same widget — and they share the card material,
/// type scale and glyph shape of a [SettingsRow].
class ItemRowCard extends StatelessWidget {
  const ItemRowCard({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.tint,
    this.trailing,
    this.onTap,
    this.accent,
  }) : assert(icon != null || leading != null);

  final String title;
  final String? subtitle;

  /// The glyph, drawn in an [ItemGlyph]. Ignored when [leading] is given.
  final IconData? icon;

  /// A bespoke leading element (an initial, an avatar) in place of the glyph.
  final Widget? leading;

  /// Colours the glyph. Defaults to the accent.
  final Color? tint;

  final Widget? trailing;
  final VoidCallback? onTap;

  /// Tints the whole card toward a status colour — the selected row.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final text = subtitle;

    return SurfaceCard(
      onTap: onTap,
      accent: accent,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(16),
        vertical: responsive.s(14),
      ),
      child: Row(
        children: [
          leading ?? ItemGlyph(icon: icon!, tint: tint ?? colors.accent),
          SizedBox(width: responsive.s(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.2),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (text != null) ...[
                  SizedBox(height: responsive.s(3)),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12.2),
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: responsive.s(10)),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The rounded-square glyph plate used by list rows — the same shape and tint
/// strength as a [SettingsRow]'s icon, one step larger because it heads a whole
/// card rather than a line inside one.
class ItemGlyph extends StatelessWidget {
  const ItemGlyph({super.key, required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final extent = responsive.s(42).clamp(38.0, 50.0).toDouble();

    return Container(
      width: extent,
      height: extent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: Icon(icon, color: tint, size: responsive.icon(20)),
    );
  }
}

/// The one way to add to a curated list, sitting at the foot of the list it
/// adds to — a tinted, unelevated card so it reads as a slot waiting to be
/// filled rather than as another record.
class ItemAddTile extends StatelessWidget {
  const ItemAddTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Semantics(
      button: true,
      label: title,
      child: SurfaceCard(
        onTap: onTap,
        elevated: false,
        tinted: true,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(16),
          vertical: responsive.s(14),
        ),
        child: Row(
          children: [
            ItemGlyph(icon: icon, tint: colors.accent),
            SizedBox(width: responsive.s(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: colors.accent,
                      fontSize: responsive.font(14.2),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(3)),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12.2),
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.s(10)),
            Icon(
              Icons.add_rounded,
              color: colors.accent,
              size: responsive.icon(20),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row-level remove control: a quiet bordered disc with a cross.
///
/// Deliberately quiet. Removing one entry is not the page's main action, and a
/// red bin on every row turned a calm list into a column of warnings.
class RowRemoveButton extends StatelessWidget {
  const RowRemoveButton({super.key, required this.label, required this.onTap});

  /// What is removed — read to screen readers as "Remove [label]".
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final extent = responsive.s(34).clamp(32.0, 40.0).toDouble();

    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      pressScale: 0.9,
      semanticLabel: 'Remove $label',
      child: Container(
        width: extent,
        height: extent,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: Icon(
          Icons.close_rounded,
          size: responsive.icon(16),
          color: colors.inkMute,
        ),
      ),
    );
  }
}

/// The panel revealed behind an [ItemRowCard] as it is swiped away — the card's
/// exact shape, so the row appears to slide off its own red silhouette.
class ItemSwipeBackground extends StatelessWidget {
  const ItemSwipeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.symmetric(horizontal: responsive.s(22)),
      decoration: BoxDecoration(
        color: MedGuardPalette.ruby,
        borderRadius: BorderRadius.circular(responsive.radius(22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Remove',
            style: GoogleFonts.inter(
              color: MedGuardPalette.pureWhite,
              fontSize: responsive.font(13),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: responsive.s(8)),
          Icon(
            Icons.delete_rounded,
            color: MedGuardPalette.pureWhite,
            size: responsive.icon(20),
          ),
        ],
      ),
    );
  }
}
