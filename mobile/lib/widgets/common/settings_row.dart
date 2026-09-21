import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';
import 'surface_card.dart';

/// A group of settings rows inside one card, divided by hairlines.
///
/// Rows go in a card and the group's heading stays outside it, which is the
/// app's section grammar (see [SectionBlock]). Grouping matters here beyond
/// looks: a settings list with no grouping is just a wall of switches, and the
/// user has to read every label to find the one they want.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(14),
        vertical: responsive.s(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              // Indented past the icon so the divider separates the LABELS,
              // which is what the eye is scanning down.
              CardDivider(indent: responsive.s(46)),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// A settings row that opens something — another screen, a picker, a sheet.
///
/// [value] shows the current setting on the right. This is the detail that
/// makes a settings list usable: without it the user must open each row to find
/// out what it is set to.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
    this.value,
    this.tint,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The current setting, shown right-aligned before the chevron.
  final String? value;

  /// Null for a row that only states a fact — it then carries no chevron,
  /// because a chevron promises somewhere to go.
  final VoidCallback? onTap;

  /// Colours the icon disc. Defaults to the accent.
  final Color? tint;

  /// Paints the label and icon in the danger colour — for rows that destroy
  /// data. There is at most one of these per group, by convention.
  final bool destructive;

  /// Replaces the chevron entirely (a switch, a badge).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final accent = destructive ? colors.danger : (tint ?? colors.accent);

    final tap = onTap;

    return Pressable(
      onTap: tap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              tap();
            },
      pressScale: tap == null ? 1 : 0.985,
      semanticLabel: title,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: responsive.s(11)),
        child: Row(
          children: [
            _RowIcon(icon: icon, tint: accent),
            SizedBox(width: responsive.s(13)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: destructive ? colors.danger : colors.ink,
                      fontSize: responsive.font(14),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: responsive.s(2)),
                    Text(
                      subtitle!,
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
            ] else ...[
              if (value != null) ...[
                SizedBox(width: responsive.s(12)),
                // Bounded, NOT flexible. A `Flexible` here competed with the
                // label's `Expanded` for the row's free space: each was offered
                // half, the short value used a fraction of its half, and the
                // leftover was parked after the chevron — which is why "Off"
                // and its chevron floated in from the right margin instead of
                // sitting on it. With one flex child the label absorbs
                // everything spare and the value lands hard against the edge.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: responsive.s(120)),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      color: colors.inkSoft,
                      fontSize: responsive.font(12.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (tap != null) ...[
                SizedBox(width: responsive.s(4)),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.inkMute,
                  size: responsive.icon(20),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A settings row carrying a switch. Tapping anywhere on the row toggles it —
/// aiming for a small switch is a needless precision task.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// A row that is present but currently inapplicable — greyed, not hidden, so
  /// the user can see the setting exists and work out why it is unavailable.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Pressable(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged(!value);
              }
            : null,
        disabled: !enabled,
        pressScale: 0.985,
        semanticLabel: title,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.s(7)),
          child: Row(
            children: [
              _RowIcon(icon: icon, tint: colors.accent),
              SizedBox(width: responsive.s(13)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(14),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: responsive.s(2)),
                      Text(
                        subtitle!,
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
              SizedBox(width: responsive.s(8)),
              // Absorbs its own taps so dragging the switch still works, while
              // the row-wide tap above handles everything else.
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeTrackColor: colors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final size = responsive.s(34);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(responsive.radius(11)),
      ),
      child: Icon(icon, color: tint, size: responsive.icon(18)),
    );
  }
}
