// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

class _CareInsightSection extends StatelessWidget {
  const _CareInsightSection();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSectionHeader(
          title: 'Care Insights',
          action: 'Updated today',
          subtitle: 'Trusted medication safety reads.',
        ),
        SizedBox(height: responsive.s(16).clamp(14.0, 18.0).toDouble()),
        const _HomeInsightHeroCard(),
        SizedBox(height: responsive.s(12)),
        const Row(
          children: [
            Expanded(
              child: _HomeSmallInsightCard(
                arrowKey: ValueKey('home-pill-insight-arrow'),
                pillLabel: 'Pill guidance',
                title: 'Pill safety basics',
                body: 'Check strength, storage, and warnings before use.',
                imageAsset: _homeInsightSecondaryAsset,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _HomeSmallInsightCard(
                arrowKey: ValueKey('home-food-insight-arrow'),
                pillLabel: 'Food + drug',
                title: 'Food-drug checks',
                body: 'Food timing can change how medicines work.',
                imageAsset: _homeInsightFoodAsset,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeInsightHeroCard extends StatelessWidget {
  const _HomeInsightHeroCard();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(responsive.radius(26)),
      child: SizedBox(
        // Grows with the user's accessibility text scale so the copy inside
        // never overflows the fixed frame.
        height:
            responsive.s(270).clamp(250.0, 300.0).toDouble() *
            responsive.textScale.clamp(1.0, 1.4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _homeInsightCoverAsset,
              key: const ValueKey('home-insight-cover-image'),
              fit: BoxFit.cover,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.24),
                    Colors.black.withValues(alpha: 0.70),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(
                responsive.s(16).clamp(14.0, 18.0).toDouble(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HomeGlassPill(label: 'Medication safety'),
                  SizedBox(height: responsive.s(8)),
                  const _HomeGlassPill(label: 'FDA update'),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Medication safety updates to review',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: MedGuardPalette.pureWhite,
                                fontSize: responsive.font(22),
                                fontWeight: FontWeight.w600,
                                height: 1.04,
                              ),
                            ),
                            SizedBox(height: responsive.s(8)),
                            Text(
                              'Verified drug safety notices help you spot label changes before they affect a daily routine.',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: MedGuardPalette.whiteAlpha(0.88),
                                fontSize: responsive.font(12.2),
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: responsive.s(12)),
                      const _HomeGlassArrow(
                        key: ValueKey('home-insight-arrow'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSmallInsightCard extends StatelessWidget {
  const _HomeSmallInsightCard({
    required this.arrowKey,
    required this.pillLabel,
    required this.title,
    required this.body,
    required this.imageAsset,
  });

  final Key arrowKey;
  final String pillLabel;
  final String title;
  final String body;
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(responsive.radius(22)),
      child: SizedBox(
        height:
            responsive.s(204).clamp(192.0, 220.0).toDouble() *
            responsive.textScale.clamp(1.0, 1.4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(imageAsset, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.66),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(
                responsive.s(13).clamp(12.0, 15.0).toDouble(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeGlassPill(label: pillLabel),
                  const Spacer(),
                  _HomeGlassArrow(
                    key: arrowKey,
                    size: responsive.s(36).clamp(34.0, 38.0).toDouble(),
                    iconSize: responsive.icon(18),
                  ),
                  SizedBox(height: responsive.s(8)),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: GoogleFonts.inter(
                      color: MedGuardPalette.pureWhite,
                      fontSize: responsive.font(14.5),
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: responsive.s(6)),
                  Text(
                    body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: MedGuardPalette.whiteAlpha(0.86),
                      fontSize: responsive.font(11.2),
                      fontWeight: FontWeight.w400,
                      height: 1.28,
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
}

class _HomeGlassPill extends StatelessWidget {
  const _HomeGlassPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MedGuardPalette.pureWhite.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: MedGuardPalette.pureWhite.withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: MedGuardPalette.pureWhite,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeGlassArrow extends StatelessWidget {
  const _HomeGlassArrow({super.key, this.size = 44, this.iconSize = 22});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MedGuardPalette.pureWhite.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(
              color: MedGuardPalette.pureWhite.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(
            Icons.north_east_rounded,
            color: MedGuardPalette.pureWhite,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

// ── Supporting editorial + cards ─────────────────────────────────────────────

const _medicationTruthInterval = Duration(seconds: 6);

class _MedicationTruth {
  const _MedicationTruth({required this.text, required this.topic});

  final String text;
  final String topic;
}

const _medicationTruths = [
  _MedicationTruth(
    text:
        'Some medicines work differently when taken with certain everyday foods.',
    topic: 'Food interactions',
  ),
  _MedicationTruth(
    text:
        'Generic medicines must match brand drugs for active ingredients too.',
    topic: 'Generic medicines',
  ),
  _MedicationTruth(
    text: 'Supplements can change how prescriptions behave inside your body.',
    topic: 'Supplements',
  ),
  _MedicationTruth(
    text: 'Medicine cabinets near showers can shorten shelf life over time.',
    topic: 'Storage',
  ),
  _MedicationTruth(
    text:
        'Cold remedies may duplicate ingredients already in prescriptions at home.',
    topic: 'OTC safety',
  ),
];

/// A quiet, rotating editorial note with a teal accent rail. Tap to advance.
class _MedicationTruthSection extends StatefulWidget {
  const _MedicationTruthSection();

  @override
  State<_MedicationTruthSection> createState() =>
      _MedicationTruthSectionState();
}

class _MedicationTruthSectionState extends State<_MedicationTruthSection> {
  Timer? _timer;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_medicationTruthInterval, (_) {
      _advanceTruth();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _advanceTruth() {
    if (!mounted) return;
    setState(() {
      _index = (_index + 1) % _medicationTruths.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final truth = _medicationTruths[_index];

    return Padding(
      key: const ValueKey('home-medication-truth-section'),
      padding: EdgeInsets.symmetric(
        vertical: responsive.s(3).clamp(2.0, 5.0).toDouble(),
      ),
      child: Semantics(
        button: true,
        label: 'Medication truth',
        child: Pressable(
          onTap: _advanceTruth,
          pressScale: 0.99,
          child: _AccentEditorial(
            eyebrow: 'Medication truth',
            trailing: '${_index + 1}/${_medicationTruths.length}',
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.18),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: Column(
                key: ValueKey('medication-truth-${truth.text}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    truth.text,
                    style: GoogleFonts.inter(
                      color: context.colors.ink,
                      fontSize: responsive.font(15),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      height: 1.34,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(6).clamp(5.0, 7.0)),
                  Text(
                    truth.topic,
                    style: GoogleFonts.inter(
                      color: context.colors.inkMute,
                      fontSize: responsive.font(12),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared minimal editorial layout — a solid teal vertical accent line on the
/// leading edge, an uppercase-tracked eyebrow, and italic body text.
class _AccentEditorial extends StatelessWidget {
  const _AccentEditorial({
    required this.eyebrow,
    required this.child,
    this.trailing,
  });

  final String eyebrow;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: responsive.s(3).clamp(3.0, 4.0).toDouble(),
            decoration: BoxDecoration(
              color: context.colors.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          SizedBox(width: responsive.s(14).clamp(12.0, 16.0)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        eyebrow,
                        style: GoogleFonts.inter(
                          color: context.colors.accent,
                          fontSize: responsive.font(11.5),
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: GoogleFonts.inter(
                          color: context.colors.inkMute,
                          fontSize: responsive.font(11.5),
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: responsive.s(9).clamp(8.0, 11.0)),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DidYouKnowSection extends StatelessWidget {
  const _DidYouKnowSection();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Padding(
      key: const ValueKey('home-did-you-know-section'),
      padding: EdgeInsets.symmetric(
        vertical: responsive.s(3).clamp(2.0, 5.0).toDouble(),
      ),
      child: Semantics(
        label: 'Did you know',
        child: _AccentEditorial(
          eyebrow: 'Did you know',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Taking doses at consistent times helps clinicians spot patterns.',
                style: GoogleFonts.inter(
                  color: context.colors.ink,
                  fontSize: responsive.font(15),
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  height: 1.34,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(height: responsive.s(7).clamp(6.0, 9.0)),
              Text(
                'Small changes are easier to review when your routine is steady.',
                style: GoogleFonts.inter(
                  color: context.colors.inkSoft,
                  fontSize: responsive.font(13),
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  height: 1.34,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
