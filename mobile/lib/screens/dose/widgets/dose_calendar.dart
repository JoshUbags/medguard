part of '../dose_screen.dart';

/// The calendar. One widget, three shapes — a day strip, a week row, or a month
/// grid — so switching range reshapes the same surface instead of swapping in a
/// visually unrelated control.
///
/// Every cell is painted from [DoseDayStat], so a day's adherence is legible
/// straight off the calendar: a filled ring for a fully-adhered day, a partial
/// arc where doses were missed, a hollow ring for days still pending, and
/// nothing at all for days with no scheduled dose.
class _DoseCalendar extends StatelessWidget {
  const _DoseCalendar({
    required this.range,
    required this.selectedDay,
    required this.visibleMonth,
    required this.today,
    required this.stats,
    required this.onSelectDay,
    required this.onShift,
    required this.onToday,
  });

  final DoseRange range;
  final DateTime selectedDay;
  final DateTime visibleMonth;
  final DateTime today;
  final Map<String, DoseDayStat> stats;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<int> onShift;
  final VoidCallback onToday;

  String get _title {
    switch (range) {
      case DoseRange.day:
        if (selectedDay == today) return 'Today';
        if (selectedDay == today.add(const Duration(days: 1))) {
          return 'Tomorrow';
        }
        if (selectedDay == today.subtract(const Duration(days: 1))) {
          return 'Yesterday';
        }
        return '${_monthNames[selectedDay.month - 1]} ${selectedDay.day}';
      case DoseRange.week:
        final start = selectedDay.subtract(
          Duration(days: selectedDay.weekday % 7),
        );
        final end = start.add(const Duration(days: 6));
        return start.month == end.month
            ? '${_shortDate(start)} – ${end.day}'
            : '${_shortDate(start)} – ${_shortDate(end)}';
      case DoseRange.month:
        return '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}';
    }
  }

  bool get _showTodayShortcut {
    switch (range) {
      case DoseRange.day:
      case DoseRange.week:
        return selectedDay != today;
      case DoseRange.month:
        return visibleMonth.year != today.year ||
            visibleMonth.month != today.month;
    }
  }

  /// What the caption above the calendar says the grid is for. It changes with
  /// the range because the calendar's JOB changes: in Day view it picks the day
  /// the timeline shows, in Week and Month it also summarises the period.
  String get _caption => switch (range) {
    DoseRange.day => 'Tap a day to see what is due on it',
    DoseRange.week => 'Tap a day to see its doses; the ring shows adherence',
    DoseRange.month => 'Tap any date to see what was due, and what happened',
  };

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return _DoseSection(
      title: 'Calendar',
      caption: _caption,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalendarChrome(
            title: _title,
            showToday: _showTodayShortcut,
            onPrevious: () => onShift(-1),
            onNext: () => onShift(1),
            onToday: onToday,
          ),
          SizedBox(height: responsive.s(14)),
          if (range == DoseRange.month)
            _MonthGrid(
              visibleMonth: visibleMonth,
              selectedDay: selectedDay,
              today: today,
              stats: stats,
              onSelectDay: onSelectDay,
            )
          else
            _WeekRow(
              selectedDay: selectedDay,
              today: today,
              stats: stats,
              onSelectDay: onSelectDay,
              expanded: range == DoseRange.week,
            ),
          SizedBox(height: responsive.s(12)),
          const _CalendarLegend(),
        ],
      ),
    );
  }
}

