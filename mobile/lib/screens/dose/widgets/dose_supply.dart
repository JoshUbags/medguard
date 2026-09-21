part of '../dose_screen.dart';

/// Timing intelligence: the doses whose clock times collide for interacting
/// medicines, plus how adherence holds up across the parts of the day.
///
/// This is the panel that turns raw logs into advice — "you miss your evening
/// dose" and "these two shouldn't be taken together" — rather than just
/// reporting numbers back.
class _DoseTimingPanel extends StatelessWidget {
  const _DoseTimingPanel({
    required this.conflicts,
    required this.byPartOfDay,
    this.reviewPending = false,
  });

  final List<DoseStaggerSuggestion> conflicts;
  final List<PartOfDayAdherence> byPartOfDay;

  /// The regimen's interaction review has not been completed, so no conflict
  /// analysis has been run. The panel says so plainly rather than showing
  /// "no conflicts", which would read as a clean bill of health nobody earned.
  final bool reviewPending;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final scored = byPartOfDay
        .where((part) => part.due > 0)
        .toList(growable: false);

    return _DoseSection(
      title: 'Timing',
      caption: 'Conflicts and time-of-day patterns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Conflicts ──────────────────────────────────────────────────────
          if (reviewPending)
            const _TimingPendingRow()
          else if (conflicts.isEmpty)
            const _TimingClearRow(
              text: 'No interacting medicines share a scheduled time.',
            )
          else
            for (var i = 0; i < conflicts.length; i++) ...[
              _ConflictRow(suggestion: conflicts[i]),
              if (i != conflicts.length - 1) SizedBox(height: responsive.s(10)),
            ],

          if (scored.isNotEmpty) ...[
            SizedBox(height: responsive.s(16)),
            Divider(color: colors.border, height: 1),
            SizedBox(height: responsive.s(14)),
            Text(
              'ADHERENCE BY TIME OF DAY',
              style: GoogleFonts.inter(
                color: colors.inkMute,
                fontSize: responsive.font(10.5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            SizedBox(height: responsive.s(12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final part in scored) ...[
                  Expanded(child: _PartOfDayBar(part: part)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Timing conflicts are gated behind the interaction review, so before it is
/// done the panel reports the honest state — "not checked yet" — with the route
/// to fix it, rather than an unearned all-clear.
class _TimingPendingRow extends StatelessWidget {
  const _TimingPendingRow();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.fact_check_rounded,
          color: colors.warning,
          size: responsive.icon(18),
        ),
        SizedBox(width: responsive.s(10)),
        Expanded(
          child: Text(
            'Timing conflicts are checked once you complete the interaction '
            'review on the Interactions tab.',
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.6),
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimingClearRow extends StatelessWidget {
  const _TimingClearRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Row(
      children: [
        Icon(
          Icons.verified_rounded,
          color: colors.accent,
          size: responsive.icon(18),
        ),
        SizedBox(width: responsive.s(10)),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.6),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.suggestion});

  final DoseStaggerSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(responsive.s(12).clamp(11.0, 14.0).toDouble()),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(responsive.radius(14)),
        border: Border.all(color: colors.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule_rounded,
            color: colors.warning,
            size: responsive.icon(18),
          ),
          SizedBox(width: responsive.s(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${suggestion.first.drugName} + ${suggestion.second.drugName} '
                  'at ${DoseService.formatSlotForDisplay(suggestion.sharedSlot)}',
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(12.8),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: responsive.s(4)),
                Text(
                  suggestion.message,
                  style: GoogleFonts.inter(
                    color: colors.inkSoft,
                    fontSize: responsive.font(11.8),
                    fontWeight: FontWeight.w400,
                    height: 1.4,
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

class _PartOfDayBar extends StatelessWidget {
  const _PartOfDayBar({required this.part});

  final PartOfDayAdherence part;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final percent = part.percent.clamp(0.0, 1.0);
    final tone = percent >= 0.85
        ? colors.accent
        : percent >= 0.6
        ? colors.warning
        : colors.danger;
    final maxHeight = responsive.s(56).clamp(48.0, 66.0).toDouble();

    return Column(
      children: [
        Text(
          '${part.percentRounded}%',
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(11.4),
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        SizedBox(height: responsive.s(6)),
        SizedBox(
          height: maxHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent),
                duration: const Duration(milliseconds: 640),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  final barHeight = (maxHeight * value).clamp(4.0, maxHeight);
                  return Container(
                    width: responsive.s(18).clamp(16.0, 24.0).toDouble(),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: responsive.s(6)),
        Text(
          part.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(9.8),
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// The supply / refill panel: days of supply left per medicine, urgent refills
/// surfaced first, and the estimated run-out date. All of it comes from
/// [DoseService]'s existing depletion math, which nothing was surfacing before.
class _DoseSupplyPanel extends StatelessWidget {
  const _DoseSupplyPanel({
    required this.refills,
    required this.hasSchedules,
    required this.onAddSchedule,
  });

  final List<RefillStatus> refills;
  final bool hasSchedules;
  final VoidCallback onAddSchedule;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final tracked = refills
        .where((r) => r.depletionDate != null)
        .toList(growable: false);
    final soon = tracked.where((r) => r.daysRemaining <= 7).length;

    return _DoseSection(
      title: 'Supply & refills',
      caption: tracked.isEmpty
          ? 'Track how long each supply lasts'
          : soon == 0
          ? 'All supplies comfortable'
          : '$soon ${soon == 1 ? 'refill' : 'refills'} due soon',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tracked.isEmpty)
            _DoseEmptyNote(
              icon: Icons.inventory_2_rounded,
              title: hasSchedules
                  ? 'No supply recorded yet'
                  : 'Nothing to track yet',
              body: hasSchedules
                  ? 'Add a quantity to a medicine (how many tablets you were '
                        'dispensed) and MedGuard estimates when it runs out and '
                        'when to reorder.'
                  : 'Once you add a medicine with a quantity, its days-of-supply '
                        'and refill date show up here.',
              actionLabel: hasSchedules ? null : 'Add a schedule',
              onAction: hasSchedules ? null : onAddSchedule,
            )
          else
            for (var i = 0; i < tracked.length; i++) ...[
              _RefillRow(status: tracked[i]),
              if (i != tracked.length - 1) SizedBox(height: responsive.s(10)),
            ],
        ],
      ),
    );
  }
}

class _RefillRow extends StatelessWidget {
  const _RefillRow({required this.status});

  final RefillStatus status;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final days = status.daysRemaining;
    final tone = status.overdue || status.urgent
        ? colors.danger
        : days <= 7
        ? colors.warning
        : colors.accent;

    final headline = status.overdue
        ? 'Overdue by ${-days} ${(-days) == 1 ? 'day' : 'days'}'
        : days == 0
        ? 'Refill today'
        : '$days ${days == 1 ? 'day' : 'days'} of supply';

    // A 30-day reference window so the bar reads as "how full is the bottle".
    final fill = (days.clamp(0, 30)) / 30;

    return Container(
      padding: EdgeInsets.all(responsive.s(12).clamp(11.0, 14.0).toDouble()),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: responsive.s(34).clamp(32.0, 40.0).toDouble(),
                height: responsive.s(34).clamp(32.0, 40.0).toDouble(),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  status.overdue
                      ? Icons.error_rounded
                      : Icons.local_pharmacy_rounded,
                  color: tone,
                  size: responsive.icon(17),
                ),
              ),
              SizedBox(width: responsive.s(11)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.schedule.drugName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(13.4),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(2)),
                    Text(
                      status.depletionDate == null
                          ? headline
                          : '$headline · runs out ${_shortDate(status.depletionDate!)}',
                      style: GoogleFonts.inter(
                        color: colors.inkSoft,
                        fontSize: responsive.font(11.6),
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(10)),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fill.toDouble()),
              duration: const Duration(milliseconds: 620),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: responsive.s(6).clamp(5.0, 8.0).toDouble(),
                backgroundColor: colors.border,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
