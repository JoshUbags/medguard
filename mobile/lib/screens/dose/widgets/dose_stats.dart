part of '../dose_screen.dart';

/// The stats block for whatever period the calendar is showing.
///
/// A single adherence ring carries the headline figure; four tiles beneath it
/// break that figure into the counts it came from, so the percentage is never
/// an unexplained number. The streak and the week-on-week trend sit under both.
class _DoseStatsPanel extends StatelessWidget {
  const _DoseStatsPanel({
    required this.range,
    required this.board,
    required this.loading,
    required this.selectedDay,
    required this.today,
  });

  final DoseRange range;
  final DoseBoard? board;
  final bool loading;
  final DateTime selectedDay;
  final DateTime today;

  String get _caption {
    switch (range) {
      case DoseRange.day:
        if (selectedDay == today) return 'Today so far';
        return '${_monthNames[selectedDay.month - 1].substring(0, 3)} '
            '${selectedDay.day}';
      case DoseRange.week:
        return 'This week';
      case DoseRange.month:
        return _monthNames[selectedDay.month - 1];
    }
  }

  /// What the figures cover.
  ///
  /// Day view deliberately loads the whole surrounding week (the strip above
  /// the timeline needs every neighbouring day), so the board's range summary
  /// spans seven days. Reporting that under a "Today so far" caption would be
  /// plainly wrong, so Day view recomputes its totals from the selected day's
  /// calendar stat alone; Week and Month use the range summary as loaded.
  (AdherenceSummary, int) _figures() {
    final data = board;
    if (data == null) return (AdherenceSummary.empty, 0);

    if (range == DoseRange.day) {
      final stat = data.dayStats[DoseService.dayKey(selectedDay)];
      if (stat == null) return (AdherenceSummary.empty, 0);
      return (
        AdherenceSummary(
          scheduled: stat.due - stat.pending,
          taken: stat.adhered,
          late: 0,
          skipped: stat.skipped,
          missed: stat.missed,
        ),
        stat.pending,
      );
    }

    var pending = 0;
    for (final stat in data.dayStats.values) {
      pending += stat.pending;
    }
    return (data.rangeSummary, pending);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final (summary, pending) = _figures();
    final hasData = summary.scheduled > 0;

    return _DoseSection(
      title: 'Adherence',
      caption: _caption,
      trailing: _StreakChip(
        streak: board?.streak ?? 0,
        trend: board?.trend ?? 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AdherenceRing(
                percent: hasData ? summary.percent : 0,
                loading: loading,
                hasData: hasData,
              ),
              SizedBox(width: responsive.s(18)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasData
                          ? '${summary.adhered} of ${summary.scheduled} doses on time'
                          : loading
                          ? 'Reading your schedule…'
                          : 'No doses were due in this period',
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(13.4),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: responsive.s(6)),
                    Text(
                      _supportingLine(summary, pending),
                      style: GoogleFonts.inter(
                        color: colors.inkSoft,
                        fontSize: responsive.font(12.2),
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(16)),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Taken',
                  value: '${summary.taken + summary.late}',
                  tone: colors.accent,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Expanded(
                child: _StatTile(
                  label: 'Missed',
                  value: '${summary.missed}',
                  tone: colors.danger,
                  icon: Icons.cancel_rounded,
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Expanded(
                child: _StatTile(
                  label: 'Skipped',
                  value: '${summary.skipped}',
                  tone: colors.warning,
                  icon: Icons.remove_circle_rounded,
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Expanded(
                child: _StatTile(
                  label: 'Upcoming',
                  value: '$pending',
                  tone: colors.inkMute,
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _supportingLine(AdherenceSummary summary, int pending) {
    if (summary.scheduled == 0) {
      return pending > 0
          ? '$pending ${pending == 1 ? 'dose is' : 'doses are'} still ahead in this period.'
          : 'Add a schedule and adherence starts tracking automatically.';
    }
    if (summary.missed == 0 && summary.skipped == 0) {
      return 'Every dose that came due was logged. Keep it going.';
    }
    final parts = <String>[];
    if (summary.missed > 0) parts.add('${summary.missed} missed');
    if (summary.skipped > 0) parts.add('${summary.skipped} skipped');
    return '${parts.join(' · ')}${pending > 0 ? ' · $pending still ahead' : ''}.';
  }
}

/// The headline adherence ring: a thick teal arc over a faint track with the
/// live percentage centred, animating up from zero whenever the figure changes.
class _AdherenceRing extends StatelessWidget {
  const _AdherenceRing({
    required this.percent,
    required this.loading,
    required this.hasData,
  });

  final double percent;
  final bool loading;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final size = responsive.s(88).clamp(78.0, 104.0).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              value: value,
              track: colors.border,
              // The ring earns its colour: strong adherence reads teal,
              // slipping adherence amber, poor adherence ruby.
              arc: !hasData
                  ? colors.border
                  : value >= 0.85
                  ? colors.accent
                  : value >= 0.6
                  ? colors.warning
                  : colors.danger,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasData ? '${(value * 100).round()}%' : '—',
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(21),
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: responsive.s(2)),
                  Text(
                    loading ? 'loading' : 'on time',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(9.8),
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.arc,
  });

  final double value;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.10;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );

    canvas.drawCircle(
      size.center(Offset.zero),
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.arc != arc ||
      oldDelegate.track != track;
}

/// One count tile beneath the ring.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: responsive.s(10),
        horizontal: responsive.s(6),
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: responsive.icon(15)),
          SizedBox(height: responsive.s(6)),
          Text(
            value,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(15),
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          SizedBox(height: responsive.s(3)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.inter(
                color: colors.inkMute,
                fontSize: responsive.font(10.4),
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The streak chip: a flame, the day count, and a trend arrow comparing this
/// week to last. Reads "0 days" honestly rather than hiding when there's no
/// streak yet — a visible zero is what makes the first day feel like progress.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak, required this.trend});

  final int streak;
  final int trend;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final active = streak > 0;
    final tone = active ? colors.warning : colors.inkMute;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(10),
        vertical: responsive.s(7),
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.local_fire_department_rounded
                : Icons.local_fire_department_outlined,
            color: tone,
            size: responsive.icon(14),
          ),
          SizedBox(width: responsive.s(5)),
          Text(
            '$streak ${streak == 1 ? 'day' : 'days'}',
            style: GoogleFonts.inter(
              color: tone,
              fontSize: responsive.font(11.6),
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          if (trend != 0) ...[
            SizedBox(width: responsive.s(5)),
            Icon(
              trend > 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: trend > 0 ? colors.accent : colors.danger,
              size: responsive.icon(14),
            ),
          ],
        ],
      ),
    );
  }
}

/// Week/Month view's list: how each medicine is doing over the period, worst
/// first, so the one that needs attention is the first thing read.
class _DoseDrugBreakdown extends StatelessWidget {
  const _DoseDrugBreakdown({
    required this.rows,
    required this.loading,
    required this.range,
    required this.onAddSchedule,
    required this.onEditSchedule,
  });

  final List<DrugAdherence> rows;
  final bool loading;
  final DoseRange range;
  final VoidCallback onAddSchedule;

  /// Tapping a medicine opens its schedule for editing.
  final ValueChanged<DoseSchedule> onEditSchedule;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final scored = rows
        .where((row) => row.summary.scheduled > 0)
        .toList(growable: false);

    return _DoseSection(
      title: 'By medicine',
      caption: range == DoseRange.week
          ? 'This week, lowest first'
          : 'This month, lowest first',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scored.isEmpty)
            _DoseEmptyNote(
              icon: Icons.local_pharmacy_rounded,
              title: loading
                  ? 'Loading your medicines'
                  : 'Nothing to compare yet',
              body: loading
                  ? 'One moment while your schedule is read.'
                  : 'Once doses come due, each medicine gets its own adherence '
                        'bar here so you can see which one slips.',
              actionLabel: loading ? null : 'Add a schedule',
              onAction: loading ? null : onAddSchedule,
            )
          else
            for (var i = 0; i < scored.length; i++) ...[
              _DrugAdherenceRow(
                row: scored[i],
                onTap: () => onEditSchedule(scored[i].schedule),
              ),
              if (i != scored.length - 1) SizedBox(height: responsive.s(12)),
            ],
        ],
      ),
    );
  }
}

class _DrugAdherenceRow extends StatelessWidget {
  const _DrugAdherenceRow({required this.row, required this.onTap});

  final DrugAdherence row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final percent = row.summary.percent.clamp(0.0, 1.0);
    final tone = percent >= 0.85
        ? colors.accent
        : percent >= 0.6
        ? colors.warning
        : colors.danger;

    return Pressable(
      onTap: onTap,
      pressScale: 0.98,
      semanticLabel:
          '${row.schedule.drugName}, ${row.summary.percentRounded} percent '
          'adherence. Edit schedule.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The medicine's colour chip, the same one the timeline uses, so
              // a row here is instantly matched to its doses above.
              _MedicineChip(
                drugId: row.schedule.drugId,
                name: row.schedule.drugName,
                size: responsive.s(26).clamp(24.0, 30.0).toDouble(),
              ),
              SizedBox(width: responsive.s(9)),
              Expanded(
                child: Text(
                  row.schedule.drugName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.2),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Text(
                '${row.summary.adhered}/${row.summary.scheduled}',
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(11.6),
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Text(
                '${row.summary.percentRounded}%',
                style: GoogleFonts.inter(
                  color: tone,
                  fontSize: responsive.font(12.4),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(7)),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: percent),
              duration: const Duration(milliseconds: 620),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: responsive.s(6).clamp(5.0, 8.0).toDouble(),
                backgroundColor: colors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
