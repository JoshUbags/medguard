import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../welcome/welcome_assets.dart';
import 'medication_context_screen.dart';
import 'onboarding_chrome.dart';

class InteractionReviewScreen extends StatefulWidget {
  const InteractionReviewScreen({super.key});

  @override
  State<InteractionReviewScreen> createState() =>
      _InteractionReviewScreenState();
}

class _InteractionReviewScreenState extends State<InteractionReviewScreen>
    with SingleTickerProviderStateMixin {
  int _activeInsight = 0;
  late final AnimationController _float;

  static const _insights = <_Insight>[
    _Insight(
      label: 'Signal',
      title: 'Major bleeding signal',
      body: 'Warfarin with ibuprofen may increase bleeding risk.',
      icon: Icons.warning_amber_rounded,
      accent: MedGuardPalette.ruby,
    ),
    _Insight(
      label: 'Decision',
      title: 'Use a safer plan',
      body: 'Choose a safer pain option or document monitoring.',
      icon: Icons.verified_rounded,
      accent: MedGuardPalette.teal,
    ),
    _Insight(
      label: 'Monitor',
      title: 'Monitor for bleeding',
      body: 'Watch for bruising, dark stool, bleeding, or dizziness.',
      icon: Icons.monitor_heart_rounded,
      accent: Color(0xFFE8751A),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _next() {
    Navigator.of(
      context,
    ).push(onboardingSlideRoute(const MedicationContextScreen()));
  }

  void _back() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insight = _insights[_activeInsight];

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
                child: _InteractionInstruction(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _InteractionHero(
                  animation: _float,
                  insight: insight,
                  insights: _insights,
                  activeInsight: _activeInsight,
                  onSelect: (index) => setState(() => _activeInsight = index),
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
                          TextSpan(text: 'Review Drug\n'),
                          TextSpan(
                            text: 'Interaction',
                            style: TextStyle(color: MedGuardPalette.teal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    const _InteractionTags(),
                    const SizedBox(height: 12),
                    Text(
                      'MedGuard turns drug-pair warnings into clear risk, action, and monitoring cues.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: context.colors.inkSoft,
                        fontSize: 13.2,
                        height: 1.46,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
              OnboardingFooter(activeIndex: 0, onBack: _back, onNext: _next),
            ],
          ),
        ),
      ),
    );
  }
}

class _InteractionHero extends StatelessWidget {
  const _InteractionHero({
    required this.animation,
    required this.insight,
    required this.insights,
    required this.activeInsight,
    required this.onSelect,
  });

  final Animation<double> animation;
  final _Insight insight;
  final List<_Insight> insights;
  final int activeInsight;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 320;
            final caseWidth = math.min(
              constraints.maxWidth * (compact ? 0.76 : 0.80),
              compact ? 284.0 : 304.0,
            );
            final imageScale = compact ? 0.92 : 1.0;
            return RepaintBoundary(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  _FloatingDepthCard(
                    asset: 'assets/images/onboarding/04.jpg',
                    width: 224 * imageScale,
                    height: 282 * imageScale,
                    angle: -0.18,
                    // Dropped lower than its mirror on the right so its top
                    // corner stays clear of the "Tap a step…" instruction above.
                    offset: Offset(-124, -14 - 10 * t),
                  ),
                  _FloatingDepthCard(
                    asset: 'assets/images/onboarding/06.jpg',
                    width: 224 * imageScale,
                    height: 282 * imageScale,
                    angle: 0.18,
                    offset: Offset(124, 44 + 10 * t),
                  ),
                  SizedBox(
                    width: caseWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: caseWidth,
                        child: _GlassCase024(
                          insight: insight,
                          insights: insights,
                          activeInsight: activeInsight,
                          onSelect: onSelect,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FloatingDepthCard extends StatelessWidget {
  const _FloatingDepthCard({
    required this.asset,
    required this.width,
    required this.height,
    required this.angle,
    required this.offset,
  });

  final String asset;
  final double width;
  final double height;
  final double angle;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: angle,
          child: Opacity(
            opacity: 0.34,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  asset,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  cacheWidth: kOnboardingDepthCardCacheWidth,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCase024 extends StatelessWidget {
  const _GlassCase024({
    required this.insight,
    required this.insights,
    required this.activeInsight,
    required this.onSelect,
    required this.compact,
  });

  final _Insight insight;
  final List<_Insight> insights;
  final int activeInsight;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 24.0 : 28.0;
    // Liquid-glass: a controlled blur behind a softly translucent surface with a
    // bright top edge and layered, teal-tinted depth — translucent enough to
    // read as glass, opaque enough to keep the clinical content perfectly legible.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.colors.surface.withValues(alpha: 0.78),
                context.colors.surfaceAlt.withValues(alpha: 0.62),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: context.colors.surface.withValues(alpha: 0.85),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: context.colors.accent.withValues(alpha: 0.12),
                blurRadius: 34,
                spreadRadius: -8,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: MedGuardPalette.blackAlpha(0.05),
                blurRadius: 14,
                spreadRadius: -8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Case 024',
                    style: GoogleFonts.inter(
                      color: context.colors.ink,
                      fontSize: compact ? 13.2 : 13.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // The case's risk classification is fixed at High, so the
                  // badge must always read in the high-risk tone — never recolour
                  // to the selected step's accent (which can be teal or amber and
                  // would misrepresent a High verdict as Low/Moderate).
                  const _CaseBadge(label: 'High', accent: MedGuardPalette.ruby),
                ],
              ),
              SizedBox(height: compact ? 7 : 9),
              Row(
                children: [
                  Expanded(
                    child: OnboardingDrugPill(
                      label: 'Warfarin',
                      compact: compact,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
                    child: Icon(
                      Icons.add_rounded,
                      color: context.colors.inkMute,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: OnboardingDrugPill(
                      label: 'Ibuprofen',
                      compact: compact,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 7 : 9),
              _CaseSummaryRow(
                icon: Icons.account_circle_rounded,
                label: 'Context',
                value: 'Adult on anticoagulant therapy',
                accent: MedGuardPalette.teal,
                compact: compact,
              ),
              SizedBox(height: compact ? 7 : 8),
              Row(
                children: [
                  for (int i = 0; i < insights.length; i++) ...[
                    Expanded(
                      child: _InsightChip(
                        insight: insights[i],
                        selected: i == activeInsight,
                        onTap: () => onSelect(i),
                        compact: compact,
                      ),
                    ),
                    if (i != insights.length - 1)
                      SizedBox(width: compact ? 5 : 7),
                  ],
                ],
              ),
              SizedBox(height: compact ? 7 : 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _InsightReadout(
                  key: ValueKey(insight.label),
                  insight: insight,
                  compact: compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InteractionInstruction extends StatelessWidget {
  const _InteractionInstruction();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Tap a step to update Case 024.',
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

class _InteractionTags extends StatelessWidget {
  const _InteractionTags();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OnboardingTag(icon: Icons.bolt_rounded, label: 'Severity Signal'),
        OnboardingTag(icon: Icons.verified_rounded, label: 'Decision Ready'),
      ],
    );
  }
}

class _CaseBadge extends StatelessWidget {
  const _CaseBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CaseSummaryRow extends StatelessWidget {
  const _CaseSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: compact ? 16 : 17),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: compact ? 11.2 : 11.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: context.colors.inkSoft,
                fontSize: compact ? 11.2 : 11.8,
                height: 1.26,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.insight,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final _Insight insight;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? insight.accent.withValues(alpha: 0.13)
              : context.colors.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? insight.accent.withValues(alpha: 0.30)
                : MedGuardPalette.inkAlpha(0.06),
          ),
        ),
        // Icon + label share one vertically-centred row, so each of the three
        // section selectors lines its glyph up with its header identically.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              insight.icon,
              size: compact ? 11.5 : 12.5,
              color: selected ? insight.accent : context.colors.inkMute,
            ),
            SizedBox(width: compact ? 3 : 4),
            Flexible(
              child: Text(
                insight.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: GoogleFonts.inter(
                  color: context.colors.ink,
                  fontSize: compact ? 11 : 11.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightReadout extends StatelessWidget {
  const _InsightReadout({
    super.key,
    required this.insight,
    required this.compact,
  });

  final _Insight insight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 9 : 10),
      decoration: BoxDecoration(
        color: insight.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: insight.accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // Icon disc and header sit on one centred baseline for a clean,
            // consistent rhythm across all three sections.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: compact ? 24 : 26,
                height: compact ? 24 : 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: insight.accent.withValues(alpha: 0.13),
                ),
                child: Icon(
                  insight.icon,
                  color: insight.accent,
                  size: compact ? 14 : 15,
                ),
              ),
              SizedBox(width: compact ? 8 : 9),
              Expanded(
                child: Text(
                  insight.title,
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: compact ? 12.4 : 12.8,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 3 : 4),
          Text(
            insight.body,
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: compact ? 11.2 : 11.6,
              height: 1.30,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Insight {
  const _Insight({
    required this.label,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
}
