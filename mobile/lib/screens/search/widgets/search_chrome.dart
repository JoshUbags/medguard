// Part of `search_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../search_screen.dart';

/// The signed-in user's id, or the on-device workspace id.
///
/// `FirebaseAuth.instance` THROWS when no Firebase app has been initialised —
/// it does not return null — so the `??` fallback below never sees that case
/// and cannot cover it. Every caller here used to sit inside a `catch (_)` that
/// swallowed the throw by accident; the moment one didn't, opening Search threw
/// straight out of `initState`. Guarded at the source instead, the same way
/// [headerDisplayName] and [headerPhotoUrl] guard theirs.
String _currentUserId() {
  try {
    return FirebaseAuth.instance.currentUser?.uid ?? _localUserId;
  } catch (_) {
    return _localUserId;
  }
}

bool _hasDrugClassification(Drug drug) {
  return drug.atcCode?.trim().isNotEmpty ?? false;
}

bool _hasDrugDescription(Drug drug) {
  return drug.description?.trim().isNotEmpty ?? false;
}

bool _hasDrugUseNotes(Drug drug) {
  return drug.indication?.trim().isNotEmpty ?? false;
}

/// Whether the record's own text mentions food at all — the cheap proxy behind
/// the "Food notes" scope. It is a text match, not a curated interaction list,
/// which is why the pill is named after what it does rather than promising
/// "food guidance".
bool _mentionsFood(Drug drug) {
  final text = '${drug.description ?? ''} ${drug.indication ?? ''}';
  return text.toLowerCase().contains('food');
}

/// What an ATC code says a medicine IS — the one table the search feature reads
/// it from.
///
/// This ladder of prefixes used to be written out three separate times: once in
/// the result card for its short label and tint, once in the detail sheet for
/// the long family name, and once more in the same sheet for the "what to watch
/// for" paragraph. Adding a family meant finding all three, and they had
/// already drifted — the card had a colour for every family, the sheet had a
/// long name for every family, and neither knew what the third one said.
class _DrugFamily {
  const _DrugFamily({
    required this.shortLabel,
    required this.longLabel,
    required this.tint,
    required this.watchFor,
  });

  /// The class line on a result card — short enough to sit under a name.
  final String shortLabel;

  /// The family in full, for the detail sheet.
  final String longLabel;

  final Color tint;

  /// The clause that follows the medicine's name in "What to watch for".
  final String watchFor;

  /// The family for [atcCode], or null when the record carries no code.
  ///
  /// Null rather than an "Unknown" member so each caller picks the fallback
  /// that suits it: the card wants "Needs classification" in muted ink, the
  /// sheet's header wants "Medication record", and its facts list wants the row
  /// left out entirely.
  static _DrugFamily? forCode(String? atcCode) {
    final code = atcCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) return null;

    if (code.startsWith('B01')) {
      return const _DrugFamily(
        shortLabel: 'Blood medicine',
        longLabel: 'Blood and clotting medicines',
        tint: MedGuardPalette.rubyDeep,
        watchFor:
            'is grouped with blood and clotting medicines. Review bleeding '
            'risk when paired with pain relievers, anticoagulants, '
            'supplements, or medicines that affect platelets.',
      );
    }
    if (code.startsWith('A10')) {
      return const _DrugFamily(
        shortLabel: 'Blood sugar',
        longLabel: 'Blood sugar medicines',
        tint: Color(0xFF1E8A6F),
        watchFor:
            'is grouped with blood sugar medicines. Review meal timing, kidney '
            'context, low blood sugar symptoms, and duplicate diabetes '
            'therapy.',
      );
    }
    if (code.startsWith('C')) {
      return const _DrugFamily(
        shortLabel: 'Heart care',
        longLabel: 'Heart and blood pressure medicines',
        tint: Color(0xFFC0392B),
        watchFor:
            'is grouped with heart and blood pressure medicines. Review '
            'dizziness, pulse changes, electrolytes, swelling, and overlapping '
            'pressure-lowering effects.',
      );
    }
    if (code.startsWith('J')) {
      return const _DrugFamily(
        shortLabel: 'Infection care',
        longLabel: 'Infection treatment medicines',
        tint: Color(0xFF8E44AD),
        watchFor:
            'is grouped with infection treatment medicines. Review allergy '
            'history, timing with minerals or antacids, stomach effects, and '
            'completion of the prescribed course.',
      );
    }
    if (code.startsWith('N')) {
      return const _DrugFamily(
        shortLabel: 'Nerve care',
        longLabel: 'Nervous system medicines',
        tint: Color(0xFF1F6FB2),
        watchFor:
            'is grouped with nervous system medicines. Review drowsiness, '
            'falls risk, driving safety, mood changes, and overlap with other '
            'calming medicines.',
      );
    }

