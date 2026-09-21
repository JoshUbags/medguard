import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/dose_log.dart';
import '../../models/dose_schedule.dart';
import '../../models/user_medication.dart';
import '../../services/dose_reminder_scheduler.dart';
import '../../services/dose_service.dart';
import '../../services/interaction_checker.dart';
import '../../services/regimen_review_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../utils/keyboard.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/floating_nav_bar.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/section_header.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/page_background.dart';

part 'widgets/dose_calendar.dart';
part 'widgets/dose_editor.dart';
part 'widgets/dose_stats.dart';
part 'widgets/dose_timeline.dart';
part 'widgets/dose_supply.dart';

/// How much of the calendar the page is showing — and therefore what the stats
/// summarise and what the list below the calendar contains.
enum DoseRange {
  day('Day'),
  week('Week'),
  month('Month');

  const DoseRange(this.label);
  final String label;
}

/// The Dose tab: schedule, adherence and supply for the user's medicines.
///
/// The page always renders. Every section has a designed zero-state, so the
/// calendar, the stats and the supply panel are all visible and legible before
/// a single schedule exists — the page teaches what it will show rather than
/// hiding behind an "add a medication first" wall.
class DoseScreen extends StatefulWidget {
  const DoseScreen({
    super.key,
    this.showNavigation = true,
    this.bottomContentPadding = 0,
    this.now,
    this.onOpenProfile,
  });

  static const String routeName = '/dose';

  final bool showNavigation;
  final double bottomContentPadding;

  /// Injectable clock for tests; defaults to the wall clock.
  final DateTime Function()? now;

  /// Opens the profile screen. Null when standalone — falls back to the route.
  final VoidCallback? onOpenProfile;

  @override
  State<DoseScreen> createState() => _DoseScreenState();
}

class _DoseScreenState extends State<DoseScreen> {
  final DoseService _doses = DoseService.instance;
  final RegimenReviewService _reviews = RegimenReviewService.current;

  /// Whether the regimen's interaction review has been completed. Gates the
  /// timing-conflict panel, which is regimen analysis like any other.
  bool _regimenReviewed = false;

  DoseRange _range = DoseRange.day;
  late DateTime _selectedDay;

  /// The month the calendar is showing. Follows the selection, but can be
  /// paged independently in month view.
  late DateTime _visibleMonth;

  DoseBoard? _board;
  bool _loading = true;

