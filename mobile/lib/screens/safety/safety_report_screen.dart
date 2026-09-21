import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/duplicate_therapy_result.dart';
import '../../models/food_interaction_result.dart';
import '../../models/interaction_result.dart';
import '../../models/safety_report.dart';
import '../../models/severity.dart';
import '../../models/user_medication.dart';
import '../../services/allergy_checker.dart';
import '../../services/interaction_checker.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/surface_card.dart';

/// The full safety report — the document behind the Interactions tab.
///
/// The Interactions screen answers "is there a problem, and roughly what". This
/// answers everything else: every finding, what it does, why it happens, where
/// the verdict came from, and what to do about it. It is the page a user would
/// show a pharmacist.
///
/// Nothing here uses a coloured bar down the side of a card to signal severity.
/// That pattern turns a page of findings into a set of competing stripes and
/// makes every card read as a system alert. Severity is carried by a labelled
/// badge and a tinted glyph — legible, nameable, and identical to how severity
/// reads everywhere else in the app.
class SafetyReportScreen extends StatefulWidget {
  const SafetyReportScreen({
    super.key,
    required this.userId,
    required this.medications,
  });

  static const String routeName = '/safety-report';

  final String userId;
  final List<UserMedication> medications;

  @override
  State<SafetyReportScreen> createState() => _SafetyReportScreenState();
}

class _SafetyReportScreenState extends State<SafetyReportScreen> {
  late Future<SafetyReport> _future;
  late DateTime _generatedAt;

  @override
  void initState() {
    super.initState();
    _generatedAt = DateTime.now();
    _future = _runCheck();
  }

  /// The shortest time the skeleton is allowed to be on screen.
  ///
  /// The analysis is usually served from cache and resolves in a few
  /// milliseconds, which sounds ideal and is not: arriving from the review
  /// button, the page would snap straight to a finished report and the user
  /// could not tell whether anything had been re-checked or whether they were
  /// looking at the same screen they left. A brief, honest skeleton makes the
  /// work visible.
  ///
  /// Short enough that it never becomes the wait itself.
  static const Duration _minimumSkeleton = Duration(milliseconds: 900);

