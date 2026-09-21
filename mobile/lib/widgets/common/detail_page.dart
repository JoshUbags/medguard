import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../utils/keyboard.dart';
import 'page_background.dart';
import 'page_header.dart';
import 'pressable.dart';

/// THE chrome for every routed screen that is not one of the five tabs.
///
/// Search, the legal documents, allergies, foods, settings, profile,
/// notifications, check history, the drug monograph and the safety report are
/// all this widget. Consistency here is not a nicety: a back button that moves
/// between screens is the kind of thing users feel as sloppiness without being
/// able to name it.
///
/// The layout is deliberately plain — a back control, a large title with any
/// actions on its trailing edge, an optional subtitle, then content — and it
/// all scrolls together.
///
/// There is no pinned bar and no title that migrates into one. That is a
/// deliberate reversal: this used to carry a frosted bar that faded in as the
/// large title scrolled away, which is a fine pattern and the wrong one here.
/// It gave routed pages a piece of chrome no primary tab has, so moving from
/// Home into Settings changed the shape of the app. A header that simply
/// scrolls away reads as the same surface as everything else, and the back
/// gesture stays available regardless of scroll position.
class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leadingActions = const [],
    this.slivers,
    this.child,
    this.floatingAction,
    this.onBack,
    this.onRefresh,
    this.bottomInset = 28,
    this.scrollController,
    this.showBack = true,
    this.dismissKeyboardOnDrag = false,
  }) : assert(
         slivers != null || child != null,
         'A DetailPage needs either slivers or a child.',
       );

  final String title;
  final String? subtitle;

  /// Controls on the title's trailing edge. Build them with [DetailPageAction]
  /// so they share one shape and hit target.
  final List<Widget> actions;

  /// Controls beside the back button, on the leading edge — for an action that
  /// belongs to the page as a whole rather than to its content (Profile's
  /// settings gear).
  final List<Widget> leadingActions;

  /// Page content as slivers, for long or lazily-built pages.
  final List<Widget>? slivers;

  /// Page content as a single box, for short pages. Wrapped in page padding
  /// and the tablet width constraint automatically.
  final Widget? child;

  final Widget? floatingAction;

  /// Overrides the back control's action. Defaults to popping the route.
  final VoidCallback? onBack;

  /// Adds pull-to-refresh when the page has something to re-fetch.
  final Future<void> Function()? onRefresh;

  /// Space kept below the last element.
  final double bottomInset;

  final ScrollController? scrollController;

  /// Set false for a page that cannot be backed out of.
  final bool showBack;

  /// Ends text entry when the user starts dragging the page.
  ///
  /// Off by default because most routed pages have no text field and the
  /// behaviour would be invisible. Turn it on for one that does (Search), so
  /// its results are not read through a half-screen keyboard.
  final bool dismissKeyboardOnDrag;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final hasTopRow = showBack || leadingActions.isNotEmpty;

    final content = <Widget>[
      SliverToBoxAdapter(
        child: responsive.constrain(
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.pageX,
              MedGuardSpacing.screenTop(responsive),
              responsive.pageX,
              responsive.s(subtitle == null ? 18 : 20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTopRow) ...[
                  Row(
                    children: [
                      if (showBack)
                        _BackControl(
                          onTap:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        ),
                      const Spacer(),
                      for (final action in leadingActions) ...[
                        SizedBox(width: responsive.s(8)),
                        action,
                      ],
                    ],
                  ),
                  SizedBox(height: responsive.s(18)),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: pageTitleStyle(responsive, colors.ink),
                          ),
                          if (subtitle != null) ...[
                            SizedBox(height: responsive.s(6)),
                            Text(
                              subtitle!,
                              style: pageSubtitleStyle(
                                responsive,
                                colors.inkSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    for (final action in actions) ...[
                      SizedBox(width: responsive.s(10)),
                      action,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      if (slivers != null)
        ...slivers!
      else
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: child,
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: SizedBox(
          // Trimmed to match every other screen's trailing space — see
          // `_endInsetHalving` in floating_nav_bar.dart.
          height:
              (responsive.s(bottomInset) +
                  MediaQuery.paddingOf(context).bottom) *
              0.68,
        ),
      ),
    ];

    Widget scroll = CustomScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      keyboardDismissBehavior: dismissKeyboardOnDrag
          ? kDismissKeyboardOnDrag
          : ScrollViewKeyboardDismissBehavior.manual,
      slivers: content,
    );

    if (onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: onRefresh!,
        color: colors.accent,
        backgroundColor: colors.surface,
        child: scroll,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(colors),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        floatingActionButton: floatingAction,
        // The same ambient canvas every tab carries, so a routed page is not a
        // flat white sheet dropped on top of a textured app.
        body: PageBackground(child: SafeArea(bottom: false, child: scroll)),
      ),
    );
  }
}

/// The back affordance: a compact labelled pill above the title.
///
/// A pill rather than a bare chevron because it has to survive on a page whose
/// first content might be anything — a photograph, a coloured card, a dense
/// table — and an unbacked glyph disappears against half of those. The word
/// "Back" costs almost nothing here and removes any doubt about what it does.
class _BackControl extends StatelessWidget {
  const _BackControl({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      key: const ValueKey('detail-back'),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      pressScale: 0.94,
      semanticLabel: 'Back',
      child: Container(
        padding: EdgeInsets.fromLTRB(
          responsive.s(9),
          responsive.s(7),
          responsive.s(13),
          responsive.s(7),
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back_rounded,
              size: responsive.icon(15),
              color: colors.ink,
            ),
            SizedBox(width: responsive.s(6)),
            Text(
              'Back',
              style: GoogleFonts.inter(
                color: colors.ink,
                fontSize: responsive.font(12.6),
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page action — the same tinted pill the notifications page uses for
/// "Mark read", so every routed page's action reads as one control type.
class DetailPageAction extends StatelessWidget {
  const DetailPageAction({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.label,
    this.tint,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Shown beside the glyph. Strongly preferred: a labelled control is
  /// unambiguous, and there is room for one beside a page title.
  final String? label;

  /// Colours the control — for a destructive or emphasised action.
  final Color? tint;

  /// A small dot on the corner, for an action with something waiting behind it.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final tone = tint ?? colors.accent;
    final text = label;

    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      pressScale: 0.94,
      semanticLabel: semanticLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(text == null ? 10 : 12),
              vertical: responsive.s(8),
            ),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: tone, size: responsive.icon(15)),
                if (text != null) ...[
                  SizedBox(width: responsive.s(6)),
                  Text(
                    text,
                    style: GoogleFonts.inter(
                      color: tone,
                      fontSize: responsive.font(12),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (badge)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: responsive.s(8),
                height: responsive.s(8),
                decoration: BoxDecoration(
                  color: colors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.scaffold, width: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
