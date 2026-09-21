import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/drug.dart';
import '../../models/user_allergy.dart';
import '../../models/user_food.dart';
import '../../services/allergy_checker.dart';
import '../../services/database_service.dart';
import '../../services/interaction_checker.dart';
import '../../services/notification_preferences.dart';
import '../../services/user_data_service.dart';
import '../drug/drug_monograph_screen.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_shadows.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/surface_card.dart';
import '../medications/medications_screen.dart';

part 'widgets/search_chrome.dart';
part 'widgets/search_states.dart';
part 'widgets/search_results.dart';
part 'widgets/search_details.dart';

typedef SearchDrugs = Future<List<Drug>> Function(String query, {int limit});
typedef AddDrug = Future<void> Function(Drug drug);
typedef LoadAddedDrugIds = Future<Set<int>> Function();

/// The allergy pre-check run before a medicine is saved. Injectable for the
/// same reason the three above are: it reaches the bundled clinical database,
/// which a widget test has no business opening.
typedef CheckAllergies = Future<List<AllergyHit>> Function(Drug drug);

/// What a drug result means to the user. Asked per result, at the moment of
/// adding — see [_SearchScreenState._saveResult].
enum _SaveAs { medicine, allergy }

const _searchDebounce = Duration(milliseconds: 300);
const _resultLimit = 25;
const _localUserId = 'local-device';

