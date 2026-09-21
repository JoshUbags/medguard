import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/interaction_result.dart';
import '../../models/safety_report.dart';
import '../../models/severity.dart';
import '../../models/user_medication.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../common/app_button.dart';
import '../common/severity_colors.dart';

/// Runs the regimen analysis for a set of medicines. Injected so the host
/// screen decides whether the check records history, and so tests can drive it.
typedef AnalyzeRegimenRisk =
    Future<SafetyReport> Function(List<UserMedication> medications);

// ── Tier colours, previously owned by the Home screen. They live with the
// gauge now because the gauge is the only thing that reads them, and it is no
// longer part of Home.
const _riskClearTeal = SeverityColors.low;
const _riskDangerRuby = SeverityColors.high;
const _riskCautionAmber = SeverityColors.moderate;

/// A faint wash of [accent], for the badge behind a tier label.
Color _riskBadgeBgFor(Color accent) => accent.withValues(alpha: 0.12);

/// The featured-card surface, copied EXACTLY from Home's quick-access tiles.
///
/// These literal values matter. When the gauge was extracted out of Home this
/// was rewritten as an approximation built from `colors.surface` plus five
/// percent accent, which is far paler than the original pair below — the card
/// lost the light brand wash that distinguished it from every plain white
/// surface on the page and started reading as an ordinary card.
LinearGradient _homeFeaturedGradient(MedGuardColors colors) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: colors.isDark
      ? [colors.surfaceAlt, colors.surface]
      : const [Color(0xFFF3FAF8), Color(0xFFE7F2EF)],
);

Color _homeFeaturedBorder(MedGuardColors colors) =>
    colors.isDark ? colors.border : const Color(0xFFD7E9E5);

/// True while a Flutter widget test drives the binding — endless animations
/// hold a composed first frame there instead of spinning `pumpAndSettle`.
bool _runningUnderFlutterTest() {
  try {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
  } catch (_) {
    return false;
  }
}

// Transition duration for a quick-access tile's focused-state styling. Tapping a
// tile runs its action immediately — no app-colour flash — so the only press
// feedback is the tactile scale from [Pressable].

class RegimenRiskCard extends StatefulWidget {
  const RegimenRiskCard({
    super.key,
    required this.medications,
    required this.loading,
    required this.onReview,
    required this.onLearnMore,
    required this.analyzeRegimenRisk,
    required this.regimenReviewed,
    this.animationNonce = 0,
    this.compact = false,
    this.actionLabel = 'Review',
    this.actionBusy = false,
  });

  final List<UserMedication> medications;
  final bool loading;
  final VoidCallback onReview;
  final VoidCallback onLearnMore;
  final AnalyzeRegimenRisk analyzeRegimenRisk;

  /// Whether the user has completed the interaction review for this exact
  /// regimen. Until they have, the card shows the review prompt and the
  /// analysis is not run at all — see [RegimenReviewService].
  final bool regimenReviewed;

  /// Incremented when the Home screen is revisited so the risk needle re-sweeps
  /// from the lowest position to the live verdict.
  final int animationNonce;

  /// The minimal form: eyebrow, verdict, the meter, and a single way through to
  /// the full analysis. Home uses it.
  ///
  /// Home and Interactions run the SAME component against the SAME report on
  /// purpose — the compact card is a crop of the full one, not a second
  /// implementation of it. That is what makes the two screens agree: there is
  /// no separate home-summary code path that can drift from the real verdict,
  /// and a change to how risk is scored or worded lands on both at once.
  ///
  /// What compact drops is everything that invites a decision — the "Pair
  /// status" line, the context strip, the primary-driver breakdown, and the
  /// second button. Home's job is to tell you whether to go and look; the
  /// looking happens on Interactions.
  final bool compact;

  /// The card's single action. Home and Interactions pass the SAME words, so
  /// the control a user learns on one page is the control they meet on the
  /// other.
  final String actionLabel;

  /// Shows the action mid-flight.
  final bool actionBusy;

  @override
  State<RegimenRiskCard> createState() => _RegimenRiskCardState();
}

class _RegimenRiskCardState extends State<RegimenRiskCard> {
  Future<SafetyReport>? _reportFuture;
  String _medicationFingerprint = '';

  @override
  void initState() {
    super.initState();
    _syncReportFuture();
  }

  @override
  void didUpdateWidget(covariant RegimenRiskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncReportFuture();
  }

  void _syncReportFuture() {
    final fingerprint = widget.medications
        .map((medication) => medication.drugId)
        .join(',');
    // No analysis is started for an unreviewed regimen: the gate withholds the
    // work, not just the pixels, so nothing can leak through a cache or a
    // half-resolved future the moment the card rebuilds.
    if (widget.loading ||
        widget.medications.length < 2 ||
        !widget.regimenReviewed) {
      _medicationFingerprint = fingerprint;
      _reportFuture = null;
      return;
    }
    if (_reportFuture != null && _medicationFingerprint == fingerprint) {
      return;
    }
    _medicationFingerprint = fingerprint;
    _reportFuture = widget.analyzeRegimenRisk(widget.medications);
  }

