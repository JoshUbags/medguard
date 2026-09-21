import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/user_food.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/item_row.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/surface_card.dart';

const _localUserId = 'local-device';

/// Foods/drinks with well-known drug interactions, offered as one-tap picks so
/// the most common cases don't need typing.
const _quickFoodPicks = [
  'Grapefruit',
  'Dairy / Milk',
  'Alcohol',
  'Leafy greens',
  'Caffeine',
  'Bananas',
  'Aged cheese',
  'Cranberry',
];

/// Lets the user curate the foods and drinks they regularly consume so MedGuard
/// can weigh drug–food interactions against what they actually eat.
///
/// Laid out exactly like Allergies — picks in a card, the list beneath with its
/// add tile at the foot — because the two are the same task on different data.
class FoodManagementScreen extends StatefulWidget {
  const FoodManagementScreen({super.key});

  static const String routeName = '/foods';

  @override
  State<FoodManagementScreen> createState() => _FoodManagementScreenState();
}

class _FoodManagementScreenState extends State<FoodManagementScreen> {
  List<UserFood> _foods = const [];
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
    UserDataService.instance.foodsRevision.addListener(_load);
  }

  @override
  void dispose() {
    UserDataService.instance.foodsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final foods = await UserDataService.instance.getUserFoods(_userId);
      if (!mounted) return;
      setState(() {
        _foods = foods;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _has(String label) =>
      _foods.any((f) => f.label.toLowerCase() == label.toLowerCase());

  Future<void> _add(String label) async {
    final clean = label.trim();
    if (clean.isEmpty || _has(clean)) return;
    HapticFeedback.selectionClick();
    await UserDataService.instance.addFood(userId: _userId, label: clean);
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final saved = await showModalSheet<bool>(
      context: context,
      title: 'Add a food or drink',
      subtitle:
          'Anything you have regularly — a supplement or a herbal tea counts '
          'too.',
      icon: Icons.restaurant_rounded,
      confirmLabel: 'Add to my list',
      onConfirm: () => controller.text.trim().isNotEmpty,
      builder: (_) => AppTextField(
        controller: controller,
        label: 'Food or drink',
        hint: 'For example, St John\'s wort',
        icon: Icons.restaurant_rounded,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
      ),
    );
    if (saved != true || !mounted) return;
    await _add(controller.text);
  }

  /// Removes [food] optimistically (so a swiped row leaves the tree cleanly)
  /// and offers an UNDO that re-adds it.
  Future<void> _removeWithUndo(UserFood food) async {
    HapticFeedback.selectionClick();
    setState(() {
      _foods = _foods.where((f) => f.id != food.id).toList();
    });
    await UserDataService.instance.removeFood(food.id);
    if (!mounted) return;
    AppSnack.undo(
      context,
      '${food.label} removed',
      onUndo: () =>
          UserDataService.instance.addFood(userId: _userId, label: food.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final count = _foods.length;

    return DetailPage(
      title: 'Foods and drinks',
      subtitle:
          'Grapefruit, alcohol, dairy and leafy greens all change how some '
          'medicines behave. MedGuard checks your regimen against what you '
          'have.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionBlock(
                    title: 'Common ones',
                    subtitle:
                        'The foods and drinks that interact with the most '
                        'medicines.',
                    child: Wrap(
                      spacing: responsive.s(8),
                      runSpacing: responsive.s(8),
                      children: [
                        for (final food in _quickFoodPicks)
                          _PickChip(
                            label: food,
                            selected: _has(food),
                            onTap: () => _add(food),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: sectionGap(responsive)),
                  SectionBlock(
                    title: 'Your list',
                    subtitle: count == 0
                        ? 'Nothing recorded yet. Tap a common one above, or '
                              'add your own.'
                        : 'Swipe left on one, or tap its cross, to remove it.',
                    action: count == 0 ? null : '$count',
                    card: false,
                    children: [
                      if (_loading)
                        const LoadingView(message: 'Reading your list')
                      else ...[
                        for (final food in _foods)
                          Dismissible(
                            key: ValueKey('food-${food.id}'),
                            direction: DismissDirection.endToStart,
                            background: const ItemSwipeBackground(),
                            onDismissed: (_) => _removeWithUndo(food),
                            child: ItemRowCard(
                              icon: Icons.restaurant_rounded,
                              title: food.label,
                              trailing: RowRemoveButton(
                                label: food.label,
                                onTap: () => _removeWithUndo(food),
                              ),
                            ),
                          ),
                        ItemAddTile(
                          title: 'Add something else',
                          subtitle: 'Any food, drink or supplement',
                          icon: Icons.edit_rounded,
                          onTap: _addCustom,
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

/// A one-tap pick — the same chip as the Allergies screen's class picks.
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