/// Look a medicine up, then file it — as something you take, or something you
/// react to.
///
/// Chrome-wise this is a [DetailPage] like every other routed screen. It used
/// to hand-roll its own header: a 30pt title where the shared one is 24, its own
/// circular action button, and — because the header was invented rather than
/// inherited — **no back control at all**, on a page reached by `pushNamed` from
/// six different places. The page now carries the same back pill, title scale
/// and ambient canvas as Profile, Settings and Allergies.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.searchDrugs,
    this.addDrug,
    this.loadAddedDrugIds,
    this.checkAllergies,
    this.onOpenMedications,
  });

  static const String routeName = '/search';

  final SearchDrugs? searchDrugs;
  final AddDrug? addDrug;
  final LoadAddedDrugIds? loadAddedDrugIds;
  final CheckAllergies? checkAllergies;
  final VoidCallback? onOpenMedications;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  Timer? _debounce;
  String _query = '';
  int _requestSerial = 0;
  Set<int> _addedDrugIds = const {};
  Set<int> _addingDrugIds = const {};
  List<Drug> _results = const [];
  _SearchSort _sort = _SearchSort.relevance;
  bool _loading = false;
  String? _error;
  _QuickFilter _activeFilter = _QuickFilter.all;

  /// What a result will be saved as. Folds in the whole of the old
  /// "Add to your profile" screen — see [SearchIntent].
  SearchIntent _intent = SearchIntent.medicine;

  /// Drug ids already recorded as allergies, so the card can show "Recorded"
  /// instead of offering to record a second time.
  Set<int> _allergyDrugIds = const {};

  /// Foods already saved, lower-cased for comparison.
  Set<String> _savedFoods = const {};

  SearchDrugs get _searchDrugs => widget.searchDrugs ?? _defaultSearchDrugs;
  AddDrug get _addDrug => widget.addDrug ?? _defaultAddDrug;
  LoadAddedDrugIds get _loadAddedDrugIds =>
      widget.loadAddedDrugIds ?? _defaultLoadAddedDrugIds;

  /// The results actually rendered, after the one scope filter and the sort.
  ///
  /// Scope is ONE piece of state ([_activeFilter]), driven by the pill row and
  /// nothing else. It used to be three: this row, a "Match source" panel and a
  /// "Clinical detail level" radio list, the last two behind a modal sheet and
  /// each writing to its own field — so three controls could narrow the same
  /// list at once and the page could not say which of them had done it.
  List<Drug> get _visibleResults {
    final filtered = _results
        .where((drug) => _activeFilter.matches(drug, _addedDrugIds))
        .toList(growable: false);
    return _sortResults(filtered);
  }

  List<Drug> _sortResults(List<Drug> drugs) {
    final sorted = List<Drug>.of(drugs);
    switch (_sort) {
      case _SearchSort.relevance:
        return sorted;
      case _SearchSort.name:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return sorted;
      case _SearchSort.identifiers:
        sorted.sort((a, b) {
          final bScore = _identifierScore(b);
          final aScore = _identifierScore(a);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return sorted;
    }
  }

  int _identifierScore(Drug drug) {
    var score = 0;
    if (_hasDrugClassification(drug)) score++;
    if (_hasDrugDescription(drug)) score++;
    if (_hasDrugUseNotes(drug)) score++;
    return score;
  }

  @override
  void initState() {
    super.initState();
    _loadAddedIds();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Reads what the user has already filed, so results can show as ticked.
  ///
  /// All three reads are ISSUED together and settle independently. They used to
  /// be awaited in a chain — allergies did not start until medicines came back,
  /// foods not until allergies did — which is the opposite of what the comment
  /// below them promised, and made the screen's warm-up as slow as the sum of
  /// three round trips instead of the longest one. Each failure is swallowed on
  /// its own: an unreachable allergy list leaves those chips un-ticked, which
  /// is a cosmetic loss, not a broken screen.
  Future<void> _loadAddedIds() async {
    final userId = _currentUserId();
    final service = UserDataService.instance;

    final medicines = _loadAddedDrugIds();
    final allergies = service.getUserAllergies(userId);
    final foods = service.getUserFoods(userId);

    // The medicine list is the page's primary state, so it paints as soon as it
    // lands rather than waiting on the two decorative sets.
    try {
      final ids = await medicines;
      if (!mounted) return;
      setState(() => _addedDrugIds = ids);
    } catch (_) {
      if (!mounted) return;
      setState(() => _addedDrugIds = const {});
    }

    final results = await Future.wait([
      allergies.then<Object?>((v) => v).catchError((_) => null),
      foods.then<Object?>((v) => v).catchError((_) => null),
    ]);
    if (!mounted) return;

    final loadedAllergies = results[0] as List<UserAllergy>?;
    final loadedFoods = results[1] as List<UserFood>?;
    setState(() {
      if (loadedAllergies != null) {
        _allergyDrugIds = {
          for (final a in loadedAllergies)
            if (a.drugId != null) a.drugId!,
        };
      }
      if (loadedFoods != null) {
        _savedFoods = {for (final f in loadedFoods) f.label.toLowerCase()};
      }
    });
  }

  /// Records the drug as an allergy rather than as something the user takes.
  Future<void> _recordAllergy(Drug drug) async {
    if (_allergyDrugIds.contains(drug.id) ||
        _addingDrugIds.contains(drug.id)) {
      return;
    }
    setState(() => _addingDrugIds = {..._addingDrugIds, drug.id});
    try {
      await UserDataService.instance.addDrugAllergy(
        userId: _currentUserId(),
        drugId: drug.id,
        drugName: drug.name,
      );
      if (!mounted) return;
      setState(() {
        _allergyDrugIds = {..._allergyDrugIds, drug.id};
        _addingDrugIds = _addingDrugIds.difference({drug.id});
      });
      _showSnack('Recorded an allergy to ${drug.name}', isError: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingDrugIds = _addingDrugIds.difference({drug.id}));
      _showSnack('${drug.name} was not recorded — try again.');
    }
  }

  /// Saves a free-text food or drink.
  Future<void> _addFood(String label) async {
    final clean = label.trim();
    if (clean.isEmpty || _savedFoods.contains(clean.toLowerCase())) return;
    try {
      await UserDataService.instance.addFood(
        userId: _currentUserId(),
        label: clean,
      );
      if (!mounted) return;
      setState(() => _savedFoods = {..._savedFoods, clean.toLowerCase()});
      _showSnack('Added $clean', isError: false);
    } catch (_) {
      if (!mounted) return;
      _showSnack('$clean was not added — try again.');
    }
  }

  /// Asks what the medicine means to the user, then saves it accordingly.
  ///
  /// A drug result can mean two different things — "I take this" or "I react to
  /// this" — and the screen cannot infer which. This used to be a mode set by a
  /// chip at the top of the page, which meant adding a single allergy required
  /// switching the mode, adding, and remembering to switch back; forget the
  /// last step and the next medicine you add is filed as an allergy.
  ///
  /// Asked here, the question is scoped to the one result it concerns and
  /// cannot leak into the next one.
  Future<void> _saveResult(Drug drug) async {
    final already = _addedDrugIds.contains(drug.id);
    final allergic = _allergyDrugIds.contains(drug.id);

    final choice = await showOptionSheet<_SaveAs>(
      context: context,
      title: 'Add ${drug.name}',
      subtitle: 'Which of these is true for you?',
      options: [
        SheetOption(
          value: _SaveAs.medicine,
          label: 'I take this',
          detail: already
              ? 'Already in your medicines'
              : 'Adds it to your regimen and checks it against the rest',
          icon: Icons.local_pharmacy_rounded,
          enabled: !already,
        ),
        SheetOption(
          value: _SaveAs.allergy,
          label: 'I react to this',
          detail: allergic
              ? 'Already recorded as an allergy'
              : 'Records an allergy so MedGuard warns you about it and its class',
          icon: Icons.warning_amber_rounded,
          enabled: !allergic,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    await switch (choice) {
      _SaveAs.medicine => _addMedication(drug),
      _SaveAs.allergy => _recordAllergy(drug),
    };
  }

  void _setIntent(SearchIntent intent) {
    if (intent == _intent) return;
    HapticFeedback.selectionClick();
    setState(() => _intent = intent);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      _requestSerial++;
      setState(() {
        _query = '';
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _error = null;
    });
    _debounce = Timer(_searchDebounce, () => _runSearch(query));
  }

  Future<void> _runSearch([String? requestedQuery]) async {
    final query = (requestedQuery ?? _searchCtrl.text).trim();
    if (query.isEmpty) return;

    final requestId = ++_requestSerial;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });

    try {
      final results = await _searchDrugs(query, limit: _resultLimit);
      if (!mounted || requestId != _requestSerial || query != _query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestSerial || query != _query) return;
      setState(() {
        _results = const [];
        _loading = false;
        _error = 'Search unavailable';
      });
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    _requestSerial++;
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _results = const [];
      _loading = false;
      _error = null;
    });
    _searchFocus.requestFocus();
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    _runSearch(value);
  }

  void _openMedications() {
    if (widget.onOpenMedications != null) {
      widget.onOpenMedications!();
      return;
    }
    Navigator.of(context).pushNamed(MedicationsScreen.routeName);
  }

  void _chooseSuggestion(String query) {
    _searchCtrl.text = query;
    _searchCtrl.selection = TextSelection.collapsed(offset: query.length);
    _onSearchChanged(query);
    _searchFocus.requestFocus();
  }

  Future<void> _addMedication(Drug drug) async {
    if (_addedDrugIds.contains(drug.id) || _addingDrugIds.contains(drug.id)) {
      return;
    }

    // Hard block when a drug matches a recorded allergy (direct or
    // class-level cross-reactivity). We surface a confirmation dialog the user
    // can override — clinicians sometimes need to add a drug deliberately even
    // when the regimen has an allergy of the same class on file.
    final hits = await _allergyHits(drug);
    if (hits.isNotEmpty && mounted) {
      final proceed = await _confirmAllergyAdd(drug, hits);
      if (!proceed) return;
    }
    if (!mounted) return;

    setState(() => _addingDrugIds = {..._addingDrugIds, drug.id});
    try {
      await _addDrug(drug);
      if (!mounted) return;
      setState(() {
        _addedDrugIds = {..._addedDrugIds, drug.id};
        _addingDrugIds = _addingDrugIds.difference({drug.id});
      });
      _showSnack('Added ${drug.name}', isError: false);
      // Warn if the new medicine interacts with anything already saved.
      // Best-effort and gated by the safety-alerts preference.
      unawaited(_checkInteractionsForNewDrug(drug));
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingDrugIds = _addingDrugIds.difference({drug.id}));
      _showSnack(
        '${drug.name} was not added — saving to your medicine list failed. '
        'Your regimen is unchanged; try again.',
      );
    }
  }

  Future<List<AllergyHit>> _allergyHits(Drug drug) async {
    try {
      return await (widget.checkAllergies ?? _defaultCheckAllergies)(drug);
    } catch (_) {
      return const [];
    }
  }

  /// The one modal in the app that argues against what the user just asked for.
  ///
  /// It lists the specific conflicts rather than warning in general, because
  /// "this may conflict with your allergies" is dismissable noise and "this is
  /// a penicillin, and you recorded a penicillin allergy" is not. The confirm
  /// action is deliberately worded "Add anyway" — the user keeps the ability to
  /// override, and the wording makes sure they know that is what they are
  /// doing.
  Future<bool> _confirmAllergyAdd(Drug drug, List<AllergyHit> hits) async {
    final colors = context.colors;
    final response = await showModalSheet<bool>(
      context: context,
      title: 'Allergy conflict',
      subtitle:
          'Adding ${drug.name} may conflict with an allergy you have recorded.',
      icon: Icons.warning_amber_rounded,
      iconTint: colors.warning,
      confirmLabel: 'Add anyway',
      cancelLabel: 'Don\'t add',
      builder: (ctx) {
        final r = MedGuardResponsive.of(ctx);
        final c = ctx.colors;
        return Container(
          padding: EdgeInsets.all(r.s(14)),
          decoration: BoxDecoration(
            color: c.warningAlpha(0.09),
            borderRadius: BorderRadius.circular(r.radius(16)),
            border: Border.all(color: c.warningAlpha(0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < hits.length; i++) ...[
                if (i > 0) SizedBox(height: r.s(8)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: r.s(5),
                      height: r.s(5),
                      margin: EdgeInsets.only(top: r.s(6)),
                      decoration: BoxDecoration(
                        color: c.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: r.s(9)),
                    Expanded(
                      child: Text(
                        hits[i].summary,
                        style: GoogleFonts.inter(
                          color: c.ink,
                          fontSize: r.font(12.8),
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
    return response ?? false;
  }

  Future<void> _checkInteractionsForNewDrug(Drug drug) async {
    try {
      if (!await NotificationPreferences.safetyAlerts()) return;
      final otherIds = _addedDrugIds.where((id) => id != drug.id).toList();
      if (otherIds.isEmpty) return;
      final report = await InteractionChecker.analyze([drug.id, ...otherIds]);
      final involves = report.drugInteractions
          .where((i) => i.drugAId == drug.id || i.drugBId == drug.id)
          .toList();
      if (involves.isEmpty || !mounted) return;
      final partnerCount = involves
          .map((i) => i.drugAId == drug.id ? i.drugBId : i.drugAId)
          .toSet()
          .length;
      final word = partnerCount == 1 ? 'medicine' : 'medicines';
      _showInteractionSnack(
        '${drug.name} may interact with $partnerCount saved $word — review your safety report.',
      );
    } catch (_) {
      // Interaction lookup unavailable — silently skip the alert.
    }
  }

  /// Both of the search screen's transient messages go through the shared
  /// app toast, so an "added" confirmation here looks identical to one raised
  /// anywhere else in the app.
  void _showInteractionSnack(String message) {
    AppSnack.warning(context, message);
  }

  void _showSnack(String message, {bool isError = true}) {
    if (isError) {
      AppSnack.error(context, message);
    } else {
      AppSnack.success(context, message);
    }
  }

  void _openDrugDetails(Drug drug) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.colors.scaffold,
      builder: (context) {
        return _DrugDetailsSheet(
          drug: drug,
          isAdded: _addedDrugIds.contains(drug.id),
          isAdding: _addingDrugIds.contains(drug.id),
          onAdd: () {
            Navigator.of(context).pop();
            _addMedication(drug);
          },
        );
      },
    );
  }

  /// The sort order, picked through the app's shared option sheet.
  ///
  /// It used to be a Material [PopupMenuButton] — the only one in the app —
  /// which dropped a square-cornered menu wherever the anchor happened to be
  /// while every other choice on every other screen rises from the bottom as a
  /// sheet.
  Future<void> _pickSort() async {
    final picked = await showOptionSheet<_SearchSort>(
      context: context,
      title: 'Sort results',
      subtitle: 'Changes the order of the list. It never changes which records '
          'are in it.',
      selected: _sort,
      options: [
        for (final sort in _SearchSort.values)
          SheetOption(
            value: sort,
            label: sort.label,
            detail: sort.detail,
            icon: sort.icon,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = picked);
  }

  /// Wraps a box in the page's horizontal padding and tablet width constraint.
  ///
  /// Every sliver on the page goes through this, which is what keeps the search
  /// field, the filter pills and the result cards on ONE left edge. The states
  /// used to hard-code `horizontal: 20` while the rest of the page used
  /// [MedGuardResponsive.pageX], so the empty state and the result list sat on
  /// two different margins at every size except the one they were tuned on.
  Widget _pageSliver(BuildContext context, Widget child) {
    final responsive = MedGuardResponsive.of(context);
    return SliverToBoxAdapter(
      child: responsive.constrain(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final isFood = _intent == SearchIntent.food;

    return DetailPage(
      title: 'Search',
      subtitle:
          'Look up a medicine or a food, then file it — as something you take, '
          'or something you react to.',
      // Scrolling results ends text entry, so the list is not read through a
      // half-screen keyboard.
      dismissKeyboardOnDrag: true,
      actions: [
        DetailPageAction(
          key: const ValueKey('search-header-action'),
          icon: Icons.inventory_2_rounded,
          label: 'Medicines',
          semanticLabel: 'View medications',
          onTap: _openMedications,
        ),
      ],
      slivers: [
        _pageSliver(
          context,
          _IntentSelector(active: _intent, onChanged: _setIntent),
        ),
        SliverToBoxAdapter(child: SizedBox(height: responsive.s(12))),

        _pageSliver(
          context,
          _SearchField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            showClear: _query.isNotEmpty,
            hint: _intent.hint,
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
            onSubmitted: isFood
                ? (value) {
                    unawaited(_addFood(value));
                    _clearSearch();
                  }
                : _submitSearch,
          ),
        ),

        // The scope row is the one control that bleeds past the page margin:
        // six pills cannot fit a phone's width, so it scrolls, and it supplies
        // its own inset rather than riding in [_pageSliver].
        if (!isFood) ...[
          SliverToBoxAdapter(child: SizedBox(height: responsive.s(12))),
          SliverToBoxAdapter(
            child: _QuickFilterRow(
              active: _activeFilter,
              onChanged: (filter) => setState(() => _activeFilter = filter),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: sectionGap(responsive))),

        _pageSliver(
          context,
          isFood
              ? _FoodBody(
                  query: _query,
                  saved: _savedFoods,
                  onAdd: (label) => unawaited(_addFood(label)),
                )
              : _SearchBody(
                  query: _query,
                  loading: _loading,
                  error: _error,
                  results: _visibleResults,
                  addingDrugIds: _addingDrugIds,
                  // Ticked when the drug is in EITHER list — the card's job is
                  // to say "you have already filed this", not which drawer it
                  // went in.
                  savedIds: {..._addedDrugIds, ..._allergyDrugIds},
                  onRetry: () => _runSearch(_query),
                  onSuggestion: _chooseSuggestion,
                  onAdd: _saveResult,
                  onOpenDetails: _openDrugDetails,
                  sort: _sort,
                  onPickSort: _pickSort,
                ),
        ),
      ],
    );
  }
}

Future<List<Drug>> _defaultSearchDrugs(
  String query, {
  int limit = _resultLimit,
}) {
  return DatabaseService.instance.searchDrugs(query, limit: limit);
}

Future<void> _defaultAddDrug(Drug drug) async {
  await UserDataService.instance.addMedication(
    userId: _currentUserId(),
    drugId: drug.id,
    drugName: drug.name,
    atcCode: drug.atcCode,
  );
}

Future<List<AllergyHit>> _defaultCheckAllergies(Drug drug) {
  return AllergyChecker().checkDrug(
    userId: _currentUserId(),
    drugId: drug.id,
    drugName: drug.name,
  );
}

Future<Set<int>> _defaultLoadAddedDrugIds() async {
  final ids = await UserDataService.instance.getUserMedicationIds(
    _currentUserId(),
  );
  return ids.toSet();
}
