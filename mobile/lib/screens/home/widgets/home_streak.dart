// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

// ── Login-consistency strip ─────────────────────────────────────────────────

/// How many days the consistency window spans — a standard rolling week.
const int _streakWindowDays = 7;

/// A real login-consistency card over a standardised rolling 7-day window that
/// always ends on today (today is consistently the last cell). Active days come
/// straight from [LoginActivityService] — never back-filled, so the streak is
/// honest.
class _LoginStreakSection extends StatelessWidget {
  const _LoginStreakSection({required this.loginDays, required this.now});

  final Set<String> loginDays;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final raw = now();
    final today = DateTime(raw.year, raw.month, raw.day);
    final streak = LoginActivityService.streakFrom(loginDays, now: today);

    final windowStart = _windowStart(today);
    final days = [
      for (var i = 0; i < _streakWindowDays; i++)
        windowStart.add(Duration(days: i)),
    ];
    final activeThisWeek = days
        .where((d) => loginDays.contains(LoginActivityService.dayKey(d)))
        .length;

    final headline = streak >= 2 ? '$streak-day streak' : 'Welcome aboard';
    final caption = streak >= 2
        ? 'Checking in keeps your safety reads current'
        : 'Your check-in streak starts here';

    final iconSize = responsive.s(42).clamp(38.0, 46.0).toDouble();

    return Container(
      key: const ValueKey('home-login-streak-section'),
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(17).clamp(15.0, 19.0).toDouble()),
      decoration: BoxDecoration(
        // A whisper of warm amber bleeds in from the top-left so the card feels
        // tied to the flame mark. In dark it's a subtly warm-lifted surface.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.colors.isDark
              ? [context.colors.surfaceAlt, context.colors.surface]
              : const [Color(0xFFFFF8F1), MedGuardPalette.pureWhite],
          stops: const [0.0, 0.6],
        ),
        borderRadius: BorderRadius.circular(responsive.radius(24)),
        border: Border.all(
          color: context.colors.isDark
              ? context.colors.border
              : const Color(0xFFF0E4D6),
        ),
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.inkAlpha(0.04),
            blurRadius: responsive.s(16),
            offset: Offset(0, responsive.s(6)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The flame mark, kept — now seated in a soft amber halo so it
              // reads as the card's anchor.
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFE9D2), Color(0xFFFEF1E4)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _homeWarnFor(context).withValues(alpha: 0.18),
                  ),
                ),
                alignment: Alignment.center,
                // A live, flickering flame — sways and pulses like a real fire
                // rather than a flat glyph.
                child: _AnimatedFlame(size: responsive.icon(27)),
              ),
              SizedBox(width: responsive.s(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      style: GoogleFonts.inter(
                        color: context.colors.ink,
                        fontSize: responsive.font(16.5),
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: responsive.s(5)),
                    Text(
                      caption,
                      maxLines: 2,
                      style: GoogleFonts.inter(
                        color: context.colors.inkMute,
                        fontSize: responsive.font(11.5),
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.s(12)),
              // The right-hand stat, reimagined as a circular progress ring:
              // active days fill an amber arc around the live count.
              _StreakRing(active: activeThisWeek, total: _streakWindowDays),
            ],
          ),
          SizedBox(height: responsive.s(15).clamp(13.0, 17.0).toDouble()),
          Container(
            height: 1,
            color: context.colors.isDark
                ? context.colors.border
                : const Color(0xFFF0E4D6),
          ),
          SizedBox(height: responsive.s(13).clamp(11.0, 15.0).toDouble()),
          _LoginWeekStrip(days: days, loginDays: loginDays, today: today),
        ],
      ),
    );
  }

  /// First day of the standardised rolling [_streakWindowDays]-day window:
  /// always the six days before today, so today is consistently the last cell.
  DateTime _windowStart(DateTime today) {
    return today.subtract(const Duration(days: _streakWindowDays - 1));
  }
}

/// A small, self-contained flame that flickers and sways like real fire —
/// stacked orange → amber → gold tongues over a warm glow, with a couple of
/// embers drifting up. The streak strip's anchor mark. Under widget tests the
/// flicker is frozen to a single frame so `pumpAndSettle` never hangs.
class _AnimatedFlame extends StatefulWidget {
  const _AnimatedFlame({required this.size});

  final double size;

  @override
  State<_AnimatedFlame> createState() => _AnimatedFlameState();
}

