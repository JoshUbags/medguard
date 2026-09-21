import 'package:flutter/material.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_shadows.dart';
import 'pressable.dart';
import 'section_header.dart';

/// THE card surface. One radius, one border, one shadow, everywhere.
///
/// Screens used to each declare their own `Container(decoration: BoxDecoration(
/// … ))` and had drifted to five different corner radii and three different
/// shadows, which is the single biggest reason the app read as assembled from
/// parts. Anything raised off the canvas is this widget.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.radius = 22,
    this.tinted = false,
    this.accent,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Raw (pre-scale) corner radius. The default is the app's card radius; only
  /// override it for a genuinely different class of object (a compact chip, a
  /// full-bleed hero).
  final double radius;

  /// Fills with [MedGuardColors.surfaceAlt] instead of the surface colour —
  /// for a card nested INSIDE another card, where the same fill twice over
  /// would make the nesting invisible.
  final bool tinted;

  /// Tints the border and fill toward a status colour (danger, warning, accent)
  /// so a card can carry meaning without being shouted in colour.
  final Color? accent;

  /// Set false for a card sitting on an already-raised surface, where a second
  /// shadow reads as grime rather than as elevation.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final r = BorderRadius.circular(responsive.radius(radius));
    final tone = accent;

    final card = Container(
      padding: padding ?? EdgeInsets.all(responsive.s(16)),
      decoration: BoxDecoration(
        color: tone != null
            ? Color.alphaBlend(
                tone.withValues(alpha: colors.isDark ? 0.10 : 0.05),
                tinted ? colors.surfaceAlt : colors.surface,
              )
            : (tinted ? colors.surfaceAlt : colors.surface),
        borderRadius: r,
        border: Border.all(
          color: tone != null ? tone.withValues(alpha: 0.22) : colors.border,
        ),
        boxShadow: elevated ? MedGuardShadows.card : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Pressable(onTap: onTap, pressScale: 0.985, child: card);
  }
}

/// THE page section: a [SectionHeader] standing on the canvas, and the content
/// beneath it inside a [SurfaceCard].
///
/// This is the app's layout grammar, made explicit. The heading and its caption
/// live OUTSIDE the box; only the content goes in it. Sections that put their
/// own title inside the card are what made several pages read as a stack of
/// unrelated panels — there was no consistent line for the eye to follow down
/// the page.
///
/// Pass [child] for the common case. Pass [children] to get several cards under
/// one heading, evenly spaced.
class SectionBlock extends StatelessWidget {
  const SectionBlock({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.trailing,
    this.child,
    this.children,
    this.padding,
    this.card = true,
  }) : assert(
         child != null || children != null,
         'A section needs either a child or children.',
       );

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  final Widget? child;
  final List<Widget>? children;

  /// Padding inside the card. Ignored when [card] is false.
  final EdgeInsetsGeometry? padding;

  /// Set false when the content brings its own surfaces (a list of cards, a
  /// horizontal carousel) and wrapping it in one more box would be a box
  /// inside a box.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final items = children ?? <Widget>[child!];

    // A section's card always spans the page. Without the explicit width the
    // card hugged its content, so a section of chips drew a box a third
    // narrower than every other card on the page.
    Widget wrap(Widget content) => card
        ? SizedBox(
            width: double.infinity,
            child: SurfaceCard(padding: padding, child: content),
          )
        : content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          action: action,
          onAction: onAction,
          trailing: trailing,
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: responsive.s(12)),
          wrap(items[i]),
        ],
      ],
    );
  }
}

/// The standard gap between two [SectionBlock]s down a page. Bigger than the
/// gap between cards inside one section, so the page groups visually before it
/// lists.
double sectionGap(MedGuardResponsive responsive) =>
    responsive.s(28).clamp(24.0, 34.0).toDouble();

/// A hairline divider between rows inside a card, inset so it never touches the
/// card's rounded edge.
class CardDivider extends StatelessWidget {
  const CardDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        indent,
        responsive.s(10),
        0,
        responsive.s(10),
      ),
      child: Container(height: 1, color: context.colors.border),
    );
  }
}