/// The title row: period label, a Today shortcut when the user has navigated
/// away, and the two paging arrows.
class _CalendarChrome extends StatelessWidget {
  const _CalendarChrome({
    required this.title,
    required this.showToday,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String title;
  final bool showToday;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(15.5),
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.1,
            ),
          ),
        ),
        if (showToday) ...[
          Pressable(
            onTap: onToday,
            pressScale: 0.94,
            semanticLabel: 'Jump to today',
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.s(10),
                vertical: responsive.s(6),
              ),
              decoration: BoxDecoration(
                color: colors.accentAlpha(0.10),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'Today',
                style: GoogleFonts.inter(
                  color: colors.accent,
                  fontSize: responsive.font(11.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(width: responsive.s(8)),
        ],
        _CalendarArrow(
          icon: Icons.chevron_left_rounded,
          semanticLabel: 'Previous period',
          onTap: onPrevious,
        ),
        SizedBox(width: responsive.s(6)),
        _CalendarArrow(
          icon: Icons.chevron_right_rounded,
          semanticLabel: 'Next period',
          onTap: onNext,
        ),
      ],
    );
  }
}

class _CalendarArrow extends StatelessWidget {
  const _CalendarArrow({
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
    final size = responsive.s(30).clamp(28.0, 36.0).toDouble();
    return Pressable(
      onTap: onTap,
      pressScale: 0.88,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceAlt,
          border: Border.all(color: colors.border),
        ),
        child: Icon(icon, color: colors.inkSoft, size: size * 0.62),
      ),
    );
  }
}

/// The seven-day row used by both Day and Week view. In Day view it is the
/// picker for the timeline below; in Week view it is the week being summarised.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.selectedDay,
    required this.today,
    required this.stats,
    required this.onSelectDay,
    required this.expanded,
  });

  final DateTime selectedDay;
  final DateTime today;
  final Map<String, DoseDayStat> stats;
  final ValueChanged<DateTime> onSelectDay;

  /// Week view gives each cell more height for its dose count.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final start = selectedDay.subtract(Duration(days: selectedDay.weekday % 7));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayCell(
              day: start.add(Duration(days: i)),
              selectedDay: selectedDay,
              today: today,
              stats: stats,
              onSelect: onSelectDay,
              showWeekday: true,
              tall: expanded,
            ),
          ),
      ],
    );
  }
}

