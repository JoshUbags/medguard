import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/dose_schedule.dart';
import '../../models/safety_report.dart';
import '../../models/user_medication.dart';
import '../../services/auth_profile_preferences.dart';
import '../../services/connectivity_service.dart';
import '../../services/dose_service.dart';
import '../../services/interaction_checker.dart';
import '../../services/login_activity_service.dart';
import '../../services/notification_center.dart';
import '../../services/regimen_review_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/account_avatar.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_shadows.dart';
import '../../theme/medguard_spacing.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/floating_nav_bar.dart';
import '../../widgets/common/notification_bell.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/severity_colors.dart';
import '../allergies/allergy_management_screen.dart';
import '../dose/dose_screen.dart';
import '../emergency/emergency_screen.dart';
import '../medications/medications_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../../widgets/common/page_background.dart';
import '../../widgets/safety/regimen_risk.dart';

part 'widgets/home_danger.dart';
part 'widgets/home_streak.dart';
part 'widgets/home_alerts.dart';
part 'widgets/home_doses.dart';
part 'widgets/home_insights.dart';
part 'widgets/home_quick_access.dart';

const _localUserId = 'local-device';

// The app's general decorative amber (the streak flame card, the dose streak
// chip) — a warm accent, NOT a risk tier. The moderate RISK tone is the
// canonical [SeverityColors.moderate] below.
const _homeAmber = Color(0xFFD97706);
// The high-risk tone, mirrored from the canonical [SeverityColors] so home's
// danger surfaces read the same ruby as every other severity surface in the
// app. The gauge's full tier palette moved with the gauge to
// `widgets/safety/regimen_risk.dart`.
const _riskDangerRuby = SeverityColors.high;
const _riskInactiveTrack = Color(0xFFE3E8E7);

/// Danger / caution tones resolved for the current brightness — brighten on the
/// dark surface (rubyDeep/amber fall low there) while staying exact in light.
/// For solid FILLS with white text keep the raw tones; these are for foregrounds
/// and tinted washes on a surface.
Color _homeDangerFor(BuildContext context) =>
    SeverityColors.foreground(_riskDangerRuby, Theme.of(context).brightness);
Color _homeWarnFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFBBF24)
    : _homeAmber;

// The pinned header chrome is a solid, opaque bar (no glass, no gloss): one flat
// fill shared by the bar and the left profile slab so they read as a single
// surface. The only depth cues are soft shadows — under the bar where the feed
// scrolls beneath it, and down the slab's right edge where the pills tuck under.

/// Clips the pinned header to its own bounds at the top/sides (so the greeting
/// can slide up and out of view) while letting [extraBottom] pixels of the bar's
/// drop shadow spill below the bar onto the feed scrolling underneath.
class _HeaderBottomShadowClip extends CustomClipper<Rect> {
  const _HeaderBottomShadowClip(this.extraBottom);

  final double extraBottom;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height + extraBottom);

  @override
  bool shouldReclip(_HeaderBottomShadowClip oldClipper) =>
      oldClipper.extraBottom != extraBottom;
}

const _homeInsightCoverAsset = 'assets/images/mainshell/03.jpg';
const _homeInsightSecondaryAsset = 'assets/images/mainshell/02.jpg';
const _homeInsightFoodAsset = 'assets/images/mainshell/01.jpg';

typedef AnalyzeRegimenRisk =
    Future<SafetyReport> Function(List<UserMedication> medications);

enum _HomeSectionId { quickAccess, risk, insights, dose, alerts }

extension on _HomeSectionId {
  String get keySuffix {
    return switch (this) {
      _HomeSectionId.quickAccess => 'quick-access',
      _HomeSectionId.risk => 'risk',
      _HomeSectionId.insights => 'insights',
      _HomeSectionId.dose => 'dose',
      _HomeSectionId.alerts => 'alerts',
    };
  }
}

/// One primary section, surfaced both as a pill in the pinned header chrome and
/// as a keyed landing target down the feed, so tapping a pill scrolls to the
/// matching section and scrolling lights the matching pill.
class _HomeSectionTarget {
  const _HomeSectionTarget({
    required this.id,
    required this.label,
    required this.icon,
    required this.iconColor,
  });

  final _HomeSectionId id;
  final String label;
  final IconData icon;

  /// The resting (inactive) icon tint. Each pill carries a purposeful colour
  /// drawn from the MedGuard palette so the row reads with quick recognition
  /// while staying cohesive — the active pill always inverts to white on teal.
  final Color iconColor;
}

// The five primary sections, in the order they appear both in the pill row and
// down the feed. Each resting icon colour is meaningful: brand teal for Access,
// caution amber for Risk, info indigo for Insights, steady sage for Doses, and
// the alert red for Alerts.
const _homeSectionTargets = [
  _HomeSectionTarget(
    id: _HomeSectionId.quickAccess,
    label: 'Access',
    icon: Icons.bolt_rounded,
    iconColor: MedGuardPalette.teal,
  ),
  _HomeSectionTarget(
    id: _HomeSectionId.risk,
    label: 'Risk',
    icon: Icons.monitor_heart_rounded,
    iconColor: Color(0xFFB45309),
  ),
  _HomeSectionTarget(
    id: _HomeSectionId.insights,
    label: 'Insights',
    icon: Icons.lightbulb_outline_rounded,
    iconColor: Color(0xFF4C5BAC),
  ),
  _HomeSectionTarget(
    id: _HomeSectionId.dose,
    label: 'Doses',
    icon: Icons.alarm_rounded,
    iconColor: Color(0xFF44786A),
  ),
  _HomeSectionTarget(
    id: _HomeSectionId.alerts,
    label: 'Alerts',
    icon: Icons.notifications_none_rounded,
    iconColor: Color(0xFFB42318),
  ),
];

// ── Header geometry, shared by the screen (scroll-spy / tap offsets) and the
// collapsing header delegate so they can never disagree. ────────────────────
double _hdrPillHeight(MedGuardResponsive r) =>
    r.s(32).clamp(30.0, 36.0).toDouble();
double _hdrSpaceUnder(MedGuardResponsive r) =>
    r.s(12).clamp(10.0, 14.0).toDouble();
double _hdrCollapsedTopPad(MedGuardResponsive r) =>
    r.s(16).clamp(14.0, 20.0).toDouble();

