// Part of `search_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../search_screen.dart';

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.query,
    required this.loading,
    required this.error,
    required this.results,
    required this.addingDrugIds,
    required this.savedIds,
    required this.onRetry,
    required this.onSuggestion,
    required this.onAdd,
    required this.onOpenDetails,
    required this.sort,
    required this.onPickSort,
  });

  final String query;
  final bool loading;
  final String? error;
  final List<Drug> results;
  final Set<int> addingDrugIds;

  /// The ids already filed as EITHER a medicine or an allergy.
  final Set<int> savedIds;
  final VoidCallback onRetry;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<Drug> onAdd;
  final ValueChanged<Drug> onOpenDetails;
  final _SearchSort sort;
  final VoidCallback onPickSort;

  @override
  Widget build(BuildContext context) {
    // Page padding and the tablet constraint are applied ONCE by the caller
    // (`_SearchScreenState._pageSliver`), so every state below — the list, the
    // skeletons, the empty prompt and the error — lands on the same margin.
    if (loading) return const _SearchLoadingSection();
    if (error != null) return _SearchErrorState(onRetry: onRetry);
    if (query.isEmpty) return _EmptySearchState(onSuggestion: onSuggestion);
    if (results.isEmpty) return _NoResultsState(query: query);
    final responsive = MedGuardResponsive.of(context);

    // The result list is a section like any other on a routed screen: heading,
    // one line of state, and the control that acts on it in the trailing slot.
    // The count and the sort control used to be a bespoke row, with a tinted
    // panel below it repeating that same count as "N shown" beside two tallies
    // the scope pills already offer as filters.
    return SectionBlock(
      title: 'Results',
      subtitle: results.length == 1
          ? '1 medicine matches "$query".'
          : '${results.length} medicines match "$query".',
      action: sort.label,
      onAction: onPickSort,
      card: false,
      children: [
        for (int index = 0; index < results.length; index++)
          _StaggeredSearchItem(
            index: index,
            child: _DrugResultCard(
              query: query,
              style: _DrugCardStyle.forDrug(context, results[index]),
              drug: results[index],
              isAdded: savedIds.contains(results[index].id),
              isAdding: addingDrugIds.contains(results[index].id),
              onAdd: () => onAdd(results[index]),
              onOpenDetails: () => onOpenDetails(results[index]),
            ),
          ),
        SizedBox(height: responsive.s(2)),
      ],
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    'Aspirin',
    'Metformin',
    'Lisinopril',
    'Ibuprofen',
    'Amoxicillin',
  ];

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    // One section, two cards. The block used to open with a large glyph and its
    // own 21pt heading — a second page title, four lines under the real one —
    // and carried a "See all" pill that did not show all of anything: it ran
    // the first suggestion, which is what tapping that suggestion already did.
    return SectionBlock(
      title: 'Popular searches',
      subtitle:
          'Tap one to try it, or type a generic name, a brand name or a '
          'synonym. Anything you add here is checked against the rest of your '
          'regimen.',
      card: false,
      children: [
        SurfaceCard(
          padding: EdgeInsets.all(responsive.s(16)),
          child: Wrap(
            spacing: responsive.s(9),
            runSpacing: responsive.s(9),
            children: [
              for (final suggestion in _suggestions)
                _SuggestionChip(
                  label: suggestion,
                  onTap: () => onSuggestion(suggestion),
                ),
            ],
          ),
        ),
        const _SearchGuidancePanel(),
      ],
    );
  }
}

/// Two tips for getting a hit out of the local database.
///
/// Tinted with the ACCENT. This panel used to be ruby — the same red the app
/// uses for an interaction that could hurt you — which put a hazard colour on
/// the single most benign block on the page. In an app whose whole job is
/// flagging danger, red has to mean danger and nothing else.
class _SearchGuidancePanel extends StatelessWidget {
  const _SearchGuidancePanel();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final mark = responsive.s(32).clamp(28.0, 38.0).toDouble();