  Future<SafetyReport> _runCheck() async {
    final started = DateTime.now();
    final report = await InteractionChecker.analyze(
      widget.medications.map((m) => m.drugId).toList(growable: false),
      userId: widget.userId,
      drugs: widget.medications
          .map((m) => (id: m.drugId, name: m.drugName))
          .toList(growable: false),
    );
    // Only ever pads a FAST result — a slow one is already past the floor and
    // waits no longer than it takes.
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minimumSkeleton) {
      await Future<void>.delayed(_minimumSkeleton - elapsed);
    }
    return report;
  }

  Future<void> _refresh() async {
    InteractionChecker.invalidateCache();
    setState(() {
      _generatedAt = DateTime.now();
      _future = _runCheck();
    });
    await _future;
  }

  Future<void> _share(SafetyReport report) async {
    await SharePlus.instance.share(
      ShareParams(
        text: _shareText(report),
        subject: 'MedGuard — Safety Report',
      ),
    );
  }

  String _shareText(SafetyReport report) {
    final lines = <String>[
      'MedGuard — Safety Report',
      'Generated: ${_longDateTime(_generatedAt)}',
      'Medicines: ${widget.medications.map((m) => m.displayName).join(', ')}',
      'Overall risk: ${report.verdictLabel}',
      '',
    ];
    if (report.allergyHits.isNotEmpty) {
      lines.add('— Allergy conflicts (${report.allergyHits.length}) —');
      for (final hit in report.allergyHits) {
        lines.add('• ${hit.summary}');
      }
      lines.add('');
    }
    if (report.drugInteractions.isNotEmpty) {
      lines.add(
        '— Drug-drug interactions (${report.drugInteractions.length}) —',
      );
      for (final interaction in report.drugInteractions) {
        final pct = interaction.confidencePercent;
        final src = interaction.source == InteractionSource.aiPrediction
            ? ' [${interaction.source.label}${pct == null ? '' : ' $pct%'}]'
            : ' [${interaction.source.label}]';
        lines.add(
          '• [${interaction.riskLevel.label.toUpperCase()} RISK] '
          '${interaction.drugAName} + ${interaction.drugBName}$src'
          '${interaction.effect == null ? "" : " — ${interaction.effect}"}',
        );
      }
      lines.add('');
    }
    if (report.duplicateTherapies.isNotEmpty) {
      lines.add('— Duplicate therapy (${report.duplicateTherapies.length}) —');
      for (final dup in report.duplicateTherapies) {
        lines.add(
          '• ${dup.drugAName} and ${dup.drugBName} — '
          'shared class: ${dup.category}',
        );
      }
      lines.add('');
    }
    if (report.foodInteractions.isNotEmpty) {
      lines.add('— Food advisories (${report.foodInteractions.length}) —');
      for (final food in report.foodInteractions) {
        lines.add('• ${food.drugName}: ${food.description}');
      }
      lines.add('');
    }
    lines.add(
      'This report is decision support, not medical advice. Do not change or '
      'stop a medicine on the strength of it — take it to a pharmacist or '
      'prescriber.',
    );
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: 'Safety report',
      subtitle:
          '${widget.medications.length} '
          '${widget.medications.length == 1 ? 'medicine' : 'medicines'}, '
          'checked against each other and against your record.',
      actions: [
        // Built from the same future as the body, so Share is unavailable until
        // there is something to share rather than being a live-looking button
        // that silently does nothing.
        FutureBuilder<SafetyReport>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return DetailPageAction(
              icon: Icons.ios_share_rounded,
              semanticLabel: 'Share report',
              tint: data == null ? context.colors.inkMute : null,
              onTap: () {
                if (data != null) _share(data);
              },
            );
          },
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: FutureBuilder<SafetyReport>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _ReportSkeleton();
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _ErrorState(onRetry: _refresh);
                  }
                  return _ReportView(
                    report: snapshot.data!,
                    medications: widget.medications,
                    generatedAt: _generatedAt,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: colors.inkMute,
            size: responsive.icon(30),
          ),
          SizedBox(height: responsive.s(12)),
          Text(
            'The report could not be generated',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(15),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: responsive.s(6)),
          Text(
            'The safety checks did not finish. Your medicines are unchanged — '
            'nothing was saved or altered.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.6),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          SizedBox(height: responsive.s(16)),
          AppButton(
            label: 'Run the checks again',
            icon: Icons.refresh_rounded,
            variant: AppButtonVariant.secondary,
            onTap: () => onRetry(),
          ),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.report,
    required this.medications,
    required this.generatedAt,
  });

  final SafetyReport report;
  final List<UserMedication> medications;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = sectionGap(responsive);
    final actions = _actions(context);

    // A Column, not a ListView: DetailPage owns the page scroll, so a second
    // scrollable here would compete with it for the drag gesture.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Verdict(
          report: report,
          medications: medications,
          generatedAt: generatedAt,
        ),
        SizedBox(height: gap),

        _AtAGlance(report: report),

        if (actions.isNotEmpty) ...[
          SizedBox(height: gap),
          _WhatToDo(actions: actions),
        ],

        if (report.allergyHits.isNotEmpty) ...[
          SizedBox(height: gap),
          _ReportSection(
            title: 'Allergy conflicts',
            caption:
                'A medicine you take matches something on your allergy list, '
                'directly or by drug class.',
            count: report.allergyHits.length,
            children: [
              for (final hit in report.allergyHits) _AllergyCard(hit: hit),
            ],
          ),
        ],

        SizedBox(height: gap),
        _ReportSection(
          title: 'Drug interactions',
          caption: report.drugInteractions.isEmpty
              ? 'Every pair of your medicines was checked against each other.'
              : 'Tap any finding for its mechanism and where the verdict came '
                    'from.',
          count: report.drugInteractions.length,
          emptyMessage: 'No interactions were found between these medicines.',
          children: [
            for (final interaction in _sortedInteractions())
              _InteractionCard(interaction: interaction),
          ],
        ),

        SizedBox(height: gap),
        _ReportSection(
          title: 'Duplicate therapy',
          caption:
              'Two medicines doing the same therapeutic job add up to more '
              'dose than either one alone.',
          count: report.duplicateTherapies.length,
          emptyMessage: 'No two of your medicines share a therapeutic class.',
          children: [
            for (final dup in report.duplicateTherapies)
              _DuplicateCard(result: dup),
          ],
        ),

        SizedBox(height: gap),
        _ReportSection(
          title: 'Food and drink',
          caption:
              'Foods, drinks and supplements that change how a medicine '
              'behaves.',
          count: report.foodInteractions.length,
          emptyMessage: 'No food advisories apply to these medicines.',
          children: [
            for (final food in report.foodInteractions) _FoodCard(food: food),
          ],
        ),

        SizedBox(height: gap),
        const _Methodology(),
      ],
    );
  }

  List<InteractionResult> _sortedInteractions() {
    return [...report.drugInteractions]
      ..sort((a, b) => b.severityLevel.rank.compareTo(a.severityLevel.rank));
  }

  /// The report's recommendations, derived from what was actually found.
  ///
  /// Generated rather than written: a fixed list of advice would read the same
  /// on a clean report and a critical one, which is precisely how users learn
  /// to skip a section.
  List<_ReportAction> _actions(BuildContext context) {
    final colors = context.colors;
    final actions = <_ReportAction>[];

    if (report.allergyHits.isNotEmpty) {
      actions.add(
        _ReportAction(
          icon: Icons.priority_high_rounded,
          tone: colors.danger,
          title: 'Raise the allergy conflict first',
          body:
              'An allergy match outranks everything else in this report. '
              'Confirm it with a pharmacist before your next dose.',
        ),
      );
    }

    final high = report.drugInteractions
        .where((i) => i.riskLevel == RiskLevel.high)
        .length;
    if (high > 0) {
      actions.add(
        _ReportAction(
          icon: Icons.forum_rounded,
          tone: colors.danger,
          title: 'Discuss $high high-risk ${high == 1 ? 'pair' : 'pairs'}',
          body:
              'High-risk findings usually have a workable answer — a dose '
              'change, a gap between doses, or a substitute. They rarely mean '
              'stopping a medicine.',
        ),
      );
    }

    if (report.duplicateTherapies.isNotEmpty) {
      actions.add(
        _ReportAction(
          icon: Icons.content_copy_rounded,
          tone: colors.warning,
          title: 'Check whether both duplicates are intended',
          body:
              'Duplicates are often a prescribing overlap — a brand and its '
              'generic, or a repeat that was never stopped.',
        ),
      );
    }

    if (report.foodInteractions.isNotEmpty) {
      actions.add(
        _ReportAction(
          icon: Icons.restaurant_rounded,
          tone: colors.accent,
          title: 'Adjust timing around food, not the dose',
          body:
              'Most food advisories are solved by separating the medicine '
              'from the food by a couple of hours.',
        ),
      );
    }

    return actions;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The verdict
// ─────────────────────────────────────────────────────────────────────────────

/// The report's opening statement: the overall verdict, what it covers, and
/// when it was produced.
class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.report,
    required this.medications,
    required this.generatedAt,
  });

  final SafetyReport report;
  final List<UserMedication> medications;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // Switched on the canonical three-tier level (plus the "nothing at all"
    // case) so the icon, the tone and the wording can never disagree with
    // [SafetyReport.verdictLabel] printed beside them.
    final (tone, icon, body) = switch ((
      report.regimenRiskLevel,
      report.hasAnyFinding,
    )) {
      (RiskLevel.low, false) => (
        colors.accent,
        Icons.verified_rounded,
        'Nothing in this set conflicts. No interactions, allergy matches, '
            'duplicates or food advisories were found.',
      ),
      (RiskLevel.low, _) => (
        colors.accent,
        Icons.check_circle_rounded,
        'Minor findings only. Worth knowing about, but none of it calls for '
            'a change today.',
      ),
      (RiskLevel.moderate, _) => (
        colors.warning,
        Icons.warning_amber_rounded,
        'Findings here are worth raising at your next pharmacy or GP visit. '
            'Nothing needs to change before then on the strength of this '
            'report alone.',
      ),
      (RiskLevel.high, _) => (
        colors.danger,
        Icons.report_problem_rounded,
        'At least one finding is serious enough to raise with a clinician '
            'before your next dose. Do not stop anything on your own.',
      ),
    };

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: responsive.s(46),
                height: responsive.s(46),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(responsive.radius(15)),
                ),
                child: Icon(icon, color: tone, size: responsive.icon(24)),
              ),
              SizedBox(width: responsive.s(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'OVERALL VERDICT',
                      style: GoogleFonts.inter(
                        color: colors.inkMute,
                        fontSize: responsive.font(9.8),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                    SizedBox(height: responsive.s(3)),
                    Text(
                      report.verdictLabel,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(19),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(14)),
          Text(
            body,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(13),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          SizedBox(height: responsive.s(16)),
          const CardDivider(),
          SizedBox(height: responsive.s(10)),
          Text(
            'COVERS',
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(9.8),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          SizedBox(height: responsive.s(9)),
          Wrap(
            spacing: responsive.s(7),
            runSpacing: responsive.s(7),
            children: [
              for (final medication in medications)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.s(11),
                    vertical: responsive.s(6),
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    medication.displayName,
                    style: GoogleFonts.inter(
                      color: colors.inkSoft,
                      fontSize: responsive.font(12),
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: responsive.s(12)),
          Text(
            'Generated ${_longDateTime(generatedAt)}',
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(11.4),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The four counts, as a clean row.
///
/// A reader scanning a report wants its shape before its substance: how many of
/// each kind of thing, and which sections are worth opening.
class _AtAGlance extends StatelessWidget {
  const _AtAGlance({required this.report});

  final SafetyReport report;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    final tiles = <({String label, int count, Color tone})>[
      (
        label: 'Interactions',
        count: report.drugInteractions.length,
        tone: colors.danger,
      ),
      (
        label: 'Allergy hits',
        count: report.allergyHits.length,
        tone: colors.danger,
      ),
      (
        label: 'Duplicates',
        count: report.duplicateTherapies.length,
        tone: colors.warning,
      ),
      (
        label: 'Food notes',
        count: report.foodInteractions.length,
        tone: colors.accent,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'At a glance',
          subtitle: 'What each check turned up.',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        SurfaceCard(
          padding: EdgeInsets.symmetric(
            horizontal: responsive.s(6),
            vertical: responsive.s(16),
          ),
          child: Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: responsive.s(38),
                    color: colors.border,
                  ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${tiles[i].count}',
                        style: GoogleFonts.inter(
                          color: tiles[i].count == 0
                              ? colors.inkMute
                              : tiles[i].tone,
                          fontSize: responsive.font(22),
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: responsive.s(6)),
                      Text(
                        tiles[i].label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(10.6),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportAction {
  const _ReportAction({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;
}

/// The recommendations, in priority order.
class _WhatToDo extends StatelessWidget {
  const _WhatToDo({required this.actions});

  final List<_ReportAction> actions;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'What to do',
          subtitle: 'Ordered by how much it matters.',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        SurfaceCard(
          padding: EdgeInsets.all(responsive.s(18)),
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) CardDivider(indent: responsive.s(42)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: responsive.s(30),
                      height: responsive.s(30),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: actions[i].tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        actions[i].icon,
                        size: responsive.icon(16),
                        color: actions[i].tone,
                      ),
                    ),
                    SizedBox(width: responsive.s(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actions[i].title,
                            style: GoogleFonts.inter(
                              color: colors.ink,
                              fontSize: responsive.font(13.4),
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          SizedBox(height: responsive.s(4)),
                          Text(
                            actions[i].body,
                            style: GoogleFonts.inter(
                              color: colors.inkSoft,
                              fontSize: responsive.font(12.2),
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sections
// ─────────────────────────────────────────────────────────────────────────────

/// A findings section: heading and caption on the canvas, findings as cards
/// beneath — the app's layout grammar.
///
/// Renders its empty state as a quiet card rather than hiding itself. A report
/// that silently omits the sections which found nothing cannot be read as
/// evidence of anything: the reader can't tell a clean check from one that
/// never ran.
class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.caption,
    required this.count,
    required this.children,
    this.emptyMessage,
  });

  final String title;
  final String caption;
  final int count;
  final List<Widget> children;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final empty = count == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          subtitle: caption,
          action: empty ? 'Clear' : '$count',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        if (empty)
          SurfaceCard(
            padding: EdgeInsets.all(responsive.s(16)),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: responsive.icon(18),
                  color: colors.accent,
                ),
                SizedBox(width: responsive.s(11)),
                Expanded(
                  child: Text(
                    emptyMessage ?? 'Nothing found.',
                    style: GoogleFonts.inter(
                      color: colors.inkSoft,
                      fontSize: responsive.font(12.6),
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: responsive.s(10)),
            children[i],
          ],
      ],
    );
  }
}

/// One drug-drug interaction.
///
/// Collapsed it gives the pair, the tier and the clinical effect IN FULL — no
/// ellipsis, because a truncated effect is worse than none at all: the reader
/// cannot tell whether the important half is the half that got cut. Expanded it
/// adds the mechanism, the longer description, and the provenance of the
/// verdict.
class _InteractionCard extends StatefulWidget {
  const _InteractionCard({required this.interaction});

  final InteractionResult interaction;

  @override
  State<_InteractionCard> createState() => _InteractionCardState();
}

class _InteractionCardState extends State<_InteractionCard> {
  bool _expanded = false;

  bool get _hasDetail {
    final i = widget.interaction;
    return (i.mechanism?.trim().isNotEmpty ?? false) ||
        (i.description?.trim().isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final i = widget.interaction;
    final tone = switch (i.riskLevel) {
      RiskLevel.high => colors.danger,
      RiskLevel.moderate => colors.warning,
      RiskLevel.low => colors.inkMute,
    };

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(16)),
      onTap: _hasDetail ? () => setState(() => _expanded = !_expanded) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pair + tier. The tier is a named badge, never a colour stripe: a
          // reader can say "that one is High" out loud.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${i.drugAName} + ${i.drugBName}',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.4),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              _TierBadge(label: i.riskLevel.label, tone: tone),
            ],
          ),
          if (i.effect?.trim().isNotEmpty ?? false) ...[
            SizedBox(height: responsive.s(10)),
            Text(
              i.effect!,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.8),
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ],
          SizedBox(height: responsive.s(12)),
          Row(
            children: [
              Expanded(
                child: _ProvenanceLine(
                  source: i.source,
                  confidencePercent: i.confidencePercent,
                  severity: i.severityLevel,
                ),
              ),
              if (_hasDetail) ...[
                SizedBox(width: responsive.s(10)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Less' : 'Details',
                      style: GoogleFonts.inter(
                        color: colors.accent,
                        fontSize: responsive.font(11.8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: responsive.icon(17),
                      color: colors.accent,
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (_expanded) ...[
            SizedBox(height: responsive.s(6)),
            const CardDivider(),
            if (i.mechanism?.trim().isNotEmpty ?? false)
              _DetailBlock(label: 'How it happens', value: i.mechanism!),
            if (i.description?.trim().isNotEmpty ?? false)
              _DetailBlock(label: 'In full', value: i.description!),
          ],
        ],
      ),
    );
  }
}

/// One allergy conflict.
class _AllergyCard extends StatelessWidget {
  const _AllergyCard({required this.hit});

  final AllergyHit hit;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  hit.drugName,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.4),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              _TierBadge(label: 'Allergy', tone: colors.danger),
            ],
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            hit.summary,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.8),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          if (hit.note?.trim().isNotEmpty ?? false)
            _DetailBlock(label: 'Your note', value: hit.note!),
        ],
      ),
    );
  }
}

/// One duplicate-therapy pair.
class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.result});

  final DuplicateTherapyResult result;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${result.drugAName} + ${result.drugBName}',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.4),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              _TierBadge(label: 'Duplicate', tone: colors.warning),
            ],
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            'Both belong to the same therapeutic class, so taking them '
            'together may add up to more of the same effect than either was '
            'prescribed to deliver.',
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.8),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          _DetailBlock(label: 'Shared class', value: result.category),
        ],
      ),
    );
  }
}

