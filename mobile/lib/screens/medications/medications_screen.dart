import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/interaction_result.dart';
import '../../models/regimen_analysis.dart';
import '../../models/safety_report.dart';
import '../../models/severity.dart';
import '../../models/user_medication.dart';
import '../../services/database_service.dart';
import '../../services/interaction_checker.dart';
import '../../services/regimen_analyser.dart';
import '../../services/regimen_review_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/floating_nav_bar.dart';
import '../../widgets/common/page_background.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/surface_card.dart';
import '../../widgets/safety/regimen_risk.dart';
import '../profile/profile_screen.dart';
import '../safety/safety_report_screen.dart';
import '../search/search_screen.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/app_snack.dart';

part 'widgets/regimen_risk_panel.dart';

const String _localUserId = 'local-device';

/// The Interactions tab — where a regimen is assembled, reviewed, and only then
/// spoken about.
///
/// **Nothing is asserted until the user asks for it.** Adding a medicine
/// changes the regimen and therefore invalidates whatever was last reviewed;
/// the page immediately falls silent — no verdict, no counts, no findings —
/// until Review is pressed again. Every section stays on screen throughout, so
/// the page always shows what it *will* tell you, but none of them claim a
/// result they do not have.
///
/// That rule is not a UI preference. Analysis appearing on its own the moment a
/// second medicine is saved would mean the app had assessed a regimen the user
/// never confirmed was current — and a stale "All clear" is the most dangerous
/// thing a safety tool can display. [RegimenReviewService] holds the gate; this
/// screen is where it is opened.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({
    super.key,
    this.showNavigation = true,
    this.bottomContentPadding = 0,
    this.onOpenProfile,
    this.loadMedications,
    this.runReview,
  });

  static const String routeName = '/medications';

  final bool showNavigation;
  final double bottomContentPadding;

  /// Opens the profile screen from the header avatar.
  final VoidCallback? onOpenProfile;

  /// Injectable loaders so the flow can be driven in tests without a store.
  final Future<List<UserMedication>> Function()? loadMedications;
  final Future<SafetyReport> Function(List<UserMedication>)? runReview;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  final RegimenReviewService _reviews = RegimenReviewService.current;

  List<UserMedication> _medications = const [];

  /// The drug ids staged for the next review. Defaults to everything — the
  /// common case is "check my whole regimen"; the selector exists for the
  /// narrower question, not the usual one.
  Set<int> _selected = const {};

  /// Every drug id this screen has seen, so a medicine added while the page is
  /// open joins the selection, while one the user deliberately unticked stays
  /// out.
  Set<int> _seenIds = const {};

  /// The results. Null until a review has been run for the CURRENT selection —
  /// this nullness is the gate, and everything the page states is derived from
  /// it rather than from a separate flag that could fall out of step.
  SafetyReport? _report;
  RegimenAnalysis? _analysis;

  bool _loadingMedicines = true;
  bool _running = false;
  bool _failed = false;

  DateTime? _reviewedAt;

  /// Guards against an older, slower run landing after a newer one.
  int _runSerial = 0;

  @override
  void initState() {
    super.initState();
    UserDataService.instance.medicationsRevision.addListener(_onDataChanged);
    _reviews.revision.addListener(_onDataChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    UserDataService.instance.medicationsRevision.removeListener(_onDataChanged);
    _reviews.revision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  String _userId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? _localUserId;
    } catch (_) {
      return _localUserId;
    }
  }

  Future<List<UserMedication>> _loadMedications() {
    final loader = widget.loadMedications;
    if (loader != null) return loader();
    return UserDataService.instance.getUserMedications(_userId());
  }

  List<UserMedication> get _included =>
      _medications.where((m) => _selected.contains(m.drugId)).toList();

  bool get _checkable => _included.length >= 2;

  /// True once results exist for exactly what is selected now.
  bool get _hasResults => _report != null;

  Future<void> _load() async {
    final userId = _userId();
    await _reviews.load(userId);
    List<UserMedication> medications;
    try {
      medications = await _loadMedications();
    } catch (_) {
      medications = const [];
    }
    if (!mounted) return;

    final ids = medications.map((m) => m.drugId).toSet();
    final firstLoad = _loadingMedicines;
    final previousSelection = _selected;

    setState(() {
      _medications = medications;
      _selected = firstLoad
          ? ids
          : {..._selected.where(ids.contains), ...ids.difference(_seenIds)};
      _seenIds = ids;
      _loadingMedicines = false;
    });

    // The regimen changed underneath whatever was last reviewed — drop the
    // results rather than letting them describe a set that no longer exists.
    if (!firstLoad && !_sameSet(previousSelection, _selected)) {
      _discardResults();
    }
  }

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _discardResults() {
    _runSerial++;
    if (!mounted) return;
    setState(() {
      _report = null;
      _analysis = null;
      _reviewedAt = null;
      _failed = false;
      _running = false;
    });
  }

  void _toggle(int drugId) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = _selected.contains(drugId)
          ? ({..._selected}..remove(drugId))
          : ({..._selected}..add(drugId));
    });
    // Changing what is being checked invalidates what was said about it.
    _discardResults();
  }

  void _selectAll() {
    HapticFeedback.selectionClick();
    setState(() => _selected = _medications.map((m) => m.drugId).toSet());
    _discardResults();
  }

  void _selectNone() {
    HapticFeedback.selectionClick();
    setState(() => _selected = const {});
    _discardResults();
  }

  /// The one action that makes the page speak.
  Future<void> _review() async {
    if (!_checkable || _running) return;
    HapticFeedback.mediumImpact();
    final included = _included;
    final ids = included.map((m) => m.drugId).toList(growable: false);
    final serial = ++_runSerial;

    setState(() {
      _running = true;
      _failed = false;
    });

    try {
      final runner = widget.runReview;
      // Recorded to the audit history: this IS the user's deliberate check.
      final report = runner != null
          ? await runner(included)
          : await InteractionChecker.analyze(
              ids,
              userId: _userId(),
              drugs: included
                  .map((m) => (id: m.drugId, name: m.drugName))
                  .toList(growable: false),
            );
      if (!mounted || serial != _runSerial) return;

      // The findings land the moment they are known. The metabolic pass below
      // is a SECOND, slower query, and it deliberately does not gate this: it
      // used to be awaited here, which meant a slow — or, with no database
      // available, a never-completing — enzyme lookup left the page saying
      // "checking" forever while the results sat in hand.
      setState(() {
        _report = report;
        _reviewedAt = DateTime.now();
        _running = false;
      });

      unawaited(_loadPathways(included, report, serial));

      // Activates the regimen's verdicts everywhere else in the app. Kept
      // separate from the analysis above so a preferences failure cannot cost
      // the user the results they just waited for.
      try {
        await _reviews.markReviewed(_userId(), ids);
      } catch (_) {}

      // Reviewing takes you to the findings. Staying put and asking the user
      // to find a second button is what made the page feel like it had done
      // nothing.
      if (mounted) _openReport();
    } catch (_) {
      if (!mounted || serial != _runSerial) return;
      setState(() {
        _running = false;
        _failed = true;
      });
    }
  }

  /// The metabolic-cascade pass, folded into the page whenever it resolves.
  ///
  /// Entirely optional: losing it costs the "Metabolic pathways" section and
  /// nothing else, so every failure here is swallowed rather than surfaced.
  Future<void> _loadPathways(
    List<UserMedication> included,
    SafetyReport report,
    int serial,
  ) async {
    try {
      final enzymes = await DatabaseService.instance.getDrugEnzymes(
        included.map((m) => m.drugId).toList(growable: false),
      );
      if (!mounted || serial != _runSerial) return;
      setState(() {
        _analysis = RegimenAnalyser.analyze(
          medications: included,
          report: report,
          enzymeRecords: enzymes,
        );
      });
    } catch (_) {
      // No pathways section this time.
    }
  }

  void _openReport() {
    if (!_hasResults) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SafetyReportScreen(userId: _userId(), medications: _included),
      ),
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

  /// Takes a medicine out of the regimen entirely.
  ///
  /// The rail could already exclude one from a check; it could not delete one,
  /// so the only way to correct a mis-added medicine was to go and find it in
  /// another screen. Adding and removing belong in the same place.
  Future<void> _removeMedicine(UserMedication medication) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Remove ${medication.displayName}?',
      message:
          'It comes out of your regimen entirely, and anything already '
          'reviewed will need reviewing again. Dose schedules for it are kept.',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed != true) return;
    try {
      await UserDataService.instance.removeMedicationByDrug(
        userId: _userId(),
        drugId: medication.drugId,
      );
      if (!mounted) return;
      AppSnack.success(context, '${medication.displayName} removed');
    } catch (_) {
      if (!mounted) return;
      AppSnack.error(context, 'Could not remove ${medication.displayName}');
    }
  }

  void _openSearch() {
    Navigator.of(context).pushNamed(SearchScreen.routeName);
  }

  void _addMedicine() {
    Navigator.of(context).pushNamed(SearchScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final gap = sectionGap(responsive);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(colors),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        body: PageBackground(
          tone: PageTone.clinical,
          child: SafeArea(
            bottom: false,
            child: responsive.constrain(
              ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  0,
                  MedGuardSpacing.screenTop(responsive),
                  0,
                  0,
                ),
                children: [
                  // The header keeps the page's horizontal inset; the regimen
                  // rail below deliberately does not, so it can run to the edge.
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.pageX,
                    ),
                    child: PageHeader(
                      title: 'Interactions',
                      subtitle: _headerSubtitle(),
                      onOpenProfile: _openProfile,
                      // The same slot Home fills with its notification bell,
                      // at the same size, so the two headers are one object
                      // with a different action in it.
                      actions: [
                        HeaderIconAction(
                          key: const ValueKey('interactions-header-search'),
                          icon: Icons.search_rounded,
                          size: headerAvatarSize(responsive),
                          onTap: _openSearch,
                          semanticLabel: 'Search medicines',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: responsive.s(16)),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.pageX,
                    ),
                    child: _PagePill(
                      medicineCount: _medications.length,
                      reviewed: _hasResults,
                      running: _running,
                    ),
                  ),
                  SizedBox(height: gap),

                  // ── What will be checked ────────────────────────────────
                  _RegimenRail(
                    medications: _medications,
                    selected: _selected,
                    loading: _loadingMedicines,
                    running: _running,
                    onToggle: _toggle,
                    onAll: _selectAll,
                    onNone: _selectNone,
                    onAdd: _addMedicine,
                    onRemove: (m) => unawaited(_removeMedicine(m)),
                  ),
                  SizedBox(height: gap),

                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.pageX,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── The verdict ─────────────────────────────────
                        _RiskSection(
                          medications: _included,
                          report: _report,
                          running: _running,
                          failed: _failed,
                          checkable: _checkable,
                          reviewedAt: _reviewedAt,
                          onReview: () {
                            if (_hasResults) {
                              _openReport();
                            } else {
                              unawaited(_review());
                            }
                          },
                          onOpenReport: _openReport,
                        ),
                        SizedBox(height: gap),

                        // ── The four checks ─────────────────────────────
                        _SafetyAxes(
                          report: _report,
                          running: _running,
                          checkable: _checkable,
                        ),
                        SizedBox(height: gap),

                        // ── Findings ────────────────────────────────────
                        _FindingsSection(
                          report: _report,
                          running: _running,
                          checkable: _checkable,
                          onOpenReport: _openReport,
                        ),

                        // ── Metabolism, when there is any ───────────────
                        if (_analysis?.cascades.isNotEmpty ?? false) ...[
                          SizedBox(height: gap),
                          _MetabolicPathways(cascades: _analysis!.cascades),
                        ],

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
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.showNavigation
            ? const FloatingNavBar(current: AppNavTab.interactions)
            : null,
      ),
    );
  }

  String _headerSubtitle() {
    if (_loadingMedicines) return 'Reading your regimen…';
    if (_medications.isEmpty) {
      return 'Add two or more medicines and MedGuard checks them against '
          'each other.';
    }
    if (!_checkable) {
      return 'Choose at least two medicines to check against each other.';
    }
    if (_running) return 'Checking every pair…';
    if (_hasResults) {
      return 'Reviewed ${_included.length} of ${_medications.length} '
          '${_medications.length == 1 ? 'medicine' : 'medicines'}.';
    }
    return '${_included.length} '
        '${_included.length == 1 ? 'medicine' : 'medicines'} ready to review.';
  }
}
