import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../widgets/common/floating_nav_bar.dart';
import '../../theme/medguard_shadows.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/section_header.dart';
import '../profile/profile_screen.dart';
import 'insights_content.dart';
import 'insights_reader.dart';
import '../../widgets/common/page_background.dart';

/// The Insights tab — a small, curated medication-safety publication, laid out
/// in the app's own structure rather than in a newspaper's.
///
/// It is built exactly like Home: the shared [PageHeader], then a column of
/// titled sections separated by one [MedGuardSpacing.sectionDivider] beat each,
/// every section introduced by the shared [SectionHeader] (title, status pill,
/// one-line subtitle) and followed by its content. The page used to open with a
/// printed masthead and divide itself with all-caps rules — a second design
/// language that made this tab read as a different product from the rest of the
/// app. Nothing here is bespoke chrome any more; only the *content* of each
/// section is particular to Insights.
///
/// Six sections, in reading order: the lead story, the figures behind it, the
/// briefing, a quiz to check what stuck, the remaining pieces, and the fact of
/// the day — so a long scroll has a rhythm rather than being seven cards in a
/// row.
///
/// Everything is bundled — copy, images, sources — so the page renders instantly
/// and works with no connection. Each piece names the body it came from (FDA,
/// WHO, NHS, peer-reviewed literature) and links out, because unattributed
/// health copy is not worth publishing.
/// Questions asked per sitting — mirrors `_QuizCardState._roundLength`, which
/// is what the header and the masthead figure advertise.
const int _quizRoundLength = 3;

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({
    super.key,
    this.showNavigation = true,
    this.bottomContentPadding = 0,
    this.onOpenProfile,
  });

  static const String routeName = '/insights';

  final bool showNavigation;
  final double bottomContentPadding;

  /// Opens the profile screen from the header avatar.
  final VoidCallback? onOpenProfile;

  void _openProfile(BuildContext context) {
    final handler = onOpenProfile;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).pushNamed(ProfileScreen.routeName);
  }

  void _open(BuildContext context, InsightArticle article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InsightsReaderScreen(article: article),
      ),
    );
  }

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// The current edition, e.g. "July 2026" — the one editorial signal kept from
  /// the old masthead, now carried by the lead section's status pill instead of
  /// by a printed rule at the top of the page.
  static String _edition() {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // The app's ONE section beat — the same divider Home puts between its
    // blocks, so the two feeds scroll at the same rhythm.
    final sectionGap = MedGuardSpacing.sectionDivider(responsive);
    final headerGap = sectionHeaderGap(responsive);
    // The even beat between cards INSIDE a section, always tighter than the
    // gap between sections so the grouping is legible without a rule.
    final cardGap = responsive.s(12).clamp(10.0, 14.0).toDouble();

    final lead = kInsightArticles.first;
    final rest = kInsightArticles.skip(1).toList(growable: false);
    // The feed breaks after the third follow-up so the quiz lands mid-scroll
    // rather than stranded at the bottom where nobody reaches it.
    const breakAfter = 3;
    final briefing = rest.take(breakAfter).toList(growable: false);
    final alsoWorth = rest.skip(breakAfter).toList(growable: false);

    // One story per card, laid out as a wide picture card at the head of a run
    // and compact rows beneath it. A feed of identical cards is what makes a
    // page feel generated; alternating twice is what stops it.
    List<Widget> feed(List<InsightArticle> run, int startIndex) => [
      for (var i = 0; i < run.length; i++) ...[
        if (i != 0) SizedBox(height: cardGap),
        if (i == 0)
          _FeatureCard(
            article: run[i],
            index: startIndex + i,
            onTap: () => _open(context, run[i]),
          )
        else
          _StoryRow(
            article: run[i],
            index: startIndex + i,
            onTap: () => _open(context, run[i]),
          ),
      ],
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(colors),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        // The ambient canvas sits BEHIND the whole scroll rather than being a
        // banner at the top, so the colour is a property of the page instead of
        // a decoration on it. This was the fix for the page reading as "white":
        // every card here is legitimately a white surface, and the problem was
        // never the cards — it was that they sat on a canvas the same colour as
        // themselves, so nothing had edges and the whole page went flat.
        body: PageBackground(
          child: SafeArea(
            bottom: false,
            child: responsive.constrain(
              ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                responsive.pageX,
                MedGuardSpacing.screenTop(responsive),
                responsive.pageX,
                0,
              ),
              children: [
                // The same header component every other primary tab uses, so
                // the avatar lands on the identical pixel across the app.
                PageHeader(
                  title: 'Insights',
                  subtitle: 'Medication safety, worth five minutes.',
                  onOpenProfile: () => _openProfile(context),
                ),

                // ── The masthead ─────────────────────────────────────────
                SizedBox(height: responsive.s(20)),
                _EditionMasthead(
                  edition: _edition(),
                  storyCount: kInsightArticles.length,
                  minutes: kInsightArticles.fold<int>(
                    0,
                    (sum, a) => sum + a.readMinutes,
                  ),
                ),

                // ── The lead ─────────────────────────────────────────────
                SizedBox(height: sectionGap),
                SectionHeader(
                  title: 'This edition',
                  action: _edition(),
                  subtitle: 'The story worth reading first.',
                ),
                SizedBox(height: headerGap),
                _LeadStory(article: lead, onTap: () => _open(context, lead)),

                // ── By the numbers ───────────────────────────────────────
                SizedBox(height: sectionGap),
                const SectionHeader(
                  title: 'By the numbers',
                  action: 'Sourced',
                  subtitle: 'Figures each body will stand behind.',
                ),
                SizedBox(height: headerGap),
                const _FigureStrip(),

                // ── The briefing ─────────────────────────────────────────
                SizedBox(height: sectionGap),
                SectionHeader(
                  title: 'The briefing',
                  action: '${briefing.length} reads',
                  subtitle: 'Short pieces on the risks that come up most.',
                ),
                SizedBox(height: headerGap),
                ...feed(briefing, 2),

                // ── Quick check ──────────────────────────────────────────
                SizedBox(height: sectionGap),
                const SectionHeader(
                  title: 'Quick check',
                  action: '$_quizRoundLength questions',
                  subtitle: 'Every answer explains itself, right or wrong.',
                ),
                SizedBox(height: headerGap),
                const _QuizCard(),

                // ── Also worth knowing ───────────────────────────────────
                SizedBox(height: sectionGap),
                SectionHeader(
                  title: 'Also worth knowing',
                  action: '${alsoWorth.length} reads',
                  subtitle: 'The rest of this edition, in brief.',
                ),
                SizedBox(height: headerGap),
                ...feed(alsoWorth, 2 + briefing.length),

                // ── Fact of the day ──────────────────────────────────────
                SizedBox(height: sectionGap),
                const SectionHeader(
                  title: 'Did you know',
                  action: 'Daily',
                  subtitle: 'One checkable fact, changed each day.',
                ),
                SizedBox(height: headerGap),
                const _FactStrip(),

                // ── The colophon ─────────────────────────────────────────
                SizedBox(height: sectionGap),
                const _Colophon(),
                SizedBox(
                  height: screenEndContentInset(
                    context,
                    reserveFloatingNav:
                        !showNavigation && bottomContentPadding > 0,
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: showNavigation
            ? const FloatingNavBar(current: AppNavTab.insights)
            : null,
      ),
    );
  }
}

/// The edition masthead: a deep brand-teal band naming the issue and what is in
/// it.
///
/// The one genuinely saturated surface on the page, and it earns that by being
/// the only element here that is about the publication rather than about a
/// story. It does the job the old printed rule did — telling you this is an
/// edition, published on a cadence, with a finite amount to read — but as an
/// object rather than a line of small caps, which is what stops the page
/// opening on an unbroken column of white cards.
///
/// The figures are computed, not written: the story count and total reading
/// time come from the article set, so an edition with more in it says so.
class _EditionMasthead extends StatelessWidget {
  const _EditionMasthead({
    required this.edition,
    required this.storyCount,
    required this.minutes,
  });

  final String edition;
  final int storyCount;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(20).clamp(18.0, 26.0).toDouble()),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(24)),
        border: Border.all(color: colors.border),
        boxShadow: MedGuardShadows.card,
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
                  color: colors.accentAlpha(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'EDITION',
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(9.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(9)),
              Text(
                edition,
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(16)),
          Text(
            'Medication safety,\nworth five minutes.',
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(22),
              fontWeight: FontWeight.w700,
              height: 1.22,
              letterSpacing: -0.6,
            ),
          ),
          SizedBox(height: responsive.s(8)),
          Text(
            'Plain-English pieces on the interactions, timings and habits that '
            'decide whether a regimen works.',
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.6),
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
          SizedBox(height: responsive.s(18)),
          Row(
            children: [
              _MastheadFigure(
                value: '$storyCount',
                label: storyCount == 1 ? 'story' : 'stories',
              ),
              Container(
                width: 1,
                height: responsive.s(26),
                margin: EdgeInsets.symmetric(horizontal: responsive.s(16)),
                color: colors.border,
              ),
              _MastheadFigure(value: '$minutes', label: 'min total'),
              Container(
                width: 1,
                height: responsive.s(26),
                margin: EdgeInsets.symmetric(horizontal: responsive.s(16)),
                color: colors.border,
              ),
              const _MastheadFigure(
                value: '$_quizRoundLength',
                label: 'quiz Qs',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MastheadFigure extends StatelessWidget {
  const _MastheadFigure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(18),
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: responsive.s(3)),
        Text(
          label,
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(10.6),
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _FigureStrip extends StatelessWidget {
  const _FigureStrip();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final width = responsive.s(196).clamp(176.0, 236.0).toDouble();

    return SizedBox(
      height: responsive.s(172).clamp(158.0, 200.0).toDouble(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: kInsightFigures.length,
        separatorBuilder: (_, _) => SizedBox(width: responsive.s(12)),
        itemBuilder: (context, index) {
          final figure = kInsightFigures[index];
          return SizedBox(
            width: width,
            child: Container(
              padding: EdgeInsets.all(responsive.s(16).clamp(14.0, 19.0)),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(responsive.radius(20)),
                border: Border.all(color: colors.border),
                boxShadow: MedGuardShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A short accent rule — the figure's colour, used as a mark
                  // rather than as a wash.
                  Container(
                    width: responsive.s(22),
                    height: 3,
                    decoration: BoxDecoration(
                      color: figure.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(height: responsive.s(12)),
                  Text(
                    figure.value,
                    maxLines: 1,
                    style: GoogleFonts.inter(
                      color: figure.accent,
                      fontSize: responsive.font(32),
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -1.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(10)),
                  Expanded(
                    child: Text(
                      figure.caption,
                      style: GoogleFonts.inter(
                        color: colors.inkSoft,
                        fontSize: responsive.font(12.2),
                        fontWeight: FontWeight.w500,
                        height: 1.42,
                      ),
                    ),
                  ),
                  SizedBox(height: responsive.s(10)),
                  Text(
                    figure.source.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(9.4),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A wide picture card — the second tier of the layout, between the lead poster
/// and the compact rows. Its job is to break the rhythm so the feed does not
/// settle into one repeated shape.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.article,
    required this.index,
    required this.onTap,
  });

  final InsightArticle article;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = BorderRadius.circular(responsive.radius(22));

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      semanticLabel: '${article.title}. ${article.dek}',
      child: DecoratedBox(
        // The shadow lives outside the clip so the antialiased corners can't
        // shave it off.
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: MedGuardShadows.card,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: radius,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.asset(article.image, fit: BoxFit.cover),
              ),
              Padding(
                padding: EdgeInsets.all(responsive.s(16).clamp(14.0, 20.0)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StoryNumber(index: index),
                        SizedBox(width: responsive.s(10)),
                        Flexible(child: _CategoryChip(article: article)),
                      ],
                    ),
                    SizedBox(height: responsive.s(11)),
                    Text(
                      article.title,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(18),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.4,
                      ),
                    ),
                    SizedBox(height: responsive.s(8)),
                    Text(
                      article.dek,
                      style: GoogleFonts.inter(
                        color: colors.inkSoft,
                        fontSize: responsive.font(12.8),
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: responsive.s(14)),
                    // A footer that balances the card: how long it takes on the
                    // left, where the tap goes on the right.
                    Row(
                      children: [
                        _ReadTime(minutes: article.readMinutes),
                        const Spacer(),
                        _ReadCue(accent: article.accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Read" affordance on a story card — the piece's own accent colour, so a
/// card says where it goes without another line of copy.
class _ReadCue extends StatelessWidget {
  const _ReadCue({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Read',
          style: GoogleFonts.inter(
            color: accent,
            fontSize: responsive.font(11.8),
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        SizedBox(width: responsive.s(2)),
        Icon(
          Icons.chevron_right_rounded,
          color: accent,
          size: responsive.icon(15),
        ),
      ],
    );
  }
}

/// The story's number in the issue, set in the same tabular figures the rest of
/// the app uses for counts. Numbering the briefing turns a list into an order —
/// the reader knows where they are and how much is left.
class _StoryNumber extends StatelessWidget {
  const _StoryNumber({required this.index, this.onDark = false});

  final int index;

  /// Set when the number sits on a photograph, where a plain grey figure is
  /// unreadable against an unpredictable background. It gains a dark scrim and
  /// white ink so it stays legible on any image in the set.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final label = Text(
      index.toString().padLeft(2, '0'),
      style: GoogleFonts.inter(
        color: onDark ? MedGuardPalette.pureWhite : colors.inkMute,
        fontSize: responsive.font(12.6),
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: 0.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (!onDark) return label;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(7),
        vertical: responsive.s(4),
      ),
      decoration: BoxDecoration(
        color: MedGuardPalette.blackAlpha(0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: label,
    );
  }
}

/// The foot of the issue: what this is, and what it is not.
class _Colophon extends StatelessWidget {
  const _Colophon();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: colors.border),
        SizedBox(height: responsive.s(14)),
        Text(
          'Compiled from published guidance by the FDA, the WHO, the NHS and '
          'peer-reviewed literature. Every piece links its source. General '
          'information only — decisions about your own medicines belong with '
          'your doctor or pharmacist.',
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(11.4),
            fontWeight: FontWeight.w400,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

/// The lead: a full-bleed photograph with the headline set over a dark scrim.
/// One story on the page gets to be a poster; the rest are rows.
class _LeadStory extends StatelessWidget {
  const _LeadStory({required this.article, required this.onTap});

  final InsightArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = BorderRadius.circular(responsive.radius(26));
    final height = responsive.s(320).clamp(280.0, 380.0).toDouble();

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      semanticLabel: '${article.title}. ${article.dek}',
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: colors.surfaceAlt,
          // The poster carries the app's card elevation, simply deeper — same
          // shape, same negative spread so the edges dissolve rather than
          // banding into a grey rectangle under the card.
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.12),
              blurRadius: responsive.s(30),
              spreadRadius: -10,
              offset: Offset(0, responsive.s(14)),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(article.image, fit: BoxFit.cover),
            // A scrim weighted to the bottom, where the type sits. Without it
            // the headline is at the mercy of whatever the photo is doing.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x140B1A1C),
                    Color(0x8A05171A),
                    Color(0xF2031012),
                  ],
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(responsive.s(18).clamp(16.0, 22.0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CategoryChip(article: article, onDark: true),
                      const Spacer(),
                      _ReadTime(minutes: article.readMinutes, onDark: true),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    article.title,
                    style: GoogleFonts.inter(
                      color: MedGuardPalette.pureWhite,
                      fontSize: responsive.font(25),
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: responsive.s(9)),
                  Text(
                    article.dek,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: MedGuardPalette.whiteAlpha(0.82),
                      fontSize: responsive.font(13),
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: responsive.s(14)),
                  Row(
                    children: [
                      Text(
                        'Read the story',
                        style: GoogleFonts.inter(
                          color: MedGuardPalette.pureWhite,
                          fontSize: responsive.font(12.6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: responsive.s(5)),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: MedGuardPalette.pureWhite,
                        size: responsive.icon(15),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A follow-up story: thumbnail left, headline and meta right. The same shape
/// every time, so the feed scans in a straight line down the page.
class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.article,
    required this.index,
    required this.onTap,
  });

  final InsightArticle article;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // A column of the card's width, not a square inset in it. The picture used
    // to be a padded thumbnail floating in white space, which is what made the
    // run read as a list of database rows rather than as an edition.
    final railWidth = responsive.s(108).clamp(92.0, 132.0).toDouble();
    final radius = BorderRadius.circular(responsive.radius(20));

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      semanticLabel: '${article.title}. ${article.dek}',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: radius,
          border: Border.all(color: colors.border),
          boxShadow: MedGuardShadows.card,
        ),
        // The card carries NO padding of its own — the picture is flush to
        // three of its edges, and only the text column is inset.
        child: ClipRRect(
          borderRadius: radius,
          // IntrinsicHeight is what lets the picture run the full height of
          // whatever the text turns out to be: the Row sizes to its tallest
          // child (the text), and the stretched image then fills exactly that.
          // Without it the image has no height to fill and collapses.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: railWidth,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(article.image, fit: BoxFit.cover),
                      // A soft scrim on the inner edge so the photograph meets
                      // the text column without a hard seam.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              colors.surface.withValues(alpha: 0.22),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: responsive.s(10),
                        top: responsive.s(10),
                        child: _StoryNumber(index: index, onDark: true),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(
                      responsive.s(14).clamp(13.0, 17.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CategoryChip(article: article),
                        SizedBox(height: responsive.s(9)),
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: colors.ink,
                            fontSize: responsive.font(15),
                            fontWeight: FontWeight.w700,
                            height: 1.26,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: responsive.s(6)),
                        Text(
                          article.dek,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: colors.inkSoft,
                            fontSize: responsive.font(12.2),
                            fontWeight: FontWeight.w400,
                            height: 1.42,
                          ),
                        ),
                        SizedBox(height: responsive.s(11)),
                        Row(
                          children: [
                            _ReadTime(minutes: article.readMinutes),
                            const Spacer(),
                            _ReadCue(accent: article.accent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.article, this.onDark = false});

  final InsightArticle article;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // On a photograph the category has to hold against whatever is underneath,
    // so it becomes a scrimmed chip instead of a colour tint.
    final ink = onDark ? MedGuardPalette.pureWhite : article.accent;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(9),
        vertical: responsive.s(4),
      ),
      decoration: BoxDecoration(
        color: onDark
            ? MedGuardPalette.blackAlpha(0.34)
            : article.accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: onDark
              ? MedGuardPalette.whiteAlpha(0.34)
              : article.accent.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        article.category.toUpperCase(),
        style: GoogleFonts.inter(
          color: ink,
          fontSize: responsive.font(9.4),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          height: 1.25,
        ),
      ),
    );
  }
}

class _ReadTime extends StatelessWidget {
  const _ReadTime({required this.minutes, this.onDark = false});

  final int minutes;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final tone = onDark ? MedGuardPalette.whiteAlpha(0.86) : colors.inkMute;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, color: tone, size: responsive.icon(13)),
        SizedBox(width: responsive.s(5)),
        Text(
          '$minutes min read',
          style: GoogleFonts.inter(
            color: tone,
            fontSize: responsive.font(11.4),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The quiz break: one question at a time, answered in place, with the reason
/// shown afterwards. A score that arrives without an explanation teaches
/// nothing, so every answer reveals why — right or wrong.
class _QuizCard extends StatefulWidget {
  const _QuizCard();

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  /// How many questions one sitting asks.
  ///
  /// The whole bank used to be one run, so a longer bank meant a longer quiz —
  /// nine questions is a test, not a quick check, and the section is called
  /// "Quick check". Three is short enough to finish standing up.
  static const int _roundLength = 3;

  int _index = 0;
  int? _picked;
  int _score = 0;
  bool _finished = false;

  /// This sitting's questions, drawn from the bank.
  ///
  /// Which three depends on the day, so the bank's full range is seen over a
  /// week or so rather than the first three every time — the reason for having
  /// more questions than a round uses.
  late List<InsightQuizQuestion> _round = _drawRound();

  List<InsightQuizQuestion> _drawRound() {
    final bank = kInsightQuiz;
    if (bank.length <= _roundLength) return List.of(bank);
    final offset = DateTime.now().day * _roundLength;
    return [
      for (var i = 0; i < _roundLength; i++) bank[(offset + i) % bank.length],
    ];
  }

  InsightQuizQuestion get _question => _round[_index];
  bool get _answered => _picked != null;

  void _pick(int option) {
    if (_answered) return;
    HapticFeedback.selectionClick();
    setState(() {
      _picked = option;
      if (option == _question.answerIndex) _score++;
    });
  }

  void _next() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_index == _round.length - 1) {
        _finished = true;
      } else {
        _index++;
        _picked = null;
      }
    });
  }

  void _restart() {
    _round = _drawRound();
    HapticFeedback.selectionClick();
    setState(() {
      _index = 0;
      _picked = null;
      _score = 0;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final pad = responsive.s(20).clamp(17.0, 24.0).toDouble();

    return Container(
      key: const ValueKey('insights-quiz'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(responsive.radius(26)),
        // The same deep brand teal the Home dose band and the Dose page panel
        // use, so the quiz reads as part of the app rather than an insert.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF04564E), MedGuardPalette.tealDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.tealDeep.withValues(alpha: 0.26),
            blurRadius: responsive.s(26),
            offset: Offset(0, responsive.s(10)),
          ),
        ],
      ),
      child: _finished ? _buildResult(responsive) : _buildQuestion(responsive),
    );
  }

  Widget _buildQuestion(MedGuardResponsive responsive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.quiz_rounded,
              color: MedGuardPalette.pureWhite,
              size: responsive.icon(16),
            ),
            SizedBox(width: responsive.s(8)),
            Text(
              'QUICK CHECK',
              style: GoogleFonts.inter(
                color: MedGuardPalette.pureWhite,
                fontSize: responsive.font(10.4),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                height: 1,
              ),
            ),
            const Spacer(),
            Text(
              '${_index + 1} / ${_round.length}',
              style: GoogleFonts.inter(
                color: MedGuardPalette.whiteAlpha(0.62),
                fontSize: responsive.font(11.4),
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
        SizedBox(height: responsive.s(16)),
        Text(
          _question.question,
          style: GoogleFonts.inter(
            color: MedGuardPalette.pureWhite,
            fontSize: responsive.font(16.5),
            fontWeight: FontWeight.w700,
            height: 1.32,
            letterSpacing: -0.25,
          ),
        ),
        SizedBox(height: responsive.s(16)),
        for (var i = 0; i < _question.options.length; i++) ...[
          _QuizOption(
            label: _question.options[i],
            state: !_answered
                ? _OptionState.idle
                : i == _question.answerIndex
                ? _OptionState.correct
                : i == _picked
                ? _OptionState.wrong
                : _OptionState.dimmed,
            onTap: () => _pick(i),
          ),
          if (i != _question.options.length - 1)
            SizedBox(height: responsive.s(8)),
        ],
        if (_answered) ...[
          SizedBox(height: responsive.s(14)),
          Container(
            padding: EdgeInsets.all(responsive.s(13)),
            decoration: BoxDecoration(
              color: MedGuardPalette.whiteAlpha(0.10),
              borderRadius: BorderRadius.circular(responsive.radius(14)),
            ),
            child: Text(
              _question.explanation,
              style: GoogleFonts.inter(
                color: MedGuardPalette.whiteAlpha(0.86),
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: responsive.s(14)),
          _QuizButton(
            label: _index == _round.length - 1
                ? 'See result'
                : 'Next question',
            onTap: _next,
          ),
        ],
      ],
    );
  }

  Widget _buildResult(MedGuardResponsive responsive) {
    final total = kInsightQuiz.length;
    final perfect = _score == total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          perfect ? Icons.workspace_premium_rounded : Icons.school_rounded,
          color: MedGuardPalette.pureWhite,
          size: responsive.icon(26),
        ),
        SizedBox(height: responsive.s(12)),
        Text(
          '$_score of $total',
          style: GoogleFonts.inter(
            color: MedGuardPalette.pureWhite,
            fontSize: responsive.font(26),
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        SizedBox(height: responsive.s(7)),
        Text(
          perfect
              ? 'Full marks. You already read labels like a pharmacist.'
              : 'Worth a second pass — the stories here cover every answer.',
          style: GoogleFonts.inter(
            color: MedGuardPalette.whiteAlpha(0.82),
            fontSize: responsive.font(12.8),
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
        SizedBox(height: responsive.s(16)),
        _QuizButton(label: 'Try again', onTap: _restart),
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final (Color fill, Color border, Color ink, IconData? mark) =
        switch (state) {
          _OptionState.idle => (
            MedGuardPalette.whiteAlpha(0.10),
            MedGuardPalette.whiteAlpha(0.18),
            MedGuardPalette.pureWhite,
            null,
          ),
          _OptionState.correct => (
            const Color(0xFF7FF5E2).withValues(alpha: 0.20),
            const Color(0xFF7FF5E2),
            const Color(0xFF7FF5E2),
            Icons.check_circle_rounded,
          ),
          _OptionState.wrong => (
            const Color(0xFFFF8A8C).withValues(alpha: 0.18),
            const Color(0xFFFF8A8C),
            const Color(0xFFFF8A8C),
            Icons.cancel_rounded,
          ),
          _OptionState.dimmed => (
            MedGuardPalette.whiteAlpha(0.05),
            MedGuardPalette.whiteAlpha(0.10),
            MedGuardPalette.whiteAlpha(0.48),
            null,
          ),
        };

    return Pressable(
      onTap: state == _OptionState.idle ? onTap : null,
      pressScale: 0.98,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(13),
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(responsive.radius(14)),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: ink,
                  fontSize: responsive.font(13.2),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (mark != null) ...[
              SizedBox(width: responsive.s(8)),
              Icon(mark, color: ink, size: responsive.icon(17)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The white pill used for the quiz's forward action — the strongest contrast
/// available on the deep teal ground.
class _QuizButton extends StatelessWidget {
  const _QuizButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Pressable(
      onTap: onTap,
      pressScale: 0.96,
      semanticLabel: label,
      child: Container(
        height: responsive.s(44).clamp(42.0, 50.0).toDouble(),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: responsive.s(22)),
        decoration: const ShapeDecoration(
          color: MedGuardPalette.pureWhite,
          shape: StadiumBorder(),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: MedGuardPalette.tealDeep,
            fontSize: responsive.font(13.2),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A single checkable fact, rotating by day. Light relief between the quiz and
/// the rest of the feed, and short enough to actually land.
class _FactStrip extends StatelessWidget {
  const _FactStrip();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final facts = kInsightFacts;
    final today = DateTime.now();
    final fact = facts[today.day % facts.length];

    // A clean surface, like every other card on the page. The quiz is the ONE
    // dark element in the edition; a second one here made the foot of the page
    // compete with it for the same job, and three different special
    // backgrounds in one scroll is what stops any of them meaning anything.
    //
    // What separates this from a plain card is a single accent rule down the
    // left of the fact itself — enough to mark it as a pull-quote rather than
    // another paragraph, without another filled box.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(20).clamp(18.0, 24.0)),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(24)),
        border: Border.all(color: colors.border),
        boxShadow: MedGuardShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: responsive.icon(15),
                color: colors.accent,
              ),
              SizedBox(width: responsive.s(8)),
              Expanded(
                child: Text(
                  'DID YOU KNOW',
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(10.4),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    height: 1,
                  ),
                ),
              ),
              Text(
                _dayLabel(today),
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(10.6),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  height: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(16)),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: responsive.s(3),
                  decoration: BoxDecoration(
                    color: colors.accentAlpha(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(width: responsive.s(14)),
                Expanded(
                  // Set at reading size, not caption size. It is the whole
                  // point of the section, and it used to be typeset smaller
                  // than the card's own label.
                  child: Text(
                    fact,
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(14.6),
                      fontWeight: FontWeight.w500,
                      height: 1.55,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: responsive.s(16)),
          Row(
            children: [
              Icon(
                Icons.event_repeat_rounded,
                size: responsive.icon(13),
                color: colors.inkMute,
              ),
              SizedBox(width: responsive.s(7)),
              Expanded(
                child: Text(
                  'A new one every day — ${facts.length} in the set.',
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(11.6),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

