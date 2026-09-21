import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';

class TopTextNavigationAction extends StatelessWidget {
  const TopTextNavigationAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconAfterLabel = false,
    this.color,
    this.fontSize = 13.2,
    this.fontWeight = FontWeight.w600,
    this.iconSize = 18,
    this.iconQuarterTurns = 0,
    this.semanticLabel,
    this.edgeAligned = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool iconAfterLabel;

  /// Icon + label colour. Defaults to the theme's primary ink when omitted, so
  /// the control stays legible in both light and dark.
  final Color? color;
  final double fontSize;
  final FontWeight fontWeight;
  final double iconSize;
  final int iconQuarterTurns;
  final String? semanticLabel;

  /// When true the leading icon hugs the start edge (no left padding), so the
  /// control lines up with the body content beneath it instead of sitting a
  /// few pixels inset. The tap target keeps its vertical padding.
  final bool edgeAligned;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.colors.ink;
    final rawIcon = Icon(icon, color: effectiveColor, size: iconSize);
    final iconWidget = iconQuarterTurns == 0
        ? rawIcon
        : RotatedBox(quarterTurns: iconQuarterTurns, child: rawIcon);
    final labelWidget = Text(
      label,
      style: GoogleFonts.inter(
        color: effectiveColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.18,
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: ConstrainedBox(
          // Apple's 44pt minimum touch target: the label may be small, but
          // the tappable area never is — taps register reliably.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: edgeAligned
                ? const EdgeInsets.fromLTRB(0, 9, 12, 9)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: iconAfterLabel
                  ? [labelWidget, const SizedBox(width: 5), iconWidget]
                  : [iconWidget, const SizedBox(width: 5), labelWidget],
            ),
          ),
        ),
      ),
    );
  }
}
