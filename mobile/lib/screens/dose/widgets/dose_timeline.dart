part of '../dose_screen.dart';

/// The selected day's doses, laid out as a vertical time rail grouped by part
/// of day. Each dose can be taken, skipped, or — once logged — undone, and the
/// whole day can be settled in one tap.
///
/// The rail is what makes the day readable at a glance: a continuous line with
/// a node per dose, the node filled once the dose has an outcome, so how much
/// of the day is done is legible without reading a single word.
class _DoseTimeline extends StatelessWidget {
  const _DoseTimeline({
    required this.occurrences,
    required this.loading,
    required this.selectedDay,
    required this.now,
    required this.hasSchedules,
    required this.onLog,
    required this.onClear,
    required this.onMarkAllTaken,
    required this.onAddSchedule,
    required this.onEditSchedule,
    required this.onManageSchedules,
  });

  final List<DoseOccurrence> occurrences;
  final bool loading;
  final DateTime selectedDay;
  final DateTime now;
  final bool hasSchedules;
  final void Function(DoseOccurrence, DoseLogStatus) onLog;
  final ValueChanged<DoseOccurrence> onClear;
  final VoidCallback onMarkAllTaken;
  final VoidCallback onAddSchedule;

  /// Long-pressing a dose opens its schedule for editing.
  final ValueChanged<DoseSchedule> onEditSchedule;

  /// The explicit route into schedule management, for when long-press is not
  /// discovered.
  final VoidCallback onManageSchedules;

  /// The doses grouped into Morning / Afternoon / Evening / Night, in order,
  /// dropping any group with nothing in it.
  List<({String label, List<DoseOccurrence> doses})> get _groups {
    final buckets = <String, List<DoseOccurrence>>{};
    for (final occ in occurrences) {
      final label = DoseService.partOfDayLabel(occ.scheduledTime.hour);
      buckets.putIfAbsent(label, () => []).add(occ);
    }
    const order = ['Morning', 'Afternoon', 'Evening', 'Night'];
    return [
      for (final label in order)
        if (buckets[label] != null && buckets[label]!.isNotEmpty)
          (label: label, doses: buckets[label]!),
    ];
  }

  int get _outstanding => occurrences
      .where((occ) => !occ.isLogged && !occ.scheduledTime.isAfter(now))
      .length;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final groups = _groups;
    final logged = occurrences.where((occ) => occ.isLogged).length;

    // Deliberately NOT wrapped in a _DoseCard. The doses are themselves cards
    // on the rail, and nesting them inside another panel is what made this the
    // most compressed part of the page — a card, inside a card, inside a page
    // margin. The section heading now sits on the page like any other heading.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DoseSectionHeader(
          title: 'Schedule',
          caption: occurrences.isEmpty
              ? 'No doses on this day'
              : '$logged of ${occurrences.length} logged',
          trailing: _outstanding == 0
              ? null
              : _MarkAllButton(count: _outstanding, onTap: onMarkAllTaken),
        ),
        SizedBox(height: responsive.s(16)),
        if (occurrences.isEmpty)
          _DoseCard(
            child: _DoseEmptyNote(
              icon: hasSchedules
                  ? Icons.event_available_rounded
                  : Icons.alarm_add_rounded,
              title: loading
                  ? 'Loading this day'
                  : hasSchedules
                  ? 'Nothing scheduled for this day'
                  : 'No dose schedules yet',
              body: loading
                  ? 'One moment while your schedule is read.'
                  : hasSchedules
                  ? 'Your medicines are not due on this date. Pick another day '
                        'on the calendar above.'
                  : 'Add a medicine with a time and MedGuard will build your '
                        'daily timeline, remind you, and track every dose here.',
              actionLabel: loading || hasSchedules ? null : 'Add a medication',
              onAction: loading || hasSchedules ? null : onAddSchedule,
            ),
          )
        else
          for (var g = 0; g < groups.length; g++) ...[
            _TimelineGroup(
              label: groups[g].label,
              doses: groups[g].doses,
              now: now,
              isLastGroup: g == groups.length - 1,
              onLog: onLog,
              onClear: onClear,
              onEditSchedule: onEditSchedule,
            ),
            if (g != groups.length - 1) SizedBox(height: responsive.s(10)),
          ],
        if (hasSchedules) ...[
          SizedBox(height: responsive.s(8)),
          _ManageSchedulesLink(onTap: onManageSchedules),
        ],
      ],
    );
  }
}