class _AnimatedFlameState extends State<_AnimatedFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // A calmer, longer cycle reads as a confident, steady flame rather than a
      // frantic flicker.
      duration: const Duration(milliseconds: 2200),
    );
    if (!_runningUnderFlutterTest()) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // A gentle breath scales the whole flame so it feels alive without
            // any jump — anchored at the base so it grows upward like real fire.
            final phase = _controller.value * 2 * math.pi;
            final breathe = 1 + 0.035 * math.sin(phase);
            return Transform.scale(
              scale: breathe,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(painter: _FlamePainter(t: _controller.value)),
            );
          },
        ),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.t});

  /// Animation phase in [0, 1).
  final double t;

  static const _outerLow = Color(0xFFFB923C); // warm orange
  static const _outerHigh = Color(0xFFEA580C); // deep ember orange
  static const _midLow = Color(0xFFFCD34D); // gold
  static const _midHigh = Color(0xFFF59E0B); // amber
  static const _core = Color(0xFFFFF6DA); // near-white hot core

  /// A single flame tongue: a teardrop with a slightly concave base and a
  /// pointed, swayable tip.
  Path _flame(
    double cx,
    double baseY,
    double width,
    double height,
    double tipDx,
    double bulge,
  ) {
    final tipX = cx + tipDx;
    final tipY = baseY - height;
    final hw = width / 2;
    return Path()
      ..moveTo(cx - hw, baseY)
      ..cubicTo(
        cx - hw * (1 + bulge),
        baseY - height * 0.46,
        tipX - width * 0.24,
        tipY + height * 0.30,
        tipX,
        tipY,
      )
      ..cubicTo(
        tipX + width * 0.24,
        tipY + height * 0.30,
        cx + hw * (1 + bulge),
        baseY - height * 0.46,
        cx + hw,
        baseY,
      )
      ..quadraticBezierTo(cx, baseY - height * 0.18, cx - hw, baseY)
      ..close();
  }

  Paint _verticalGradient(
    double cx,
    double baseY,
    double height,
    Color low,
    Color high,
  ) {
    final rect = Rect.fromLTRB(cx - height, baseY - height, cx + height, baseY);
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [low, high],
      ).createShader(rect);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final baseY = h * 0.90;
    final phase = t * 2 * math.pi;
    final sway = math.sin(phase);
    final sway2 = math.sin(phase * 1.7 + 0.9);
    final flick = (math.sin(phase * 2.3) + math.sin(phase * 3.9 + 1.3)) * 0.5;

    // Soft warm glow behind the flame.
    canvas.drawCircle(
      Offset(cx, baseY - h * 0.32),
      w * 0.44 * (0.9 + 0.12 * flick),
      Paint()
        ..color = _outerHigh.withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.11),
    );

    // Outer tongue.
    final oh = h * 0.76 * (0.95 + 0.07 * flick);
    canvas.drawPath(
      _flame(cx, baseY, w * 0.64, oh, w * 0.07 * sway, 0.06 + 0.03 * sway2),
      _verticalGradient(cx, baseY, oh, _outerLow, _outerHigh),
    );

    // Middle tongue, swaying slightly against the outer one.
    final mh = h * 0.55 * (0.94 + 0.09 * flick);
    canvas.drawPath(
      _flame(cx, baseY - h * 0.02, w * 0.42, mh, -w * 0.05 * sway, 0.04),
      _verticalGradient(cx, baseY, mh, _midLow, _midHigh),
    );

    // Hot core.
    final ch = h * 0.32 * (0.9 + 0.14 * flick);
    canvas.drawPath(
      _flame(cx, baseY - h * 0.06, w * 0.20, ch, w * 0.03 * sway2, 0.02),
      Paint()..color = _core.withValues(alpha: 0.96),
    );

    // Two embers drifting up and fading out.
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final ex =
          cx +
          w * 0.10 * math.sin(p * 6.2 + i) +
          (i == 0 ? -w * 0.06 : w * 0.06);
      final ey = baseY - h * 0.30 - p * h * 0.55;
      final alpha = ((1 - p) * 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(ex, ey),
        w * 0.035 * (1 - p * 0.5),
        Paint()..color = _midLow.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t;
}

/// The rolling 7-day check-in row, revealed with a gentle staggered entrance:
/// each day cell fades and rises into place in sequence, so the week reads as
/// "filling in" rather than appearing all at once. The motion runs once on first
/// mount (frozen flat under widget tests) and is deliberately subtle.
class _LoginWeekStrip extends StatefulWidget {
  const _LoginWeekStrip({
    required this.days,
    required this.loginDays,
    required this.today,
  });