/// The month grid — six rows of seven, with leading/trailing blanks so the
/// weekday columns line up.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.today,
    required this.stats,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final DateTime today;
  final Map<String, DoseDayStat> stats;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    // weekday: Mon=1 … Sun=7; the grid starts on Sunday.
    final leading = first.weekday % 7;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final initial in _weekdayInitials)
              Expanded(
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(10.5),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: responsive.s(8)),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final index = row * 7 + col - leading + 1;
                      if (index < 1 || index > daysInMonth) {
                        return SizedBox(height: responsive.s(42));
                      }
                      return _DayCell(
                        day: DateTime(
                          visibleMonth.year,
                          visibleMonth.month,
                          index,
                        ),
                        selectedDay: selectedDay,
                        today: today,
                        stats: stats,
                        onSelect: onSelectDay,
                        showWeekday: false,
                        tall: false,
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// One calendar day.
///
/// The ring around the number IS the data: a full teal ring means every dose
/// that day was taken, a partial arc shows how much of the day was adhered to,
/// a ruby arc marks missed doses, and a faint dashed-looking track means doses
/// are scheduled but not yet due. Days with nothing scheduled carry no ring at
/// all, so a glance across the month shows exactly where the regimen is dense.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selectedDay,
    required this.today,
    required this.stats,
    required this.onSelect,
    required this.showWeekday,
    required this.tall,
  });

  final DateTime day;
  final DateTime selectedDay;
  final DateTime today;
  final Map<String, DoseDayStat> stats;
  final ValueChanged<DateTime> onSelect;
  final bool showWeekday;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final stat = stats[DoseService.dayKey(day)];
    final selected = day == selectedDay;
    final isToday = day == today;
    final future = day.isAfter(today);
    final ringSize = responsive.s(tall ? 34 : 30).clamp(26.0, 38.0).toDouble();

    return Pressable(
      onTap: () => onSelect(day),
      pressScale: 0.92,
      semanticLabel: _semantics(stat),
      selected: selected,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: responsive.s(1.5)),
        padding: EdgeInsets.symmetric(vertical: responsive.s(5)),
        decoration: BoxDecoration(
          color: selected ? colors.accentAlpha(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(13)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWeekday) ...[
              Text(
                _weekdayInitials[day.weekday % 7],
                style: GoogleFonts.inter(
                  color: selected ? colors.accent : colors.inkMute,
                  fontSize: responsive.font(10.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: responsive.s(6)),
            ],
            SizedBox(
              width: ringSize,
              height: ringSize,
              child: CustomPaint(
                painter: _DayRingPainter(
                  stat: stat,
                  future: future,
                  track: colors.border,
                  adhered: colors.accent,
                  missed: colors.danger,
                  skipped: colors.warning,
                ),
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: GoogleFonts.inter(
                      color: selected
                          ? colors.accent
                          : isToday
                          ? colors.ink
                          : future
                          ? colors.inkMute
                          : colors.inkSoft,
                      fontSize: responsive.font(12.6),
                      fontWeight: selected || isToday
                          ? FontWeight.w700
                          : FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            if (isToday) ...[
              SizedBox(height: responsive.s(3)),
              Container(
                width: responsive.s(4).clamp(3.0, 5.0).toDouble(),
                height: responsive.s(4).clamp(3.0, 5.0).toDouble(),
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ] else
              SizedBox(height: responsive.s(3) + 4),
            if (tall) ...[
              SizedBox(height: responsive.s(4)),
              Text(
                stat == null ? '—' : '${stat.adhered}/${stat.due}',
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(10),
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _semantics(DoseDayStat? stat) {
    final label = '${_monthNames[day.month - 1]} ${day.day}';
    if (stat == null) return '$label, no doses scheduled';
    return '$label, ${stat.adhered} of ${stat.due} doses taken';
  }
}

/// Paints a day cell's outcome ring. Segments run clockwise from the top:
/// adhered (teal), skipped (amber), missed (ruby), then the untouched track.
class _DayRingPainter extends CustomPainter {
  const _DayRingPainter({
    required this.stat,
    required this.future,
    required this.track,
    required this.adhered,
    required this.missed,
    required this.skipped,
  });

  final DoseDayStat? stat;
  final bool future;
  final Color track;
  final Color adhered;
  final Color missed;
  final Color skipped;

  @override
  void paint(Canvas canvas, Size size) {
    final data = stat;
    if (data == null || data.due == 0) return;

    final stroke = size.width * 0.085;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );

    // The full track — faint for a day whose doses are still ahead, so a
    // pending day never looks like a failed one.
    canvas.drawCircle(
      size.center(Offset.zero),
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = future ? track.withValues(alpha: 0.55) : track,
    );

    const start = -math.pi / 2;
    final sweepPer = (2 * math.pi) / data.due;
    var cursor = start;

    void arc(int count, Color color) {
      if (count <= 0) return;
      canvas.drawArc(
        rect,
        cursor,
        sweepPer * count,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      cursor += sweepPer * count;
    }

    arc(data.adhered, adhered);
    arc(data.skipped, skipped);
    arc(data.missed, missed);
  }

  @override
  bool shouldRepaint(covariant _DayRingPainter oldDelegate) =>
      oldDelegate.stat?.adhered != stat?.adhered ||
      oldDelegate.stat?.missed != stat?.missed ||
      oldDelegate.stat?.skipped != stat?.skipped ||
      oldDelegate.stat?.due != stat?.due ||
      oldDelegate.future != future ||
      oldDelegate.track != track;
}

/// Explains what the ring colours mean — without it the calendar is pretty but
/// unreadable.
class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: responsive.s(7).clamp(6.0, 8.0).toDouble(),
          height: responsive.s(7).clamp(6.0, 8.0).toDouble(),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: responsive.s(5)),
        Text(
          label,
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(10.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: responsive.s(14),
      runSpacing: responsive.s(6),
      children: [
        dot(colors.accent, 'Taken'),
        dot(colors.warning, 'Skipped'),
        dot(colors.danger, 'Missed'),
        dot(colors.border, 'Scheduled'),
      ],
    );
  }
}
