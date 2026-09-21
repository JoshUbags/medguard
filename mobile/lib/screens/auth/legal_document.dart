import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/surface_card.dart';

/// One plain-language takeaway in a document's "In short" card.
class LegalPoint {
  const LegalPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

/// One clause. Numbered automatically in reading order, so a clause moved
/// between groups can never leave the numbering out of sequence.
class LegalClause {
  const LegalClause({
    required this.title,
    required this.icon,
    this.paragraphs = const [],
    this.bullets = const [],
    this.emphasized = false,
  });

  final String title;
  final IconData icon;
  final List<String> paragraphs;
  final List<String> bullets;

  /// The safety-critical clause, set in amber so it stands apart.
  final bool emphasized;
}

/// A themed run of clauses under one section heading.
class LegalGroup {
  const LegalGroup({required this.title, required this.clauses});

  final String title;
  final List<LegalClause> clauses;
}

/// THE layout for a legal document — the privacy policy and the terms.
///
/// The two used to be different designs: the policy a long run of bare text
/// under a meta card, the terms a stack of bespoke cards with hard-coded
/// colours and clause numbers that ran 01, 02, 05, 03. They are one kind of
/// page, so they are now one widget: provenance first, the short version, then
/// every clause as a numbered card under the app's standard section headings.
///
/// Built on [DetailPage] like every other routed screen, so there is always an
/// obvious way back to the sign-up flow a user opened the document from.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.documentLabel,
    required this.updatedAt,
    required this.summary,
    required this.groups,
  });

  final String title;
  final String subtitle;

  /// The document's name as it reads on the provenance card.
  final String documentLabel;
  final String updatedAt;
  final List<LegalPoint> summary;
  final List<LegalGroup> groups;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = SizedBox(height: sectionGap(responsive));
    final clauseCount = groups.fold<int>(0, (n, g) => n + g.clauses.length);

    var number = 0;
    final sections = <Widget>[
      for (final group in groups)
        SectionBlock(
          title: group.title,
          action:
              '${group.clauses.length} '
              '${group.clauses.length == 1 ? 'clause' : 'clauses'}',
          card: false,
          children: [
            for (final clause in group.clauses)
              _ClauseCard(clause: clause, number: ++number),
          ],
        ),
    ];

    return DetailPage(
      title: title,
      subtitle: subtitle,
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LegalMeta(
                    label: documentLabel,
                    updatedAt: updatedAt,
                    clauseCount: clauseCount,
                  ),
                  if (summary.isNotEmpty) ...[
                    gap,
                    SectionBlock(
                      title: 'In short',
                      subtitle:
                          'The points that matter most, before the '
                          'detail.',
                      child: _Summary(points: summary),
                    ),
                  ],
                  for (final section in sections) ...[gap, section],
                  gap,
                  const _LegalContact(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which document this is, when it last changed, and how long it is.
///
/// "Last updated" belongs at the TOP of a legal document: for a returning user
/// it is the single most useful fact on the page.
class _LegalMeta extends StatelessWidget {
  const _LegalMeta({
    required this.label,
    required this.updatedAt,
    required this.clauseCount,
  });

  final String label;
  final String updatedAt;
  final int clauseCount;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(16)),
      child: Row(
        children: [
          _Glyph(icon: Icons.description_rounded, tint: colors.accent),
          SizedBox(width: responsive.s(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.2),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: responsive.s(3)),
                Text(
                  'Last updated $updatedAt · $clauseCount clauses',
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
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.points});

  final List<LegalPoint> points;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      children: [
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) SizedBox(height: responsive.s(14)),
          Row(
            children: [
              Icon(
                points[i].icon,
                size: responsive.icon(18),
                color: colors.accent,
              ),
              SizedBox(width: responsive.s(12)),
              Expanded(
                child: Text(
                  points[i].text,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.2),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ClauseCard extends StatelessWidget {
  const _ClauseCard({required this.clause, required this.number});

  final LegalClause clause;
  final int number;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final tone = clause.emphasized ? colors.warning : colors.accent;
    final numberLabel = 'Clause ${number.toString().padLeft(2, '0')}';

    return SurfaceCard(
      accent: clause.emphasized ? colors.warning : null,
      padding: EdgeInsets.all(responsive.s(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Glyph(icon: clause.icon, tint: tone),
              SizedBox(width: responsive.s(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clause.emphasized
                          ? '$numberLabel · Important'
                          : numberLabel,
                      style: GoogleFonts.inter(
                        color: clause.emphasized ? tone : colors.inkMute,
                        fontSize: responsive.font(11.6),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(3)),
                    Text(
                      clause.title,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(15.2),
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(14)),
          for (var i = 0; i < clause.paragraphs.length; i++) ...[
            if (i > 0) SizedBox(height: responsive.s(10)),
            Text(
              clause.paragraphs[i],
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(13.2),
                fontWeight: FontWeight.w400,
                height: 1.55,
              ),
            ),
          ],
          if (clause.paragraphs.isNotEmpty && clause.bullets.isNotEmpty)
            SizedBox(height: responsive.s(12)),
          for (var i = 0; i < clause.bullets.length; i++) ...[
            if (i > 0) SizedBox(height: responsive.s(9)),
            _Bullet(text: clause.bullets[i], tone: tone),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final dot = responsive.s(6).clamp(5.0, 7.0).toDouble();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: dot,
          height: dot,
          margin: EdgeInsets.only(top: responsive.s(8)),
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        SizedBox(width: responsive.s(11)),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(13.2),
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Where to take a question, so the document ends on a way forward rather than
/// on its last clause.
class _LegalContact extends StatelessWidget {
  const _LegalContact();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      tinted: true,
      elevated: false,
      padding: EdgeInsets.all(responsive.s(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(icon: Icons.support_agent_rounded, tint: colors.accent),
          SizedBox(width: responsive.s(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Questions about this document?',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: responsive.s(4)),
                Text(
                  'Reach the MedGuard team through the support channel in the '
                  'app. For anything urgent or medical, contact a clinician '
                  'or emergency service.',
                  style: GoogleFonts.inter(
                    color: colors.inkSoft,
                    fontSize: responsive.font(12.6),
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final extent = responsive.s(40).clamp(36.0, 46.0).toDouble();

    return Container(
      width: extent,
      height: extent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(responsive.radius(13)),
      ),
      child: Icon(icon, size: responsive.icon(19), color: tint),
    );
  }
}