  final List<DateTime> days;
  final Set<String> loginDays;
  final DateTime today;

  @override
  State<_LoginWeekStrip> createState() => _LoginWeekStripState();
}

class _LoginWeekStripState extends State<_LoginWeekStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    if (_runningUnderFlutterTest()) {
      _controller.value = 1.0;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.days.length;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              _staggered(
                i,
                count,
                _LoginDayCell(
                  letter: _calendarDayLetters[widget.days[i].weekday % 7],
                  active: widget.loginDays.contains(
                    LoginActivityService.dayKey(widget.days[i]),
                  ),
                  isToday: widget.days[i] == widget.today,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Fades + lifts each cell into place, offset so the cells cascade left→right.
  Widget _staggered(int index, int count, Widget child) {
    final start = (index / count) * 0.5;
    final progress = ((_controller.value - start) / 0.5).clamp(0.0, 1.0);
    final t = Curves.easeOutCubic.transform(progress);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 9), child: child),
    );
  }
}

class _LoginDayCell extends StatelessWidget {
  const _LoginDayCell({
    required this.letter,
    required this.active,
    required this.isToday,
  });

  final String letter;
  final bool active;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final dot = responsive.s(27).clamp(24.0, 31.0).toDouble();

    final Color bg;
    final Border? border;
    Widget? glyph;
    if (isToday) {
      // Today: the app's colour filled in, with a white tick — the standout cell
      // that always sits last in the week.
      bg = MedGuardPalette.teal;
      border = null;
      glyph = Icon(
        Icons.check_rounded,
        color: MedGuardPalette.pureWhite,
        size: responsive.icon(15),
      );
    } else if (active) {
      // A previous logged-in day: a teal outline over a light tint with a teal
      // tick — clearly checked, but quieter than today.
      bg = context.colors.accentAlpha(0.10);
      border = Border.all(color: context.colors.accent, width: 2);
      glyph = Icon(
        Icons.check_rounded,
        color: context.colors.accent,
        size: responsive.icon(15),
      );
    } else {
      // A missed day: a calm, empty grey dot.
      bg = context.colors.inkAlpha(0.05);
      border = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          letter,
          style: GoogleFonts.inter(
            color: isToday ? context.colors.accent : context.colors.inkMute,
            fontSize: responsive.font(10.5),
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w700,
            height: 1.0,
          ),
        ),
        SizedBox(height: responsive.s(7)),
        Container(
          width: dot,
          height: dot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border,
          ),
          child: glyph,
        ),
      ],
    );
  }
}

/// The login card's right-hand stat as a circular progress ring: an amber arc
/// fills one segment per active day around a live count, tying the figure to the
/// flame mark. A faint track shows the remaining days in the window.
class _StreakRing extends StatelessWidget {
  const _StreakRing({required this.active, required this.total});

  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final size = responsive.s(52).clamp(48.0, 58.0).toDouble();
    final fraction = total == 0 ? 0.0 : (active / total).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      // On first mount the amber arc sweeps up to the active fraction while the
      // count ticks up to its value, so the stat lands rather than simply
      // appearing — a small, premium touch tied to the flame mark.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 920),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          final count = (active * t).round();
          return CustomPaint(
            painter: _StreakRingPainter(
              fraction: fraction * t,
              active: active > 0,
              warn: _homeWarnFor(context),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: GoogleFonts.inter(
                      color: active > 0
                          ? _homeWarnFor(context)
                          : context.colors.inkMute,
                      fontSize: responsive.font(18),
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: responsive.s(1)),
                  Text(
                    'of $total',
                    style: GoogleFonts.inter(
                      color: context.colors.inkMute,
                      fontSize: responsive.font(8.5),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StreakRingPainter extends CustomPainter {
  const _StreakRingPainter({
    required this.fraction,
    required this.active,
    required this.warn,
  });

  final double fraction;
  final bool active;
  final Color warn;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.width * 0.11;
    final radius = (size.width - stroke) / 2;

    // Faint track for the full window.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = warn.withValues(alpha: 0.16),
    );

    if (!active) return;

    // Amber arc covering the active fraction of the window.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = warn,
    );
  }

  @override
  bool shouldRepaint(covariant _StreakRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.active != active ||
      oldDelegate.warn != warn;
}
