// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

/// The kind of dangerous concern — drives the row's tag and icon.
enum _DangerKind { interaction, allergy, duplicate }

extension on _DangerKind {
  String get tag => switch (this) {
    _DangerKind.interaction => 'Interaction',
    _DangerKind.allergy => 'Allergy',
    _DangerKind.duplicate => 'Duplicate',
  };

  IconData get icon => switch (this) {
    _DangerKind.interaction => Icons.sync_problem_rounded,
    _DangerKind.allergy => Icons.coronavirus_rounded,
    _DangerKind.duplicate => Icons.layers_rounded,
  };
}

/// One concern line shown in the danger popup.
class _DangerConcern {
  const _DangerConcern({
    required this.kind,
    required this.title,
    required this.detail,
  });
  final _DangerKind kind;
  final String title;
  final String detail;
}

List<_DangerConcern> _dangerConcernsFrom(SafetyReport report) {
  final concerns = <_DangerConcern>[
    for (final i in report.drugInteractions.where((i) => i.riskLevel.isHigh))
      _DangerConcern(
        kind: _DangerKind.interaction,
        title: '${i.drugAName} + ${i.drugBName}',
        detail: i.effect?.trim().isNotEmpty == true
            ? i.effect!.trim()
            : 'High-risk drug interaction — avoid taking together.',
      ),
    for (final hit in report.allergyHits)
      _DangerConcern(
        kind: _DangerKind.allergy,
        title: hit.drugName,
        detail: hit.summary,
      ),
    for (final dup in report.duplicateTherapies)
      _DangerConcern(
        kind: _DangerKind.duplicate,
        title: '${dup.drugAName} + ${dup.drugBName}',
        detail:
            'Both are ${dup.category} — taking both risks an additive dose.',
      ),
  ];
  return concerns;
}

class _DangerDetailsSheet extends StatelessWidget {
  const _DangerDetailsSheet({
    required this.report,
    required this.onReview,
    required this.onSkip,
  });