/// The quiet route into editing an existing schedule. Long-pressing a dose does
/// the same thing, but a long-press is not discoverable on its own — this is.
class _ManageSchedulesLink extends StatelessWidget {
  const _ManageSchedulesLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      semanticLabel: 'Manage dose schedules',
      child: Container(
        padding: EdgeInsets.symmetric(vertical: responsive.s(9)),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              color: colors.inkMute,
              size: responsive.icon(15),
            ),
            SizedBox(width: responsive.s(6)),
            Text(
              'Manage schedules',
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkAllButton extends StatelessWidget {
  const _MarkAllButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.94,
      semanticLabel: 'Mark $count outstanding doses taken',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(11),
          vertical: responsive.s(7),
        ),
        decoration: BoxDecoration(
          color: colors.accentAlpha(0.10),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all_rounded,
              color: colors.accent,
              size: responsive.icon(14),
            ),
            SizedBox(width: responsive.s(5)),
            Text(
              'Take all',
              style: GoogleFonts.inter(
                color: colors.accent,
                fontSize: responsive.font(11.6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One part-of-day section: its heading, then its doses on the shared rail.
class _TimelineGroup extends StatelessWidget {
  const _TimelineGroup({
    required this.label,
    required this.doses,
    required this.now,
    required this.isLastGroup,
    required this.onLog,
    required this.onClear,
    required this.onEditSchedule,
  });

  final String label;
  final List<DoseOccurrence> doses;
  final DateTime now;
  final bool isLastGroup;
  final void Function(DoseOccurrence, DoseLogStatus) onLog;
  final ValueChanged<DoseOccurrence> onClear;
  final ValueChanged<DoseSchedule> onEditSchedule;

  static IconData _icon(String label) => switch (label) {
    'Morning' => Icons.wb_twilight_rounded,
    'Afternoon' => Icons.light_mode_rounded,
    'Evening' => Icons.wb_incandescent_rounded,
    _ => Icons.bedtime_rounded,
  };

  /// Each part of the day carries its own warmth — sunrise amber through to
  /// night indigo. It is the cheapest possible way to make a long schedule
  /// legible at a glance, and it stops the page reading as one white slab.
  static Color _tone(String label) => switch (label) {
    'Morning' => const Color(0xFFE8963C),
    'Afternoon' => const Color(0xFF3FAE6A),
    'Evening' => const Color(0xFF7A6FF0),
    _ => const Color(0xFF4C63AC),
  };

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final tone = _tone(label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: responsive.s(10)),
          child: Row(
            children: [
              // A tinted capsule rather than a bare caption: the period header
              // now has enough presence to divide the day properly.
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.s(10),
                  vertical: responsive.s(6),
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: tone.withValues(alpha: 0.20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(label), color: tone, size: responsive.icon(13)),
                    SizedBox(width: responsive.s(6)),
                    Text(
                      label.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: tone,
                        fontSize: responsive.font(10.2),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.s(10)),
              Expanded(
                child: Container(
                  height: 1,
                  color: tone.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < doses.length; i++)
          _TimelineRow(
            occurrence: doses[i],
            now: now,
            // The rail runs on through every row except the very last one on
            // the whole timeline.
            continues: i != doses.length - 1 || !isLastGroup,
            onLog: onLog,
            onClear: onClear,
            onEditSchedule: onEditSchedule,
          ),
      ],
    );
  }
}

/// One dose on the rail: the node and its connecting line, the time, the
/// medicine, and the action controls.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.occurrence,
    required this.now,
    required this.continues,
    required this.onLog,
    required this.onClear,
    required this.onEditSchedule,
  });

  final DoseOccurrence occurrence;
  final DateTime now;
  final bool continues;
  final void Function(DoseOccurrence, DoseLogStatus) onLog;
  final ValueChanged<DoseOccurrence> onClear;
  final ValueChanged<DoseSchedule> onEditSchedule;

  bool get _future => occurrence.scheduledTime.isAfter(now);
  bool get _overdue => !_future && !occurrence.isLogged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final status = occurrence.status;
    final tone = switch (status) {
      DoseLogStatus.taken || DoseLogStatus.late => colors.accent,
      DoseLogStatus.skipped => colors.warning,
      DoseLogStatus.missed => colors.danger,
      null => _overdue ? colors.danger : colors.inkMute,
    };
    final nodeSize = responsive.s(13).clamp(11.0, 16.0).toDouble();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── The time gutter: the clock time is the thing the eye scans a
          // schedule for, so it gets its own column rather than being buried
          // in the card's body text. ───────────────────────────────────────
          SizedBox(
            width: responsive.s(50).clamp(46.0, 60.0).toDouble(),
            child: Padding(
              padding: EdgeInsets.only(top: responsive.s(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _clock(occurrence.scheduledTime),
                    style: GoogleFonts.inter(
                      color: occurrence.isLogged ? colors.inkMute : colors.ink,
                      fontSize: responsive.font(13.6),
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.2,
                      // Tabular figures keep the column edge straight down the
                      // list instead of wobbling with each digit's width.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: responsive.s(2)),
                  Text(
                    occurrence.scheduledTime.hour < 12 ? 'AM' : 'PM',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(9.6),
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: responsive.s(10)),
          // ── The rail ───────────────────────────────────────────────────────
          SizedBox(
            width: responsive.s(16).clamp(14.0, 20.0).toDouble(),
            child: Column(
              children: [
                SizedBox(height: responsive.s(15)),
                Container(
                  width: nodeSize,
                  height: nodeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: occurrence.isLogged ? tone : colors.surface,
                    border: Border.all(
                      color: occurrence.isLogged
                          ? tone
                          : tone.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                ),
                if (continues)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: EdgeInsets.symmetric(vertical: responsive.s(3)),
                      color: colors.border,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: responsive.s(10)),
          // ── The dose ───────────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: responsive.s(12)),
              child: GestureDetector(
                // Long-press edits the schedule this dose came from. It sits on
                // a GestureDetector rather than the Pressable wrapper because
                // the row's own Take/Skip buttons must keep winning ordinary
                // taps — only the press-and-hold is claimed here.
                behavior: HitTestBehavior.deferToChild,
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  onEditSchedule(occurrence.schedule);
                },
                child: Container(
                  padding: EdgeInsets.all(
                    responsive.s(15).clamp(13.0, 18.0).toDouble(),
                  ),
                  decoration: BoxDecoration(
                    color: occurrence.isLogged
                        ? colors.surfaceAlt
                        : colors.surface,
                    borderRadius: BorderRadius.circular(responsive.radius(18)),
                    border: Border.all(
                      color: _overdue
                          ? colors.danger.withValues(alpha: 0.28)
                          : colors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The medicine's own colour chip — the same colour it
                          // carries everywhere else on the page, so a regimen
                          // becomes recognisable rather than a grey list.
                          _MedicineChip(
                            drugId: occurrence.schedule.drugId,
                            name: occurrence.schedule.drugName,
                            size: responsive.s(36).clamp(32.0, 42.0).toDouble(),
                          ),
                          SizedBox(width: responsive.s(11)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  occurrence.schedule.drugName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: colors.ink,
                                    fontSize: responsive.font(14.6),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                  ),
                                ),
                                // The strength is optional and the time now
                                // lives in the gutter, so this line appears
                                // only when there is genuinely something to say.
                                if (occurrence.schedule.doseLabel
                                    case final dose?) ...[
                                  SizedBox(height: responsive.s(4)),
                                  _DoseFact(
                                    icon: Icons.local_pharmacy_rounded,
                                    label: dose,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: responsive.s(8)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatusPill(
                                status: status,
                                overdue: _overdue,
                                future: _future,
                                tone: tone,
                              ),
                              SizedBox(height: responsive.s(6)),
                              // A visible route to edit / reschedule. The
                              // long-press still works, but a hidden gesture
                              // cannot be the only way to change a dose time.
                              _RowIconAction(
                                icon: Icons.edit_calendar_rounded,
                                semanticLabel:
                                    'Edit or reschedule '
                                    '${occurrence.schedule.drugName}',
                                onTap: () =>
                                    onEditSchedule(occurrence.schedule),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.s(14)),
                      if (occurrence.isLogged)
                        _UndoRow(onUndo: () => onClear(occurrence))
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _DoseAction(
                                label: 'Take',
                                icon: Icons.check_rounded,
                                tone: colors.accent,
                                filled: true,
                                onTap: () => onLog(
                                  occurrence,
                                  // A dose logged well after its slot is
                                  // recorded as late, not on time — adherence
                                  // has to mean something.
                                  _lateBy(occurrence, now)
                                      ? DoseLogStatus.late
                                      : DoseLogStatus.taken,
                                ),
                              ),
                            ),
                            SizedBox(width: responsive.s(9)),
                            Expanded(
                              child: _DoseAction(
                                label: 'Skip',
                                icon: Icons.remove_rounded,
                                tone: colors.warning,
                                filled: false,
                                onTap: () =>
                                    onLog(occurrence, DoseLogStatus.skipped),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// More than an hour past its slot counts as late.
  static bool _lateBy(DoseOccurrence occurrence, DateTime now) =>
      now.difference(occurrence.scheduledTime).inMinutes > 60;

  /// `8:00` — the 12-hour clock time without its meridiem, which the gutter
  /// prints separately underneath.
  static String _clock(DateTime time) {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour12:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// One fact on a dose row — a glyph and its value, sized to its content so a
/// [Wrap] can flow it onto the next line rather than clipping it.
class _DoseFact extends StatelessWidget {
  const _DoseFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: colors.inkMute, size: responsive.icon(13)),
        SizedBox(width: responsive.s(5)),
        Text(
          label,
          style: GoogleFonts.inter(
            color: colors.inkSoft,
            fontSize: responsive.font(12.2),
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// A small, quiet glyph action inside a dose row — the visible counterpart to
/// a gesture, sized to a real 40pt touch target despite its small mark.
class _RowIconAction extends StatelessWidget {
  const _RowIconAction({
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
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.88,
      semanticLabel: semanticLabel,
      child: Container(
        width: responsive.s(30).clamp(28.0, 34.0).toDouble(),
        height: responsive.s(30).clamp(28.0, 34.0).toDouble(),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: Icon(icon, color: colors.inkMute, size: responsive.icon(16)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.overdue,
    required this.future,
    required this.tone,
  });

  final DoseLogStatus? status;
  final bool overdue;
  final bool future;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final (String label, IconData icon) = switch (status) {
      DoseLogStatus.taken => ('Taken', Icons.check_circle_rounded),
      DoseLogStatus.late => ('Late', Icons.history_rounded),
      DoseLogStatus.skipped => ('Skipped', Icons.remove_circle_rounded),
      DoseLogStatus.missed => ('Missed', Icons.cancel_rounded),
      null =>
        overdue
            ? ('Overdue', Icons.error_rounded)
            : future
            ? ('Upcoming', Icons.schedule_rounded)
            : ('Due now', Icons.notifications_active_rounded),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(8),
        vertical: responsive.s(5),
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: responsive.icon(12)),
          SizedBox(width: responsive.s(4)),
          Text(
            label,
            style: GoogleFonts.inter(
              color: tone,
              fontSize: responsive.font(10.6),
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseAction extends StatelessWidget {
  const _DoseAction({
    required this.label,
    required this.icon,
    required this.tone,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      semanticLabel: label,
      child: Container(
        height: responsive.s(36).clamp(34.0, 42.0).toDouble(),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? tone : tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(responsive.radius(11)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: filled ? colors.surface : tone,
              size: responsive.icon(15),
            ),
            SizedBox(width: responsive.s(5)),
            Text(
              label,
              style: GoogleFonts.inter(
                color: filled ? colors.surface : tone,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoRow extends StatelessWidget {
  const _UndoRow({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: onUndo,
        pressScale: 0.95,
        semanticLabel: 'Undo this dose log',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.s(2)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.undo_rounded,
                color: colors.inkMute,
                size: responsive.icon(14),
              ),
              SizedBox(width: responsive.s(5)),
              Text(
                'Undo',
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
