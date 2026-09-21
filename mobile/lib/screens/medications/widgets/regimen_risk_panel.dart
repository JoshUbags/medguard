part of '../medications_screen.dart';

/// A section on this page: heading and caption on the canvas, content in a
/// card — the app's layout grammar, matching [SectionBlock] and Dose's
/// `_DoseSection`.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.caption,
    this.action,
    this.onAction,
    this.card = true,
  });

  final String title;
  final String? caption;
  final String? action;
  final VoidCallback? onAction;
  final bool card;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          subtitle: caption,
          action: action,
          onAction: onAction,
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        if (card)
          SurfaceCard(padding: EdgeInsets.all(responsive.s(18)), child: child)
        else
          child,
      ],
    );
  }
}


/// One line under the header saying what the page does.
///
/// Every section below states its own status in its header chip, which answers
/// "what is this block". None of them answered "what is this page", and a
/// screen whose first content is a row of medicines gives a first-time user no
/// idea why they are looking at it.
class _PagePill extends StatelessWidget {
  const _PagePill({
    required this.medicineCount,
    required this.reviewed,
    required this.running,
  });

  final int medicineCount;
  final bool reviewed;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    final (IconData icon, Color tone, String text) = running
        ? (
            Icons.hourglass_top_rounded,
            colors.inkMute,
            'Checking every pair of your medicines against a bundled clinical '
                'database, your allergies and your foods.',
          )
        : reviewed
        ? (
            Icons.verified_user_rounded,
            colors.accent,
            'Reviewed. These findings are live across the app until you change '
                'the medicines being checked.',
          )
        : medicineCount < 2
        ? (
            Icons.info_outline_rounded,
            colors.inkMute,
            'MedGuard checks your medicines against each other, your allergies '
                'and the foods you have listed. It needs at least two.',
          )
        : (
            Icons.fact_check_outlined,
            colors.accent,
            'Choose which medicines to check, then review them together — '
                'nothing is assessed until you do.',
          );

    return Container(
      padding: EdgeInsets.all(responsive.s(13)),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: colors.isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(responsive.radius(16)),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: responsive.icon(16), color: tone),
          SizedBox(width: responsive.s(10)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The regimen rail — what will be checked, and the button that checks it
// ─────────────────────────────────────────────────────────────────────────────

/// The medicines, as a horizontal rail of pills, with the review action beneath.
///
/// The rail runs edge to edge and fades out at both ends rather than stopping at
/// a margin — the same treatment as Home's section-pill row. A wrapped grid of
/// chips inside a card made eight medicines look like a form to fill in; a rail
/// that visibly continues past the edge reads as a list you scroll, and keeps
/// the section a fixed height however many medicines there are.
///
/// There is no icon in front of a medicine name. A pill icon beside the word
/// "Ibuprofen" tells the reader nothing they did not already know, and twelve of
/// them in a row is just visual noise; the tick when a pill is selected is the
/// only glyph that carries information here.
class _RegimenRail extends StatelessWidget {
  const _RegimenRail({
    required this.medications,
    required this.selected,
    required this.loading,
    required this.running,
    required this.onToggle,
    required this.onAll,
    required this.onNone,
    required this.onAdd,
    required this.onRemove,
  });

  final List<UserMedication> medications;
  final Set<int> selected;
  final bool loading;
  final bool running;
  final ValueChanged<int> onToggle;
  final VoidCallback onAll;
  final VoidCallback onNone;
  final VoidCallback onAdd;
  final ValueChanged<UserMedication> onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final all = medications.isNotEmpty && selected.length == medications.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
          child: SectionHeader(
            title: 'Your medicines',
            subtitle: medications.isEmpty
                ? 'Nothing saved yet.'
                : 'Tap to include or leave out. Long-press to remove one '
                      'from your regimen.',
            action: medications.isEmpty
                ? 'None saved'
                : (all ? 'Clear all' : 'Select all'),
            onAction: medications.isEmpty ? null : (all ? onNone : onAll),
          ),
        ),
        SizedBox(height: sectionHeaderGap(responsive)),

        if (loading)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
            child: _RailSkeleton(),
          )
        else if (medications.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
            child: _EmptyRegimen(onAdd: onAdd),
          )
        else ...[
          _FadingRail(
            inset: responsive.pageX,
            children: [
              for (final medication in medications)
                _MedicinePill(
                  medication: medication,
                  included: selected.contains(medication.drugId),
                  onTap: () => onToggle(medication.drugId),
                  onRemove: () => onRemove(medication),
                ),
              _AddPill(onTap: onAdd),
            ],
          ),
        ],
      ],
    );
  }
}