  final SafetyReport report;
  final VoidCallback onReview;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final concerns = _dangerConcernsFrom(report);
    // Keep the sheet concise: at most three concerns inline; the rest live in the
    // full report (reached via "Review").
    final shown = concerns.take(3).toList();
    final extra = concerns.length - shown.length;
    final chip = responsive.s(40).clamp(36.0, 44.0).toDouble();
    final padX = responsive.s(18).clamp(16.0, 20.0).toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(responsive.s(10).clamp(8.0, 12.0)),
        child: Container(
          key: const ValueKey('home-danger-sheet'),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(responsive.radius(26)),
            boxShadow: MedGuardShadows.modal,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle.
              Center(
                child: Container(
                  width: responsive.s(36).clamp(32.0, 42.0),
                  height: 4,
                  margin: EdgeInsets.only(
                    top: responsive.s(9),
                    bottom: responsive.s(2),
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.inkAlpha(0.10),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              // ── Compact header: danger chip + eyebrow + headline ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padX,
                  responsive.s(12),
                  padX,
                  responsive.s(13),
                ),
                child: Row(
                  children: [
                    Container(
                      width: chip,
                      height: chip,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _homeDangerFor(context).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          responsive.radius(13),
                        ),
                      ),
                      child: Icon(
                        Icons.warning_rounded,
                        color: _homeDangerFor(context),
                        size: responsive.icon(21),
                      ),
                    ),
                    SizedBox(width: responsive.s(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SAFETY ALERT',
                            style: GoogleFonts.inter(
                              color: _homeDangerFor(context),
                              fontSize: responsive.font(10.5),
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              letterSpacing: 0.6,
                            ),
                          ),
                          SizedBox(height: responsive.s(4)),
                          Text(
                            concerns.length == 1
                                ? 'A high-risk combination'
                                : '${concerns.length} high-risk concerns',
                            style: GoogleFonts.inter(
                              color: context.colors.ink,
                              fontSize: responsive.font(17),
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Concern list — capped so the sheet never runs off-screen ──
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.36,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: padX),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final concern in shown)
                        _DangerConcernRow(concern: concern),
                      if (extra > 0)
                        Padding(
                          padding: EdgeInsets.only(
                            top: responsive.s(2),
                            bottom: responsive.s(4),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.more_horiz_rounded,
                                size: responsive.icon(16),
                                color: context.colors.inkMute,
                              ),
                              SizedBox(width: responsive.s(7)),
                              Text(
                                '$extra more in the full report',
                                style: GoogleFonts.inter(
                                  color: context.colors.inkMute,
                                  fontSize: responsive.font(11.5),
                                  fontWeight: FontWeight.w600,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: responsive.s(14)),
              // ── Actions — quiet dismiss + emphasised review, side by side ──
              Padding(
                padding: EdgeInsets.fromLTRB(padX, 0, padX, responsive.s(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('home-danger-sheet-skip'),
                        label: 'Dismiss',
                        variant: AppButtonVariant.secondary,
                        onTap: onSkip,
                      ),
                    ),
                    SizedBox(width: responsive.s(10)),
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('home-danger-sheet-review'),
                        label: 'Review',
                        icon: Icons.fact_check_rounded,
                        onTap: onReview,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerConcernRow extends StatelessWidget {
  const _DangerConcernRow({required this.concern});

  final _DangerConcern concern;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final iconChip = responsive.s(32).clamp(28.0, 36.0).toDouble();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: responsive.s(8)),
      padding: EdgeInsets.all(responsive.s(11).clamp(10.0, 13.0)),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(responsive.radius(14)),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: iconChip,
            height: iconChip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _homeDangerFor(context).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(responsive.radius(9)),
            ),
            child: Icon(
              concern.kind.icon,
              color: _homeDangerFor(context),
              size: responsive.icon(16),
            ),
          ),
          SizedBox(width: responsive.s(11)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        concern.title,
                        style: GoogleFonts.inter(
                          color: context.colors.ink,
                          fontSize: responsive.font(13.5),
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                    ),
                    SizedBox(width: responsive.s(8)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.s(7).clamp(6.0, 9.0),
                        vertical: responsive.s(3).clamp(2.0, 4.0),
                      ),
                      decoration: BoxDecoration(
                        color: _homeDangerFor(context).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        concern.kind.tag.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: _homeDangerFor(context),
                          fontSize: responsive.font(9.5),
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.s(5)),
                Text(
                  concern.detail,
                  style: GoogleFonts.inter(
                    color: context.colors.inkSoft,
                    fontSize: responsive.font(12),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
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

// ── Powerful, quietly-rotating app caption ──────────────────────────────────

const _homeCaptions = <(String, String)>[
  ('Your medicines,', 'fully guarded'),
  ('Every dose,', 'carefully checked'),
  ('Real clarity,', 'less confusion'),
  ('Stay protected,', 'stay confident'),
  ('Total confidence,', 'every dose'),
  ('Fewer risks,', 'more calm'),
  ('Smarter safety,', 'made human'),
];

/// A two-part caption that changes on each fresh load with no visible cue that
/// it rotates: a small grey lead line, then a big dark-teal statement that
/// never wraps (it scales down to fit instead).
class _HomeAppCaption extends StatefulWidget {
  const _HomeAppCaption();

  @override
  State<_HomeAppCaption> createState() => _HomeAppCaptionState();
}

class _HomeAppCaptionState extends State<_HomeAppCaption> {
  late final (String, String) _caption;

  @override
  void initState() {
    super.initState();
    // Chosen once per screen life so it stays stable through rebuilds, but a
    // different one greets the user next time they open the app.
    final index =
        DateTime.now().millisecondsSinceEpoch.abs() % _homeCaptions.length;
    _caption = _homeCaptions[index];
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // Pin the whole caption to the left edge of the page (the parent feed column
    // centres shrink-wrapped children, which is why it used to float to the
    // middle). The Align stretches to the full content width so both lines start
    // hard against the page margin.
    return Align(
      key: const ValueKey('home-app-caption'),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _caption.$1,
            maxLines: 1,
            style: GoogleFonts.inter(
              color: context.colors.inkMute,
              fontSize: responsive.font(19),
              fontWeight: FontWeight.w400,
              height: 1.0,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: responsive.s(5).clamp(4.0, 7.0).toDouble()),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _caption.$2,
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.inter(
                color: context.colors.accent,
                fontSize: responsive.font(44),
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
