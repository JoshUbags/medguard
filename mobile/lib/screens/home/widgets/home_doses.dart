// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

class _DosesSection extends StatefulWidget {
  const _DosesSection({
    required this.onOpenDose,
    required this.doseService,
    required this.userId,
    required this.now,
    this.summary,
  });

  final VoidCallback onOpenDose;
  final DoseService doseService;
  final String userId;
  final DateTime Function() now;

  /// Live weekly adherence; null when nothing has been scheduled or logged
  /// yet (the strip is simply omitted — no sample numbers). The expanded
  /// version of this data lives on the Dose page.
  final DoseSummary? summary;

  @override
  State<_DosesSection> createState() => _DosesSectionState();
}

class _DosesSectionState extends State<_DosesSection> {
  // Real schedules for this user — empty until the first load resolves, and
  // refreshed whenever a dose schedule is added, edited, or removed.
  List<DoseSchedule> _schedules = const [];
  bool _loaded = false;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.now());
    widget.doseService.revision.addListener(_loadSchedules);
    _loadSchedules();
  }

  @override
  void dispose() {
    widget.doseService.revision.removeListener(_loadSchedules);
    super.dispose();
  }

  Future<void> _loadSchedules() async {
    try {
      final schedules = await widget.doseService.getSchedules(widget.userId);
      if (!mounted) return;
      setState(() {
        _schedules = schedules;
        _loaded = true;
      });
    } catch (_) {
      // No writable store yet (e.g. fresh install / unit tests) — treat as an
      // empty schedule rather than failing the whole dashboard.
      if (!mounted) return;
      setState(() {
        _schedules = const [];
        _loaded = true;
      });
    }
  }

  DateTime _dateOnly(DateTime v) => DateTime(v.year, v.month, v.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime get _today => _dateOnly(widget.now());
  bool get _selectedIsToday => _isSameDay(_selectedDate, _today);

  bool _hasDoseOn(DateTime date) =>
      _schedules.any((s) => s.slotsOn(date).isNotEmpty);

  void _selectDate(DateTime date) {
    final normalized = _dateOnly(date);
    if (_isSameDay(normalized, _selectedDate)) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDate = normalized);
  }

  /// Expands the user's active schedules into the concrete doses due on [date],
  /// sorted by time of day, as lightweight preview items for the home card.
  List<_DosePreviewItem> _dosesForDate(DateTime date) {
    final rows = <({String slot, _DosePreviewItem item})>[];
    final ordered = [..._schedules]
      ..sort(
        (a, b) => a.drugName.toLowerCase().compareTo(b.drugName.toLowerCase()),
      );
    var colorIndex = 0;
    for (final schedule in ordered) {
      for (final slot in schedule.slotsOn(date)) {
        rows.add((
          slot: slot,
          item: _DosePreviewItem(
            id: '${schedule.id}-$slot',
            time: _formatDoseSlot(slot),
            name: '${schedule.drugName} ${schedule.doseLabel ?? ''}'.trim(),
            detail: _doseSlotBucket(slot),
            badge: '',
            icon: Icons.local_pharmacy_rounded,
            color: _doseAccentColors[colorIndex++ % _doseAccentColors.length],
          ),
        ));
      }
    }
    rows.sort((a, b) => a.slot.compareTo(b.slot));
    return rows.map((row) => row.item).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final hasSchedules = _schedules.isNotEmpty;
    final doses = _dosesForDate(_selectedDate);
    final subtitle = !_loaded
        ? 'Loading your dose schedule'
        : hasSchedules
        ? 'Tap a day to view doses.'
        : 'Set a reminder to see doses.';
    final innerPad = responsive.s(16).clamp(14.0, 18.0).toDouble();

    // A white card crowned by a dark, premium header band (the deep app shade)
    // that carries the live adherence read in white; the interactive day-picker
    // and the selected day's agenda live on the clean white body below.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(
          title: 'Dose Schedule',
          // When there are schedules, both the header "See all" and the quiet
          // in-card "View full schedule" link open the Dose page. When empty,
          // the panel's own "Add a reminder" button is the single action.
          action: hasSchedules ? 'See all' : 'Set up below',
          subtitle: subtitle,
          onAction: hasSchedules ? widget.onOpenDose : null,
        ),
        SizedBox(height: responsive.s(14).clamp(12.0, 16.0).toDouble()),
        Container(
          key: const ValueKey('home-doses-section-panel'),
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(responsive.radius(24)),
            border: Border.all(color: context.colors.border),
            boxShadow: _homeCardShadow(responsive),
          ),
          child: Column(
            key: const ValueKey('home-doses-section'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Premium header band — the app's deep brand teal (a flat,
              // rich shade, no gradient/gloss); the live adherence read sits on
              // it in white at ~7:1 contrast. On-brand and premium rather than a
              // neutral dark block.
              Container(
                width: double.infinity,
                // The app's deep brand teal — a darker, richer premium shade
                // than the primary, so the band reads as a considered dark
                // surface while staying unmistakably on-brand.
                color: MedGuardPalette.tealDeep,
                padding: EdgeInsets.all(innerPad),
                child: _DoseDarkHeader(summary: widget.summary),
              ),
              // ── White body: the day-picker + the selected day's plan ────────
              Padding(
                padding: EdgeInsets.all(innerPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DoseWeekCalendar(
                      today: _today,
                      selectedDate: _selectedDate,
                      hasDoseOn: _hasDoseOn,
                      onDaySelected: _selectDate,
                    ),
                    SizedBox(height: responsive.s(16).clamp(14.0, 18.0)),
                    Container(height: 1, color: context.colors.inkAlpha(0.06)),
                    SizedBox(height: responsive.s(16).clamp(14.0, 18.0)),
                    // ── Setup prompt, rest-day state, or the day's doses ──
                    if (_loaded && !hasSchedules)
                      _DoseSetupEmpty(onAdd: widget.onOpenDose)
                    else ...[
                      _DoseSelectedDayLabel(
                        date: _selectedDate,
                        isToday: _selectedIsToday,
                        doseCount: doses.length,
                      ),
                      SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
                      // Next dose — the day's first dose, or a rest-day note.
                      if (doses.isEmpty)
                        const _DoseDayEmpty()
                      else ...[
                        _NextDoseHero(
                          item: doses.first,
                          badge: _selectedIsToday ? null : 'First up',
                        ),
                        // Upcoming — the selected day's later doses.
                        if (doses.length > 1) ...[
                          SizedBox(height: responsive.s(16).clamp(14.0, 18.0)),
                          Text(
                            _selectedIsToday ? 'Later today' : 'Also scheduled',
                            style: GoogleFonts.inter(
                              color: context.colors.inkMute,
                              fontSize: responsive.font(11),
                              fontWeight: FontWeight.w700,
                              height: 1,
                              letterSpacing: 0.6,
                            ),
                          ),
                          SizedBox(height: responsive.s(12)),
                          for (var i = 1; i < doses.length; i++)
                            _UpcomingDoseRow(
                              key: ValueKey('home-dose-preview-${doses[i].id}'),
                              item: doses[i],
                              isLast: i == doses.length - 1,
                            ),
                        ],
                      ],
                    ],
                    // A quiet, non-dominant path to the full Dose Schedule —
                    // a natural extension of the card rather than a separate
                    // feature. Shown only once there are schedules to view.
                    if (hasSchedules) ...[
                      SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
                      Container(
                        height: 1,
                        color: context.colors.inkAlpha(0.06),
                      ),
                      _DoseScheduleLink(onTap: widget.onOpenDose),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet "View full schedule" link at the foot of the dose card — a light
/// path to the full Dose Schedule screen that stays visually subordinate to the
/// card's content.
class _DoseScheduleLink extends StatelessWidget {
  const _DoseScheduleLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Pressable(
      key: const ValueKey('home-dose-view-all-link'),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: responsive.s(10).clamp(9.0, 12.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'View full schedule',
              style: GoogleFonts.inter(
                color: context.colors.accent,
                fontSize: responsive.font(12.6),
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            SizedBox(width: responsive.s(5)),
            Icon(
              Icons.arrow_forward_rounded,
              size: responsive.icon(15),
              color: context.colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark premium header band atop the dose card — a white adherence ring (or
/// a calendar mark when there's no data yet), the live on-time read, and an
/// optional streak chip, all on the deep app shade.
class _DoseDarkHeader extends StatelessWidget {
  const _DoseDarkHeader({required this.summary});

  final DoseSummary? summary;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final s = summary;
    final hasData = s != null;
    final ring = responsive.s(48).clamp(44.0, 54.0).toDouble();
    final title = hasData ? 'On time this week' : 'Stay on schedule';
    final caption = hasData
        ? '${s.dosesLogged} of ${s.dosesScheduled} doses logged'
        : 'Your medicines, day by day';

    return Row(
      children: [
        if (hasData)
          _DoseAdherenceRing(percent: s.percentRounded, size: ring, dark: true)
        else
          Container(
            width: ring,
            height: ring,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MedGuardPalette.whiteAlpha(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: MedGuardPalette.whiteAlpha(0.24)),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              color: MedGuardPalette.pureWhite,
              size: responsive.icon(22),
            ),
          ),
        SizedBox(width: responsive.s(13).clamp(11.0, 15.0)),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                style: GoogleFonts.inter(
                  color: MedGuardPalette.pureWhite,
                  fontSize: responsive.font(15.5),
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: responsive.s(4)),
              Text(
                caption,
                maxLines: 1,
                style: GoogleFonts.inter(
                  color: MedGuardPalette.whiteAlpha(0.78),
                  fontSize: responsive.font(12.2),
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (hasData && s.streak >= 2) ...[
          SizedBox(width: responsive.s(8)),
          _DoseStreakChip(streak: s.streak),
        ],
      ],
    );
  }
}

/// The adherence header that sits in white directly on the teal dose card — a
/// solid white progress ring, the live "on-time" figure, an optional streak
/// chip, and a slim per-day week strip. Display only (the section's single nav
/// link lives in the header's "See all").
/// A quiet adherence footer at the foot of the dose card: a small teal ring,
/// the live on-time read, and an optional streak chip — all on white.
/// A compact amber streak chip for the dose header — flame + day count.
class _DoseStreakChip extends StatelessWidget {
  const _DoseStreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(9).clamp(8.0, 11.0),
        vertical: responsive.s(6).clamp(5.0, 8.0),
      ),
      decoration: BoxDecoration(
        color: context.colors.isDark
            ? context.colors.warningAlpha(0.16)
            : const Color(0xFFFEF1E4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _homeWarnFor(context).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: _homeAmber,
            size: responsive.icon(14),
          ),
          SizedBox(width: responsive.s(4)),
          Text(
            '$streak',
            style: GoogleFonts.inter(
              color: context.colors.isDark
                  ? context.colors.warning
                  : const Color(0xFF9A5B12),
              fontSize: responsive.font(12.5),
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact circular adherence ring: a teal arc over a faint teal track, with
/// the live percentage centred in deep teal — on the dose card's white surface.
class _DoseAdherenceRing extends StatelessWidget {
  const _DoseAdherenceRing({
    required this.percent,
    required this.size,
    this.dark = false,
  });

  final int percent;
  final double size;

  /// On the dark header band the ring flips to a white arc over a faint white
  /// track, with the percentage in white; on white it reads in teal.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DoseRingPainter(
          percent.clamp(0, 100) / 100,
          track: dark
              ? MedGuardPalette.whiteAlpha(0.24)
              : context.colors.accentAlpha(0.16),
          arc: dark ? MedGuardPalette.pureWhite : MedGuardPalette.teal,
        ),
        child: Center(
          child: Text(
            '$percent%',
            style: GoogleFonts.inter(
              color: dark ? MedGuardPalette.pureWhite : context.colors.accent,
              fontSize: responsive.font(dark ? 12.5 : 12),
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _DoseRingPainter extends CustomPainter {
  const _DoseRingPainter(
    this.fraction, {
    required this.track,
    required this.arc,
  });

  final double fraction;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.width * 0.12;
    final radius = (size.width - stroke) / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_DoseRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}

/// Accent colours cycled across a day's dose chips so multiple medicines read
/// as visually distinct without per-drug theming.
const _doseAccentColors = <Color>[
  _homeAmber,
  Color(0xFFEF6C82),
  Color(0xFF7DD3C8),
  Color(0xFF5C7CFA),
  Color(0xFFF2B705),
];

/// '08:00' → '8:00 AM'.
String _formatDoseSlot(String slot) {
  final parts = slot.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final period = hour < 12 ? 'AM' : 'PM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

/// '08:00' → 'Morning' — the part of day a slot falls in.
String _doseSlotBucket(String slot) {
  final hour = int.tryParse(slot.split(':').first) ?? 0;
  if (hour < 12) return 'Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Evening';
  return 'Night';
}

/// Shown on the dark dose panel when the user has not created any reminders
/// yet — a friendly prompt with a one-tap route into the dose planner.
class _DoseSetupEmpty extends StatelessWidget {
  const _DoseSetupEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Container(
      key: const ValueKey('home-dose-setup-empty'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(16).clamp(14.0, 18.0),
        vertical: responsive.s(20).clamp(18.0, 24.0),
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Container(
            width: responsive.s(44).clamp(40.0, 48.0).toDouble(),
            height: responsive.s(44).clamp(40.0, 48.0).toDouble(),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.accentAlpha(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.alarm_add_rounded,
              color: context.colors.accent,
              size: responsive.icon(20),
            ),
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            'No reminders yet',
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: responsive.font(14),
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          SizedBox(height: responsive.s(4)),
          Text(
            'Set up a dose reminder to track your schedule and on-time streak.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: responsive.font(12),
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
          // The shared app button, so the empty-state CTA matches every other
          // primary action in the app rather than being a bespoke pill.
          AppButton(
            label: 'Add a reminder',
            icon: Icons.add_rounded,
            expand: false,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _DoseSelectedDayLabel extends StatelessWidget {
  const _DoseSelectedDayLabel({
    required this.date,
    required this.isToday,
    required this.doseCount,
  });

  final DateTime date;
  final bool isToday;
  final int doseCount;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final dayName = _calendarWeekdayFull[date.weekday];
    final monthName = _calendarMonthNames[date.month];
    // One consistent long date format everywhere in this section (e.g.
    // "Wednesday 18 June") — never a mix of long and short. On a very narrow
    // screen it scales down a touch rather than switching to an abbreviated form.
    final fullLabel = '$dayName ${date.day} $monthName';
    final countLabel = doseCount == 0
        ? 'No doses'
        : doseCount == 1
        ? '1 dose'
        : '$doseCount doses';
    // A generous line height so descenders (y, g, p, q, j) in day and month
    // names are never clipped.
    final dateStyle = GoogleFonts.inter(
      color: context.colors.ink,
      fontSize: responsive.font(13.4),
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return Row(
      key: const ValueKey('home-dose-selected-day-label'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.calendar_month_rounded,
          color: context.colors.accent,
          size: responsive.icon(15),
        ),
        SizedBox(width: responsive.s(8)),
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                fullLabel,
                maxLines: 1,
                softWrap: false,
                style: dateStyle,
              ),
            ),
          ),
        ),
        if (isToday) ...[
          SizedBox(width: responsive.s(8)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(8).clamp(7.0, 10.0),
              vertical: responsive.s(3).clamp(2.0, 4.0),
            ),
            decoration: BoxDecoration(
              // Filled pill with a white label — keep the deep brand teal so the
              // label stays legible (the dark-mode accent is too light to fill).
              color: MedGuardPalette.teal,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Today',
              style: GoogleFonts.inter(
                color: MedGuardPalette.pureWhite,
                fontSize: responsive.font(9.6),
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
        const Spacer(),
        Text(
          countLabel,
          style: GoogleFonts.inter(
            color: context.colors.inkMute,
            fontSize: responsive.font(11.6),
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _DoseDayEmpty extends StatelessWidget {
  const _DoseDayEmpty();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Container(
      key: const ValueKey('home-dose-day-empty'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(16).clamp(14.0, 18.0),
        vertical: responsive.s(20).clamp(18.0, 24.0),
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Container(
            width: responsive.s(44).clamp(40.0, 48.0).toDouble(),
            height: responsive.s(44).clamp(40.0, 48.0).toDouble(),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.accentAlpha(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bedtime_rounded,
              color: context.colors.accent,
              size: responsive.icon(20),
            ),
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            'No doses scheduled',
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: responsive.font(14),
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          SizedBox(height: responsive.s(4)),
          Text(
            'Nothing is due on this day — a clear rest day.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: responsive.font(12),
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextDoseHero extends StatelessWidget {
  const _NextDoseHero({required this.item, this.badge});

  final _DosePreviewItem item;

  /// Overrides [item.badge] in the pill beside the "NEXT DOSE" label — used so
  /// a day other than today reads "First up" instead of "In 2 hrs".
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final pad = responsive.s(15).clamp(14.0, 17.0).toDouble();
    // A clean white card — no side rail, no timeline. The dose's accent colour
    // lives only in the icon disc; the NEXT DOSE tag + relative timing lead, the
    // medicine name follows, and the time + part-of-day sit inline beneath it.
    return Container(
      key: const ValueKey('home-next-dose-hero'),
      width: double.infinity,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(18)),
        border: Border.all(color: context.colors.border),
        boxShadow: _homeCardShadow(responsive),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.s(8).clamp(7.0, 10.0),
                  vertical: responsive.s(4).clamp(3.0, 5.0),
                ),
                decoration: BoxDecoration(
                  color: MedGuardPalette.teal,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'NEXT DOSE',
                  style: GoogleFonts.inter(
                    color: MedGuardPalette.pureWhite,
                    fontSize: responsive.font(10),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(8)),
              Text(
                badge ?? item.badge,
                style: GoogleFonts.inter(
                  color: context.colors.inkMute,
                  fontSize: responsive.font(11.6),
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(12).clamp(10.0, 14.0)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: responsive.s(46).clamp(42.0, 50.0).toDouble(),
                height: responsive.s(46).clamp(42.0, 50.0).toDouble(),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item.icon,
                  color: item.color,
                  size: responsive.icon(22),
                ),
              ),
              SizedBox(width: responsive.s(12).clamp(11.0, 14.0)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      style: GoogleFonts.inter(
                        color: context.colors.ink,
                        fontSize: responsive.font(16),
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: responsive.s(4)),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          color: context.colors.accent,
                          size: responsive.icon(14),
                        ),
                        SizedBox(width: responsive.s(5)),
                        Text(
                          item.time,
                          style: GoogleFonts.inter(
                            color: context.colors.accent,
                            fontSize: responsive.font(14),
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (item.detail.trim().isNotEmpty) ...[
                          SizedBox(width: responsive.s(8)),
                          Text(
                            '•',
                            style: GoogleFonts.inter(
                              color: context.colors.inkSoft,
                              fontSize: responsive.font(12),
                              height: 1.0,
                            ),
                          ),
                          SizedBox(width: responsive.s(8)),
                          Flexible(
                            child: Text(
                              item.detail,
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                color: context.colors.inkSoft,
                                fontSize: responsive.font(12.4),
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingDoseRow extends StatelessWidget {
  const _UpcomingDoseRow({super.key, required this.item, required this.isLast});

  final _DosePreviewItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final dot = responsive.s(8).clamp(7.0, 10.0).toDouble();

    // A clean, compact dose row — a small accent dot, the medicine + part-of-day,
    // and the time on the right. No connecting rail, no timeline thread.
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : responsive.s(14).clamp(12.0, 16.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: item.color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: responsive.s(12).clamp(10.0, 14.0)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: responsive.font(13.6),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: responsive.s(2)),
                Text(
                  item.detail,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: context.colors.inkSoft,
                    fontSize: responsive.font(11.6),
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: responsive.s(14).clamp(12.0, 18.0)),
          Text(
            item.time,
            style: GoogleFonts.inter(
              color: context.colors.accent,
              fontSize: responsive.font(13),
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

const _doseScheduleDotColor = Color(0xFF22C55E);

const List<String> _calendarMonthNames = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _calendarDayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

// Indexed by DateTime.weekday (1 = Monday … 7 = Sunday); index 0 is unused.
const List<String> _calendarWeekdayFull = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class _CalendarDay {
  const _CalendarDay({
    required this.label,
    required this.date,
    required this.fullDate,
    required this.selected,
    required this.isToday,
    required this.hasDose,
  });

  final String label;
  final String date;
  final DateTime fullDate;
  final bool selected;
  final bool isToday;
  final bool hasDose;
}

class _DoseWeekCalendar extends StatefulWidget {
  const _DoseWeekCalendar({
    required this.today,
    required this.selectedDate,
    required this.hasDoseOn,
    required this.onDaySelected,
  });

  final DateTime today;
  final DateTime selectedDate;

  /// Whether the given day has at least one scheduled dose (drives the day dot).
  final bool Function(DateTime) hasDoseOn;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<_DoseWeekCalendar> createState() => _DoseWeekCalendarState();
}

class _DoseWeekCalendarState extends State<_DoseWeekCalendar> {
  int _weekOffset = 0;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime get _weekStart {
    final today = widget.today;
    final daysSinceSunday = today.weekday % 7;
    final thisSunday = DateTime(
      today.year,
      today.month,
      today.day - daysSinceSunday,
    );
    return thisSunday.add(Duration(days: 7 * _weekOffset));
  }

  List<_CalendarDay> get _days {
    final start = _weekStart;
    return List<_CalendarDay>.generate(7, (i) {
      final date = start.add(Duration(days: i));
      return _CalendarDay(
        label: _calendarDayLetters[i],
        date: date.day.toString().padLeft(2, '0'),
        fullDate: date,
        selected: _isSameDay(date, widget.selectedDate),
        isToday: _isSameDay(date, widget.today),
        hasDose: widget.hasDoseOn(date),
      );
    });
  }

  String get _monthLabel {
    final start = _weekStart;
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${_calendarMonthNames[start.month]} ${start.year}';
    }
    return '${_calendarMonthNames[start.month]} – ${_calendarMonthNames[end.month]} ${end.year}';
  }

  void _shiftWeek(int delta) {
    setState(() => _weekOffset += delta);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final days = _days;
    final labelColor = context.colors.ink;
    return Column(
      key: const ValueKey('home-dose-week-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _monthLabel,
                style: GoogleFonts.inter(
                  color: labelColor,
                  fontSize: responsive.font(15.4),
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
            _CalendarArrowButton(
              key: const ValueKey('home-dose-week-prev'),
              icon: Icons.arrow_back_rounded,
              onTap: () => _shiftWeek(-1),
            ),
            SizedBox(width: responsive.s(8).clamp(7.0, 10.0)),
            _CalendarArrowButton(
              key: const ValueKey('home-dose-week-next'),
              icon: Icons.arrow_forward_rounded,
              onTap: () => _shiftWeek(1),
            ),
          ],
        ),
        SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: _DoseDayCell(
                  day: day,
                  onTap: () => widget.onDaySelected(day.fullDate),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  const _CalendarArrowButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final size = responsive.s(30).clamp(28.0, 34.0).toDouble();
    return Pressable(
      onTap: onTap,
      pressScale: 0.92,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.accentAlpha(0.07),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: context.colors.accent,
          size: responsive.icon(15),
        ),
      ),
    );
  }
}

class _DoseDayCell extends StatelessWidget {
  const _DoseDayCell({required this.day, this.onTap});

  final _CalendarDay day;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final dotSize = responsive.s(5).clamp(4.0, 6.0).toDouble();
    final selected = day.selected;

    // Selected = teal bubble + white text; idle days read in ink/mute.
    const selectedBg = MedGuardPalette.teal;
    final selectedLabelColor = MedGuardPalette.whiteAlpha(0.85);
    const selectedDateColor = MedGuardPalette.pureWhite;
    final idleLabelColor = context.colors.inkMute;
    final idleDateColor = context.colors.ink;
    final dotColor = selected
        ? MedGuardPalette.pureWhite
        : _doseScheduleDotColor;

    // Today (when not the selected day) keeps a faint outline so it stays
    // identifiable while the user browses other days.
    final showTodayRing = day.isToday && !selected;
    final ringColor = context.colors.accentAlpha(0.30);

    // Idle days that have a scheduled dose get a whisper of teal fill so the
    // week reads at a glance which days carry medicines — not just a tiny dot.
    final Color background;
    if (selected) {
      background = selectedBg;
    } else if (day.hasDose && !day.isToday) {
      background = context.colors.accentAlpha(0.06);
    } else {
      background = Colors.transparent;
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(2).clamp(1.0, 3.0),
      ),
      child: Pressable(
        onTap: onTap,
        pressScale: 0.93,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            vertical: responsive.s(8).clamp(7.0, 10.0),
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: showTodayRing
                ? Border.all(color: ringColor, width: 1.4)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                day.label,
                style: GoogleFonts.inter(
                  color: selected ? selectedLabelColor : idleLabelColor,
                  fontSize: responsive.font(11),
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              SizedBox(height: responsive.s(7).clamp(6.0, 9.0)),
              Text(
                day.date,
                style: GoogleFonts.inter(
                  color: selected ? selectedDateColor : idleDateColor,
                  fontSize: responsive.font(14.6),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  height: 1,
                ),
              ),
              SizedBox(height: responsive.s(6).clamp(5.0, 7.0)),
              SizedBox(
                height: dotSize,
                width: dotSize,
                child: day.hasDose
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DosePreviewItem {
  const _DosePreviewItem({
    required this.id,
    required this.time,
    required this.name,
    required this.detail,
    required this.badge,
    required this.icon,
    required this.color,
  });

  final String id;
  final String time;
  final String name;
  final String detail;
  final String badge;
  final IconData icon;
  final Color color;
}