    final group = code.length >= 3 ? code.substring(0, 3) : code;
    return _DrugFamily(
      shortLabel: '$group class',
      longLabel: '$group class medicines',
      tint: MedGuardPalette.teal,
      watchFor:
          'belongs to the $group medicine class. Review the medicine class, '
          'dose context, and new symptoms after it is added.',
    );
  }
}

String? _cleanDrugText(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  var cleaned = raw
      .replaceAll(RegExp(r'\[[A-Za-z]\d+[^\]]*\]'), '')
      .replaceAll(RegExp(r'\{[A-Za-z]\d+[^}]*\}'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\s+([,.;:])'),
    (match) => match.group(1)!,
  );
  cleaned = cleaned
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.showClear,
    required this.onChanged,
    required this.onClear,
    required this.onSubmitted,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  /// Placeholder text — states the errand, so the field never reads as a
  /// generic box whose effect depends on a chip somewhere above it.
  final String hint;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final extent = responsive.s(50).clamp(46.0, 58.0).toDouble();

    return Container(
      height: extent,
      padding: EdgeInsets.only(
        left: responsive.s(14),
        right: showClear ? responsive.s(4) : responsive.s(14),
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
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
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
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
                hintText: hint,
                hintStyle: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(13.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (showClear)
            IconButton(
              tooltip: 'Clear search',
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              color: colors.inkMute,
              icon: Icon(Icons.cancel_rounded, size: responsive.icon(18)),
            ),
        ],
      ),
    );
  }
}

/// The fill under a SELECTED pill, in both themes.
///
/// Deliberately the brand teal rather than [MedGuardColors.accent]. `accent` is
/// the theme-resolved *foreground* teal, which brightens to `#4FD1C5` in dark
/// mode so it stays legible as text on a dark card — used as a FILL it produces
/// a near-white slab, and the white label on top of it dropped to roughly 1.6:1.
/// This is the same rule [AppButton] follows for its filled variants, so a
/// selected pill and a primary button are the same teal on the same page.
const Color _selectedPillFill = MedGuardPalette.teal;

/// How wide the result list is — THE scope control, and the only one.
///
/// Every narrowing the screen offers is one of these pills. There used to be
/// three separate mechanisms: this row, a "Match source" panel in a filter sheet
/// that re-offered [classified] under another name, and a "Clinical detail
/// level" radio list in the same sheet that re-offered [described] and
/// [useNotes]. Three controls, two of them behind a modal, all writing to
/// different state, and the user had no way of telling which of them was
/// currently narrowing the list.
enum _QuickFilter { all, saved, classified, described, useNotes, foodNotes }

enum _SearchSort { relevance, name, identifiers }

extension on _SearchSort {
  String get label {
    return switch (this) {
      _SearchSort.relevance => 'Relevance',
      _SearchSort.name => 'Name A-Z',
      _SearchSort.identifiers => 'Most complete',
    };
  }

  String get detail {
    return switch (this) {
      _SearchSort.relevance => 'The database\'s own best match first',
      _SearchSort.name => 'Alphabetical, regardless of match strength',
      _SearchSort.identifiers => 'Records carrying the most information first',
    };
  }

  IconData get icon {
    return switch (this) {
      _SearchSort.relevance => Icons.auto_awesome_rounded,
      _SearchSort.name => Icons.sort_by_alpha_rounded,
      _SearchSort.identifiers => Icons.fact_check_rounded,
    };
  }
}

extension on _QuickFilter {
  String get label {
    return switch (this) {
      _QuickFilter.all => 'All',
      _QuickFilter.saved => 'Saved',
      _QuickFilter.classified => 'Classified',
      _QuickFilter.described => 'Has description',
      _QuickFilter.useNotes => 'Has use notes',
      _QuickFilter.foodNotes => 'Food notes',
    };
  }

  IconData get icon {
    return switch (this) {
      _QuickFilter.all => Icons.list_alt_rounded,
      _QuickFilter.saved => Icons.check_rounded,
      _QuickFilter.classified => Icons.category_rounded,
      _QuickFilter.described => Icons.notes_rounded,
      _QuickFilter.useNotes => Icons.assignment_turned_in_rounded,
      _QuickFilter.foodNotes => Icons.restaurant_rounded,
    };
  }

  bool matches(Drug drug, Set<int> savedIds) {
    return switch (this) {
      _QuickFilter.all => true,
      _QuickFilter.saved => savedIds.contains(drug.id),
      _QuickFilter.classified => _hasDrugClassification(drug),
      _QuickFilter.described => _hasDrugDescription(drug),
      _QuickFilter.useNotes => _hasDrugUseNotes(drug),
      _QuickFilter.foodNotes => _mentionsFood(drug),
    };
  }
}