/// The gap above the greeting — sourced from the app-wide universal top gap so
/// home and every other screen begin at exactly the same height.
double _hdrTopPadExtra(MedGuardResponsive r) => MedGuardSpacing.screenTop(r);
double _hdrTextGap(MedGuardResponsive r) => r.s(5).clamp(4.0, 6.0).toDouble();

/// The profile avatar (and the notification bell beside it) is EXACTLY as tall
/// as the greeting + name text block at the far left: both text lines render at
/// line-height 1.0, so the block is the two font sizes plus the gap between —
/// including the user's system accessibility text scale, so the pairing holds
/// at every text size.
double _hdrAvatarSize(MedGuardResponsive r) =>
    (r.font(13) + _hdrTextGap(r) + r.font(22)) * r.textScale.clamp(1.0, 1.6);

/// Breathing room the glass capsule adds around the bell + avatar pair —
/// sourced from the shared header cluster so the two can never disagree.
const double _hdrGlassPad = kHeaderGlassPad;

/// Full height of the expanded header row (the glass capsule is the tallest
/// element: avatar + its capsule padding).
double _hdrHeaderRowHeight(MedGuardResponsive r) =>
    _hdrAvatarSize(r) + _hdrGlassPad * 2;
double _hdrGapToPills(MedGuardResponsive r) =>
    r.s(22).clamp(20.0, 24.0).toDouble();

/// Pinned (fully collapsed) header height: status-bar inset + a top pad that
/// keeps the pinned row clear of the very top + the single pill row + the space
/// beneath it before the bar's bottom edge.
double homeHeaderMinExtent(MedGuardResponsive r, double topInset) =>
    topInset + _hdrCollapsedTopPad(r) + _hdrPillHeight(r) + _hdrSpaceUnder(r);