  /// Guards against overlapping loads. Several services bump their revision
  /// for a single user action (saving a schedule touches both the dose and the
  /// medication revisions), which would otherwise fire two full board loads at
  /// once and let the slower one overwrite the newer result.
  bool _loadInFlight = false;
  bool _reloadQueued = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final today = _now;
    _selectedDay = DateTime(today.year, today.month, today.day);
    _visibleMonth = DateTime(today.year, today.month);
    _doses.revision.addListener(_reload);
    UserDataService.instance.medicationsRevision.addListener(_reload);
    // Completing (or invalidating) the interaction review changes what the
    // timing panel is allowed to show, so it reloads the board like any other
    // data change.
    _reviews.revision.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    _doses.revision.removeListener(_reload);
    UserDataService.instance.medicationsRevision.removeListener(_reload);
    _reviews.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  String _userId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'local-device';
    } catch (_) {
      return 'local-device';
    }
  }

  /// The inclusive calendar window the current range covers.
  (DateTime, DateTime) _window() {
    switch (_range) {
      case DoseRange.day:
        // A day view still loads the surrounding week so the day strip above
        // the timeline can show each neighbouring day's outcome.
        final start = _selectedDay.subtract(
          Duration(days: _selectedDay.weekday % 7),
        );
        return (start, start.add(const Duration(days: 6)));
      case DoseRange.week:
        final start = _selectedDay.subtract(
          Duration(days: _selectedDay.weekday % 7),
        );
        return (start, start.add(const Duration(days: 6)));
      case DoseRange.month:
        final start = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
        final end = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
        return (start, end);
    }
  }

  Future<void> _load() async {
    if (_loadInFlight) {
      // Coalesce: remember that the data changed again and re-run once the
      // in-flight load finishes, so the board always settles on the latest.
      _reloadQueued = true;
      return;
    }
    _loadInFlight = true;
    final (from, to) = _window();
    final now = _now;
    try {
      // Interaction knowledge for the timing-conflict panel. A failure here
      // (no store yet, engine unavailable) must not cost the whole board, so
      // conflicts simply go unreported.
      //
      // Gated on the interaction review: timing conflicts ARE regimen
      // analysis, so they stay unreported — and the analysis stays unrun —
      // until the user has completed the review on the Interactions screen.
      Set<String> interacting = const {};
      var reviewed = false;
      try {
        final userId = _userId();
        final medications = await UserDataService.instance.getUserMedications(
          userId,
        );
        final drugIds = medications
            .map((m) => m.drugId)
            .toList(growable: false);
        await _reviews.load(userId);
        reviewed = _reviews.isReviewed(userId, drugIds);
        if (reviewed && medications.length >= 2) {
          final report = await InteractionChecker.analyze(drugIds);
          interacting = {
            for (final i in report.drugInteractions)
              _pairKey(i.drugAId, i.drugBId),
          };
        }
      } catch (_) {}

      final board = await _doses.loadBoard(
        _userId(),
        from: from,
        to: to,
        selectedDay: _selectedDay,
        asOf: now,
        interacts: interacting.isEmpty
            ? null
            : (a, b) => interacting.contains(_pairKey(a, b)),
      );
      if (!mounted) return;
      setState(() {
        _board = board;
        _regimenReviewed = reviewed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _board = DoseBoard.emptyFor(_selectedDay);
        _regimenReviewed = false;
        _loading = false;
      });
    } finally {
      _loadInFlight = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        unawaited(_load());
      }
    }
  }

  static String _pairKey(int a, int b) => a < b ? '$a:$b' : '$b:$a';

  void _selectRange(DoseRange range) {
    if (_range == range) return;
    HapticFeedback.selectionClick();
    setState(() {
      _range = range;
      _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
    _reload();
  }

  void _selectDay(DateTime day) {
    final normalised = DateTime(day.year, day.month, day.day);
    if (normalised == _selectedDay) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDay = normalised;
      _visibleMonth = DateTime(normalised.year, normalised.month);
    });
    _reload();
  }

  void _shiftPeriod(int direction) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (_range) {
        case DoseRange.day:
          _selectedDay = _selectedDay.add(Duration(days: direction));
        case DoseRange.week:
          _selectedDay = _selectedDay.add(Duration(days: 7 * direction));
        case DoseRange.month:
          _visibleMonth = DateTime(
            _visibleMonth.year,
            _visibleMonth.month + direction,
          );
          // Keep the selection inside the month being shown.
          final lastDay = DateTime(
            _visibleMonth.year,
            _visibleMonth.month + 1,
            0,
          ).day;
          _selectedDay = DateTime(
            _visibleMonth.year,
            _visibleMonth.month,
            math.min(_selectedDay.day, lastDay),
          );
      }
      _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
    _reload();
  }

  void _goToToday() {
    final today = _now;
    _selectDay(DateTime(today.year, today.month, today.day));
  }

  Future<void> _logDose(DoseOccurrence occurrence, DoseLogStatus status) async {
    HapticFeedback.lightImpact();
    await _doses.logDose(
      scheduleId: occurrence.schedule.id,
      scheduledTime: occurrence.scheduledTime,
      status: status,
      loggedAt: _now,
    );
    if (!mounted) return;
    AppSnack.success(
      context,
      '${occurrence.schedule.drugName} marked ${status.label.toLowerCase()}',
    );
  }

  Future<void> _clearDose(DoseOccurrence occurrence) async {
    HapticFeedback.selectionClick();
    await _doses.clearDoseLog(
      scheduleId: occurrence.schedule.id,
      scheduledTime: occurrence.scheduledTime,
    );
  }

  Future<void> _markDayTaken() async {
    final written = await _doses.logRemainingForDay(
      userId: _userId(),
      day: _selectedDay,
      status: DoseLogStatus.taken,
      asOf: _now,
    );
    if (!mounted) return;
    if (written == 0) {
      AppSnack.show(context, 'Nothing left to log for this day.');
      return;
    }
    AppSnack.success(
      context,
      '$written ${written == 1 ? 'dose' : 'doses'} marked taken',
    );
  }

  void _openProfile() {
    final handler = widget.onOpenProfile;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).pushNamed(ProfileScreen.routeName);
  }

  /// Opens the schedule editor — new when [existing] is null, otherwise
  /// editing that schedule. A save/delete bumps [DoseService.revision], which
  /// reloads the board through the listener, so no manual refresh is needed.
  Future<void> _editSchedule([DoseSchedule? existing]) async {
    await showDoseScheduleEditor(
      context,
      existing: existing,
      userId: _userId(),
      now: _now,
    );
  }

  void _addSchedule() => unawaited(_editSchedule());

  /// Lets the user pick which schedule to edit when more than one exists.
  Future<void> _manageSchedules() async {
    final schedules = _board?.schedules ?? const <DoseSchedule>[];
    if (schedules.isEmpty) return;
    if (schedules.length == 1) {
      await _editSchedule(schedules.first);
      return;
    }
    final picked = await showModalBottomSheet<DoseSchedule>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SchedulePickerSheet(schedules: schedules),
    );
    if (picked == null) return;
    await _editSchedule(picked);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final board = _board;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    // TWO gaps and only two, which is what makes a long page legible: the
    // section divider between unrelated blocks, and a tighter in-group beat
    // between controls that belong to each other (the range switch, its
    // calendar and the list they filter). The page previously used one flat
    // gap for both, so nothing on it read as grouped.
    final gap = responsive.s(28).clamp(24.0, 34.0).toDouble();
    final groupGap = responsive.s(14).clamp(12.0, 18.0).toDouble();

    final occurrences = board?.dayOccurrences ?? const <DoseOccurrence>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(colors),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        body: PageBackground(
          tone: PageTone.routine,
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
            onRefresh: _load,
            color: colors.accent,
            backgroundColor: colors.surface,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // ── The page header. The SAME header as Home, Insights and
                // Interactions.
                //
                // Dose used to open with a full-bleed dark teal masthead — a
                // pinned band carrying its own date rail, arc and identity
                // cluster. It looked striking in isolation and wrong in
                // sequence: switching to this tab changed the colour of the top
                // third of the screen and moved the avatar, so the app appeared
                // to hand you to a different product. One header, one place.
                SliverToBoxAdapter(
                  child: responsive.constrain(
                    Padding(
                      padding: responsive.pagePadding(
                        top: MedGuardSpacing.screenTopGap(responsive),
                        bottom: 22,
                      ),
                      child: PageHeader(
                        title: 'Doses',
                        subtitle: _headerSubtitle(board, occurrences, today),
                        onOpenProfile: _openProfile,
                        actions: [
                          _DoseAddButton(
                            key: const ValueKey('dose-header-add'),
                            size: headerAvatarSize(responsive),
                            onTap: _addSchedule,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: responsive.constrain(
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.pageX,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // What to take next, as a banner rather than a card —
                          // it is an answer, not a section.
                          if (board?.hasSchedules ?? false) ...[
                            _NextUpBanner(
                              occurrences: occurrences,
                              loading: _loading,
                              hasSchedules: true,
                              now: now,
                              selectedDay: _selectedDay,
                              today: today,
                              onLog: _logDose,
                              onAddSchedule: _addSchedule,
                            ),
                            SizedBox(height: gap),
                          ],

                          // ── The schedule group ─────────────────────────
                          //
                          // The range switch, the calendar it reshapes, and the
                          // day list they point at are ONE group, so the gaps
                          // between them are the tight in-group beat and only
                          // the group's edges get a full section divider.
                          _DoseRangeSelector(
                            active: _range,
                            onSelected: _selectRange,
                          ),
                          SizedBox(height: groupGap),

                          // The calendar is now shown in EVERY range, Day
                          // included. It used to be hidden in Day view because
                          // the masthead's rail was the day picker — so when
                          // the masthead went, tapping "Day" left the page with
                          // no way to change date at all. The range now
                          // controls the calendar's SHAPE (week row or month
                          // grid), never whether it exists.
                          _DoseCalendar(
                            range: _range,
                            selectedDay: _selectedDay,
                            visibleMonth: _visibleMonth,
                            today: today,
                            stats: board?.dayStats ?? const {},
                            onSelectDay: _selectDay,
                            onShift: _shiftPeriod,
                            onToday: _goToToday,
                          ),
                          SizedBox(height: groupGap),

                          // …and the timeline for the selected day is ALWAYS
                          // beneath it. Previously Week and Month swapped it
                          // out for the per-medicine breakdown, so tapping a
                          // date on the month grid changed the selection and
                          // showed nothing about that date — the one thing a
                          // person taps a calendar date to find out.
                          _DoseTimeline(
                            occurrences: occurrences,
                            loading: _loading,
                            selectedDay: _selectedDay,
                            now: now,
                            hasSchedules: board?.hasSchedules ?? false,
                            onLog: _logDose,
                            onClear: _clearDose,
                            onMarkAllTaken: _markDayTaken,
                            onAddSchedule: _addSchedule,
                            onEditSchedule: (schedule) =>
                                unawaited(_editSchedule(schedule)),
                            onManageSchedules: () =>
                                unawaited(_manageSchedules()),
                          ),

                          // With nothing scheduled yet, the invitation to
                          // start goes HERE — under the calendar the user has
                          // just seen, so it reads as "and here is how you
                          // fill it" rather than as a wall in front of the
                          // page.
                          if (!(board?.hasSchedules ?? false)) ...[
                            SizedBox(height: gap),
                            _DoseInvite(onAddSchedule: _addSchedule),
                          ],

                          // The per-medicine breakdown is additional in the
                          // wider ranges rather than a replacement: over a week
                          // or a month "which medicine do I slip on" is a real
                          // question, and over a single day it is not.
                          if (_range != DoseRange.day) ...[
                            SizedBox(height: gap),
                            _DoseDrugBreakdown(
                              rows: board?.byDrug ?? const [],
                              loading: _loading,
                              range: _range,
                              onAddSchedule: _addSchedule,
                              onEditSchedule: (schedule) =>
                                  unawaited(_editSchedule(schedule)),
                            ),
                          ],

                          SizedBox(height: gap),
                          _DoseStatsPanel(
                            range: _range,
                            board: board,
                            loading: _loading,
                            selectedDay: _selectedDay,
                            today: today,
                          ),
                          SizedBox(height: gap),
                          // Timing conflicts are regimen analysis, so the panel
                          // stays behind the interaction-review gate:
                          // unreviewed regimens report no conflicts because
                          // none were computed.
                          _DoseTimingPanel(
                            conflicts: _regimenReviewed
                                ? (board?.conflicts ?? const [])
                                : const [],
                            byPartOfDay: board?.byPartOfDay ?? const [],
                            reviewPending: !_regimenReviewed,
                          ),
                          SizedBox(height: gap),
                          _DoseSupplyPanel(
                            refills: board?.refills ?? const [],
                            hasSchedules: board?.hasSchedules ?? false,
                            onAddSchedule: _addSchedule,
                          ),
                          SizedBox(
                            height: screenEndContentInset(
                              context,
                              reserveFloatingNav:
                                  !widget.showNavigation &&
                                  widget.bottomContentPadding > 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
        bottomNavigationBar: widget.showNavigation
            ? const FloatingNavBar(current: AppNavTab.dose)
            : null,
      ),
    );
  }

  /// The one line under the page title. Reports the state of the day the user
  /// is actually looking at, so the header stays useful as they move around the
  /// calendar instead of repeating a fixed slogan.
  String _headerSubtitle(
    DoseBoard? board,
    List<DoseOccurrence> occurrences,
    DateTime today,
  ) {
    if (_loading && board == null) return 'Reading your schedule…';
    if (!(board?.hasSchedules ?? false)) {
      return 'Set a reminder and MedGuard keeps the schedule.';
    }
    if (occurrences.isEmpty) {
      return _selectedDay == today
          ? 'Nothing scheduled for today.'
          : 'Nothing scheduled for ${_longDate(_selectedDay)}.';
    }
    final logged = occurrences.where((o) => o.isLogged).length;
    final when = _selectedDay == today ? 'today' : _longDate(_selectedDay);
    if (logged == occurrences.length) {
      return 'All ${occurrences.length} '
          '${occurrences.length == 1 ? 'dose' : 'doses'} logged for $when.';
    }
    return '$logged of ${occurrences.length} doses logged for $when.';
  }
}

/// "12 March" — the date form used in running prose on this page.
String _longDate(DateTime day) => '${day.day} ${_monthNames[day.month - 1]}';

/// The "add a schedule" action inside the header capsule. Sized and styled to
/// sit beside the avatar exactly as Home's notification bell does.
class _DoseAddButton extends StatelessWidget {
  const _DoseAddButton({super.key, required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = colors.isDark;
    final fill = isDark
        ? MedGuardPalette.whiteAlpha(0.08)
        : colors.surface.withValues(alpha: 0.92);
    final edge = isDark
        ? MedGuardPalette.whiteAlpha(0.10)
        : colors.ink.withValues(alpha: 0.06);
    return Pressable(
      onTap: onTap,
      pressScale: 0.9,
      semanticLabel: 'Add a dose schedule',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: edge),
        ),
        child: Icon(
          Icons.add_rounded,
          color: colors.ink,
          size: size * 0.48,
        ),
      ),
    );
  }
}

/// A stable accent colour per medicine, derived from its drug id.
///
/// This is what gives the dose experience its own visual language: the same
/// medicine is the same colour on the today panel, in the timeline, and in the
/// breakdown, so a regimen becomes recognisable at a glance instead of reading
/// as an undifferentiated grey list. The palette is drawn from the brand's cool
/// family plus two warm accents, all tuned to hold contrast on both themes.
const List<Color> _medicineAccents = [
  Color(0xFF0E9F8C), // teal
  Color(0xFF3E8EF0), // blue
  Color(0xFF7A6FF0), // indigo
  Color(0xFFCE6BA8), // rose
  Color(0xFFD98324), // amber
  Color(0xFF3FAE6A), // green
];

Color medicineAccent(int drugId) =>
    _medicineAccents[drugId.abs() % _medicineAccents.length];

/// The medicine's colour chip — a rounded square carrying its initial in its
/// own accent. Small, but it is the single element that makes the timeline
/// scannable, because you learn a medicine's colour after one look.
class _MedicineChip extends StatelessWidget {
  const _MedicineChip({
    required this.drugId,
    required this.name,
    required this.size,
  });

  final int drugId;
  final String name;
  final double size;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = medicineAccent(drugId);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.11),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        _initial,
        style: GoogleFonts.inter(
          color: accent,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// What to take next, as an inline banner rather than another card.
///
/// The masthead already carries the day's headline numbers, so this does one
/// job only: name the next dose and put Take and Skip under the thumb. Its
/// left edge is a colour bar in the medicine's own accent — the same colour
/// that medicine carries in the timeline below — so the banner and the row it
/// refers to are visibly the same thing.
///
/// It is scoped to the day you are LOOKING at, not to the wall clock, so it
/// says so. On today it reads "up next" / "due now" with a countdown; on
/// another day it names that day and drops the countdown, because "in 4h" is
/// meaningless about last Tuesday. The Take and Skip actions stay live on every
/// day — back-filling a dose you forgot to log is the single most common thing
/// anyone does on this screen.
class _NextUpBanner extends StatelessWidget {
  const _NextUpBanner({
    required this.occurrences,
    required this.loading,
    required this.hasSchedules,
    required this.now,
    required this.selectedDay,
    required this.today,
    required this.onLog,
    required this.onAddSchedule,
  });

  final List<DoseOccurrence> occurrences;
  final bool loading;
  final bool hasSchedules;
  final DateTime now;
  final DateTime selectedDay;
  final DateTime today;
  final void Function(DoseOccurrence, DoseLogStatus) onLog;
  final VoidCallback onAddSchedule;

  bool get _isToday => selectedDay == today;
  bool get _isPast => selectedDay.isBefore(today);

  /// The banner's all-caps kicker, honest about which day it describes.
  String _kicker({required bool overdue}) {
    if (_isToday) return overdue ? 'DUE NOW' : 'UP NEXT';
    if (_isPast) return 'NOT LOGGED';
    return 'SCHEDULED';
  }

  DoseOccurrence? get _next {
    final pending = occurrences.where((o) => !o.isLogged).toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    if (pending.isEmpty) return null;
    final overdue = pending
        .where((o) => !o.scheduledTime.isAfter(now))
        .toList(growable: false);
    return overdue.isNotEmpty ? overdue.first : pending.first;
  }

  String _relative(DateTime target) {
    final diff = target.difference(now);
    final ahead = !diff.isNegative;
    final minutes = diff.abs().inMinutes;
    if (minutes < 1) return 'now';
    final label = minutes < 60
        ? '${minutes}m'
        : minutes % 60 == 0
        ? '${minutes ~/ 60}h'
        : '${minutes ~/ 60}h ${minutes % 60}m';
    return ahead ? 'in $label' : '$label ago';
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    if (loading) {
      return _BannerShell(
        accent: colors.inkMute,
        child: Row(
          children: [
            const MorphLoader(size: 22),
            SizedBox(width: responsive.s(12)),
            Expanded(
              child: Text(
                'Reading your schedule…',
                style: GoogleFonts.inter(
                  color: colors.inkSoft,
                  fontSize: responsive.font(13.2),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // With no schedules there is no "next dose" to report, and the invite
    // that used to stand in for it here now sits BELOW the calendar — see the
    // page build. A first-time user should meet the thing the page is (a
    // calendar of doses) before being asked to fill it.
    if (!hasSchedules) return const SizedBox.shrink();

    final next = _next;
    if (next == null) {
      return _BannerShell(
        accent: colors.accent,
        child: Row(
          children: [
            Icon(
              Icons.task_alt_rounded,
              color: colors.accent,
              size: responsive.icon(21),
            ),
            SizedBox(width: responsive.s(12)),
            Expanded(
              child: Text(
                occurrences.isEmpty
                    ? 'Nothing due on this day'
                    : _isToday
                    ? 'Every dose logged today'
                    : 'Every dose logged',
                style: GoogleFonts.inter(
                  color: colors.ink,
                  fontSize: responsive.font(14.4),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // "Overdue" only means anything on today. A pending dose on a past day is
    // simply unlogged, and painting it in the danger colour every time the user
    // scrolls back through the week is alarm fatigue, not information.
    final overdue = _isToday && !next.scheduledTime.isAfter(now);
    final accent = medicineAccent(next.schedule.drugId);

    return _BannerShell(
      accent: overdue ? colors.danger : accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MedicineChip(
                drugId: next.schedule.drugId,
                name: next.schedule.drugName,
                size: responsive.s(40).clamp(36.0, 46.0).toDouble(),
              ),
              SizedBox(width: responsive.s(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _kicker(overdue: overdue),
                          style: GoogleFonts.inter(
                            color: overdue ? colors.danger : colors.accent,
                            fontSize: responsive.font(9.4),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            height: 1,
                          ),
                        ),
                        SizedBox(width: responsive.s(8)),
                        Flexible(
                          child: Text(
                            // A countdown only reads on today; on any other day
                            // the day itself is the useful second fact.
                            _isToday
                                ? _relative(next.scheduledTime)
                                : _shortDate(selectedDay),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: colors.inkMute,
                              fontSize: responsive.font(10.8),
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.s(6)),
                    Text(
                      next.schedule.drugName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(16.5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(4)),
                    Wrap(
                      spacing: responsive.s(12),
                      runSpacing: responsive.s(4),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (next.schedule.doseLabel case final dose?)
                          _HeroFact(
                            icon: Icons.local_pharmacy_rounded,
                            label: dose,
                          ),
                        _HeroFact(
                          icon: Icons.schedule_rounded,
                          label: _formatSlotTime(next.scheduledTime),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(14)),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _HeroButton(
                  label: 'Mark as taken',
                  icon: Icons.check_rounded,
                  onTap: () => onLog(
                    next,
                    now.difference(next.scheduledTime).inMinutes > 60
                        ? DoseLogStatus.late
                        : DoseLogStatus.taken,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(10)),
              Expanded(
                flex: 2,
                child: _HeroButton(
                  label: 'Skip',
                  icon: Icons.remove_rounded,
                  filled: false,
                  onTap: () => onLog(next, DoseLogStatus.skipped),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The banner surface: a light panel with a solid colour bar down its leading
/// edge. The bar is the whole idea — it ties the banner to a specific medicine
/// and gives the sheet its first spot of colour without another filled card.
class _BannerShell extends StatelessWidget {
  const _BannerShell({required this.child, required this.accent});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = BorderRadius.circular(responsive.radius(20));
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(color: accent.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: responsive.s(20),
            offset: Offset(0, responsive.s(8)),
          ),
        ],
      ),
      // No accent bar down the left edge. A solid stripe of brand colour on
      // one side of a card is a strong, permanent mark for something that is
      // usually just a card, and it reads as a slab bolted to the layout
      // rather than as part of it. The tinted border and the shadow already
      // say "this one matters"; the meaning lives in the content.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(
                  responsive.s(16).clamp(14.0, 20.0).toDouble(),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The zero state: no schedules at all. An invitation, not an error.
/// The zero state: what happens once a reminder exists, as three numbered
/// steps, and the one control that starts it.
///
/// Deliberately NOT the icon-title-paragraph-button shape used for empty states
/// elsewhere in the app. This is the only screen a user can arrive at where the
/// whole page is inert until they act, so the empty state has a bigger job than
/// apologising for having no data: it has to make the payoff concrete. Three
/// steps with a connecting spine reads as a process the user is about to start
/// rather than a wall they have hit, and each step names something the page
/// above will then actually show them.
class _DoseInvite extends StatelessWidget {
  const _DoseInvite({required this.onAddSchedule});

  final VoidCallback onAddSchedule;

  static const _steps = <({IconData icon, String title, String body})>[
    (
      icon: Icons.local_pharmacy_rounded,
      title: 'Pick a medicine and its times',
      body: 'Once a day, four times a day, or only on certain weekdays.',
    ),
    (
      icon: Icons.notifications_active_rounded,
      title: 'Get reminded, even offline',
      body: 'Alerts fire from the device, so they work with no signal.',
    ),
    (
      icon: Icons.insights_rounded,
      title: 'Watch the picture build',
      body: 'The calendar, adherence and supply below all fill in from it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return _BannerShell(
      accent: colors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your first reminder',
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(19),
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          SizedBox(height: responsive.s(6)),
          Text(
            'Three taps, and this page starts working for you.',
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(13),
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          SizedBox(height: responsive.s(20)),
          for (var i = 0; i < _steps.length; i++)
            _InviteStep(
              index: i + 1,
              icon: _steps[i].icon,
              title: _steps[i].title,
              body: _steps[i].body,
              isLast: i == _steps.length - 1,
            ),
          SizedBox(height: responsive.s(18)),
          _HeroButton(
            label: 'Add a medication',
            icon: Icons.add_rounded,
            onTap: onAddSchedule,
          ),
        ],
      ),
    );
  }
}

/// One numbered step, with a spine running down to the next.
///
/// The spine is what turns three cards into one sequence: without it the eye
/// reads them as an unordered list of features, and the numbers become
/// decoration.
class _InviteStep extends StatelessWidget {
  const _InviteStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLast,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final disc = responsive.s(30).clamp(28.0, 36.0).toDouble();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: disc,
                height: disc,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentAlpha(0.12),
                ),
                child: Text(
                  '$index',
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(13),
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: EdgeInsets.symmetric(vertical: responsive.s(4)),
                    color: colors.accentAlpha(0.16),
                  ),
                ),
            ],
          ),
          SizedBox(width: responsive.s(14)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : responsive.s(16),
                top: responsive.s(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: responsive.icon(15),
                        color: colors.accent,
                      ),
                      SizedBox(width: responsive.s(7)),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            color: colors.ink,
                            fontSize: responsive.font(13.6),
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.s(3)),
                  Text(
                    body,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12.2),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled fact — a glyph and its value on a shared centre line, sized to
/// its content so a [Wrap] can flow them onto a second line instead of
/// clipping.
class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final glyph = colors.inkMute;
    final text = colors.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: glyph, size: responsive.icon(14)),
        SizedBox(width: responsive.s(5)),
        Text(
          label,
          style: GoogleFonts.inter(
            color: text,
            fontSize: responsive.font(12.6),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The banner's actions, at a full 48pt target: a solid brand-teal primary and
/// a quiet outlined secondary, matching the primary/secondary pairing used in
/// the medication modal and the interaction review.
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final foreground = filled ? MedGuardPalette.pureWhite : colors.inkSoft;

    return Pressable(
      onTap: onTap,
      pressScale: 0.96,
      semanticLabel: label,
      child: Container(
        height: responsive.s(46).clamp(44.0, 52.0).toDouble(),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: responsive.s(16)),
        decoration: BoxDecoration(
          color: filled ? MedGuardPalette.teal : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
          border: filled ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: responsive.icon(17)),
            SizedBox(width: responsive.s(7)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: foreground,
                  fontSize: responsive.font(13.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Day / Week / Month segmented control. A single sliding indicator rather
/// than three independently-styled chips, so the choice reads as one control.
class _DoseRangeSelector extends StatelessWidget {
  const _DoseRangeSelector({required this.active, required this.onSelected});

  final DoseRange active;
  final ValueChanged<DoseRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final height = responsive.s(40).clamp(38.0, 46.0).toDouble();

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / DoseRange.values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: segment * active.index,
                width: segment,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  // The active segment carries the brand colour rather than a
                  // white chip on grey. A selected control that differs from
                  // its neighbours only by being slightly lighter is the
                  // weakest possible signal for the one piece of state that
                  // decides what the whole page below is showing.
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final range in DoseRange.values)
                    Expanded(
                      child: Pressable(
                        onTap: () => onSelected(range),
                        pressScale: 0.96,
                        semanticLabel: '${range.label} view',
                        selected: range == active,
                        child: Container(
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: GoogleFonts.inter(
                              color: range == active
                                  ? MedGuardPalette.pureWhite
                                  : colors.inkSoft,
                              fontSize: responsive.font(13),
                              fontWeight: range == active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            child: Text(range.label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The shared card shell for every panel on this page — one surface colour,
/// one radius, one hairline, one internal padding. Sections differ by their
/// content, never by their container.
class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(16).clamp(14.0, 20.0).toDouble()),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// THE section on this page: the heading and its caption standing on the
/// canvas, and the content beneath them inside a [_DoseCard].
///
/// This is the app's layout grammar (see [SectionBlock]) applied to Dose. The
/// panels here used to put their own heading INSIDE the card, so each one read
/// as a self-contained widget rather than as a section of a page — there was no
/// single line for the eye to follow down the left edge, and the page felt like
/// a stack of unrelated boxes rather than one document.
class _DoseSection extends StatelessWidget {
  const _DoseSection({
    required this.title,
    required this.child,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DoseSectionHeader(title: title, caption: caption, trailing: trailing),
        SizedBox(height: sectionHeaderGap(responsive)),
        _DoseCard(child: child),
      ],
    );
  }
}

/// The section heading used above every panel on this page.
///
/// A thin alias over the app-wide [SectionHeader], so Dose's headings are the
/// same object at the same type scale as Home's and Insights'. It used to be a
/// separate 15pt/w700 heading with a 12pt caption, which is why this page's
/// sections read a size smaller and a shade tighter than every other feed's.
class _DoseSectionHeader extends StatelessWidget {
  const _DoseSectionHeader({required this.title, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(title: title, subtitle: caption, trailing: trailing);
}

/// The one empty-state treatment used inside panels on this page.
class _DoseEmptyNote extends StatelessWidget {
  const _DoseEmptyNote({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final disc = responsive.s(44).clamp(40.0, 52.0).toDouble();

    return Column(
      children: [
        SizedBox(height: responsive.s(6)),
        Container(
          width: disc,
          height: disc,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accentAlpha(0.08),
            border: Border.all(color: colors.accentAlpha(0.16)),
          ),
          child: Icon(icon, color: colors.accent, size: disc * 0.44),
        ),
        SizedBox(height: responsive.s(12)),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(13.8),
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        SizedBox(height: responsive.s(5)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.4),
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: responsive.s(14)),
          Pressable(
            onTap: onAction,
            pressScale: 0.95,
            semanticLabel: actionLabel,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.s(16),
                vertical: responsive.s(10),
              ),
              decoration: BoxDecoration(
                color: colors.accentAlpha(0.10),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                actionLabel!,
                style: GoogleFonts.inter(
                  color: colors.accent,
                  fontSize: responsive.font(12.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: responsive.s(4)),
      ],
    );
  }
}

/// `'08:00'` → `'8:00 AM'`.
String _formatSlotTime(DateTime time) {
  final period = time.hour < 12 ? 'AM' : 'PM';
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour12:${time.minute.toString().padLeft(2, '0')} $period';
}

const List<String> _monthNames = [
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

const List<String> _weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

String _shortDate(DateTime day) =>
    '${_monthNames[day.month - 1].substring(0, 3)} ${day.day}';
