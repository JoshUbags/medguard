import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/pressable.dart';
import 'insights_content.dart';

/// The article reader.
///
/// A photograph that collapses into a pinned bar as you scroll, then a single
/// column of text at a genuinely readable measure. Nothing else — no related
/// rail, no share tray, no comment box. The one non-negotiable is the source
/// block at the foot: every claim on this page came from somewhere, and the
/// reader gets a link to check it.
class InsightsReaderScreen extends StatelessWidget {
  const InsightsReaderScreen({super.key, required this.article});

  final InsightArticle article;

  /// Copies the source link rather than launching a browser.
  ///
  /// Opening it in place would mean adding a URL-launcher dependency and a
  /// native plugin to every build, which is not a trade worth making for one
  /// link at the foot of an article. The clipboard gets the reader to the same
  /// place in one more tap, and the URL is printed on screen either way.
  Future<void> _copySource(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: article.sourceUrl));
    if (!context.mounted) return;
    HapticFeedback.selectionClick();
    AppSnack.success(context, 'Source link copied');
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final heroHeight = responsive.s(280).clamp(240.0, 340.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The hero is a dark photograph, so the status bar needs light icons
      // regardless of the app's theme.
      value: medGuardSystemUi(colors).copyWith(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        body: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              // Scrolls away with the article rather than pinning a bar over
              // it. A reader is the one screen where nothing should compete
              // with the text, and a strip of chrome that stays put takes a
              // slice of every screenful of a long read. Back remains
              // available through the system gesture, and returns with the
              // hero the moment the reader scrolls up.
              pinned: false,
              floating: true,
              expandedHeight: heroHeight,
              backgroundColor: colors.scaffold,
              surfaceTintColor: Colors.transparent,
              foregroundColor: colors.ink,
              leading: Padding(
                padding: EdgeInsets.all(responsive.s(8)),
                child: _RoundAction(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(article.image, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x8A05171A), Color(0x1A05171A)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: responsive.constrain(
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    responsive.pageX,
                    responsive.s(24),
                    responsive.pageX,
                    responsive.s(20) + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: responsive.s(9),
                              vertical: responsive.s(4),
                            ),
                            decoration: BoxDecoration(
                              color: article.accent.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: article.accent.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              article.category.toUpperCase(),
                              style: GoogleFonts.inter(
                                color: article.accent,
                                fontSize: responsive.font(9.4),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                height: 1.25,
                              ),
                            ),
                          ),
                          SizedBox(width: responsive.s(10)),
                          Text(
                            '${article.readMinutes} min read',
                            style: GoogleFonts.inter(
                              color: colors.inkMute,
                              fontSize: responsive.font(11.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.s(14)),
                      Text(
                        article.title,
                        style: GoogleFonts.inter(
                          color: colors.ink,
                          fontSize: responsive.font(26),
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: responsive.s(12)),
                      // The standfirst, set larger and lighter than the body so
                      // the piece opens rather than simply starting.
                      Text(
                        article.dek,
                        style: GoogleFonts.inter(
                          color: colors.inkSoft,
                          fontSize: responsive.font(15),
                          fontWeight: FontWeight.w500,
                          height: 1.55,
                        ),
                      ),
                      SizedBox(height: responsive.s(20)),
                      Divider(color: colors.border, height: 1),
                      SizedBox(height: responsive.s(22)),
                      for (var i = 0; i < article.body.length; i++) ...[
                        // The opening paragraph takes a drop cap — the oldest
                        // signal in typesetting that a piece has begun, and
                        // the single cheapest thing that makes a screen of
                        // body text read as an article rather than a
                        // description field.
                        if (i == 0)
                          _OpeningParagraph(
                            text: article.body[i],
                            accent: article.accent,
                          )
                        else
                          Text(
                            article.body[i],
                            style: GoogleFonts.inter(
                              color: colors.ink,
                              fontSize: responsive.font(14.6),
                              fontWeight: FontWeight.w400,
                              // A tall measure: this is long-form reading, not
                              // interface copy.
                              height: 1.72,
                            ),
                          ),
                        SizedBox(height: responsive.s(18)),
                        // A pull quote lifted from the piece, set after the
                        // second paragraph so it breaks the column at roughly
                        // the point attention starts to drift.
                        if (i == 1 && article.body.length > 3) ...[
                          _PullQuote(
                            text: article.dek,
                            accent: article.accent,
                          ),
                          SizedBox(height: responsive.s(20)),
                        ],
                      ],
                      SizedBox(height: responsive.s(6)),
                      _SourceBlock(
                        article: article,
                        onCopy: () => _copySource(context),
                      ),
                      SizedBox(height: responsive.s(16)),
                      _ReaderDisclaimer(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first paragraph, with its opening letter set as a drop cap.
///
/// Built as an inline [WidgetSpan] rather than a floated box, so the remaining
/// lines wrap under the cap exactly as they would in print instead of being
/// pushed into a narrow column beside it.
class _OpeningParagraph extends StatelessWidget {
  const _OpeningParagraph({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final body = GoogleFonts.inter(
      color: colors.ink,
      fontSize: responsive.font(14.6),
      fontWeight: FontWeight.w400,
      height: 1.72,
    );

    if (text.isEmpty) return Text(text, style: body);
    final cap = text.characters.first;
    final rest = text.characters.skip(1).toString();

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: EdgeInsets.only(right: responsive.s(3)),
              child: Text(
                cap,
                style: GoogleFonts.inter(
                  color: accent,
                  // Roughly three lines tall, the classic proportion.
                  fontSize: responsive.font(40),
                  fontWeight: FontWeight.w800,
                  height: 0.92,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),
          TextSpan(text: rest),
        ],
      ),
      style: body,
    );
  }
}

/// A line lifted out of the piece and set large — the break that stops a long
/// column reading as an unbroken wall.
///
/// Set on its own tinted panel with a quote glyph, rather than behind a
/// coloured bar down its left edge. A left rule is a blockquote convention
/// borrowed from the web; on a phone, at this width, it reads as a status
/// stripe — the same shape the app uses for alerts — which gives an ordinary
/// pulled sentence the weight of a warning.
class _PullQuote extends StatelessWidget {
  const _PullQuote({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Container(
      padding: EdgeInsets.fromLTRB(
        responsive.s(18),
        responsive.s(16),
        responsive.s(18),
        responsive.s(18),
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: colors.isDark ? 0.10 : 0.05),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: responsive.icon(22),
            color: accent.withValues(alpha: 0.55),
          ),
          SizedBox(height: responsive.s(6)),
          Text(
            text,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(17),
              fontWeight: FontWeight.w600,
              height: 1.45,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The attribution: who said it, and a way to go and read the original.
class _SourceBlock extends StatelessWidget {
  const _SourceBlock({required this.article, required this.onCopy});

  final InsightArticle article;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: onCopy,
      pressScale: 0.985,
      semanticLabel: 'Copy the source link: ${article.sourceName}',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(responsive.s(15).clamp(14.0, 18.0)),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(responsive.radius(18)),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_rounded,
              color: colors.accent,
              size: responsive.icon(19),
            ),
            SizedBox(width: responsive.s(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SOURCE',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(9.6),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      height: 1,
                    ),
                  ),
                  SizedBox(height: responsive.s(6)),
                  Text(
                    article.sourceName,
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(13.2),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: responsive.s(4)),
                  // The URL is printed, not just linked, so the attribution
                  // still means something if the copy action is never used.
                  Text(
                    article.sourceUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(10.8),
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.s(8)),
            Icon(
              Icons.copy_rounded,
              color: colors.inkMute,
              size: responsive.icon(17),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line that keeps this an information page rather than advice. Short, and
/// present on every article.
class _ReaderDisclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Text(
      'General information, not medical advice. Decisions about your own '
      'medicines belong with your doctor or pharmacist.',
      style: GoogleFonts.inter(
        color: colors.inkMute,
        fontSize: responsive.font(11.6),
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
    );
  }
}

/// A round control that stays legible over the hero photograph.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Pressable(
      onTap: onTap,
      pressScale: 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MedGuardPalette.blackAlpha(0.42),
          border: Border.all(color: MedGuardPalette.whiteAlpha(0.24)),
        ),
        child: Icon(
          icon,
          color: MedGuardPalette.pureWhite,
          size: responsive.icon(19),
        ),
      ),
    );
  }
}
