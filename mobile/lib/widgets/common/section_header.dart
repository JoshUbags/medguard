import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';

/// THE section heading used down every feed in the app: a title, a trailing
/// status/action pill on the same line, and an optional one-line subtitle
/// beneath.
///
/// This is Home's heading, lifted out so the other feeds are literally the same
/// object rather than a lookalike. Insights and Dose each used to re-type their
/// own — a newspaper rule on one, an all-caps label on the other — which is
/// precisely why those pages read as different products from the same app. Type
/// scale, weights, the pill's two states and the gap to the subtitle all live
/// here, so a change to the app's section rhythm happens in one place.
///
/// The title is deliberately SMALLER than a page title ([kPageTitleSize]): the
/// content leads each block, not the label on top of it.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.subtitle,
    this.onAction,
    this.trailing,
  });

  final String title;

  /// The trailing pill's text — a quiet status when [onAction] is null, a
  /// tappable teal affordance ("See all") when it isn't. Null (with no
  /// [trailing]) leaves the title alone on its line.
  final String? action;

  final String? subtitle;

  /// When provided, the trailing [action] becomes a tappable teal affordance
  /// (e.g. "See all"); otherwise it reads as a quiet status label.
  final VoidCallback? onAction;

  /// A bespoke trailing control, used instead of the [action] pill when a
  /// section needs something richer than a label — the Dose page's streak chip
  /// or its "mark all taken" button. Takes precedence over [action].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final chipPad = EdgeInsets.symmetric(
      horizontal: responsive.s(10).clamp(9.0, 12.0).toDouble(),
      vertical: responsive.s(5).clamp(4.0, 7.0).toDouble(),
    );
    final chipText = GoogleFonts.inter(
      fontSize: responsive.font(11.5),
      fontWeight: FontWeight.w700,
      height: 1.0,
      letterSpacing: 0.2,
    );

    // The trailing label reads as a tidy pill on every section: a quiet neutral
    // tag for a status, or a faint teal pill with a chevron when it's tappable.
    // A bespoke [trailing] control wins over both.
    final label = action;
    final Widget? actionWidget =
        trailing ??
        (label == null
            ? null
            : onAction == null
            ? Container(
                padding: chipPad,
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: chipText.copyWith(color: colors.inkMute),
                ),
              )
            : Pressable(
                onTap: onAction,
                pressScale: 0.96,
                semanticLabel: label,
                child: Container(
                  padding: chipPad,
                  decoration: BoxDecoration(
                    color: colors.accentAlpha(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: chipText.copyWith(color: colors.accent),
                      ),
                      SizedBox(width: responsive.s(3)),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.accent,
                        size: responsive.icon(12),
                      ),
                    ],
                  ),
                ),
              ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: colors.ink,
                  fontSize: responsive.font(16.5),
                  fontWeight: FontWeight.w600,
                  height: 1.12,
                  letterSpacing: -0.25,
                ),
              ),
            ),
            ?actionWidget,
          ],
        ),
        if (subtitle != null) ...[
          SizedBox(height: responsive.s(6).clamp(5.0, 8.0).toDouble()),
          Text(
            subtitle!,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.6),
              fontWeight: FontWeight.w500,
              height: 1.32,
            ),
          ),
        ],
      ],
    );
  }
}

/// The standard gap between a [SectionHeader] and the block it introduces.
double sectionHeaderGap(MedGuardResponsive responsive) =>
    responsive.s(14).clamp(12.0, 16.0).toDouble();