    return Container(
      key: const ValueKey('search-guidance-panel'),
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(13)),
      decoration: BoxDecoration(
        color: colors.accentAlpha(0.06),
        borderRadius: BorderRadius.circular(responsive.radius(20)),
        border: Border.all(color: colors.accentAlpha(0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: mark,
            height: mark,
            decoration: BoxDecoration(
              color: colors.accentAlpha(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lightbulb_rounded,
              color: colors.accent,
              size: responsive.icon(18),
            ),
          ),
          SizedBox(width: responsive.s(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search tips',
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(12.8),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: responsive.s(6)),
                const _SearchGuidanceLine('Use generic names first.'),
                SizedBox(height: responsive.s(3)),
                const _SearchGuidanceLine(
                  'Add over-the-counter medicines too.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchGuidanceLine extends StatelessWidget {
  const _SearchGuidanceLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Text(
      text,
      style: GoogleFonts.inter(
        color: context.colors.inkSoft,
        fontSize: responsive.font(12.2),
        height: 1.34,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      semanticLabel: 'Search for $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(10),
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: colors.accent,
            fontSize: responsive.font(13),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// A query that matched nothing.
///
/// The shared [EmptyState], not a search-local lookalike — this used to be a
/// hand-built card with its own mark, its own 21pt heading and its own copy of
/// the app's empty-block geometry.
class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No medicines found',
      message:
          'Try a brand name, a generic name, or a shorter spelling for '
          '"$query".',
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // No "Report issue" affordance: it was wired to an empty callback, so the
    // one control on the app's failure path did nothing at all when pressed.
    // Retry is the action that exists, so Retry is the action offered.
    return AppErrorState(
      title: 'Search needs a retry',
      message:
          'The medication database could not be reached. Check your connection '
          'and try again.',
      onRetry: onRetry,
    );
  }
}

/// Food mode.
///
/// Foods are not drug records — there is no database to search, so this is a
/// free-text add with a set of one-tap suggestions. The suggestions carry their
/// weight: these are the handful of everyday foods and drinks that genuinely
/// interact with common medicines, so most users never need to type at all.
class _FoodBody extends StatelessWidget {
  const _FoodBody({
    required this.query,
    required this.saved,
    required this.onAdd,
  });

  final String query;

  /// Already-saved labels, lower-cased.
  final Set<String> saved;
  final ValueChanged<String> onAdd;

  /// The foods and drinks with real, well-documented interactions — grapefruit
  /// with statins and calcium-channel blockers, leafy greens with warfarin,
  /// dairy with tetracyclines, and so on.
  static const _common = <String>[
    'Grapefruit',
    'Alcohol',
    'Coffee',
    'Leafy greens',
    'Dairy / milk',
    'Bananas',
    'Aged cheese',
    'Liquorice',
    'Cranberry juice',
    'Green tea',
  ];

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final typed = query.trim();
    final alreadySaved = saved.contains(typed.toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What was typed, offered as a direct add — so a food that is not in
        // the suggestion list is one tap away rather than a dead end.
        if (typed.isNotEmpty) ...[
          SurfaceCard(
            padding: EdgeInsets.all(responsive.s(16)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        typed,
                        style: GoogleFonts.inter(
                          color: colors.ink,
                          fontSize: responsive.font(15),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: responsive.s(3)),
                      Text(
                        alreadySaved
                            ? 'Already on your list'
                            : 'Add this to the foods MedGuard checks',
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(12.2),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: responsive.s(12)),
                AppButton(
                  label: alreadySaved ? 'Added' : 'Add',
                  icon: alreadySaved ? Icons.check_rounded : Icons.add_rounded,
                  variant: alreadySaved
                      ? AppButtonVariant.tonal
                      : AppButtonVariant.primary,
                  expand: false,
                  onTap: alreadySaved ? null : () => onAdd(typed),
                ),
              ],
            ),
          ),
          SizedBox(height: responsive.s(24)),
        ],

        const SectionHeader(
          title: 'Common triggers',
          subtitle:
              'The foods and drinks that most often affect medicines. Tap to '
              'add one.',
        ),
        SizedBox(height: sectionHeaderGap(responsive)),
        Wrap(
          spacing: responsive.s(8),
          runSpacing: responsive.s(8),
          children: [
            for (final food in _common)
              _FoodChip(
                label: food,
                added: saved.contains(food.toLowerCase()),
                onTap: () => onAdd(food),
              ),
          ],
        ),
      ],
    );
  }
}

class _FoodChip extends StatelessWidget {
  const _FoodChip({
    required this.label,
    required this.added,
    required this.onTap,
  });

  final String label;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Pressable(
      onTap: added ? null : onTap,
      pressScale: 0.95,
      selected: added,
      semanticLabel: '$label${added ? ', added' : ''}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(14),
          vertical: responsive.s(10),
        ),
        decoration: BoxDecoration(
          color: added ? colors.accentAlpha(0.12) : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: added ? colors.accentAlpha(0.34) : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (added) ...[
              Icon(
                Icons.check_rounded,
                size: responsive.icon(14),
                color: colors.accent,
              ),
              SizedBox(width: responsive.s(6)),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: added ? colors.accent : colors.inkSoft,
                fontSize: responsive.font(13),
                fontWeight: added ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
