// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

/// How long a quick-access tile flashes on tap. Lived beside the risk gauge
/// until that moved to the Interactions screen; it belongs with the tiles
/// that actually use it.
const _homeTapFlashDuration = Duration(milliseconds: 120);

/// Home's section heading — now a thin alias over the app-wide [SectionHeader]
/// so every feed in the product (Home, Insights, Dose) renders the identical
/// object rather than three near-copies that drift apart a point at a time.
class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.action,
    this.subtitle,
    this.onAction,
  });

  final String title;
  final String action;
  final String? subtitle;

  /// When provided, the trailing [action] becomes a tappable teal affordance
  /// (e.g. "See all"); otherwise it reads as a quiet status label.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: title,
    action: action,
    subtitle: subtitle,
    onAction: onAction,
  );
}

class _QuickAccessSection extends StatefulWidget {
  const _QuickAccessSection({
    required this.onSearch,
    required this.onSafety,
    required this.onDose,
    required this.onAllergies,
    required this.onEmergencyCard,
  });

  final VoidCallback onSearch;
  final VoidCallback onSafety;
  final VoidCallback onDose;
  final VoidCallback onAllergies;
  final VoidCallback onEmergencyCard;

  @override
  State<_QuickAccessSection> createState() => _QuickAccessSectionState();
}

class _QuickAccessSectionState extends State<_QuickAccessSection> {
  final ScrollController _scrollController = ScrollController();
  int _focusedIndex = 0;
  static const int _lastIndex = 4;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFocusedCard);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFocusedCard);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFocusedCard() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final nextIndex = switch (offset) {
      <= 8 => 0,
      _ when offset >= maxOffset - 8 => _lastIndex,
      _ when maxOffset <= 0 => 0,
      _ => ((offset / maxOffset) * _lastIndex).round().clamp(0, _lastIndex),
    };
    if (nextIndex == _focusedIndex) return;
    setState(() => _focusedIndex = nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = responsive.s(14);
    final titleGap = responsive.s(16).clamp(14.0, 18.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSectionHeader(title: 'Quick Access', action: '5 shortcuts'),
        SizedBox(
          key: const ValueKey('home-quick-access-heading-gap'),
          height: titleGap,
        ),
        SingleChildScrollView(
          key: const ValueKey('home-quick-access-row'),
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _QuickAccessCard(
                containerKey: const ValueKey('quick-access-card-library'),
                icon: Icons.search_rounded,
                label: 'Drug library',
                value: 'Search',
                onTap: widget.onSearch,
                focused: _focusedIndex == 0,
              ),
              SizedBox(width: gap),
              _QuickAccessCard(
                containerKey: const ValueKey('quick-access-card-interactions'),
                icon: Icons.swap_horiz_rounded,
                label: 'Interaction map',
                value: 'Review',
                onTap: widget.onSafety,
                focused: _focusedIndex == 1,
              ),
              SizedBox(width: gap),
              _QuickAccessCard(
                containerKey: const ValueKey('quick-access-card-allergies'),
                icon: Icons.healing_rounded,
                label: 'Allergy list',
                value: 'Manage',
                onTap: widget.onAllergies,
                focused: _focusedIndex == 2,
              ),
              SizedBox(width: gap),
              _QuickAccessCard(
                containerKey: const ValueKey('quick-access-card-dose'),
                icon: Icons.alarm_rounded,
                label: 'Dose plan',
                value: 'Today',
                onTap: widget.onDose,
                focused: _focusedIndex == 3,
              ),
              SizedBox(width: gap),
              _QuickAccessCard(
                containerKey: const ValueKey('quick-access-card-emergency'),
                icon: Icons.badge_rounded,
                label: 'Emergency card',
                value: 'Update',
                onTap: widget.onEmergencyCard,
                focused: _focusedIndex == 4,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.containerKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.focused = false,
  });

  final Key containerKey;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final cardWidth = responsive.s(140).clamp(132.0, 158.0).toDouble();
    // Tracks both the screen scale and the user's accessibility text scale so
    // the label + value always fit inside the fixed frame.
    final cardHeight =
        responsive.s(160).clamp(150.0, 190.0).toDouble() *
        responsive.textScale.clamp(1.0, 1.4);
    final inset = responsive.s(16).clamp(14.0, 18.0).toDouble();
    final foreground = focused ? context.colors.accent : context.colors.ink;
    final muted = focused ? MedGuardPalette.teal : context.colors.inkSoft;

    return Pressable(
      onTap: onTap,
      pressScale: 0.96,
      child: AnimatedContainer(
        key: containerKey,
        duration: _homeTapFlashDuration,
        curve: Curves.easeOutCubic,
        width: cardWidth,
        height: cardHeight,
        padding: EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: focused ? null : context.colors.surface,
          gradient: focused ? _homeFeaturedGradient(context.colors) : null,
          borderRadius: BorderRadius.circular(responsive.radius(30)),
          border: Border.all(
            color: focused
                ? _homeFeaturedBorder(context.colors)
                : context.colors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: focused
                  ? context.colors.accentAlpha(0.08)
                  : context.colors.ink.withValues(alpha: 0.04),
              blurRadius: responsive.s(18),
              offset: Offset(0, responsive.s(8)),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: responsive.s(42),
              height: responsive.s(42),
              decoration: BoxDecoration(
                color: focused
                    ? context.colors.surface
                    : context.colors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: focused ? context.colors.accent : context.colors.ink,
                size: responsive.icon(22),
              ),
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: muted,
                fontSize: responsive.font(12.2),
                fontWeight: FontWeight.w400,
                height: 1.05,
              ),
            ),
            SizedBox(height: responsive.s(4)),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: foreground,
                fontSize: responsive.font(22),
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

// Soft teal-tinted gradient shared by the regimen-risk box, the next-dose
// hero, the calm safety alert hero, the focused quick-access card, and the
// weekly snapshot tiles.
// Light = the soft teal wash; dark = a subtly lifted tinted surface so the
// featured heroes still read as raised without glowing on the dark canvas.
LinearGradient _homeFeaturedGradient(MedGuardColors colors) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: colors.isDark
      ? [colors.surfaceAlt, colors.surface]
      : const [Color(0xFFF3FAF8), Color(0xFFE7F2EF)],
);
Color _homeFeaturedBorder(MedGuardColors colors) =>
    colors.isDark ? colors.border : const Color(0xFFD7E9E5);

// The home cards use the shared soft card elevation so every raised surface
// across the app lifts by exactly the same amount.
List<BoxShadow> _homeCardShadow(MedGuardResponsive r) => MedGuardShadows.card;