  @override
  Widget build(BuildContext context) {
    final initialSnapshot = widget.loading
        ? _RiskSnapshot.loading()
        : widget.medications.length < 2
        ? _RiskSnapshot.noPair(widget.medications.length)
        : !widget.regimenReviewed
        ? _RiskSnapshot.reviewPending()
        : null;

    if (initialSnapshot != null) {
      return _RiskGaugeLayout(
        snapshot: initialSnapshot,
        onReview: widget.onReview,
        onLearnMore: widget.onLearnMore,
        animationNonce: widget.animationNonce,
        compact: widget.compact,
        actionLabel: widget.actionLabel,
        actionBusy: widget.actionBusy,
      );
    }

    return FutureBuilder<SafetyReport>(
      future: _reportFuture,
      builder: (context, reportSnapshot) {
        final risk = reportSnapshot.connectionState == ConnectionState.waiting
            ? _RiskSnapshot.analyzing()
            : reportSnapshot.hasError
            ? _RiskSnapshot.unavailable()
            : _RiskSnapshot.fromReport(
                reportSnapshot.data ?? const SafetyReport.empty(),
              );
        return _RiskGaugeLayout(
          snapshot: risk,
          onReview: widget.onReview,
          onLearnMore: widget.onLearnMore,
          animationNonce: widget.animationNonce,
          compact: widget.compact,
          actionLabel: widget.actionLabel,
          actionBusy: widget.actionBusy,
        );
      },
    );
  }
}

class _RiskGaugeLayout extends StatelessWidget {
  const _RiskGaugeLayout({
    required this.snapshot,
    required this.onReview,
    required this.onLearnMore,
    this.animationNonce = 0,
    this.compact = false,
    this.actionLabel = 'Review',
    this.actionBusy = false,
  });

  final _RiskSnapshot snapshot;
  final VoidCallback onReview;
  final VoidCallback onLearnMore;
  final int animationNonce;
  final bool compact;
  final String actionLabel;
  final bool actionBusy;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Column(
      key: const ValueKey('home-risk-trend-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('home-risk-content-card'),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            responsive.s(18).clamp(16.0, 20.0),
            responsive.s(18).clamp(16.0, 20.0),
            responsive.s(18).clamp(16.0, 20.0),
            responsive.s(16).clamp(15.0, 18.0),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(responsive.radius(26)),
            gradient: _homeFeaturedGradient(context.colors),
            border: Border.all(color: _homeFeaturedBorder(context.colors)),
            boxShadow: [
              BoxShadow(
                color: context.colors.accentAlpha(0.045),
                blurRadius: responsive.s(20),
                offset: Offset(0, responsive.s(8)),
              ),
            ],
          ),
          child: _RegimenRiskCardContent(
            snapshot: snapshot,
            onReview: onReview,
            onLearnMore: onLearnMore,
            animationNonce: animationNonce,
            compact: compact,
            actionLabel: actionLabel,
            actionBusy: actionBusy,
          ),
        ),
      ],
    );
  }
}

class _RegimenRiskCardContent extends StatelessWidget {
  const _RegimenRiskCardContent({
    required this.snapshot,
    required this.onReview,
    required this.onLearnMore,
    this.animationNonce = 0,
    this.compact = false,
    this.actionLabel = 'Review',
    this.actionBusy = false,
  });

  final _RiskSnapshot snapshot;
  final VoidCallback onReview;
  final VoidCallback onLearnMore;

  /// Bumped when the Home screen is revisited so the needle re-sweeps.
  final int animationNonce;

  /// See [RegimenRiskCard.compact].
  final bool compact;
  final String actionLabel;
  final bool actionBusy;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final headline = snapshot.headline.replaceAll('\n', ' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Three informational texts, anchored to the upper-left ─────────
        // The "Interaction risk" eyebrow, the live "Pair status" label, and
        // the plain-language verdict stack in the top-left corner — the
        // original reading order, before the dial takes the focus below.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interaction risk',
                    style: GoogleFonts.inter(
                      color: context.colors.inkMute,
                      fontSize: responsive.font(12.2),
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: responsive.s(8).clamp(7.0, 10.0)),
                  // The verdict, as a chip.
                  //
                  // This slot used to hold the words "Pair status" painted in
                  // `_riskBadgeBgFor(accent)` — a twelve-percent alpha wash
                  // written to be a BACKGROUND fill and mistakenly used as the
                  // text colour, so the label rendered at 12% opacity and was
                  // effectively invisible. It was also redundant: a second
                  // label stacked between an eyebrow and a headline, saying
                  // nothing the headline did not.
                  //
                  // It now carries the canonical verdict instead, which is
                  // information rather than a caption, and reads at full
                  // strength on a tinted pill.
                  if (!compact && snapshot.verdict != null) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.s(10),
                        vertical: responsive.s(5),
                      ),
                      decoration: BoxDecoration(
                        color: _riskBadgeBgFor(snapshot.accent),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        snapshot.verdict!,
                        style: GoogleFonts.inter(
                          color: SeverityColors.foreground(
                            snapshot.accent,
                            Theme.of(context).brightness,
                          ),
                          fontSize: responsive.font(11.6),
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    SizedBox(height: responsive.s(9).clamp(8.0, 11.0)),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      return FadeTransition(
                        opacity: curved,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(curved),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey('risk-headline-$headline'),
                      child: Text(
                        headline,
                        key: const ValueKey('risk-status-text'),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        style: GoogleFonts.inter(
                          color: context.colors.ink,
                          fontSize: responsive.font(19),
                          fontWeight: FontWeight.w700,
                          height: 1.10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: responsive.s(18).clamp(15.0, 20.0)),
        _RegimenRiskMeter(snapshot: snapshot, replayNonce: animationNonce),
        if (!compact) ...[
          SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
          _RiskContextStrip(text: snapshot.contextText),
        ],
        // The single most important clinical takeaway — the primary risk driver,
        // what it does, the next clinical step, and how concentrated the risk is
        // across the four safety axes. Replaces the old "what we screened" grid
        // with information that actually supports a decision.
        if (!compact && snapshot.meterActive && snapshot.driver != null) ...[
          SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
          _PrimaryRiskDriver(driver: snapshot.driver!),
        ],
        SizedBox(height: responsive.s(16).clamp(14.0, 18.0)),
        // ONE action. The card used to offer "Review" and "Details" side by
        // side, and both went to the same place — two buttons for one
        // destination, which reads as a choice the user then has to make for
        // no reason. The host names the action; the card just renders it.
        AppButton(
          key: const ValueKey('home-risk-review-action'),
          label: actionLabel,
          icon: Icons.fact_check_rounded,
          variant: AppButtonVariant.primary,
          loading: actionBusy,
          onTap: onReview,
        ),
      ],
    );
  }
}

/// The Regimen Risk meter — a premium semicircle gauge. Short radial ticks sweep
/// a Low → High arc; at rest they read a calm theme grey, and when a verdict
/// lands a needle points to the [_RiskSnapshot.score] position while the ticks
/// around it light in the tier tone. The needle position is CONTINUOUS within
/// each Low/Moderate/High third — a barely-moderate pair and a critical-high
/// allergy land at visibly different points — and it always sweeps up from the
/// lowest position rather than snapping to a value, so the movement itself helps
/// communicate the assessment. The scale labels + caption sit centred beneath
/// the arc for an even, intentional balance.
class _RegimenRiskMeter extends StatefulWidget {
  const _RegimenRiskMeter({required this.snapshot, this.replayNonce = 0});