/// A horizontally scrolling row that dissolves at both ends instead of being
/// clipped by the page margin.
///
/// The mask is the point. A rail that stops dead at the inset looks like it has
/// run out of content; one that fades tells the eye there is more in that
/// direction. Lifted from Home's pill row so the two read as the same
/// mechanism.
class _FadingRail extends StatelessWidget {
  const _FadingRail({required this.children, required this.inset});

  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // The fade runs across roughly the page inset, so content dissolves exactly
    // as it reaches the margin the rest of the page respects.
    final fade = (inset / 2).clamp(10.0, 28.0);

    return SizedBox(
      height: responsive.s(42).clamp(38.0, 50.0).toDouble(),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final w = bounds.width <= 0 ? 1.0 : bounds.width;
          final edge = (fade / w).clamp(0.0, 0.4);
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0.0, edge, 1 - edge, 1.0],
          ).createShader(bounds);
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: inset),
          itemCount: children.length,
          separatorBuilder: (_, _) => SizedBox(width: responsive.s(8)),
          itemBuilder: (_, i) => Center(child: children[i]),
        ),
      ),
    );
  }
}

/// One medicine on the rail. No leading icon — see [_RegimenRail].
class _MedicinePill extends StatelessWidget {
  const _MedicinePill({
    required this.medication,
    required this.included,
    required this.onTap,
    required this.onRemove,
  });

  final UserMedication medication;
  final bool included;
  final VoidCallback onTap;

