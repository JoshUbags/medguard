import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/drug.dart';
import '../../models/user_allergy.dart';
import '../../services/database_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_notice.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/item_row.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/settings_row.dart';
import '../../widgets/common/surface_card.dart';

const _localUserId = 'local-device';

/// Curated set of allergy classes the user can tap once instead of typing —
/// chosen for high real-world prevalence + clear cross-reactivity coverage.
const _quickClassPicks = [
  'Penicillins',
  'Cephalosporins',
  'Sulfonamides',
  'NSAIDs',
  'Aspirin',
  'Statins',
];

class AllergyManagementScreen extends StatefulWidget {
  const AllergyManagementScreen({super.key});

  static const String routeName = '/allergies';

  @override
  State<AllergyManagementScreen> createState() =>
      _AllergyManagementScreenState();
}

class _AllergyManagementScreenState extends State<AllergyManagementScreen> {
  List<UserAllergy> _allergies = const [];
  bool _loading = true;

  String get _userId {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? _localUserId;
    } catch (_) {
      return _localUserId;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    UserDataService.instance.allergiesRevision.addListener(_load);
  }

  @override
  void dispose() {
    UserDataService.instance.allergiesRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final allergies = await UserDataService.instance.getUserAllergies(
        _userId,
      );
      if (!mounted) return;
      setState(() {
        _allergies = allergies;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addClass(String className) async {
    if (_allergies.any(
      (a) => a.label.toLowerCase() == className.toLowerCase(),
    )) {
      return;
    }
    HapticFeedback.selectionClick();
    await UserDataService.instance.addClassAllergy(
      userId: _userId,
      className: className,
    );
  }

  Future<void> _openDrugPicker() async {
    final picked = await Navigator.of(
      context,
    ).push<Drug>(MaterialPageRoute(builder: (_) => const _DrugAllergyPicker()));
    if (picked == null || !mounted) return;
    if (_allergies.any((a) => a.drugId == picked.id)) {
      showAppNotice(
        context,
        '${picked.name} is already on your list.',
        type: AppNoticeType.info,
      );
      return;
    }
    await UserDataService.instance.addDrugAllergy(
      userId: _userId,
      drugId: picked.id,
      drugName: picked.name,
    );
  }

  /// Removes [allergy] optimistically (so a swiped row leaves the tree cleanly)
  /// and offers an UNDO that re-adds it.
  Future<void> _removeWithUndo(UserAllergy allergy) async {
    HapticFeedback.selectionClick();
    setState(() {
      _allergies = _allergies.where((a) => a.id != allergy.id).toList();
    });
    await UserDataService.instance.removeAllergy(allergy.id);
    if (!mounted) return;
    AppSnack.undo(
      context,
      '${allergy.label} removed',
      onUndo: () => _restore(allergy),
    );
  }

  Future<void> _restore(UserAllergy allergy) async {
    if (allergy.isClassLevel) {
      await UserDataService.instance.addClassAllergy(
        userId: _userId,
        className: allergy.className!,
      );
    } else if (allergy.drugId != null) {
      await UserDataService.instance.addDrugAllergy(
        userId: _userId,
        drugId: allergy.drugId!,
        drugName: allergy.label,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final count = _allergies.length;

    return DetailPage(
      title: 'Allergies',
      subtitle:
          'Anything recorded here blocks a conflicting medicine before it can '
          'be saved, so every other check runs against this list.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionBlock(
                    title: 'Common classes',
                    subtitle:
                        'Most allergies are class-wide, so adding the class '
                        'catches every medicine in it.',
                    child: Wrap(
                      spacing: responsive.s(8),
                      runSpacing: responsive.s(8),
                      children: [
                        for (final cls in _quickClassPicks)
                          _PickChip(
                            label: cls,
                            selected: _allergies.any(
                              (a) => a.label.toLowerCase() == cls.toLowerCase(),
                            ),
                            onTap: () => _addClass(cls),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: sectionGap(responsive)),
                  SectionBlock(
                    title: 'Your allergies',
                    subtitle: count == 0
                        ? 'Nothing recorded yet. Tap a class above, or add a '
                              'specific medicine.'
                        : 'Swipe left on one, or tap its cross, to remove it.',
                    action: count == 0 ? null : '$count',
                    card: false,
                    children: [
                      if (_loading)
                        const LoadingView(message: 'Reading your allergies')
                      else ...[
                        for (final allergy in _allergies)
                          Dismissible(
                            key: ValueKey('allergy-${allergy.id}'),
                            direction: DismissDirection.endToStart,
                            background: const ItemSwipeBackground(),
                            onDismissed: (_) => _removeWithUndo(allergy),
                            child: ItemRowCard(
                              icon: allergy.isClassLevel
                                  ? Icons.category_rounded
                                  : Icons.medication_rounded,
                              tint: colors.danger,
                              title: allergy.label,
                              subtitle: allergy.isClassLevel
                                  ? 'Whole drug class'
                                  : 'Specific medicine',
                              trailing: RowRemoveButton(
                                label: allergy.label,
                                onTap: () => _removeWithUndo(allergy),
                              ),
                            ),
                          ),
                        ItemAddTile(
                          title: 'Add a specific medicine',
                          subtitle: 'Search the clinical reference',
                          icon: Icons.search_rounded,
                          onTap: _openDrugPicker,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A one-tap pick from a short curated list. Selected picks turn teal and
/// carry a check; unselected ones carry a plus, so the chip says what a tap
/// will do.
class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: selected ? null : onTap,
      pressScale: selected ? 1 : 0.95,
      semanticLabel: selected ? '$label, added' : 'Add $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(12),
          vertical: responsive.s(8),
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentAlpha(0.12) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.accentAlpha(0.36) : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_rounded : Icons.add_rounded,
              color: selected ? colors.accent : colors.inkMute,
              size: responsive.icon(15),
            ),
            SizedBox(width: responsive.s(6)),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? colors.accent : colors.ink,
                fontSize: responsive.font(12.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Finds a specific medicine to record as an allergy — a debounced search of
/// the bundled clinical reference that returns the picked [Drug].
///
/// A routed page like every other, not a bare Material app bar over a plain
/// list: this is where a user records something that will later block a
/// medicine from being saved, and it should look like it belongs to the
/// screen that sent them here.
class _DrugAllergyPicker extends StatefulWidget {
  const _DrugAllergyPicker();

  @override
  State<_DrugAllergyPicker> createState() => _DrugAllergyPickerState();
}

class _DrugAllergyPickerState extends State<_DrugAllergyPicker> {
  final _controller = TextEditingController();
  List<Drug> _results = const [];
  bool _busy = false;
  int _query = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final term = query.trim();
    final token = ++_query;
    if (term.length < 2) {
      setState(() {
        _results = const [];
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final hits = await DatabaseService.instance.searchDrugs(term, limit: 25);
      // A slower, older query must not overwrite the answer to a newer one.
      if (!mounted || token != _query) return;
      setState(() {
        _results = hits;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || token != _query) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final term = _controller.text.trim();

    final Widget body;
    if (term.length < 2) {
      body = const EmptyState(
        icon: Icons.search_rounded,
        title: 'Find the medicine',
        message:
            'Type at least two letters of its generic or brand name. The '
            'search runs on the bundled reference, so it works offline.',
      );
    } else if (_busy && _results.isEmpty) {
      body = const LoadingView(message: 'Searching the reference');
    } else if (_results.isEmpty) {
      body = const EmptyState(
        icon: Icons.medication_rounded,
        title: 'No matches',
        message: 'Try the generic name, or check the spelling.',
      );
    } else {
      body = SectionBlock(
        title: 'Results',
        subtitle: 'Tap a medicine to add it to your allergies.',
        action: '${_results.length}',
        card: false,
        child: SettingsGroup(
          rows: [
            for (final drug in _results)
              SettingsRow(
                icon: Icons.medication_rounded,
                title: drug.name,
                subtitle: drug.atcCode == null
                    ? 'In the clinical reference'
                    : 'ATC ${drug.atcCode}',
                onTap: () => Navigator.pop(context, drug),
              ),
          ],
        ),
      );
    }

    return DetailPage(
      title: 'Add a medicine',
      subtitle: 'Record a specific medicine you react to.',
      dismissKeyboardOnDrag: true,
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PickerSearchField(
                    controller: _controller,
                    onChanged: _search,
                  ),
                  SizedBox(height: sectionGap(responsive)),
                  body,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The search pill — the same shape, fill and glyph as the Search screen's
/// field, so looking a medicine up reads the same wherever it happens.
class _PickerSearchField extends StatelessWidget {
  const _PickerSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final extent = responsive.s(50).clamp(46.0, 58.0).toDouble();

    return Container(
      height: extent,
      padding: EdgeInsets.symmetric(horizontal: responsive.s(14)),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: colors.accent,
            size: responsive.icon(19),
          ),
          SizedBox(width: responsive.s(8)),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.words,
              autocorrect: false,
              cursorColor: colors.accent,
              style: GoogleFonts.inter(
                color: colors.ink,
                fontSize: responsive.font(14),
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search by medicine name',
                hintStyle: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(13.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
