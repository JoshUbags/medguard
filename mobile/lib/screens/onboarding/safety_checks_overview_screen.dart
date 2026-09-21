import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import 'onboarding_chrome.dart';

class SafetyChecksOverviewScreen extends StatefulWidget {
  const SafetyChecksOverviewScreen({super.key});

  @override
  State<SafetyChecksOverviewScreen> createState() =>
      _SafetyChecksOverviewScreenState();
}

class _SafetyChecksOverviewScreenState
    extends State<SafetyChecksOverviewScreen> {
  int _activeIndex = 0;

  static const _items = <_CheckItem>[
    _CheckItem(
      icon: Icons.swap_horiz_rounded,
      title: 'Drug-Drug Interactions',
      body: 'Checks risky medicine pairs.',
      detail: 'Risk grade and next step stay visible.',
      signal: 'Severity and cause cue',
      action: 'Choose safer plan',
      accent: MedGuardPalette.teal,
    ),
    _CheckItem(
      icon: Icons.water_drop_rounded,
      title: 'Food and Drink Conflicts',
      body: 'Checks intake timing conflicts.',
      detail: 'Use advice stays close to the warning.',
      signal: 'Timing conflict cue',
      action: 'Separate dose',
      accent: Color(0xFFE8751A),
    ),
    _CheckItem(
      icon: Icons.layers_rounded,
      title: 'Duplicate Therapy',
      body: 'Finds repeated therapy roles.',
      detail: 'Class overlap is easier to catch.',
      signal: 'Class overlap cue',
      action: 'Confirm active plan',
      accent: Color(0xFF5C7CFA),
    ),
    _CheckItem(
      icon: Icons.tune_rounded,
      title: 'Dose-Range Sanity',
      body: 'Flags unusual dose patterns.',
      detail: 'Dose details get a focused review.',
      signal: 'Dose pattern cue',
      action: 'Review patient factors',
      accent: Color(0xFF8E6DB5),
    ),
    _CheckItem(
      icon: Icons.assignment_ind_rounded,
      title: 'Patient-Specific Flags',
      body: 'Applies patient-specific risks.',
      detail: 'Profile risks stay visible.',
      signal: 'Profile risk cue',
      action: 'Match patient profile',
      accent: MedGuardPalette.ruby,
    ),
  ];

  void _showNextCard() {
    setState(() => _activeIndex = (_activeIndex + 1) % _items.length);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // The card stack above is elastic; everything below it is not. On the
    // smallest supported phone, or with accessibility text turned up, the fixed
    // block has to give way — so the copy tightens and the sub-line under the
    // local-only action drops rather than pushing the footer off the screen.
    final tight = responsive.isCompactPhone || responsive.textScale > 1.15;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: context.colors.scaffold,
        body: SafeArea(
          child: Column(
            children: [
              const OnboardingSkipAction(),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: _SafetyInstruction(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _SafetyStack(
                  items: _items,
                  activeIndex: _activeIndex,
                  onTap: _showNextCard,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Column(
                  children: [
                    Text.rich(
                      textAlign: TextAlign.center,
                      TextSpan(
                        style: GoogleFonts.inter(
                          color: context.colors.ink,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          height: 1.02,
                          letterSpacing: -0.4,
                        ),
                        children: const [
                          TextSpan(text: 'Five-Point\n'),
                          TextSpan(
                            text: 'Safety',
                            style: TextStyle(color: MedGuardPalette.teal),
                          ),
                          TextSpan(text: ' Checks'),
                        ],
                      ),
                    ),
                    SizedBox(height: tight ? 8 : 12),
                    const _SafetyTags(),
                    SizedBox(height: tight ? 7 : 10),
                    Text(
                      'MedGuard checks interactions, food conflicts, duplication, dosing, and patient flags.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: context.colors.inkSoft,
                        fontSize: 13.2,
                        height: 1.46,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                    SizedBox(height: tight ? 8 : 18),
                    // The last onboarding screen is the first place the account
                    // question is actually asked, so it is also the first place
                    // the answer "no account" is offered. Every check described
                    // above runs on this device; making the user sign in to
                    // reach them would contradict the screen they are reading.
                    ContinueWithoutAccountAction(
                      caption: tight ? null : 'Your record stays on this phone.',
                    ),
                    SizedBox(height: tight ? 4 : 14),
                  ],
                ),
              ),
              OnboardingFooter(
                activeIndex: 2,
                onBack: () => Navigator.of(context).pop(),
                onNext: () => completeOnboardingAndGoToSignIn(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyStack extends StatelessWidget {
  const _SafetyStack({
    required this.items,
    required this.activeIndex,
    required this.onTap,
  });

  final List<_CheckItem> items;
  final int activeIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = constraints.maxHeight < 340;
          final targetWidth = width * (compact ? 0.76 : 0.80);
          final cardWidth = targetWidth
              .clamp(compact ? 238.0 : 252.0, compact ? 284.0 : 304.0)
              .toDouble();
          final cardHeight = compact
              ? constraints.maxHeight.clamp(170.0, 204.0).toDouble()
              : 236.0;
          final baseOffset = compact ? 10.0 : 20.0;
          final drawOrder = [
            for (int offset = items.length - 1; offset >= 1; offset--)
              (activeIndex + offset) % items.length,
            activeIndex,
          ];

          return RepaintBoundary(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                for (final index in drawOrder)
                  _StackedSafetyCard(
                    key: ValueKey('safety-card-$index'),
                    item: items[index],
                    active: index == activeIndex,
                    depth: (index - activeIndex + items.length) % items.length,
                    width: cardWidth,
                    height: cardHeight,
                    baseOffset: baseOffset,
                    itemIndex: index,
                    compactLayout: compact,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StackedSafetyCard extends StatelessWidget {
  const _StackedSafetyCard({
    super.key,
    required this.item,
    required this.active,
    required this.depth,
    required this.width,
    required this.height,
    required this.baseOffset,
    required this.itemIndex,
    required this.compactLayout,
  });

  final _CheckItem item;
  final bool active;
  final int depth;
  final double width;
  final double height;
  final double baseOffset;
  final int itemIndex;
  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    final y = active ? baseOffset : baseOffset - depth * 18;
    final x = active ? 0.0 : (depth.isEven ? 14.0 : -14.0);
    final rotation = active ? 0.0 : (depth.isEven ? 0.055 : -0.055);
    final opacity = active ? 1.0 : (0.92 - depth * 0.04).clamp(0.74, 1.0);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 360),
      opacity: opacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutBack,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(x, y, 0, 1)
          ..rotateZ(rotation),
        width: width,
        height: height,
        padding: EdgeInsets.all(compactLayout ? 15 : 18),
        decoration: BoxDecoration(
          color: active
              ? context.colors.surface
              : Color.lerp(context.colors.surface, item.accent, 0.07),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active
                ? item.accent.withValues(alpha: 0.28)
                : MedGuardPalette.inkAlpha(0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: active
                  ? item.accent.withValues(alpha: 0.15)
                  : MedGuardPalette.blackAlpha(0.045),
              blurRadius: active ? 30 : 16,
              offset: Offset(0, active ? 17 : 9),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = active
                ? _ActiveSafetyCardContent(
                    item: item,
                    itemIndex: itemIndex,
                    compact: compactLayout,
                  )
                : _SafetyCardHeader(
                    item: item,
                    active: active,
                    itemIndex: itemIndex,
                    compact: true,
                  );

            if (!active) return content;

            return FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.scaleDown,
              child: SizedBox(width: constraints.maxWidth, child: content),
            );
          },
        ),
      ),
    );
  }
}

class _ActiveSafetyCardContent extends StatelessWidget {
  const _ActiveSafetyCardContent({
    required this.item,
    required this.itemIndex,
    required this.compact,
  });

  final _CheckItem item;
  final int itemIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SafetyCardHeader(
            item: item,
            active: true,
            itemIndex: itemIndex,
            compact: true,
          ),
          const SizedBox(height: 5),
          Text(
            item.body,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: 11.2,
              height: 1.16,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SafetyDetailRow(
                  icon: Icons.radar_rounded,
                  label: 'Signal',
                  value: item.signal,
                  accent: item.accent,
                  compact: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SafetyDetailRow(
                  icon: Icons.check_circle_rounded,
                  label: 'Action',
                  value: item.action,
                  accent: item.accent,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _SafetyCardNote(text: item.detail, compact: true),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SafetyCardHeader(item: item, active: true, itemIndex: itemIndex),
        const SizedBox(height: 10),
        Text(
          item.body,
          style: GoogleFonts.inter(
            color: context.colors.ink,
            fontSize: 11.6,
            height: 1.28,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 10),
        _SafetyDetailRow(
          icon: Icons.radar_rounded,
          label: 'Signal',
          value: item.signal,
          accent: item.accent,
        ),
        const SizedBox(height: 8),
        _SafetyDetailRow(
          icon: Icons.check_circle_rounded,
          label: 'Action',
          value: item.action,
          accent: item.accent,
        ),
        const SizedBox(height: 10),
        _SafetyCardNote(text: item.detail),
      ],
    );
  }
}

class _SafetyInstruction extends StatelessWidget {
  const _SafetyInstruction();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Tap cards to bring a check forward.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: context.colors.ink,
        fontSize: 11.6,
        height: 1.18,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SafetyTags extends StatelessWidget {
  const _SafetyTags();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OnboardingTag(icon: Icons.verified_rounded, label: 'Five Risk Areas'),
        OnboardingTag(
          icon: Icons.assignment_ind_rounded,
          label: 'Profile Flags',
        ),
      ],
    );
  }
}

class _SafetyDetailRow extends StatelessWidget {
  const _SafetyDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: accent, size: 12.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 11,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: context.colors.inkSoft,
                fontSize: 11.2,
                height: 1.16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: accent, size: 15),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 11,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: context.colors.inkSoft,
                    fontSize: 11.6,
                    height: 1.28,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyCardNote extends StatelessWidget {
  const _SafetyCardNote({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: context.colors.inkSoft,
          fontSize: compact ? 11.2 : 11.6,
          height: compact ? 1.16 : 1.30,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _SafetyCardHeader extends StatelessWidget {
  const _SafetyCardHeader({
    required this.item,
    required this.active,
    required this.itemIndex,
    this.compact = false,
  });

  final _CheckItem item;
  final bool active;
  final int itemIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: compact ? 32 : 38,
          height: compact ? 32 : 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: item.accent.withValues(alpha: 0.12),
          ),
          child: Icon(item.icon, color: item.accent, size: compact ? 17 : 20),
        ),
        SizedBox(width: compact ? 9 : 12),
        Expanded(
          child: Text(
            item.title,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: compact ? 13.2 : (active ? 13.6 : 13.2),
              height: 1.18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 8,
            vertical: compact ? 4 : 5,
          ),
          decoration: BoxDecoration(
            color: item.accent.withValues(alpha: active ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '0${itemIndex + 1}',
            style: GoogleFonts.inter(
              color: item.accent,
              fontSize: compact ? 11.4 : 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckItem {
  const _CheckItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.detail,
    required this.signal,
    required this.action,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final String detail;
  final String signal;
  final String action;
  final Color accent;
}