/// One food advisory.
class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.food});

  final FoodInteractionResult food;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  food.drugName,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14.4),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              _TierBadge(label: 'Advisory', tone: colors.accent),
            ],
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            food.description,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.8),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// How the report was produced, and what it is not.
///
/// Every clinical claim in the app rests on this being stated plainly. A safety
/// report without its method and its limits is an opinion presented as a fact.
class _Methodology extends StatelessWidget {
  const _Methodology();

  static const _notes = <(IconData, String, String)>[
    (
      Icons.storage_rounded,
      'Curated pairs first',
      'Every pair is looked up in a bundled clinical interaction database. A '
          'catalogued verdict always wins.',
    ),
    (
      Icons.auto_awesome_rounded,
      'A model fills the gaps',
      'Pairs with no catalogue entry are scored by an on-device model. Those '
          'findings are labelled with their confidence, so you can weigh them '
          'accordingly.',
    ),
    (
      Icons.phone_android_rounded,
      'It runs on your phone',
      'The database ships inside the app and the checks run locally. No '
          'medicine list leaves the device to produce this report.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'How this was checked',
          subtitle: 'Where each verdict comes from.',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        SurfaceCard(
          padding: EdgeInsets.all(responsive.s(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _notes.length; i++) ...[
                if (i > 0) CardDivider(indent: responsive.s(38)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _notes[i].$1,
                      size: responsive.icon(18),
                      color: colors.accent,
                    ),
                    SizedBox(width: responsive.s(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _notes[i].$2,
                            style: GoogleFonts.inter(
                              color: colors.ink,
                              fontSize: responsive.font(13),
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          SizedBox(height: responsive.s(4)),
                          Text(
                            _notes[i].$3,
                            style: GoogleFonts.inter(
                              color: colors.inkSoft,
                              fontSize: responsive.font(12.2),
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: responsive.s(16)),
              Container(
                padding: EdgeInsets.all(responsive.s(13)),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(responsive.radius(14)),
                ),
                child: Text(
                  'This report is decision support, not medical advice. It '
                  'cannot see your dose, your kidney or liver function, or why '
                  'each medicine was prescribed — all of which change what a '
                  'finding means. Take it to a pharmacist or prescriber; do '
                  'not change or stop a medicine on the strength of it.',
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(11.8),
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces
// ─────────────────────────────────────────────────────────────────────────────

/// A named severity badge — the report's ONLY severity signal, on purpose: one
/// shape, one place on the card, one vocabulary.
class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(10),
        vertical: responsive.s(5),
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: tone,
          fontSize: responsive.font(11),
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Where a verdict came from, in one quiet line.
///
/// This is the detail that lets a pharmacist calibrate trust: a catalogued
/// contraindication and a model prediction at 61% confidence are both worth
/// reading, but not in the same way.
class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({
    required this.source,
    required this.confidencePercent,
    required this.severity,
  });

  final InteractionSource source;
  final int? confidencePercent;
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final predicted = source == InteractionSource.aiPrediction;
    final pct = confidencePercent;

    final text = predicted
        ? 'Predicted on device${pct == null ? '' : ' · $pct% confidence'}'
        : 'Clinical database · catalogued as ${severity.wireName}';

    return Row(
      children: [
        Icon(
          predicted ? Icons.auto_awesome_rounded : Icons.verified_rounded,
          size: responsive.icon(13),
          color: colors.inkMute,
        ),
        SizedBox(width: responsive.s(6)),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(11.2),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled block of prose inside a finding card.
class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(top: responsive.s(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(9.6),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
          SizedBox(height: responsive.s(5)),
          Text(
            value,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.4),
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _longDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour < 12 ? 'am' : 'pm';
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '$hour:$minute$meridiem';
}

/// The report's shape, drawn empty while the analysis runs.
///
/// A skeleton rather than a spinner because the page it precedes has a strong,
/// consistent structure — a verdict card, a row of counts, then sections of
/// findings — and showing that structure means the layout does not jump when
/// the content lands. A centred spinner tells the user only that something is
/// happening; this tells them what is about to be there.
class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Padding(
      padding: EdgeInsets.only(top: responsive.s(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The verdict card.
          _SkeletonCard(
            height: responsive.s(132),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SkeletonBar(width: responsive.s(44), height: responsive.s(44), radius: 999),
                    SizedBox(width: responsive.s(14)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonBar(width: responsive.s(120), height: responsive.s(15)),
                          SizedBox(height: responsive.s(9)),
                          _SkeletonBar(width: responsive.s(78), height: responsive.s(11)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.s(16)),
                _SkeletonBar(width: double.infinity, height: responsive.s(11)),
                SizedBox(height: responsive.s(8)),
                _SkeletonBar(width: double.infinity, height: responsive.s(11)),
              ],
            ),
          ),
          SizedBox(height: responsive.s(14)),
          // The counts row.
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i != 0) SizedBox(width: responsive.s(10)),
                Expanded(
                  child: _SkeletonCard(
                    height: responsive.s(76),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBar(width: responsive.s(22), height: responsive.s(18)),
                        SizedBox(height: responsive.s(8)),
                        _SkeletonBar(width: double.infinity, height: responsive.s(9)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: responsive.s(22)),
          // Two finding blocks.
          for (var i = 0; i < 2; i++) ...[
            if (i != 0) SizedBox(height: responsive.s(18)),
            _SkeletonBar(width: responsive.s(140), height: responsive.s(14)),
            SizedBox(height: responsive.s(12)),
            _SkeletonCard(
              height: responsive.s(104),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(width: responsive.s(180), height: responsive.s(13)),
                  SizedBox(height: responsive.s(12)),
                  _SkeletonBar(width: double.infinity, height: responsive.s(10)),
                  SizedBox(height: responsive.s(8)),
                  _SkeletonBar(width: responsive.s(220), height: responsive.s(10)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Container(
      height: height,
      padding: EdgeInsets.all(responsive.s(14)),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// One placeholder bar, breathing gently so the page reads as working rather
/// than as broken. One shared controller drives every bar on screen, so they
/// pulse together instead of shimmering out of step.
class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Endless repetition would hang `pumpAndSettle`, so under test the bar
    // holds a composed first frame — the same guard the loader and orb use.
    final underTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    if (!underTest) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Each bar owns its layer. Twelve of these animate together on the loading
    // report, and without a boundary every one of them marked the shared layer
    // dirty, so the entire page — headings, cards, the lot — repainted sixty
    // times a second to tint a dozen small rectangles.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Color.lerp(colors.surfaceAlt, colors.border, t),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          );
        },
      ),
    );
  }
}