class _QuickFilterRow extends StatelessWidget {
  const _QuickFilterRow({required this.active, required this.onChanged});

  final _QuickFilter active;
  final ValueChanged<_QuickFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return SingleChildScrollView(
      key: const ValueKey('search-scope-row'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
      child: Row(
        children: [
          for (final filter in _QuickFilter.values) ...[
            if (filter != _QuickFilter.values.first)
              SizedBox(width: responsive.s(8)),
            _QuickFilterPill(
              filter: filter,
              selected: filter == active,
              onTap: () => onChanged(filter),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickFilterPill extends StatelessWidget {
  const _QuickFilterPill({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _QuickFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final foreground = selected ? MedGuardPalette.pureWhite : colors.inkSoft;

    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      selected: selected,
      semanticLabel: filter.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(12),
          vertical: responsive.s(9),
        ),
        decoration: ShapeDecoration(
          // The brand teal, not the theme-resolved `accent` — see
          // [_selectedPillFill].
          color: selected ? _selectedPillFill : colors.surface,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? _selectedPillFill : colors.border,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filter.icon, size: responsive.icon(15), color: foreground),
            SizedBox(width: responsive.s(6)),
            Text(
              filter.label,
              style: GoogleFonts.inter(
                color: foreground,
                fontSize: responsive.font(11.6),
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Intent — what the user is adding
// ─────────────────────────────────────────────────────────────────────────────

/// What a search result will be saved AS.
///
/// This is what let the separate "Add to your profile" screen be deleted. That
/// screen existed only because a drug result can mean two different things —
/// "I take this" and "I react to this" — and the search screen assumed the
/// first. Two screens over one database, with two designs and two sets of bugs,
/// to express one extra bit of information.
///
/// The selector names the DATA SOURCE — the drug database, or a free-text food.
/// What a drug result *means* to the user (something they take, or something
/// they react to) is asked at the moment of adding instead, on the card itself,
/// because that is a decision about one medicine rather than a mode the whole
/// screen sits in. Making it a mode meant a user who wanted to add one allergy
/// had to remember to switch back afterwards.
enum SearchIntent { medicine, food }

extension SearchIntentDisplay on SearchIntent {
  String get label => switch (this) {
    SearchIntent.medicine => 'Medicines',
    SearchIntent.food => 'Foods',
  };

  IconData get icon => switch (this) {
    SearchIntent.medicine => Icons.local_pharmacy_rounded,
    SearchIntent.food => Icons.restaurant_rounded,
  };

  /// The search field's placeholder — it states the errand, so the field never
  /// reads as a generic box whose effect depends on a chip somewhere above it.
  String get hint => switch (this) {
    SearchIntent.medicine => 'Search any medicine by name',
    SearchIntent.food => 'Type a food or drink',
  };
}

/// Which of the two sources the screen is searching.
///
/// Two equal segments on the page's own margin. It used to be a horizontally
/// scrolling rail behind a [ShaderMask] that dissolved at both ends — a
/// treatment that earns its keep on Home's ten section pills and does nothing
/// for a pair of options that can never overflow, beyond costing a ListView and
/// a shader every frame and leaving the first pill floating off the page's left
/// edge while everything below it lined up.
class _IntentSelector extends StatelessWidget {
  const _IntentSelector({required this.active, required this.onChanged});

  final SearchIntent active;
  final ValueChanged<SearchIntent> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Row(
      children: [
        for (final intent in SearchIntent.values) ...[
          if (intent != SearchIntent.values.first)
            SizedBox(width: responsive.s(10)),
          Expanded(
            child: _IntentPill(
              intent: intent,
              active: intent == active,
              onTap: () => onChanged(intent),
            ),
          ),
        ],
      ],
    );
  }
}

class _IntentPill extends StatelessWidget {
  const _IntentPill({
    required this.intent,
    required this.active,
    required this.onTap,
  });

  final SearchIntent intent;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      selected: active,
      semanticLabel: intent.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(vertical: responsive.s(11)),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _selectedPillFill : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _selectedPillFill : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              intent.icon,
              size: responsive.icon(15),
              color: active ? MedGuardPalette.pureWhite : colors.inkMute,
            ),
            SizedBox(width: responsive.s(7)),
            Text(
              intent.label,
              style: GoogleFonts.inter(
                color: active ? MedGuardPalette.pureWhite : colors.inkSoft,
                fontSize: responsive.font(13),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