  /// Long-press removes the medicine from the regimen entirely.
  ///
  /// On the pill rather than behind a separate edit mode: the rail is where
  /// the user already is when they notice a medicine should not be there, and
  /// a destructive action guarded by a long-press plus a confirmation sheet is
  /// hard enough to trigger by accident.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onRemove,
      child: Pressable(
      onTap: onTap,
      pressScale: 0.95,
      selected: included,
      semanticLabel:
          '${medication.displayName}, ${included ? 'included' : 'left out'}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(9),
        ),
        decoration: BoxDecoration(
          color: included ? colors.accentAlpha(0.12) : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: included ? colors.accentAlpha(0.38) : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The tick is the ONLY glyph, and it appears only when it means
            // something. An excluded pill is defined by the absence of it.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: included
                  ? Padding(
                      padding: EdgeInsets.only(right: responsive.s(6)),
                      child: Icon(
                        Icons.check_rounded,
                        size: responsive.icon(14),
                        color: colors.accent,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Text(
              medication.displayName,
              style: GoogleFonts.inter(
                color: included ? colors.ink : colors.inkSoft,
                fontSize: responsive.font(13),
                fontWeight: included ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  const _AddPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      semanticLabel: 'Add a medicine',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(9),
        ),
        decoration: BoxDecoration(
          color: colors.accentAlpha(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accentAlpha(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: responsive.icon(15),
              color: colors.accent,
            ),
            SizedBox(width: responsive.s(5)),
            Text(
              'Add',
              style: GoogleFonts.inter(
                color: colors.accent,
                fontSize: responsive.font(13),
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return SizedBox(
      height: responsive.s(42).clamp(38.0, 50.0).toDouble(),
      child: Row(
        children: [
          for (final width in const [96.0, 74.0, 110.0])
            Padding(
              padding: EdgeInsets.only(right: responsive.s(8)),
              child: Container(
                width: responsive.s(width),
                height: responsive.s(36),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The review button, and the one line of state that belongs with it.
///
/// This is the page's only primary action, so it sits directly under the
/// medicines it acts on rather than at the bottom of a long scroll. The old
/// "sign off" section down there asked the user to confirm something they had
/// already been shown — a second acknowledgement of an acknowledgement.
/// "just now" / "4 minutes ago" — the one place the page states when the
/// findings on screen were produced.
String _timeAgo(DateTime? at) {
  if (at == null) return 'just now';
  final seconds = DateTime.now().difference(at).inSeconds;
  if (seconds < 60) return 'just now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  return 'earlier';
}

class _EmptyRegimen extends StatelessWidget {
  const _EmptyRegimen({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No medicines saved yet',
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(15),
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          SizedBox(height: responsive.s(6)),
          Text(
            'MedGuard checks every pair of medicines you take against a '
            'bundled clinical database, your allergies, and the foods you '
            'have listed. It needs at least two to start.',
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.8),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          SizedBox(height: responsive.s(16)),
          AppButton(
            label: 'Add a medicine',
            icon: Icons.add_rounded,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The verdict
// ─────────────────────────────────────────────────────────────────────────────

/// The regimen-risk verdict — the same [RegimenRiskCard] Home renders, in full.
///
/// Before a review has been run this shows the gauge's own "review pending"
/// state: the meter is there, inactive, saying plainly that it has nothing to
/// report yet. That is the honest thing to draw. The alternative — hiding the
/// section until there is a result — teaches the user that the page changes
/// shape unpredictably, and hides the very control they need to find.
///
/// There is deliberately no composite-score card beneath it any more. A 0–100
/// number on a banded track was a second, competing way of saying what the meter
/// already says, in units nobody outside this codebase can interpret: "your
/// regimen is 23" answers no question a patient has.
class _RiskSection extends StatelessWidget {
  const _RiskSection({
    required this.medications,
    required this.report,
    required this.running,
    required this.failed,
    required this.checkable,
    required this.reviewedAt,
    required this.onReview,
    required this.onOpenReport,
  });

  final List<UserMedication> medications;
  final SafetyReport? report;
  final bool running;
  final bool failed;
  final bool checkable;
  final DateTime? reviewedAt;
  final VoidCallback onReview;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final data = report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Regimen risk',
          subtitle: data == null
              ? 'Your medicines weighed as one system, once you review them.'
              : 'Your medicines weighed as one system, not pair by pair.',
          action: data == null ? 'Not yet run' : 'Reviewed',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),

        RegimenRiskCard(
          medications: medications,
          loading: running,
          // The gate: the gauge only speaks once results exist for exactly this
          // selection. `regimenReviewed` is this screen's own notion of that,
          // not the service's, because the user may be reviewing a subset.
          regimenReviewed: data != null,
          actionLabel: !checkable
              ? 'Review'
              : data == null
              ? 'Review ${medications.length} medicines'
              : 'Open the full report',
          actionBusy: running,
          onReview: checkable ? onReview : () {},
          onLearnMore: onOpenReport,
          analyzeRegimenRisk: (_) async => data ?? const SafetyReport.empty(),
        ),
        if (data != null) ...[
          SizedBox(height: responsive.s(10)),
          Center(
            child: Text(
              'Reviewed ${_timeAgo(reviewedAt)}',
              style: GoogleFonts.inter(
                color: context.colors.inkMute,
                fontSize: responsive.font(11.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],

        if (failed) ...[
          SizedBox(height: responsive.s(12)),
          _InlineNotice(
            icon: Icons.error_outline_rounded,
            tone: context.colors.danger,
            text: 'The check did not finish. Your medicines are unchanged.',
            actionLabel: 'Retry',
            onAction: onReview,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The four checks
// ─────────────────────────────────────────────────────────────────────────────

/// The four safety checks and what each one found.
///
/// Every check is listed whether or not it fired, and whether or not the review
/// has run. A screen that only shows what went wrong leaves the user unable to
/// tell "we checked and it was clean" from "we never checked" — and for a safety
/// tool that distinction is the product. Before a review, every row reads "—",
/// which says exactly that: not yet known.
class _SafetyAxes extends StatelessWidget {
  const _SafetyAxes({
    required this.report,
    required this.running,
    required this.checkable,
  });

  final SafetyReport? report;
  final bool running;
  final bool checkable;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final data = report;

    final axes = <({IconData icon, String label, String blurb, Color tone, int? count})>[
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Drug interactions',
        blurb: 'Every pair of the chosen medicines, against each other',
        tone: colors.danger,
        count: data?.drugInteractions.length,
      ),
      (
        icon: Icons.coronavirus_rounded,
        label: 'Allergy conflicts',
        blurb: 'Your recorded allergies, by drug and by class',
        tone: colors.danger,
        count: data?.allergyHits.length,
      ),
      (
        icon: Icons.content_copy_rounded,
        label: 'Duplicate therapy',
        blurb: 'Two medicines doing the same therapeutic job',
        tone: colors.warning,
        count: data?.duplicateTherapies.length,
      ),
      (
        icon: Icons.restaurant_rounded,
        label: 'Food and drink',
        blurb: 'What you eat, against what you take',
        tone: colors.accent,
        count: data?.foodInteractions.length,
      ),
    ];

    final flagged = axes.where((a) => (a.count ?? 0) > 0).length;

    return _Section(
      title: 'What gets checked',
      caption: data == null
          ? 'Four checks run over your selection when you review.'
          : flagged == 0
          ? 'All four checks ran and came back clean.'
          : '$flagged of ${axes.length} checks found something.',
      child: Column(
        children: [
          for (var i = 0; i < axes.length; i++) ...[
            if (i > 0) CardDivider(indent: responsive.s(46)),
            _AxisRow(
              icon: axes[i].icon,
              label: axes[i].label,
              blurb: axes[i].blurb,
              tone: axes[i].tone,
              count: axes[i].count,
              pending: running || data == null,
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.icon,
    required this.label,
    required this.blurb,
    required this.tone,
    required this.count,
    required this.pending,
  });

  final IconData icon;
  final String label;
  final String blurb;
  final Color tone;
  final int? count;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final resolved = !pending && count != null;
    final clear = resolved && count == 0;
    final glyphTone = !resolved || clear ? colors.inkMute : tone;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: responsive.s(6)),
      child: Row(
        children: [
          Container(
            width: responsive.s(34),
            height: responsive.s(34),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: glyphTone.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(responsive.radius(11)),
            ),
            child: Icon(icon, size: responsive.icon(17), color: glyphTone),
          ),
          SizedBox(width: responsive.s(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.4),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: responsive.s(2)),
                Text(
                  blurb,
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(11.6),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: responsive.s(10)),
          // "Clear" as a word, not a zero: a column of zeroes reads as failure
          // at a glance, where a column of "Clear" reads as the reassurance it
          // actually is.
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(10),
              vertical: responsive.s(5),
            ),
            decoration: BoxDecoration(
              color: !resolved
                  ? colors.surfaceAlt
                  : clear
                  ? colors.accentAlpha(0.10)
                  : tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              !resolved ? '—' : (clear ? 'Clear' : '$count'),
              style: GoogleFonts.inter(
                color: !resolved
                    ? colors.inkMute
                    : clear
                    ? colors.accent
                    : tone,
                fontSize: responsive.font(11.6),
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Findings
// ─────────────────────────────────────────────────────────────────────────────

/// The most serious findings, listed here and explained in full on the report.
///
/// Capped at three. This page answers "is there a problem, and roughly what";
/// the report answers "here is every finding with its mechanism, evidence and
/// next step". Listing everything twice would make the report pointless and this
/// page endless.
class _FindingsSection extends StatelessWidget {
  const _FindingsSection({
    required this.report,
    required this.running,
    required this.checkable,
    required this.onOpenReport,
  });

  final SafetyReport? report;
  final bool running;
  final bool checkable;
  final VoidCallback onOpenReport;

  static const int _limit = 3;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final data = report;

    if (data == null) {
      return _Section(
        title: 'Findings',
        caption: 'What the checks turn up.',
        child: _InlineNotice(
          icon: Icons.inbox_rounded,
          tone: colors.inkMute,
          text: running
              ? 'Working through every pair…'
              : checkable
              ? 'Run the review and anything found appears here.'
              : 'Choose at least two medicines, then run the review.',
        ),
      );
    }

    final interactions = [...data.drugInteractions]
      ..sort((a, b) => b.severityLevel.rank.compareTo(a.severityLevel.rank));
    final shown = interactions.take(_limit).toList(growable: false);
    final more = interactions.length - shown.length;

    return _Section(
      title: 'Findings',
      caption: interactions.isEmpty
          ? 'No interactions between the medicines you chose.'
          : '${interactions.length} '
                '${interactions.length == 1 ? 'interaction' : 'interactions'}, '
                'most serious first.',
      action: interactions.isEmpty ? null : 'Full report',
      onAction: interactions.isEmpty ? null : onOpenReport,
      card: interactions.isEmpty,
      child: interactions.isEmpty
          ? _InlineNotice(
              icon: Icons.check_circle_rounded,
              tone: colors.accent,
              text:
                  'Nothing in this selection conflicts. Change the medicines '
                  'and MedGuard will ask you to review again.',
            )
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) SizedBox(height: responsive.s(10)),
                  _FindingRow(interaction: shown[i], onTap: onOpenReport),
                ],
                if (more > 0) ...[
                  SizedBox(height: responsive.s(12)),
                  AppButton(
                    label: 'See all ${interactions.length} findings',
                    icon: Icons.arrow_forward_rounded,
                    variant: AppButtonVariant.tonal,
                    onTap: onOpenReport,
                  ),
                ],
              ],
            ),
    );
  }
}

/// One interaction, at a glance: the pair, the tier, and what it does.
class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.interaction, required this.onTap});

  final InteractionResult interaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final level = interaction.riskLevel;
    final tone = switch (level) {
      RiskLevel.high => colors.danger,
      RiskLevel.moderate => colors.warning,
      RiskLevel.low => colors.inkMute,
    };

    return SurfaceCard(
      onTap: onTap,
      padding: EdgeInsets.all(responsive.s(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${interaction.drugAName} + ${interaction.drugBName}',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.6),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.s(9),
                  vertical: responsive.s(4),
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  level.label,
                  style: GoogleFonts.inter(
                    color: tone,
                    fontSize: responsive.font(10.8),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          if (interaction.effect != null &&
              interaction.effect!.trim().isNotEmpty) ...[
            SizedBox(height: responsive.s(7)),
            Text(
              interaction.effect!,
              // Three lines, not one with an ellipsis: a truncated clinical
              // effect is worse than none, because the reader cannot tell
              // whether the important half was the half that got cut.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metabolism
// ─────────────────────────────────────────────────────────────────────────────

/// Where two or more medicines meet at the same liver enzyme.
///
/// The section with no equivalent anywhere else in the app, and the reason this
/// page is worth visiting rather than reading a summary. A pairwise list says
/// "A and B interact". This says *why*: A blocks the enzyme that clears B, so B
/// builds up. Once a user has seen that once, every future warning about that
/// pair makes sense.
class _MetabolicPathways extends StatelessWidget {
  const _MetabolicPathways({required this.cascades});

  final List<CypCascade> cascades;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return _Section(
      title: 'Metabolic pathways',
      caption:
          'Where your medicines compete for the same liver enzyme. One '
          'blocking another\'s exit route is how levels drift.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cascades.length; i++) ...[
            if (i > 0) const CardDivider(),
            _CascadeRow(cascade: cascades[i]),
          ],
          SizedBox(height: responsive.s(14)),
          _InlineNotice(
            icon: Icons.info_outline_rounded,
            tone: context.colors.inkMute,
            text:
                'A shared pathway is not a warning on its own — many people '
                'take these combinations safely at the right doses. It is '
                'context for a pharmacist, not a reason to stop anything.',
          ),
        ],
      ),
    );
  }
}

class _CascadeRow extends StatelessWidget {
  const _CascadeRow({required this.cascade});

  final CypCascade cascade;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final modulators = [...cascade.inhibitors, ...cascade.inducers];
    final blocking = cascade.inhibitors.isNotEmpty;
    final tone = blocking ? colors.danger : colors.warning;

    return Column(
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
                color: colors.warningAlpha(0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                cascade.shortName,
                style: GoogleFonts.inter(
                  color: colors.warning,
                  fontSize: responsive.font(11.4),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            SizedBox(width: responsive.s(9)),
            Expanded(
              child: Text(
                cascade.enzymeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(11.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: responsive.s(12)),
        // The mechanism drawn as the flow it is: what acts, on what, with what
        // effect. Reading it top to bottom IS the explanation.
        _FlowNode(
          names: modulators,
          caption: '${blocking ? 'slows' : 'speeds up'} ${cascade.shortName}',
          tone: tone,
          leading: Icons.trending_flat_rounded,
        ),
        Padding(
          padding: EdgeInsets.only(left: responsive.s(13)),
          child: Container(
            width: 2,
            height: responsive.s(16),
            color: tone.withValues(alpha: 0.30),
          ),
        ),
        _FlowNode(
          names: cascade.substrates,
          caption: blocking
              ? 'may build up to higher levels than intended'
              : 'may be cleared faster, weakening the effect',
          tone: colors.inkMute,
          leading: Icons.subdirectory_arrow_right_rounded,
        ),
      ],
    );
  }
}

class _FlowNode extends StatelessWidget {
  const _FlowNode({
    required this.names,
    required this.caption,
    required this.tone,
    required this.leading,
  });

  final List<String> names;
  final String caption;
  final Color tone;
  final IconData leading;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: responsive.s(26),
          height: responsive.s(26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.withValues(alpha: 0.12),
          ),
          child: Icon(leading, size: responsive.icon(14), color: tone),
        ),
        SizedBox(width: responsive.s(10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                names.join(', '),
                style: GoogleFonts.inter(
                  color: colors.ink,
                  fontSize: responsive.font(13),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              SizedBox(height: responsive.s(2)),
              Text(
                caption,
                style: GoogleFonts.inter(
                  color: colors.inkSoft,
                  fontSize: responsive.font(12),
                  fontWeight: FontWeight.w500,
                  height: 1.4,
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
// Shared bits
// ─────────────────────────────────────────────────────────────────────────────

/// A one-line note inside a card — the page's single "here is a fact about the
/// state you are in" treatment, so notices never each invent their own look.
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.tone,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color tone;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final label = actionLabel;

    return Container(
      padding: EdgeInsets.all(responsive.s(13)),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: responsive.icon(16), color: tone),
          SizedBox(width: responsive.s(10)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.2),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
          if (label != null) ...[
            SizedBox(width: responsive.s(10)),
            Pressable(
              onTap: onAction,
              pressScale: 0.95,
              semanticLabel: label,
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: colors.accent,
                  fontSize: responsive.font(12.2),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