  final _RiskSnapshot snapshot;

  /// Bumping this replays the needle sweep from the lowest position — used when
  /// the user returns to / revisits the Home screen so the read re-animates.
  final int replayNonce;

  @override
  State<_RegimenRiskMeter> createState() => _RegimenRiskMeterState();
}

class _RegimenRiskMeterState extends State<_RegimenRiskMeter>
    with SingleTickerProviderStateMixin {
  static const _zones = ['Low', 'Moderate', 'High'];

  late final AnimationController _controller;
  // The needle interpolates from [_begin] to [_end] as the controller runs 0→1.
  double _begin = 0;
  double _end = 0;

  bool get _active =>
      widget.snapshot.meterActive && widget.snapshot.level != null;
  double get _target => _active ? widget.snapshot.score.clamp(0.0, 1.0) : 0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _end = _target;
    _begin = _active ? 0.0 : _target;
    if (_runningUnderFlutterTest()) {
      _controller.value = 1.0;
    } else if (_active) {
      _controller.forward(from: 0.0);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _RegimenRiskMeter old) {
    super.didUpdateWidget(old);
    final verdictChanged =
        old.snapshot.score != widget.snapshot.score ||
        old.snapshot.meterActive != widget.snapshot.meterActive ||
        old.snapshot.level != widget.snapshot.level;
    final revisited = old.replayNonce != widget.replayNonce;
    if (!verdictChanged && !revisited) return;
    _end = _target;
    if (_runningUnderFlutterTest()) {
      _begin = _target;
      _controller.value = 1.0;
    } else if (_active) {
      // Always re-sweep from the lowest position toward the live verdict so the
      // movement reads as an intentional, data-driven reveal.
      _begin = 0.0;
      _controller.forward(from: 0.0);
    } else {
      _begin = _target;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final snapshot = widget.snapshot;
    final active = _active;
    final level = snapshot.level;
    final brightness = Theme.of(context).brightness;
    // Painter gets the raw tier tone (+ brightness) so its neighbour logic still
    // matches; text/labels use the brightened, dark-legible foreground tone.
    final tone = active ? snapshot.accent : context.colors.inkMute;
    final labelTone = active
        ? SeverityColors.foreground(snapshot.accent, brightness)
        : context.colors.inkMute;

    return Column(
      key: const ValueKey('home-risk-meter'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The semicircle tick gauge — the focal point. The needle sweeps up from
        // the lowest position to the continuous score with an eased motion.
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = width * 0.52;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final eased = Curves.easeOutCubic.transform(_controller.value);
                final pointer = lerpDouble(_begin, _end, eased) ?? _end;
                return RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('home-risk-gauge'),
                    size: Size(width, height),
                    painter: _RiskGaugePainter(
                      pointer: pointer,
                      accent: tone,
                      active: active,
                      brightness: brightness,
                    ),
                  ),
                );
              },
            );
          },
        ),
        SizedBox(height: responsive.s(10).clamp(8.0, 12.0)),
        // Scale labels under the arc — the active tier is emphasised in its tone.
        Row(
          children: [
            for (var i = 0; i < _zones.length; i++)
              Expanded(
                child: Text(
                  _zones[i],
                  textAlign: i == 0
                      ? TextAlign.start
                      : i == _zones.length - 1
                      ? TextAlign.end
                      : TextAlign.center,
                  style: GoogleFonts.inter(
                    color: level?.rank == i ? tone : context.colors.inkMute,
                    fontSize: responsive.font(11),
                    fontWeight: level?.rank == i
                        ? FontWeight.w800
                        : FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
        // Centred stat + caption directly beneath the meter, visually balanced.
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!active) ...[
                  Icon(
                    snapshot.dialIcon,
                    color: context.colors.inkMute,
                    size: responsive.icon(18),
                  ),
                  SizedBox(width: responsive.s(7)),
                ],
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    key: const ValueKey('risk-meter-value-style'),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    style: GoogleFonts.inter(
                      color: active ? labelTone : context.colors.inkSoft,
                      fontSize: responsive.font(18),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: -0.3,
                    ),
                    child: Text(
                      snapshot.meterValue,
                      key: const ValueKey('risk-meter-value'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.s(7).clamp(6.0, 9.0)),
            Text(
              snapshot.meterCaption,
              key: const ValueKey('risk-meter-caption'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: context.colors.inkSoft,
                fontSize: responsive.font(12.3),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Paints the regimen-risk semicircle gauge: evenly spaced radial ticks across a
/// 180° Low→High arc. Idle ticks read a calm grey. When [active], the tick at the
/// [pointer] fraction lights in [accent], the ticks within a band around it carry
/// a shade of the tone — leaning toward the lower tier's colour on the low side
/// and the higher tier's on the high side — and a slim needle points to it.
class _RiskGaugePainter extends CustomPainter {
  _RiskGaugePainter({
    required this.pointer,
    required this.accent,
    required this.active,
    required this.brightness,
  });

  /// Needle position, 0 (low end) → 1 (high end).
  final double pointer;
  final Color accent;
  final bool active;
  final Brightness brightness;

  static const _idle = Color(0xFFCAD3D1);
  static const _idleDark = Color(0xFF3B4A4E);
  static const _tickCount = 37;
  // Half-width (in arc fraction) of the coloured band around the needle.
  static const _band = 0.2;

  /// The colours the band bleeds toward on the low / high side of [accent].
  (Color low, Color high) _neighbours() {
    if (accent == _riskDangerRuby) return (_riskCautionAmber, _riskDangerRuby);
    if (accent == _riskCautionAmber) return (_riskClearTeal, _riskDangerRuby);
    return (_riskClearTeal, _riskCautionAmber); // teal / low tier
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h - h * 0.04;
    final radius = math.min(w / 2 - w * 0.05, cy - 2);
    final baseLen = radius * 0.13;
    final activeLen = radius * 0.22;
    // Brighten the tier tones for the dark gauge face; the neighbour logic above
    // still keys off the raw [accent], so only the drawn colours change.
    final drawAccent = SeverityColors.foreground(accent, brightness);
    final idle = brightness == Brightness.dark ? _idleDark : _idle;
    final (rawLow, rawHigh) = _neighbours();
    final lowColor = SeverityColors.foreground(rawLow, brightness);
    final highColor = SeverityColors.foreground(rawHigh, brightness);
    final hub = Offset(cx, cy);

    // A faint baseline arc beneath the ticks for structure.
    canvas.drawArc(
      Rect.fromCircle(center: hub, radius: radius - baseLen - radius * 0.05),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = idle.withValues(alpha: 0.45),
    );

    final activeIndex = (pointer * (_tickCount - 1)).round();

    for (var i = 0; i < _tickCount; i++) {
      final f = i / (_tickCount - 1);
      final theta = math.pi * (1 - f); // π at the left (low) → 0 at the right.
      final dirX = math.cos(theta);
      final dirY = -math.sin(theta);
      final signed = f - pointer;
      final dist = signed.abs();

      Color color;
      double len;
      double stroke;
      if (!active || dist >= _band) {
        color = idle.withValues(alpha: active ? 0.8 : 0.92);
        len = baseLen;
        stroke = 2.4;
      } else {
        final t = (dist / _band).clamp(0.0, 1.0);
        final sideColor = signed < 0 ? lowColor : highColor;
        final hued = Color.lerp(drawAccent, sideColor, t * 0.8)!;
        color = Color.lerp(hued, idle, t * t)!;
        len = lerpDouble(activeLen, baseLen, t)!;
        stroke = lerpDouble(3.4, 2.5, t)!;
      }
      if (active && i == activeIndex) {
        color = drawAccent;
        len = activeLen;
        stroke = 3.6;
      }

      final outer = Offset(cx + radius * dirX, cy + radius * dirY);
      final inner = Offset(
        cx + (radius - len) * dirX,
        cy + (radius - len) * dirY,
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    if (active) {
      final theta = math.pi * (1 - pointer);
      final dirX = math.cos(theta);
      final dirY = -math.sin(theta);
      // A soft glow at the needle's tip.
      canvas.drawCircle(
        Offset(cx + radius * dirX, cy + radius * dirY),
        5.5,
        Paint()
          ..color = drawAccent.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // The needle, hub and a white centre dot.
      final needleLen = radius - activeLen - radius * 0.06;
      canvas.drawLine(
        hub,
        Offset(cx + needleLen * dirX, cy + needleLen * dirY),
        Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = drawAccent,
      );
      canvas.drawCircle(hub, 5.5, Paint()..color = drawAccent);
      canvas.drawCircle(hub, 2.4, Paint()..color = MedGuardPalette.pureWhite);
    } else {
      canvas.drawCircle(hub, 4.0, Paint()..color = idle);
    }
  }

  @override
  bool shouldRepaint(_RiskGaugePainter old) =>
      old.pointer != pointer ||
      old.accent != accent ||
      old.active != active ||
      old.brightness != brightness;
}

class _RiskContextStrip extends StatelessWidget {
  const _RiskContextStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // When the strip names the main concern, give the concern itself a stronger
    // hierarchy: a quiet "Main concern" label with the concern bold beneath it,
    // so the primary takeaway is instantly scannable. Other states (e.g. the
    // all-clear line) keep the plain single line.
    const concernPrefix = 'Main concern:';
    final isConcern = text.startsWith(concernPrefix);

    final Widget body;
    if (isConcern) {
      final concern = text.substring(concernPrefix.length).trim();
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Main concern',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: context.colors.inkMute,
              fontSize: responsive.font(11),
              fontWeight: FontWeight.w700,
              height: 1.0,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: responsive.s(4).clamp(3.0, 5.0)),
          Text(
            concern,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: responsive.font(13.6),
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      );
    } else {
      body = Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: context.colors.inkSoft,
          fontSize: responsive.font(12.2),
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      );
    }

    // Full width so the centred text reads as centred across the whole card
    // rather than hugging the left edge of the start-aligned verdict column.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        key: const ValueKey('home-risk-context-strip'),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(13).clamp(12.0, 15.0),
          vertical: responsive.s(5).clamp(4.0, 7.0),
        ),
        child: body,
      ),
    );
  }
}

/// The single most decision-relevant output of the check: the **primary risk
/// driver**. It names the one finding that matters most (the most concerning
/// interaction, allergy, or duplicate), says what it does, gives the clinical
/// priority / next step, and shows how concentrated the risk is across the four
/// safety axes. Replaces the old "what we screened" coverage grid, which only
/// restated that four axes were checked without telling the user what to do.
class _PrimaryRiskDriver extends StatelessWidget {
  const _PrimaryRiskDriver({required this.driver});

  final _RiskDriver driver;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final tone = driver.tone;
    final chip = responsive.s(40).clamp(36.0, 44.0).toDouble();

    return Container(
      key: const ValueKey('home-risk-driver'),
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(14).clamp(12.0, 16.0)),
      decoration: BoxDecoration(
        color: context.colors.isDark
            ? context.colors.inkAlpha(0.05)
            : MedGuardPalette.pureWhite.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(responsive.radius(16)),
        border: Border.all(color: _homeFeaturedBorder(context.colors)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Eyebrow + a "risk concentration" read across the four safety axes.
          Row(
            children: [
              Expanded(
                child: Text(
                  driver.eyebrow,
                  style: GoogleFonts.inter(
                    color: context.colors.inkMute,
                    fontSize: responsive.font(10),
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(width: responsive.s(8)),
              _DriverConcentrationPill(
                flagged: driver.flaggedAxes,
                total: driver.totalAxes,
                tone: tone,
                positive: driver.positive,
              ),
            ],
          ),
          SizedBox(height: responsive.s(12).clamp(10.0, 14.0)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: chip,
                height: chip,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(responsive.radius(12)),
                ),
                child: Icon(
                  driver.icon,
                  color: tone,
                  size: responsive.icon(20),
                ),
              ),
              SizedBox(width: responsive.s(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      driver.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: context.colors.ink,
                        fontSize: responsive.font(14.5),
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(3)),
                    Text(
                      driver.kindLabel,
                      style: GoogleFonts.inter(
                        color: tone,
                        fontSize: responsive.font(11.5),
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.s(11).clamp(9.0, 13.0)),
          Text(
            driver.detail,
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: responsive.font(12.4),
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (driver.priority != null) ...[
            SizedBox(height: responsive.s(12).clamp(10.0, 14.0)),
            Container(
              padding: EdgeInsets.all(responsive.s(11).clamp(10.0, 13.0)),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(responsive.radius(12)),
                border: Border.all(color: tone.withValues(alpha: 0.16)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    color: tone,
                    size: responsive.icon(15),
                  ),
                  SizedBox(width: responsive.s(9)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Clinical priority',
                          style: GoogleFonts.inter(
                            color: tone,
                            fontSize: responsive.font(10.5),
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: responsive.s(4)),
                        Text(
                          driver.priority!,
                          style: GoogleFonts.inter(
                            color: context.colors.ink,
                            fontSize: responsive.font(12.4),
                            fontWeight: FontWeight.w600,
                            height: 1.32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The "risk concentration" pill on the driver panel: how many of the four
/// safety axes were flagged, so the user sees whether the risk is isolated to a
/// single check or spread across several.
class _DriverConcentrationPill extends StatelessWidget {
  const _DriverConcentrationPill({
    required this.flagged,
    required this.total,
    required this.tone,
    required this.positive,
  });

  final int flagged;
  final int total;
  final Color tone;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final color = positive ? _riskClearTeal : tone;
    final label = positive
        ? 'All $total checks clear'
        : '$flagged of $total checks flagged';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(9).clamp(8.0, 11.0),
        vertical: responsive.s(5).clamp(4.0, 7.0),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.check_circle_rounded : Icons.radar_rounded,
            color: color,
            size: responsive.icon(12),
          ),
          SizedBox(width: responsive.s(5)),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: responsive.font(10.5),
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatWarningCount(int count, String singular, String plural) {
  return count == 1 ? '1 $singular' : '$count $plural';
}

class _RiskSnapshot {
  const _RiskSnapshot({
    required this.headline,
    required this.meterValue,
    required this.meterCaption,
    required this.contextText,
    required this.accent,
    required this.dialIcon,
    this.level,
    this.score = 0.5,
    this.driver,
    this.meterActive = true,
    this.verdict,
  });

  /// Short status shown next to the Learn More pill. Should read on its own.
  /// Examples: "High-Risk Pair Detected", "All Clear for Now".
  final String headline;

  /// Large value under the dial. This should not repeat [headline].
  final String meterValue;

  /// The canonical verdict wording — [SafetyReport.verdictLabel] — shown as the
  /// status chip. Null for the states that have no verdict yet (loading, too
  /// few medicines, review pending), which is what hides the chip entirely
  /// rather than showing an empty one.
  final String? verdict;

  /// One-line summary under the value.
  final String meterCaption;

  /// Supporting sentence under the meter.
  final String contextText;

  /// Tier status colour: teal = low, amber = moderate, ruby = high; amber is
  /// also used for the retry/unavailable state.
  final Color accent;

  /// Icon at the centre of the dial for non-active states (loading / setup).
  final IconData dialIcon;

  /// Whether the dial has a real reading to show.
  final bool meterActive;

  /// The graded risk tier (Low / Moderate / High) the dial fills to, or null for
  /// loading / setup / unavailable states.
  final RiskLevel? level;

  /// The CONTINUOUS needle position in [0, 1] across the Low→Moderate→High arc.
  /// The categorical [level] fixes which third the needle lands in; the position
  /// within that third reflects intensity, so a barely-moderate pair and a
  /// critical-high allergy sit at visibly different points. Defaults to the arc
  /// centre for idle/non-active states (where the needle is hidden anyway).
  final double score;

  /// The single most decision-relevant finding (primary risk driver), with its
  /// effect, clinical priority, and risk concentration — drives the driver
  /// panel. Null for loading / setup / unavailable states.
  final _RiskDriver? driver;

  factory _RiskSnapshot.loading() {
    return const _RiskSnapshot(
      headline: 'Building Your\nSafety Check',
      meterValue: 'Loading',
      meterCaption: 'Just a moment',
      contextText: 'Pulling your saved medicines from the cloud.',
      accent: _riskClearTeal,
      dialIcon: Icons.hourglass_top_rounded,
      meterActive: false,
    );
  }

  factory _RiskSnapshot.analyzing() {
    return const _RiskSnapshot(
      headline: 'Running Pair\nSafety Check',
      meterValue: 'Checking',
      meterCaption: 'Reviewing pairs',
      contextText: 'Cross-checking your medicines against safety databases.',
      accent: _riskClearTeal,
      dialIcon: Icons.manage_search_rounded,
      meterActive: false,
    );
  }

  factory _RiskSnapshot.noPair(int count) {
    if (count <= 0) {
      return const _RiskSnapshot(
        headline: 'Add Your\nMedicines',
        meterValue: 'Not ready',
        meterCaption: 'Waiting for medicines',
        contextText:
            'Add two or more medicines to screen them for risky combinations.',
        accent: _riskClearTeal,
        dialIcon: Icons.add_circle_outline_rounded,
        meterActive: false,
      );
    }
    return const _RiskSnapshot(
      headline: 'Add One More\nMedicine',
      meterValue: 'Not ready',
      meterCaption: 'One more to check',
      contextText:
          'One more medicine unlocks pair, food, and duplicate checks.',
      accent: _riskClearTeal,
      dialIcon: Icons.add_circle_outline_rounded,
      meterActive: false,
    );
  }

  factory _RiskSnapshot.unavailable() {
    return const _RiskSnapshot(
      headline: 'Review\nUnavailable',
      meterValue: 'Retry',
      meterCaption: 'Open Safety',
      contextText: 'Open Safety to refresh this risk check.',
      accent: _riskCautionAmber,
      dialIcon: Icons.refresh_rounded,
      meterActive: false,
    );
  }

  /// The gate: this regimen has never been reviewed, so there is no verdict to
  /// show yet. The dial deliberately holds no reading — showing a score here
  /// would BE the premature regimen information the review exists to withhold.
  factory _RiskSnapshot.reviewPending() {
    return const _RiskSnapshot(
      headline: 'Review Your\nRegimen',
      meterValue: 'Not active',
      meterCaption: 'Review required',
      contextText:
          'Your regimen activates once you complete the interaction review. '
          'Open Interactions to run it.',
      accent: _riskCautionAmber,
      dialIcon: Icons.fact_check_rounded,
      meterActive: false,
    );
  }

  /// Three-tier reading of the live report through the rules layer. The regimen
  /// is HIGH when a high-risk pair or an allergy conflict is present; MODERATE
  /// when a moderate pair or a therapeutic duplication is present; LOW otherwise.
  factory _RiskSnapshot.fromReport(SafetyReport report) {
    final level = report.regimenRiskLevel;
    final verdict = report.verdictLabel;
    final high = report.drugInteractions
        .where((i) => i.riskLevel.isHigh)
        .toList(growable: false);
    final moderate = report.drugInteractions
        .where((i) => i.riskLevel == RiskLevel.moderate)
        .toList(growable: false);
    final minor = report.drugInteractions
        .where((i) => i.riskLevel == RiskLevel.low)
        .toList(growable: false);
    // Low-tier advisory cues: minor pairs + food notes.
    final cautionCount = minor.length + report.foodInteractions.length;

    // Continuous needle position + the single primary risk driver — computed
    // once and shared by every tier branch below.
    final score = _continuousRiskScore(report, level);
    final driver = _driverFromReport(report, level);

    if (level == RiskLevel.high) {
      // HIGH = a high-risk drug pair or an allergy conflict; lead with the pair.
      final String headline;
      final String value;
      final String context;
      if (high.isNotEmpty) {
        final top = high.first;
        headline = high.length == 1
            ? 'High-Risk Pair Detected'
            : 'High-Risk Pairs Detected';
        value = _formatWarningCount(
          high.length,
          'high-risk pair',
          'high-risk pairs',
        );
        context = 'Main concern: ${top.drugAName} + ${top.drugBName}';
      } else {
        final hit = report.allergyHits.first;
        headline = report.allergyHits.length == 1
            ? 'Allergy Conflict Found'
            : 'Allergy Conflicts Found';
        value = _formatWarningCount(
          report.allergyHits.length,
          'allergy conflict',
          'allergy conflicts',
        );
        context = 'Main concern: ${hit.drugName} vs ${hit.allergyLabel}';
      }
      return _RiskSnapshot(
        headline: headline,
        meterValue: value,
        meterCaption: 'Review before the next dose',
        contextText: context,
        accent: _riskDangerRuby,
        dialIcon: Icons.priority_high_rounded,
        level: RiskLevel.high,
        score: score,
        driver: driver,
        verdict: verdict,
      );
    }

    if (level == RiskLevel.moderate) {
      // MODERATE = a moderate drug pair and/or a therapeutic duplication; lead
      // with the pair when present, otherwise the duplication.
      final String headline;
      final String value;
      final String context;
      if (moderate.isNotEmpty) {
        final top = moderate.first;
        headline = moderate.length == 1
            ? 'Moderate-Risk Pair Found'
            : 'Moderate-Risk Pairs Found';
        value = _formatWarningCount(
          moderate.length,
          'moderate pair',
          'moderate pairs',
        );
        context = 'Main concern: ${top.drugAName} + ${top.drugBName}';
      } else {
        final dup = report.duplicateTherapies.first;
        headline = report.duplicateTherapies.length == 1
            ? 'Duplicate Therapy Found'
            : 'Duplicate Therapies Found';
        value = _formatWarningCount(
          report.duplicateTherapies.length,
          'duplicate',
          'duplicates',
        );
        context =
            'Main concern: ${dup.drugAName} + ${dup.drugBName} '
            '(${dup.category})';
      }
      return _RiskSnapshot(
        headline: headline,
        meterValue: value,
        meterCaption: 'Use with care — worth monitoring',
        contextText: context,
        accent: _riskCautionAmber,
        dialIcon: Icons.warning_amber_rounded,
        level: RiskLevel.moderate,
        score: score,
        driver: driver,
        verdict: verdict,
      );
    }

    if (cautionCount > 0) {
      return _RiskSnapshot(
        headline: 'No High-Risk Findings',
        meterValue: 'Low risk',
        meterCaption: _formatWarningCount(
          cautionCount,
          'minor cue to review',
          'minor cues to review',
        ),
        contextText: 'Nothing serious — review the listed cue when convenient.',
        accent: _riskClearTeal,
        dialIcon: Icons.verified_rounded,
        level: RiskLevel.low,
        score: score,
        driver: driver,
        verdict: verdict,
      );
    }
    return _RiskSnapshot(
      headline: 'All Clear for Now',
      // Must match [SafetyReport.verdictLabel] exactly. This branch is the
      // "nothing found at all" case, which the report calls "All clear"; the
      // meter used to call it "Low risk", so a regimen with no findings
      // whatsoever was described two different ways on two screens.
      meterValue: 'All clear',
      meterCaption: 'Drugs, food, duplicates & allergies checked',
      contextText: 'No flagged concern among your saved medicines.',
      accent: _riskClearTeal,
      dialIcon: Icons.verified_rounded,
      level: RiskLevel.low,
      score: score,
      driver: driver,
      verdict: verdict,
    );
  }
}

/// The single most decision-relevant finding surfaced beneath the meter — what
/// it is, what it does, the clinical next step, and how concentrated the risk is.
class _RiskDriver {
  const _RiskDriver({
    required this.eyebrow,
    required this.icon,
    required this.kindLabel,
    required this.title,
    required this.detail,
    required this.tone,
    required this.flaggedAxes,
    required this.totalAxes,
    this.priority,
    this.positive = false,
  });

  /// Section eyebrow — "PRIMARY RISK DRIVER" when there's a real driver, or
  /// "SAFETY SUMMARY" for an all-clear regimen.
  final String eyebrow;
  final IconData icon;

  /// Short kind label — "High-risk interaction", "Allergy conflict", etc.
  final String kindLabel;

  /// The finding itself — usually "Drug A + Drug B".
  final String title;

  /// Plain-language description of what the finding does.
  final String detail;

  /// The single clinical next step, or null for an all-clear regimen.
  final String? priority;
  final Color tone;

  /// How many of the [totalAxes] safety axes were flagged — the risk
  /// concentration shown on the panel's pill.
  final int flaggedAxes;
  final int totalAxes;

  /// Positive / reassuring styling (an all-clear regimen rather than a driver).
  final bool positive;
}

/// Maps a live report to a CONTINUOUS 0→1 position on the Low→Moderate→High arc.
/// The categorical tier ([SafetyReport.regimenRiskLevel]) fixes which third the
/// needle lands in; the intensity within that third reflects how strong the
/// finding is, so a barely-moderate pair and a critical-high allergy sit visibly
/// apart — without inventing a falsely precise number. Each band is held a small
/// margin inside its third so the position always reads unambiguously in-tier.
double _continuousRiskScore(SafetyReport report, RiskLevel level) {
  const lowBand = (0.05, 0.30);
  const moderateBand = (0.37, 0.63);
  const highBand = (0.70, 0.96);

  double inBand((double, double) band, double t) =>
      band.$1 + (band.$2 - band.$1) * t.clamp(0.0, 1.0);

  switch (level) {
    case RiskLevel.high:
      final hasContraindicated = report.drugInteractions.any(
        (i) => i.severityLevel == Severity.contraindicated,
      );
      final highCount = report.drugInteractions
          .where((i) => i.riskLevel.isHigh)
          .length;
      var t = 0.30;
      if (hasContraindicated) t += 0.42; // a contraindicated pair is the worst
      if (report.allergyHits.isNotEmpty) {
        t += 0.34; // allergy conflict is severe
      }
      if (highCount > 1) {
        t += 0.10 * (highCount - 1); // multiple high pairs pile up
      }
      return inBand(highBand, t);
    case RiskLevel.moderate:
      final moderateCount = report.drugInteractions
          .where((i) => i.riskLevel == RiskLevel.moderate)
          .length;
      var t = 0.0;
      if (moderateCount > 0) {
        t += 0.45 + 0.10 * (moderateCount - 1); // a real moderate pair leads
      }
      if (report.hasDuplication) {
        t += 0.18 * report.duplicateTherapies.length;
      }
      t += 0.05 * report.foodInteractions.length; // borderline nudge
      return inBand(moderateBand, t);
    case RiskLevel.low:
      final cues =
          report.drugInteractions
              .where((i) => i.riskLevel == RiskLevel.low)
              .length +
          report.foodInteractions.length;
      final t = cues == 0 ? 0.0 : 0.35 + 0.18 * (cues - 1);
      return inBand(lowBand, t);
  }
}

/// Builds the primary risk driver: the single most concerning finding in the
/// regimen, with its effect, the clinical next step, and the risk concentration.
_RiskDriver _driverFromReport(SafetyReport report, RiskLevel level) {
  final factors = report.consideredFactors;
  final flagged = factors.where((f) => f.triggered).length;
  final total = factors.length;

  String? effectOf(InteractionResult i) {
    final e = i.effect?.trim();
    return (e != null && e.isNotEmpty) ? e : null;
  }

  switch (level) {
    case RiskLevel.high:
      final high = report.drugInteractions
          .where((i) => i.riskLevel.isHigh)
          .toList(growable: false);
      if (high.isNotEmpty) {
        final top = high.first;
        final contra = top.severityLevel == Severity.contraindicated;
        return _RiskDriver(
          eyebrow: 'PRIMARY RISK DRIVER',
          icon: Icons.sync_problem_rounded,
          kindLabel: contra ? 'Contraindicated pair' : 'High-risk interaction',
          title: '${top.drugAName} + ${top.drugBName}',
          detail:
              effectOf(top) ??
              'These two can interact dangerously when taken together.',
          priority:
              'Avoid this combination until a clinician or pharmacist confirms it is safe.',
          tone: _riskDangerRuby,
          flaggedAxes: flagged,
          totalAxes: total,
        );
      }
      final hit = report.allergyHits.first;
      return _RiskDriver(
        eyebrow: 'PRIMARY RISK DRIVER',
        icon: Icons.coronavirus_rounded,
        kindLabel: 'Allergy conflict',
        title: '${hit.drugName} vs ${hit.allergyLabel}',
        detail: hit.summary,
        priority:
            'Do not take ${hit.drugName} — it conflicts with a recorded allergy.',
        tone: _riskDangerRuby,
        flaggedAxes: flagged,
        totalAxes: total,
      );
    case RiskLevel.moderate:
      final moderate = report.drugInteractions
          .where((i) => i.riskLevel == RiskLevel.moderate)
          .toList(growable: false);
      if (moderate.isNotEmpty) {
        final top = moderate.first;
        return _RiskDriver(
          eyebrow: 'PRIMARY RISK DRIVER',
          icon: Icons.sync_problem_rounded,
          kindLabel: 'Moderate interaction',
          title: '${top.drugAName} + ${top.drugBName}',
          detail:
              effectOf(top) ??
              'These two can interact — worth monitoring when taken together.',
          priority:
              'Use together with care and watch for new or stronger side effects.',
          tone: _riskCautionAmber,
          flaggedAxes: flagged,
          totalAxes: total,
        );
      }
      final dup = report.duplicateTherapies.first;
      return _RiskDriver(
        eyebrow: 'PRIMARY RISK DRIVER',
        icon: Icons.layers_rounded,
        kindLabel: 'Duplicate therapy',
        title: '${dup.drugAName} + ${dup.drugBName}',
        detail:
            'Both are ${dup.category} — taking them together can add up to a higher combined dose.',
        priority:
            'Avoid doubling up on the same class unless a clinician has advised it.',
        tone: _riskCautionAmber,
        flaggedAxes: flagged,
        totalAxes: total,
      );
    case RiskLevel.low:
      final clear = flagged == 0;
      return _RiskDriver(
        eyebrow: 'SAFETY SUMMARY',
        icon: Icons.verified_rounded,
        kindLabel: 'No risk drivers',
        title: clear ? 'All safety checks passed' : 'No serious findings',
        detail: clear
            ? 'No interaction, duplicate, allergy, or food conflict was found across your saved medicines.'
            : 'Only minor cues were found — nothing that raises your overall regimen risk.',
        tone: _riskClearTeal,
        flaggedAxes: flagged,
        totalAxes: total,
        positive: true,
      );
  }
}