/// Expanded header height: status-bar inset + the top pad + the greeting / name
/// / avatar row + the gap + the pill row. No trailing space here — at rest the
/// pills sit on the bar's bottom edge, so a single standard section gap (the
/// feed's leading gap) separates them from the caption, exactly like every other
/// major section divider.
double homeHeaderMaxExtent(MedGuardResponsive r, double topInset) =>
    topInset +
    _hdrTopPadExtra(r) +
    _hdrHeaderRowHeight(r) +
    _hdrGapToPills(r) +
    _hdrPillHeight(r);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.showNavigation = true,
    this.bottomContentPadding = 0,
    this.onOpenSearch,
    this.onOpenSafety,
    this.onOpenDose,
    this.onOpenProfile,
    this.loadMedications,
    this.analyzeRegimenRisk,
    this.connectivityService,
    this.doseService,
    this.now,
    this.homeRevisitNonce = 0,
  });

  static const String routeName = '/home';

  final bool showNavigation;
  final double bottomContentPadding;

  /// Bumped by the host shell each time the Home tab is (re)selected, so the
  /// regimen-risk meter re-animates from the lowest position on revisit.
  final int homeRevisitNonce;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSafety;
  final VoidCallback? onOpenDose;
  final VoidCallback? onOpenProfile;
  final Future<List<UserMedication>> Function()? loadMedications;
  final AnalyzeRegimenRisk? analyzeRegimenRisk;
  final ConnectivityService? connectivityService;
  final DoseService? doseService;

  /// Injectable clock so the dose calendar can be pinned to a known day in
  /// tests; defaults to the real wall clock in production.
  final DateTime Function()? now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<List<UserMedication>> _medicationsFuture;
  late final DoseService _doseService =
      widget.doseService ?? DoseService.instance;
  DoseSummary? _doseSummary;
  // Live Action Center signals — all real, never sample state.
  int _allergyCount = 0;
  bool _allergyLoaded = false;
  int _scheduleCount = 0;
  bool _scheduleLoaded = false;
  // Real login-activity days (yyyy-mm-dd) for the consistency strip.
  Set<String> _loginDays = const <String>{};
  // Memoized regimen analysis, keyed by the medication-id fingerprint, so the
  // risk gauge and the safety-alerts timeline share one live report instead of
  // running the same checks twice.
  Future<SafetyReport>? _reportFuture;
  String _reportFingerprint = '';
  // Regimens (by drug-id fingerprint) whose danger popup has already been shown
  // this session, so the sheet appears once per distinct dangerous regimen.
  final Set<String> _dangerSheetShownFingerprints = <String>{};
  // The interaction-review gate. Until the user has completed the review for
  // the regimen they currently have, none of its analysis is run or shown —
  // see [RegimenReviewService]. Starts closed so the very first frame after a
  // cold start can never flash an ungated verdict.
  final RegimenReviewService _reviews = RegimenReviewService.current;
  bool _regimenReviewed = false;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<User?>? _userSubscription;
  // The pill that reads as active in the pinned header. Driven by EITHER a tap
  // on a pill or by scrolling a section into view (scroll-spy) — whichever
  // happened last.
  _HomeSectionId _activeSection = _HomeSectionId.quickAccess;
  // While a pill-tap is animating the feed, the scroll-spy is paused so it can't
  // briefly snap the active pill back to the first section mid-scroll.
  bool _suppressScrollSpy = false;
  // Stable keys on each primary section's subtree: the section body itself
  // (scroll-spy reads its top edge) and the leading landing gap (tap-to-section
  // scrolls the gap flush under the pinned chrome).
  late final Map<_HomeSectionId, GlobalKey> _sectionKeys = {
    for (final id in _HomeSectionId.values)
      id: GlobalKey(debugLabel: 'home-section-${id.keySuffix}'),
  };
  late final Map<_HomeSectionId, GlobalKey> _sectionLandingKeys = {
    for (final id in _HomeSectionId.values)
      id: GlobalKey(debugLabel: 'home-section-landing-${id.keySuffix}'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _medicationsFuture = _loadMedications();
    UserDataService.instance.medicationsRevision.addListener(
      _onMedicationsChanged,
    );
    // The gate must re-evaluate on BOTH inputs: the acknowledgement changing
    // (the user completed a review) and the medicine list changing (which makes
    // it a different regimen, so a previous approval no longer applies).
    _reviews.revision.addListener(_syncReviewGate);
    unawaited(_syncReviewGate());
    _doseService.revision.addListener(_loadDoseSummary);
    _doseService.revision.addListener(_loadScheduleCount);
    _loadDoseSummary();
    _loadScheduleCount();
    UserDataService.instance.allergiesRevision.addListener(_loadAllergyCount);
    _loadAllergyCount();
    _loadLoginActivity();
    _subscribeToUserChanges();
    _scrollController.addListener(_onScrollSpy);
    // The bell's badge is derived from the same medication + dose data this
    // screen already watches, so rebuild it whenever either changes.
    UserDataService.instance.medicationsRevision.addListener(_refreshBadge);
    UserDataService.instance.allergiesRevision.addListener(_refreshBadge);
    _doseService.revision.addListener(_refreshBadge);
    _refreshBadge();
  }

  void _refreshBadge() {
    unawaited(NotificationCenter.instance.refreshBadge());
  }

  /// Scroll-spy: marks the pill for whichever primary section currently sits at
  /// the top of the viewport, so scrolling activates a pill exactly like a tap.
  ///
  /// The active section is the last one whose top has crossed an anchor line.
  /// At rest that anchor sits just below the pinned chrome. The trailing
  /// sections (Doses, Alerts) can't scroll their top that high — there isn't
  /// enough content beneath them — so the anchor glides downward as the feed
  /// runs out of scroll, letting each tail section light its pill as it rises
  /// into the lower viewport, with the final section locking in at the very end.
  void _onScrollSpy() {
    if (!mounted || _suppressScrollSpy) return;
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final responsive = MedGuardResponsive.of(context);
    final chromeH = _computeChromeHeight(responsive, media.padding.top);

    var anchor = chromeH + responsive.s(28);
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      final remaining = pos.maxScrollExtent - pos.pixels;
      final viewport = pos.viewportDimension;
      if (viewport > 0 && remaining < viewport) {
        final t = (1 - (remaining / viewport)).clamp(0.0, 1.0);
        anchor = lerpDouble(anchor, screenH * 0.88, t) ?? anchor;
      }
    }

    var active = _homeSectionTargets.first.id;
    for (final target in _homeSectionTargets) {
      final ctx = _sectionKeys[target.id]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= anchor) active = target.id;
    }

    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 4) {
        active = _homeSectionTargets.last.id;
      }
    }

    if (active != _activeSection) {
      setState(() => _activeSection = active);
    }
  }

  /// Marks today as an active login and loads the recent activity set so the
  /// home can show a real (never sample) login-consistency streak.
  Future<void> _loadLoginActivity() async {
    final clock = widget.now ?? DateTime.now;
    try {
      final days = await LoginActivityService.instance.recordToday(
        now: clock(),
      );
      if (!mounted) return;
      setState(() => _loginDays = days);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loginDays = {LoginActivityService.dayKey(clock())});
    }
  }

  /// On a warm resume (the app was backgrounded and reopened) re-record today's
  /// login and reload the streak — otherwise a streak stops growing across days
  /// because `initState` only ran on the original cold start. The dose/allergy
  /// signals are refreshed too so the home is current when the user comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _loadLoginActivity();
      _loadDoseSummary();
      _loadScheduleCount();
      _loadAllergyCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserDataService.instance.medicationsRevision.removeListener(
      _onMedicationsChanged,
    );
    _doseService.revision.removeListener(_loadDoseSummary);
    _doseService.revision.removeListener(_loadScheduleCount);
    UserDataService.instance.allergiesRevision.removeListener(
      _loadAllergyCount,
    );
    UserDataService.instance.medicationsRevision.removeListener(_refreshBadge);
    UserDataService.instance.allergiesRevision.removeListener(_refreshBadge);
    _doseService.revision.removeListener(_refreshBadge);
    _reviews.revision.removeListener(_syncReviewGate);
    _userSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Live count of recorded allergies for the Action Center. Missing store
  /// (fresh install / tests) reads as zero.
  Future<void> _loadAllergyCount() async {
    try {
      final allergies = await UserDataService.instance.getUserAllergies(
        _currentUserId(),
      );
      if (!mounted) return;
      setState(() {
        _allergyCount = allergies.length;
        _allergyLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allergyCount = 0;
        _allergyLoaded = true;
      });
    }
  }

  /// Live count of saved dose schedules for the Action Center.
  Future<void> _loadScheduleCount() async {
    try {
      final schedules = await _doseService.getSchedules(_currentUserId());
      if (!mounted) return;
      setState(() {
        _scheduleCount = schedules.length;
        _scheduleLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scheduleCount = 0;
        _scheduleLoaded = true;
      });
    }
  }

  void _openAllergyManager() {
    Navigator.of(context).pushNamed(AllergyManagementScreen.routeName);
  }

  /// Loads the real weekly dose snapshot for the "This Week" card. Null (no
  /// schedule data or the store is unavailable) renders the card's honest
  /// empty state — never sample figures.
  Future<void> _loadDoseSummary() async {
    try {
      final summary = await _doseService.weeklySummary(_currentUserId());
      if (!mounted) return;
      setState(() => _doseSummary = summary.hasData ? summary : null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _doseSummary = null);
    }
  }

  void _onMedicationsChanged() {
    if (!mounted) return;
    setState(() {
      _medicationsFuture = _loadMedications();
    });
    unawaited(_syncReviewGate());
  }

  /// Re-reads the review gate for whatever regimen is currently saved.
  ///
  /// The acknowledgement is keyed by the regimen's drug ids, so this closes the
  /// gate again by itself whenever a medicine is added or removed — the user is
  /// asked to review the new combination rather than inheriting the previous
  /// one's approval. Persisted, so the answer survives a refresh, a tab switch
  /// and a cold start.
  Future<void> _syncReviewGate() async {
    final userId = _currentUserId();
    await _reviews.load(userId);
    List<int> drugIds;
    try {
      drugIds = (await _medicationsFuture)
          .map((medication) => medication.drugId)
          .toList(growable: false);
    } catch (_) {
      drugIds = const [];
    }
    if (!mounted) return;
    final reviewed = _reviews.isReviewed(userId, drugIds);
    if (reviewed == _regimenReviewed) return;
    setState(() {
      _regimenReviewed = reviewed;
      // A regimen that just went back behind the gate must drop its cached
      // report too, so re-completing the review recomputes rather than
      // replaying the old verdict.
      if (!reviewed) {
        _reportFuture = null;
        _reportFingerprint = '';
      }
    });
  }

  /// Pull-to-refresh: reload every dashboard source, then swap the medications
  /// future for an already-resolved one so the cards never flash their loading
  /// skeleton under the refresh spinner.
  Future<void> _refresh() async {
    final meds = await _loadMedications();
    await Future.wait<void>([
      _loadDoseSummary(),
      _loadScheduleCount(),
      _loadAllergyCount(),
      _loadLoginActivity(),
    ]);
    if (!mounted) return;
    setState(() => _medicationsFuture = Future.value(meds));
  }

  void _subscribeToUserChanges() {
    try {
      _userSubscription = FirebaseAuth.instance.userChanges().listen((_) {
        if (!mounted) return;
        setState(() {});
      });
    } catch (_) {
      // Firebase not initialized in tests/local mode; header falls back to "Guest".
    }
  }

  Future<List<UserMedication>> _loadMedications() {
    final loader = widget.loadMedications;
    if (loader != null) return loader();
    return UserDataService.instance.getUserMedications(_currentUserId());
  }

  Future<SafetyReport> _analyzeRegimenRisk(List<UserMedication> medications) {
    final fingerprint = medications
        .map((medication) => medication.drugId)
        .join(',');
    final cached = _reportFuture;
    if (cached != null && fingerprint == _reportFingerprint) return cached;
    _reportFingerprint = fingerprint;
    final analyzer = widget.analyzeRegimenRisk;
    final future = analyzer != null
        ? analyzer(medications)
        // Pass the drug names + user id so the ML fallback predictor and
        // allergy checks run — this makes the home gauge compute the exact same
        // SafetyReport as the Safety Report screen, so the two can never
        // disagree on whether a regimen is dangerous. recordHistory is false so
        // the passive home analysis never writes to the check log.
        : InteractionChecker.analyze(
            medications
                .map((medication) => medication.drugId)
                .toList(growable: false),
            userId: _currentUserId(),
            drugs: medications
                .map(
                  (medication) =>
                      (id: medication.drugId, name: medication.drugName),
                )
                .toList(growable: false),
            recordHistory: false,
          );
    _reportFuture = future;
    // When a fresh regimen resolves to dangerous, surface it as a bottom-sheet
    // popup (once per regimen) instead of a banner pinned to the top of the feed.
    future
        .then((report) {
          if (!mounted) return;
          _maybeShowDangerSheet(fingerprint, report);
        })
        .catchError((_) {});
    return future;
  }

  /// Shows the danger details popup at most once per distinct regimen. Suppressed
  /// under widget tests so an auto-route never interferes with pumped frames.
  void _maybeShowDangerSheet(String fingerprint, SafetyReport report) {
    // Never ahead of the review. A popup announcing a dangerous regimen is the
    // loudest possible way to leak the analysis, so it waits for the same gate
    // as everything else.
    if (!_regimenReviewed) return;
    if (!report.isRegimenHighRisk) return;
    if (_dangerSheetShownFingerprints.contains(fingerprint)) return;
    _dangerSheetShownFingerprints.add(fingerprint);
    if (_runningUnderFlutterTest()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDangerDetailsSheet(
        context,
        report: report,
        onReview: () => _go(MedicationsScreen.routeName),
      );
    });
  }

  String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? _localUserId;
    } catch (_) {
      return _localUserId;
    }
  }

  String? _displayName() {
    String? firebaseName;
    try {
      firebaseName = FirebaseAuth.instance.currentUser?.displayName;
    } catch (_) {
      // Firebase unavailable (tests / offline) — fall through to the cache.
    }
    // Prefer the authenticated account's name; fall back to the locally saved
    // name (so a valid Google/email sign-in never reads as "Guest" even if the
    // auth user's displayName is momentarily empty). Deliberately no email
    // fallback: the header greets by name, never by email address. Returns null
    // only when genuinely no name exists, leaving the "Guest" label to the
    // header itself.
    final resolved = AuthProfilePreferences.resolveDisplayName(
      firebaseDisplayName: firebaseName,
      fallback: '',
    );
    return resolved.isEmpty ? null : resolved;
  }

  String? _photoUrl() {
    try {
      final url = FirebaseAuth.instance.currentUser?.photoURL?.trim();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  void _openProfile() => _go(ProfileScreen.routeName);

  Future<void> _openNotifications() async {
    await Navigator.of(context).pushNamed(NotificationsScreen.routeName);
    // Items read (or dismissed) on the feed must shrink the badge the moment
    // the user lands back here.
    unawaited(NotificationCenter.instance.refreshBadge());
  }

  void _go(String routeName) {
    if (routeName == SearchScreen.routeName && widget.onOpenSearch != null) {
      widget.onOpenSearch!();
      return;
    }
    if (routeName == MedicationsScreen.routeName &&
        widget.onOpenSafety != null) {
      widget.onOpenSafety!();
      return;
    }
    if (routeName == DoseScreen.routeName && widget.onOpenDose != null) {
      widget.onOpenDose!();
      return;
    }
    if (routeName == ProfileScreen.routeName && widget.onOpenProfile != null) {
      widget.onOpenProfile!();
      return;
    }
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  /// Tapping a pill scrolls its section flush under the pinned chrome. The
  /// scroll-spy is paused for the animation so it can't snap the active pill
  /// back to the first section while the feed is still moving.
  Future<void> _scrollToSection(_HomeSectionId sectionId) async {
    if (sectionId != _activeSection) {
      setState(() => _activeSection = sectionId);
    }
    final targetContext =
        _sectionLandingKeys[sectionId]?.currentContext ??
        _sectionKeys[sectionId]?.currentContext;
    final box = targetContext?.findRenderObject();
    if (box == null || !_scrollController.hasClients) return;
    _suppressScrollSpy = true;
    try {
      // Reveal the landing gap at the very top, then back off by the pinned
      // header height so the section sits just below the pinned pill bar rather
      // than tucked beneath it.
      final responsive = MedGuardResponsive.of(context);
      final chromeHeight = _computeChromeHeight(
        responsive,
        MediaQuery.paddingOf(context).top,
      );
      final viewport = RenderAbstractViewport.of(box);
      final reveal = viewport.getOffsetToReveal(box, 0).offset;
      final position = _scrollController.position;
      final target = (reveal - chromeHeight).clamp(
        0.0,
        position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) _suppressScrollSpy = false;
    }
  }

  /// The height the header occupies once fully collapsed and pinned. Scroll-spy
  /// and tap-to-section offset by this so a section lands just below the pinned
  /// pill bar (not tucked behind it).
  double _computeChromeHeight(MedGuardResponsive responsive, double topInset) =>
      homeHeaderMinExtent(responsive, topInset);

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final name = _displayName();
    final photoUrl = _photoUrl();
    final topInset = MediaQuery.paddingOf(context).top;

    // The header is a real sliver at the top of the feed: it scrolls up with the
    // content (greeting / name / big avatar sliding away) and, once the pills
    // reach the top, pins and rearranges into a single solid bar — the profile
    // pinned at the far left with the pills scrolling behind it.
    final feed = CustomScrollView(
      key: const ValueKey('home-scroll-view'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HomeHeaderDelegate(
            name: name,
            photoUrl: photoUrl,
            topInset: topInset,
            minExtentValue: homeHeaderMinExtent(responsive, topInset),
            maxExtentValue: homeHeaderMaxExtent(responsive, topInset),
            onAvatarTap: _openProfile,
            onBellTap: _openNotifications,
            connectivityService: widget.connectivityService,
            activeSection: _activeSection,
            onSectionSelected: _scrollToSection,
            brightness: Theme.of(context).brightness,
          ),
        ),
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: FutureBuilder<List<UserMedication>>(
                future: _medicationsFuture,
                builder: (context, snapshot) {
                  final meds = snapshot.data ?? const [];
                  return _HomeDashboard(
                    medications: meds,
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                    onSearch: () => _go(SearchScreen.routeName),
                    onSafety: () => _go(MedicationsScreen.routeName),
                    onDose: () => _go(DoseScreen.routeName),
                    onEmergencyCard: () => Navigator.of(
                      context,
                    ).pushNamed(EmergencyScreen.routeName),
                    sectionKeys: _sectionKeys,
                    sectionLandingKeys: _sectionLandingKeys,
                    analyzeRegimenRisk: _analyzeRegimenRisk,
                    doseSummary: _doseSummary,
                    doseService: _doseService,
                    doseUserId: _currentUserId(),
                    now: widget.now ?? DateTime.now,
                    profileComplete: _displayName() != null,
                    allergyCount: _allergyCount,
                    allergyLoaded: _allergyLoaded,
                    scheduleCount: _scheduleCount,
                    scheduleLoaded: _scheduleLoaded,
                    onManageAllergies: _openAllergyManager,
                    onOpenNotifications: _openNotifications,
                    onOpenProfile: _openProfile,
                    loginDays: _loginDays,
                    riskAnimationNonce: widget.homeRevisitNonce,
                    regimenReviewed: _regimenReviewed,
                  );
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            key: const ValueKey('home-bottom-content-spacer'),
            height: screenEndContentInset(
              context,
              reserveFloatingNav:
                  !widget.showNavigation && widget.bottomContentPadding > 0,
            ),
          ),
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: context.colors.scaffold,
        // A barely-there depth system sits beneath the feed: a few large, very
        // soft circular gradients drawn from the brand palette. They read as
        // almost-invisible atmosphere — the white cards float a touch more — and
        // never compete with content.
        body: Stack(
          children: [
            // Static atmosphere — isolated in its own layer so it rasterises
            // once and never repaints while the feed scrolls over it.
            const Positioned.fill(
              child: RepaintBoundary(child: SoftPageBackground()),
            ),
            RefreshIndicator(
              onRefresh: _refresh,
              color: context.colors.accent,
              backgroundColor: context.colors.surface,
              child: feed,
            ),
          ],
        ),
        bottomNavigationBar: widget.showNavigation
            ? const FloatingNavBar(current: AppNavTab.home)
            : null,
      ),
    );
  }
}

/// True while a Flutter widget test is driving the binding — used so live
/// streams (connectivity) render a deterministic state in tests.
bool _runningUnderFlutterTest() {
  try {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
  } catch (_) {
    return false;
  }
}

/// The collapsing header delegate. While the feed is at the top it shows the
/// full chrome — greeting + name on the left, a large avatar on the right, the
/// section pills beneath. As the feed scrolls, the greeting / name / big avatar
/// slide up and fade, and once the pills reach the top the header pins as a
/// single solid bar: the profile avatar fixed at the far left (its own opaque
/// background bleeding to the screen edge) with the pills scrolling behind it.
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HomeHeaderDelegate({
    required this.name,
    required this.photoUrl,
    required this.topInset,
    required this.minExtentValue,
    required this.maxExtentValue,
    required this.onAvatarTap,
    required this.onBellTap,
    required this.connectivityService,
    required this.activeSection,
    required this.onSectionSelected,
    required this.brightness,
  });

  final String? name;
  final String? photoUrl;

  /// The active theme brightness. Compared in [shouldRebuild] so a light/dark
  /// switch repaints the pinned header IMMEDIATELY — previously it kept its
  /// old colours until the next scroll forced a rebuild.
  final Brightness brightness;

  /// The status-bar inset. The bar consumes it itself (rather than sitting in a
  /// SafeArea) so its solid fill reaches the very top of the screen.
  final double topInset;
  final double minExtentValue;
  final double maxExtentValue;
  final VoidCallback onAvatarTap;
  final VoidCallback onBellTap;
  final ConnectivityService? connectivityService;
  final _HomeSectionId activeSection;
  final ValueChanged<_HomeSectionId> onSectionSelected;

  @override
  double get minExtent => minExtentValue;

  @override
  double get maxExtent => maxExtentValue;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  /// The name shown beside the greeting: the full name when it comfortably fits,
  /// otherwise the longest single part (so "Maximilian Schwartzenberger" reads as
  /// the longer of the two names rather than truncating mid-word).
  String _displayName() {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'Guest';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return parts.first;
    if (trimmed.length > 16) {
      return parts.reduce((a, b) => b.length >= a.length ? b : a);
    }
    return trimmed;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final responsive = MedGuardResponsive.of(context);
    final pageX = responsive.pageX;
    final avatarSize = _hdrAvatarSize(responsive);
    final headerRowHeight = _hdrHeaderRowHeight(responsive);
    final pillH = _hdrPillHeight(responsive);
    final spaceUnder = _hdrSpaceUnder(responsive);
    final topPadExtra = _hdrTopPadExtra(responsive);
    final textGap = _hdrTextGap(responsive);

    final range = maxExtentValue - minExtentValue;
    // 0 while expanded → 1 once fully collapsed and pinned.
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // The greeting / name / big avatar fade out early in the collapse.
    final topOpacity = (1.0 - t * 1.8).clamp(0.0, 1.0);
    // The little left-pinned profile + its background fade in late, as the bar
    // settles into its single-row pinned form.
    final profileShow = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    // The separating hairline + shadow appear as soon as the feed leaves the top.
    final edge = (shrinkOffset / 12.0).clamp(0.0, 1.0);

    // The pinned avatar has no panel of its own: it simply sits on the bar, and
    // the pill row FADES to nothing as it slides under the avatar (a soft left
    // mask, never a solid cover) so the pills dissolve seamlessly into the bar
    // with no visible edge. A clear gap sits between the avatar and the first
    // pill, which is exactly where the fade finishes.
    final pillGap = responsive.s(20).clamp(16.0, 24.0).toDouble();
    final pillsLeadingInset = pageX + (pillH + pillGap) * profileShow;
    // Where the pill-row fade starts/ends (px from the left). Pills are fully
    // erased across the WHOLE avatar (and a little into the gap) so none can peek
    // out beside the round avatar, then they dissolve back to solid by the time
    // the first pill begins — so nothing is ever visible behind the profile.
    final fadeHideTo = pageX + pillH + pillGap * 0.35;
    final fadeClearAt = pageX + pillH + pillGap;
    // How far the bar's bottom shadow is allowed to spill onto the feed below.
    final barShadowSpill = responsive.s(16).clamp(12.0, 20.0).toDouble();

    final textBlock = Pressable(
      onTap: onAvatarTap,
      pressScale: 0.99,
      child: Column(
        key: const ValueKey('home-header-text-stack'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getGreeting(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: responsive.font(13),
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
          SizedBox(
            key: const ValueKey('home-header-text-gap'),
            height: textGap,
          ),
          Text(
            _displayName(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: responsive.font(22),
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );

    return KeyedSubtree(
      key: const ValueKey('home-pinned-header'),
      child: ClipRect(
        // Clips the top/sides (so the greeting slides up out of view) but lets
        // the bar's drop shadow spill below onto the feed scrolling under it.
        clipper: _HeaderBottomShadowClip(barShadowSpill),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The solid bar background — visual only, so taps fall through to the
            // feed beneath; only the pills and the avatar absorb touches. The
            // opaque off-white fill and its soft bottom shadow fade in with
            // scroll, so the bar is seamless with the feed at the very top and
            // reads as a clean pinned bar — with the content visibly sliding
            // under its shadowed bottom edge — once the feed leaves the top.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.scaffold.withValues(alpha: edge),
                    boxShadow: edge <= 0
                        ? null
                        : [
                            BoxShadow(
                              color: MedGuardPalette.inkAlpha(0.06 * edge),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                  ),
                ),
              ),
            ),
            // Greeting + name on the left; on the right, the notification bell
            // and the profile avatar share one clear liquid-glass capsule. The
            // whole row slides up with the scroll and fades.
            Positioned(
              top: topInset + topPadExtra - shrinkOffset,
              left: pageX,
              right: pageX,
              height: headerRowHeight,
              child: IgnorePointer(
                ignoring: topOpacity < 0.5,
                child: Opacity(
                  opacity: topOpacity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: textBlock),
                      SizedBox(width: responsive.s(12)),
                      _HeaderGlassActions(
                        avatarSize: avatarSize,
                        name: name,
                        photoUrl: photoUrl,
                        onAvatarTap: onAvatarTap,
                        onBellTap: onBellTap,
                        connectivityService: connectivityService,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The pinned pill row band: the pills sit on the bar's bottom edge at
            // rest and ease up to leave `spaceUnder` beneath them as the bar
            // collapses. As the pills scroll left they FADE OUT before reaching
            // the avatar — a soft left mask dissolves them straight into the bar,
            // so there's no panel and no edge behind the profile, just a clean
            // blend. The avatar is the lone mark at the far left.
            Positioned(
              left: 0,
              right: 0,
              bottom: spaceUnder * t,
              height: pillH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: profileShow <= 0
                        ? _HomeSectionFilterRow(
                            targets: _homeSectionTargets,
                            active: activeSection,
                            onSelected: onSectionSelected,
                            leadingInset: pillsLeadingInset,
                          )
                        : ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) {
                              final w = bounds.width <= 0 ? 1.0 : bounds.width;
                              final hideTo = (fadeHideTo / w).clamp(0.0, 1.0);
                              final clearAt = (fadeClearAt / w).clamp(
                                hideTo,
                                1.0,
                              );
                              // Left of the avatar the pills are erased (alpha 0
                              // when pinned), ramping to fully opaque past the
                              // gap — so they melt into the bar with no seam.
                              final hidden = Colors.white.withValues(
                                alpha: 1 - profileShow,
                              );
                              return LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  hidden,
                                  hidden,
                                  Colors.white,
                                  Colors.white,
                                ],
                                stops: [0.0, hideTo, clearAt, 1.0],
                              ).createShader(bounds);
                            },
                            child: _HomeSectionFilterRow(
                              targets: _homeSectionTargets,
                              active: activeSection,
                              onSelected: onSectionSelected,
                              leadingInset: pillsLeadingInset,
                            ),
                          ),
                  ),
                  if (profileShow > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: pageX),
                        child: Opacity(
                          opacity: profileShow,
                          child: AccountAvatar(
                            name: name,
                            photoUrl: photoUrl,
                            size: pillH,
                            onTap: onAvatarTap,
                            connectivityService: connectivityService,
                            avatarKey: const ValueKey('home-collapsed-avatar'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate oldDelegate) =>
      name != oldDelegate.name ||
      photoUrl != oldDelegate.photoUrl ||
      topInset != oldDelegate.topInset ||
      minExtentValue != oldDelegate.minExtentValue ||
      maxExtentValue != oldDelegate.maxExtentValue ||
      activeSection != oldDelegate.activeSection ||
      brightness != oldDelegate.brightness;
}

/// The header's trailing action cluster: the notification bell and the profile
/// avatar sharing the app's standard [HeaderGlassActions] capsule.
///
/// The glass itself lives in the shared widget so the Dose header can carry the
/// identical treatment; this wrapper only supplies Home's specific action — the
/// bell, which opens the notification feed and carries a live unread badge fed
/// by [NotificationCenter].
class _HeaderGlassActions extends StatelessWidget {
  const _HeaderGlassActions({
    required this.avatarSize,
    required this.name,
    required this.photoUrl,
    required this.onAvatarTap,
    required this.onBellTap,
    required this.connectivityService,
  });

  final double avatarSize;
  final String? name;
  final String? photoUrl;
  final VoidCallback onAvatarTap;
  final VoidCallback onBellTap;
  final ConnectivityService? connectivityService;

  @override
  Widget build(BuildContext context) {
    return HeaderGlassActions(
      key: const ValueKey('home-header-glass-actions'),
      avatarSize: avatarSize,
      name: name,
      photoUrl: photoUrl,
      onAvatarTap: onAvatarTap,
      connectivityService: connectivityService,
      avatarKey: const ValueKey('home-account-avatar'),
      statusDotKey: const ValueKey('home-avatar-connection-dot'),
      actions: [
        NotificationBell(
          key: const ValueKey('home-header-bell'),
          size: avatarSize,
          onTap: onBellTap,
          badgeKey: const ValueKey('home-header-bell-badge'),
        ),
      ],
    );
  }
}

// A slightly longer ease so the active-pill colour glides as you scroll-spy.
const _homePillActiveDuration = Duration(milliseconds: 240);

/// The horizontal section-pill row in the pinned chrome. The active pill is
/// owned by the home screen so it can be set by EITHER a tap or the scroll-spy;
/// the row glides to keep the live pill centred so the last pill is as reachable
/// as the first.
class _HomeSectionFilterRow extends StatefulWidget {
  const _HomeSectionFilterRow({
    required this.targets,
    required this.active,
    required this.onSelected,
    this.leadingInset = 0,
  });

  final List<_HomeSectionTarget> targets;
  final _HomeSectionId active;
  final ValueChanged<_HomeSectionId> onSelected;

  /// Empty space before the first pill. Used by the collapsing header to hold
  /// the pills clear of the pinned profile (and let them scroll behind it).
  final double leadingInset;

  @override
  State<_HomeSectionFilterRow> createState() => _HomeSectionFilterRowState();
}

class _HomeSectionFilterRowState extends State<_HomeSectionFilterRow> {
  final ScrollController _controller = ScrollController();
  late final Map<_HomeSectionId, GlobalKey> _chipKeys = {
    for (final target in widget.targets) target.id: GlobalKey(),
  };

  @override
  void didUpdateWidget(covariant _HomeSectionFilterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Glides the row so the live pill is centred and never stranded off the right
  /// edge — so the last pill is just as visible as the first when active.
  ///
  /// This moves only the row's own horizontal controller. (Crucially NOT
  /// `Scrollable.ensureVisible`, which would also walk up to the main vertical
  /// feed — the pills now live inside it — and fight the user's scroll.)
  void _revealActive() {
    if (!mounted || !_controller.hasClients) return;
    final ctx = _chipKeys[widget.active]?.currentContext;
    final chipBox = ctx?.findRenderObject();
    final viewportBox = context.findRenderObject();
    if (chipBox is! RenderBox ||
        !chipBox.hasSize ||
        viewportBox is! RenderBox ||
        !viewportBox.hasSize) {
      return;
    }
    final chipCentre = viewportBox
        .globalToLocal(chipBox.localToGlobal(chipBox.size.center(Offset.zero)))
        .dx;
    final position = _controller.position;
    final target =
        (_controller.offset + (chipCentre - viewportBox.size.width / 2)).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = responsive.s(9).clamp(8.0, 11.0).toDouble();

    return SingleChildScrollView(
      key: const ValueKey('home-section-filter-row'),
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          if (widget.leadingInset > 0) SizedBox(width: widget.leadingInset),
          for (var i = 0; i < widget.targets.length; i++) ...[
            KeyedSubtree(
              key: _chipKeys[widget.targets[i].id],
              child: _HomeSectionFilterChip(
                target: widget.targets[i],
                armed: widget.active == widget.targets[i].id,
                onTap: () => widget.onSelected(widget.targets[i].id),
              ),
            ),
            if (i != widget.targets.length - 1) SizedBox(width: gap),
          ],
          // Trailing breathing room so the last pill clears the right edge when
          // the row is scrolled to its end, matching the page margin.
          SizedBox(width: responsive.pageX),
        ],
      ),
    );
  }
}

class _HomeSectionFilterChip extends StatelessWidget {
  const _HomeSectionFilterChip({
    required this.target,
    required this.armed,
    required this.onTap,
  });

  final _HomeSectionTarget target;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // Shares the header geometry's pill height so the bar reserves exactly the
    // right space; kept deliberately compact.
    final height = _hdrPillHeight(responsive);
    final iconSize = responsive.icon(13);

    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      child: AnimatedContainer(
        key: ValueKey('home-section-filter-${target.id.keySuffix}'),
        duration: _homePillActiveDuration,
        curve: Curves.easeOutCubic,
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(10).clamp(9.0, 12.0).toDouble(),
        ),
        decoration: BoxDecoration(
          color: armed ? MedGuardPalette.teal : context.colors.surface,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: armed ? MedGuardPalette.teal : context.colors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: armed
                  ? context.colors.accentAlpha(0.14)
                  : MedGuardPalette.inkAlpha(0.025),
              blurRadius: responsive.s(10),
              offset: Offset(0, responsive.s(4)),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              target.icon,
              color: armed ? MedGuardPalette.pureWhite : target.iconColor,
              size: iconSize,
            ),
            SizedBox(width: responsive.s(5)),
            Text(
              target.label,
              style: GoogleFonts.inter(
                color: armed
                    ? MedGuardPalette.pureWhite
                    : context.colors.inkSoft,
                fontSize: responsive.font(11.5),
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.medications,
    required this.loading,
    required this.onSearch,
    required this.onSafety,
    required this.onDose,
    required this.onEmergencyCard,
    required this.sectionKeys,
    required this.sectionLandingKeys,
    required this.analyzeRegimenRisk,
    required this.regimenReviewed,
    required this.doseSummary,
    required this.doseService,
    required this.doseUserId,
    required this.now,
    required this.profileComplete,
    required this.allergyCount,
    required this.allergyLoaded,
    required this.scheduleCount,
    required this.scheduleLoaded,
    required this.onManageAllergies,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.loginDays,
    this.riskAnimationNonce = 0,
  });

  final List<UserMedication> medications;
  final bool loading;

  /// Incremented when the Home screen is revisited so the regimen-risk needle
  /// re-sweeps from the lowest position to the live verdict.
  final int riskAnimationNonce;
  final VoidCallback onSearch;
  final VoidCallback onSafety;
  final VoidCallback onDose;
  final VoidCallback onEmergencyCard;
  final Map<_HomeSectionId, GlobalKey> sectionKeys;
  final Map<_HomeSectionId, GlobalKey> sectionLandingKeys;
  final AnalyzeRegimenRisk analyzeRegimenRisk;
  final DoseSummary? doseSummary;
  final DoseService doseService;
  final String doseUserId;
  final DateTime Function() now;

  /// Whether the interaction review has been completed for this exact regimen.
  /// Gates every analysis-derived surface on the feed.
  final bool regimenReviewed;

  // ── Action Center signals (all real, no fake state) ──
  final bool profileComplete;
  final int allergyCount;
  final bool allergyLoaded;
  final int scheduleCount;
  final bool scheduleLoaded;
  final VoidCallback onManageAllergies;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;

  /// Recorded active login days (yyyy-mm-dd) for the consistency strip.
  final Set<String> loginDays;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final sectionGap = MedGuardSpacing.sectionDivider(responsive);
    // The gate only bites once there is a regimen worth reviewing.

    // The greeting / name / avatar header scrolls above this feed. The feed
    // reads top-to-bottom as: Quick Access → Regimen Risk → Care Insights →
    // Dose Schedule → Status Alerts, with the lighter editorial / log strips
    // tucked between them. Every gap that divides one block from the next is
    // exactly one [sectionGap] for an even rhythm.
    return Column(
      children: [
        // One standardised section gap between the header and the caption — the
        // same spacing that divides every major section.
        SizedBox(
          key: const ValueKey('home-header-content-gap'),
          height: sectionGap,
        ),
        // A dangerous regimen now surfaces as a bottom-sheet popup (driven from
        // the home state when the live report resolves), not a banner pinned to
        // the top of the feed.
        // ── Powerful, quietly-changing app caption ───────────────────
        const _HomeAppCaption(),
        // The caption + Welcome card read as one intro cluster, so the gap
        // between them is half a section beat (tighter than the full dividers).
        SizedBox(height: sectionGap / 2),
        // ── Login consistency strip ──────────────────────────────────
        _LoginStreakSection(loginDays: loginDays, now: now),

        // ── Quick Access ─────────────────────────────────────────────
        KeyedSubtree(
          key: sectionLandingKeys[_HomeSectionId.quickAccess],
          child: SizedBox(
            key: const ValueKey('home-post-library-gap'),
            height: sectionGap,
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_HomeSectionId.quickAccess],
          child: _QuickAccessSection(
            onSearch: onSearch,
            onSafety: onSafety,
            onDose: onDose,
            onAllergies: onManageAllergies,
            onEmergencyCard: onEmergencyCard,
          ),
        ),

        // ── Regimen Risk ──────────────────────────────────────────────
        //
        // The SAME component Interactions renders, in its compact form: same
        // report, same scoring, same wording, same meter. Home shows the
        // verdict and one way through; Interactions shows the reasoning and the
        // controls. Because it is one widget rather than a summary written
        // twice, the two screens cannot drift apart.
        KeyedSubtree(
          key: sectionLandingKeys[_HomeSectionId.risk],
          child: SizedBox(
            key: const ValueKey('home-section-gap-after-quick-access'),
            height: sectionGap,
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_HomeSectionId.risk],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeSectionHeader(
                title: 'Regimen Risk',
                action: medications.length >= 2 && !regimenReviewed
                    ? 'Review required'
                    : 'Auto-checked',
                subtitle: medications.length >= 2 && !regimenReviewed
                    ? 'Complete the interaction review to activate.'
                    : 'Live checks for risky combinations.',
              ),
              SizedBox(height: responsive.s(14).clamp(12.0, 16.0).toDouble()),
              RegimenRiskCard(
                compact: true,
                // The identical control Interactions shows, in the same words.
                actionLabel: medications.length >= 2
                    ? 'Review ${medications.length} medicines'
                    : 'Review',
                medications: medications,
                loading: loading,
                regimenReviewed: regimenReviewed,
                animationNonce: riskAnimationNonce,
                onReview: onSafety,
                onLearnMore: onSafety,
                analyzeRegimenRisk: analyzeRegimenRisk,
              ),
            ],
          ),
        ),

        // ── Care Insights ────────────────────────────────────────────
        KeyedSubtree(
          key: sectionLandingKeys[_HomeSectionId.insights],
          child: SizedBox(
            key: const ValueKey('home-section-gap-after-risk'),
            height: sectionGap,
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_HomeSectionId.insights],
          child: const _CareInsightSection(),
        ),

        // ── Medication truth (editorial note) ────────────────────────
        SizedBox(
          key: const ValueKey('home-section-gap-after-insights'),
          height: sectionGap,
        ),
        const _MedicationTruthSection(),

        // ── Dose Schedule ────────────────────────────────────────────
        KeyedSubtree(
          key: sectionLandingKeys[_HomeSectionId.dose],
          child: SizedBox(
            key: const ValueKey('home-section-gap-before-dose'),
            height: sectionGap,
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_HomeSectionId.dose],
          child: _DosesSection(
            onOpenDose: onDose,
            doseService: doseService,
            userId: doseUserId,
            now: now,
            summary: doseSummary,
          ),
        ),

        // ── Did you know (editorial note) ────────────────────────────
        SizedBox(
          key: const ValueKey('home-section-gap-after-dose'),
          height: sectionGap,
        ),
        const _DidYouKnowSection(),

        // ── Alerts — app-wide status summary at the end ──────────────
        KeyedSubtree(
          key: sectionLandingKeys[_HomeSectionId.alerts],
          child: SizedBox(
            key: const ValueKey('home-section-gap-before-alerts'),
            height: sectionGap,
          ),
        ),
        KeyedSubtree(
          key: sectionKeys[_HomeSectionId.alerts],
          child: _HomeAlertsSection(
            profileComplete: profileComplete,
            allergyCount: allergyCount,
            allergyLoaded: allergyLoaded,
            scheduleCount: scheduleCount,
            scheduleLoaded: scheduleLoaded,
            onCompleteProfile: onOpenProfile,
            onManageAllergies: onManageAllergies,
            onSetReminder: onDose,
            onOpenNotifications: onOpenNotifications,
          ),
        ),
      ],
    );
  }
}

/// Slides the danger details popup up from the bottom. It lists every dangerous
/// concern in the regimen and offers a "Review medicines" action plus a "Skip"
/// that simply dismisses the sheet.
Future<void> showDangerDetailsSheet(
  BuildContext context, {
  required SafetyReport report,
  required VoidCallback onReview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: MedGuardPalette.blackAlpha(0.45),
    builder: (sheetContext) => _DangerDetailsSheet(
      report: report,
      onReview: () {
        Navigator.of(sheetContext).pop();
        onReview();
      },
      onSkip: () => Navigator.of(sheetContext).pop(),
    ),
  );
}
