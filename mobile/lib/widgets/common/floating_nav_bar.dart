import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';

/// The five primary destinations. Home and Interactions sit left of the
/// animated orb, Insights and Dose to its right; the orb itself is the AI tab.
enum AppNavTab {
  home(
    label: 'Home',
    route: '/home',
    outlineIcon: Icons.grid_view_outlined,
    filledIcon: Icons.grid_view_rounded,
  ),
  interactions(
    label: 'Interaction',
    route: '/medications',
    outlineIcon: Icons.swap_horiz_rounded,
    filledIcon: Icons.swap_horiz_rounded,
  ),
  ai(
    label: 'AI',
    route: '/ai',
    outlineIcon: Icons.auto_awesome_rounded,
    filledIcon: Icons.auto_awesome_rounded,
  ),
  insights(
    label: 'Insights',
    route: '/insights',
    outlineIcon: Icons.lightbulb_outline_rounded,
    filledIcon: Icons.lightbulb_rounded,
  ),
  dose(
    label: 'Dose',
    route: '/dose',
    outlineIcon: Icons.alarm_rounded,
    filledIcon: Icons.alarm_on_rounded,
  );

  const AppNavTab({
    required this.label,
    required this.route,
    required this.outlineIcon,
    required this.filledIcon,
  });

  final String label;
  final String route;
  final IconData outlineIcon;
  final IconData filledIcon;
}

/// Space screens must reserve beneath scrolling content so the last element
/// clears the floating nav row.
const double kFloatingNavReserveHeight = 84;
const double kFloatingNavMenuReserveHeight = kFloatingNavReserveHeight;
const double kPageEndContentPadding = 2;

// Trim factor for the visible trailing space between the last content element
// and the nav — deliberately tight so pages end close to the glass.
const double _endInsetTrimFactor = 0.2;

/// Trims the trailing space a page would otherwise end with.
///
/// One constant, applied to every screen through [screenEndContentInset], which
/// is why this is a single edit rather than thirty. The device's own bottom
/// inset (the home indicator) is halved along with the rest — it is padding the
/// system already guarantees is untouchable, so reserving all of it AGAIN below
/// the last card was doubling a gap that only needed counting once.
const double _endInsetHalving = 0.68;

double floatingNavContentInset(BuildContext context) {
  final responsive = MedGuardResponsive.of(context);
  final rowHeight = responsive.s(60).clamp(56.0, 66.0).toDouble();
  final bottomOffset = responsive.s(14).clamp(12.0, 18.0).toDouble();
  final extraClearance = responsive.s(6).clamp(5.0, 8.0).toDouble();

  return ((rowHeight + bottomOffset + extraClearance) * _endInsetTrimFactor +
          MediaQuery.paddingOf(context).bottom) *
      _endInsetHalving;
}

double pageEndContentInset(BuildContext context) {
  return (kPageEndContentPadding +
          math.min(MediaQuery.paddingOf(context).bottom, 8) *
              _endInsetTrimFactor) *
      _endInsetHalving;
}

double screenEndContentInset(
  BuildContext context, {
  required bool reserveFloatingNav,
}) {
  return reserveFloatingNav
      ? floatingNavContentInset(context)
      : pageEndContentInset(context);
}

/// The floating bottom navigation — full width, with NO container or defined
/// shape of its own.
///
/// The screen's own background softly blurs and fades toward the bottom edge: a
/// masked [BackdropFilter] under a translucent scaffold-toned wash that eases to
/// nothing above the icons. No capsule, no border, no outline, no seam — the
/// items simply float on the page as it dissolves beneath them.
///
/// The wash peaks well short of opaque ([_washPeak]), so the bar reads as a
/// gentle fade rather than a solid band sitting on top of the content.
///
/// Five items across the full width: four icons with their page names beneath,
/// and dead centre the AI orb, which carries no label — the orb IS the label.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.current, this.onTabSelected});

  final AppNavTab current;
  final ValueChanged<AppNavTab>? onTabSelected;

  /// Peak strength of the scaffold-toned wash, at the very bottom edge.
  ///
  /// Effectively opaque at the base. The wash used to top out at 0.94, which
  /// left content faintly ghosting through directly behind the labels — enough
  /// to make the smallest type on the screen sit on a moving background. The
  /// fade above it is what keeps the bar from reading as a solid block, so the
  /// bottom sliver can afford to be solid.
  static const double _washPeak = 1.0;

  /// The fraction of the surface, measured from the bottom, that the wash holds
  /// near full strength before it begins to let go.
  ///
  /// Kept LOW on purpose. The wash used to sit at full strength across the
  /// whole icon row and then fall away over the short strip above it, which
  /// read as a solid block with a visible edge. Holding only the bottom sliver
  /// and dissolving across everything above gives the long, even ramp that
  /// makes the bar disappear into the page.
  static const double _solidUpTo = 0.22;

  void _select(BuildContext context, AppNavTab tab) {
    if (current == tab) return;
    HapticFeedback.lightImpact();
    final handler = onTabSelected;
    if (handler != null) {
      handler(tab);
      return;
    }
    Navigator.of(context).pushReplacementNamed(tab.route);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final rowHeight = responsive.s(58).clamp(54.0, 64.0).toDouble();
    final orbSize = responsive.s(56).clamp(50.0, 62.0).toDouble();
    // A tall clear strip above the icons. The fade needs real distance to
    // dissolve — a short ramp is exactly what produces a visible edge — and the
    // raised orb's glow needs somewhere to breathe.
    final topRoom = responsive.s(76).clamp(64.0, 96.0).toDouble();
    final bottomOffset = responsive.s(10).clamp(8.0, 14.0).toDouble();
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final surfaceHeight = topRoom + rowHeight + bottomOffset + safeBottom;
    // The side margin the item row keeps clear of the screen edges.
    //
    // The row used to run almost edge to edge (a 2–8pt inset), which pushed the
    // outer two items hard against the bezel — they read as clinging to the
    // sides rather than sitting in a considered row, and on a curved-edge phone
    // the outermost labels fell onto the curve. This is enough margin to give
    // the row a visible left and right edge without pulling the four items back
    // into a cramped huddle around the orb.
    final sideInset = responsive.s(18).clamp(14.0, 26.0).toDouble();
    // The clear span held for the orb, over and above the orb's own diameter.
    // Wide enough that the two inner items are visibly separate destinations
    // rather than neighbours of the orb.
    final orbGap = responsive.s(30).clamp(24.0, 40.0).toDouble();

    // The wash: a long, evenly-ramped dissolve from the bottom edge to nothing.
    //
    // Two things keep it seamless. First, it holds full strength only across
    // the bottom [_solidUpTo] sliver and spends the whole remaining height
    // fading, so there is no block-with-an-edge. Second, it is built from many
    // small steps through a smootherstep curve, whose first AND second
    // derivatives vanish at both ends — an ordinary linear or smoothstep ramp
    // leaves a faint Mach band where the slope changes abruptly, and that band
    // is the "line where transparency changes" this is tuned to remove.
    final washColors = <Color>[];
    final washStops = <double>[];
    const washSteps = 48;
    for (var i = 0; i <= washSteps; i++) {
      final t = i / washSteps; // 0 = bottom, 1 = top
      final f = ((t - _solidUpTo) / (1 - _solidUpTo)).clamp(0.0, 1.0);
      // smootherstep: 6f^5 - 15f^4 + 10f^3
      final eased = f * f * f * (f * (f * 6 - 15) + 10);
      washColors.add(
        colors.scaffold.withValues(alpha: _washPeak * (1 - eased)),
      );
      washStops.add(t);
    }

    // The blur is masked on the SAME curve as the wash. When the two ramps
    // disagree you see the frost end before the tint does, which reads as a
    // second edge halfway up.
    final maskColors = <Color>[];
    for (var i = 0; i <= washSteps; i++) {
      final t = i / washSteps;
      final f = ((t - _solidUpTo) / (1 - _solidUpTo)).clamp(0.0, 1.0);
      final eased = f * f * f * (f * (f * 6 - 15) + 10);
      maskColors.add(Colors.black.withValues(alpha: 1 - eased));
    }

    return SizedBox(
      key: const ValueKey('bottom-nav-surface'),
      height: surfaceHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── The frost, rising from the very bottom of the screen: a high
          // blur so busy content behind dissolves, masked on the wash's own
          // curve so the two disappear together. No border, no outline. ─────
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ClipRect(
                  child: ShaderMask(
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: maskColors,
                      stops: washStops,
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── The scaffold-toned wash over the frost. ───────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('bottom-nav-backdrop'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: washColors,
                    stops: washStops,
                  ),
                ),
              ),
            ),
          ),
          // NOTE: there is deliberately NO tinted bloom behind the bar. A wide,
          // low-alpha teal radial used to sit here to "light" the centre, but on
          // the near-white canvas it read as exactly what it was — a long, faint,
          // off-white band floating above the content with no shape of its own.
          // The orb's own coloured shadow is the only light source the bar needs.

          // ── The four side items, floating directly on the fade. ───────────
          //
          // The row runs nearly edge to edge (only a hair of inset) and holds a
          // generous gap in the middle, so the two outer items sit near the
          // screen edges and the two inner ones stand well clear of the orb.
          // Bunching all four toward the centre is what made the menu read as
          // cramped.
          Positioned(
            left: sideInset,
            right: sideInset,
            bottom: bottomOffset + safeBottom,
            height: rowHeight,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Row(
                  key: const ValueKey('bottom-nav-menu'),
                  children: [
                    Expanded(
                      child: _NavItem(
                        tab: AppNavTab.home,
                        active: current == AppNavTab.home,
                        onTap: () => _select(context, AppNavTab.home),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        tab: AppNavTab.interactions,
                        active: current == AppNavTab.interactions,
                        onTap: () => _select(context, AppNavTab.interactions),
                      ),
                    ),
                    // The raised orb floats over this gap.
                    SizedBox(width: orbSize + orbGap),
                    Expanded(
                      child: _NavItem(
                        tab: AppNavTab.insights,
                        active: current == AppNavTab.insights,
                        onTap: () => _select(context, AppNavTab.insights),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        tab: AppNavTab.dose,
                        active: current == AppNavTab.dose,
                        onTap: () => _select(context, AppNavTab.dose),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── The raised AI orb, centred and lifted above the row. ──────────
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomOffset + safeBottom + (rowHeight - orbSize) / 2,
            child: Center(
              child: SiriOrb(
                key: const ValueKey('nav-ai-orb'),
                hitKey: const ValueKey('nav-hit-ai'),
                size: orbSize,
                active: current == AppNavTab.ai,
                onTap: () => _select(context, AppNavTab.ai),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One destination: an icon centred over its page name, both centred in the
/// cell the parent [Row] hands out.
///
/// Alignment is the whole job here. The icon sits in a fixed-height box that is
/// centred on both axes, the label is centred beneath it, and the pair is
/// centred as a block in the cell — so all four items share one icon baseline
/// and one label baseline no matter how wide the label is. The active item's
/// icon rests on a soft pill that wraps the glyph only, never the label.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppNavTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final isDark = colors.isDark;

    // The wash beneath is a soft fade rather than a solid pane, so both states
    // carry near-full strength — legibility cannot lean on the background here.
    // Resting items differ from the active one by weight and the pill, not by
    // being faded out.
    final activeInk = isDark ? const Color(0xFFF2F6F5) : colors.ink;
    final restingInk = isDark
        ? const Color(0xF2EAF2F0)
        : colors.ink.withValues(alpha: 0.92);
    final pillColor = isDark
        ? const Color(0x2EFFFFFF)
        : colors.ink.withValues(alpha: 0.085);
    final iconBox = responsive.s(30).clamp(28.0, 34.0).toDouble();
    // One label slot for all four items, sized from the type scale so it tracks
    // the user's text-size setting instead of being a magic number.
    final labelHeight = responsive.font(10) * 1.35;

    return Pressable(
      key: ValueKey('nav-hit-${tab.name}'),
      onTap: onTap,
      pressScale: 0.90,
      semanticLabel: tab.label,
      selected: active,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            key: ValueKey('nav-active-pill-${tab.name}'),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: iconBox,
            // The pill grows sideways around the glyph when active; the icon
            // itself stays dead centre in either state.
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(active ? 15 : 9),
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? pillColor : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Icon(
              active ? tab.filledIcon : tab.outlineIcon,
              key: ValueKey('nav-icon-${tab.name}-$active'),
              color: active ? activeInk : restingInk,
              size: responsive.icon(21),
            ),
          ),
          SizedBox(height: responsive.s(5).clamp(4.0, 7.0).toDouble()),
          // The page name, always visible beneath its icon and always on the
          // same baseline as its neighbours'.
          //
          // The fixed height is what guarantees that baseline: a [FittedBox]
          // shrinks a long or bolder label to fit, which changes the label's
          // measured height and would otherwise nudge that item's icon a pixel
          // or two off the row the other three sit on.
          SizedBox(
            height: labelHeight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: active ? activeInk : restingInk,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: responsive.font(10),
                  letterSpacing: 0.1,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The orb palette — deliberately teal-forward: four of the six hues (≈67%)
// sit in the app's teal family, with a single blue and a single rose accent
// woven through, so the orb reads as MedGuard's teal while still glowing
// iridescent.
const List<Color> _orbColors = [
  Color(0xFF10CBB6), // vivid brand teal
  Color(0xFF23D8C0), // bright cyan-teal
  Color(0xFF0BAE9E), // deeper teal
  Color(0xFF46E6CE), // light aqua-teal
  Color(0xFF3E8EF0), // blue accent
  Color(0xFFE86FA6), // rose accent
];

/// The centrepiece: a luminous, colour-filled glass orb.
///
/// Five saturated hues orbit and blend through a heavy blur into a continuous
/// watercolour that fills the whole sphere and glows, over a soft cool-tinted
/// base (never bare white). A glassy specular sheen and a rim light give it
/// dimensional depth, and a soft multi-colour bloom behind separates it from
/// the frosted nav. No label — the orb IS the label.
class SiriOrb extends StatefulWidget {
  const SiriOrb({
    super.key,
    required this.size,
    required this.active,
    required this.onTap,
    this.hitKey,
  });

  final double size;
  final bool active;
  final VoidCallback onTap;

  /// Optional key applied to the tappable surface, so a specific instance (the
  /// nav-bar orb) can be found/tapped in tests without colliding with other
  /// orbs elsewhere on screen (e.g. the large one on the AI page).
  final Key? hitKey;

  @override
  State<SiriOrb> createState() => _SiriOrbState();
}

class _SiriOrbState extends State<SiriOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _swirl;

  @override
  void initState() {
    super.initState();
    _swirl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    // Under widget tests the endless swirl would make pumpAndSettle spin
    // forever, so the orb renders its (still colourful) first frame instead.
    final underTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    if (!underTest) _swirl.repeat();
  }

  @override
  void dispose() {
    _swirl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.colors.isDark;
    return Semantics(
      button: true,
      selected: widget.active,
      label: 'MedGuard AI',
      child: Pressable(
        key: widget.hitKey,
        onTap: widget.onTap,
        pressScale: 0.88,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          scale: widget.active ? 1.08 : 1.0,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // A soft multi-colour bloom behind the orb so it glows and lifts
              // off the frosted glass. A teal halo sits under a blue and a rose
              // cast for a full iridescent glow.
              boxShadow: [
                BoxShadow(
                  color: _orbColors[0].withValues(
                    alpha: widget.active ? 0.40 : 0.28,
                  ),
                  blurRadius: 22,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: _orbColors[1].withValues(
                    alpha: widget.active ? 0.38 : 0.26,
                  ),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(-4, 8),
                ),
                BoxShadow(
                  color: _orbColors[3].withValues(
                    alpha: widget.active ? 0.30 : 0.20,
                  ),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(5, 8),
                ),
              ],
            ),
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _swirl,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.square(widget.size),
                    painter: _OrbSwirlPainter(t: _swirl.value, dark: isDark),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbSwirlPainter extends CustomPainter {
  _OrbSwirlPainter({required this.t, required this.dark});

  final double t;
  final bool dark;

  // Per-blob motion: (x-frequency, y-frequency, phase, orbit-radius fraction).
  // The x/y frequencies are INTEGERS, so each blob traces a closed Lissajous
  // curve that is exactly periodic over one cycle — at the loop wrap every blob
  // is precisely where it began, so the swirl never shows a seam or a restart.
  // Different integer pairs per blob keep the paths weaving organically rather
  // than spinning as a ring.
  static const List<(int, int, double, double)> _orbits = [
    (1, 2, 0.0, 0.40),
    (2, 1, 1.5, 0.46),
    (1, 3, 2.9, 0.38),
    (3, 2, 4.2, 0.48),
    (2, 3, 5.6, 0.42),
    (1, 1, 3.4, 0.44),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = size.center(Offset.zero);
    final r = w / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // 1) Luminous cool-tinted base — never bare white, so no white shows
    //    through where the colour is thinnest.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.2, -0.28),
          radius: 1.2,
          // A teal-tinted cool base so the sphere never washes to plain white
          // and stays in the brand family even where the colour is thinnest.
          colors: [Color(0xFFE6F7F4), Color(0xFFCDE9E4), Color(0xFFBBDDD8)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // 2) The swirling colour field — five saturated blobs orbit and blend
    //    through a heavy blur into one continuous, luminous watercolour that
    //    fills the whole sphere.
    final angle = t * 2 * math.pi;
    canvas.saveLayer(
      rect.inflate(r * 0.4),
      Paint()
        ..imageFilter = ImageFilter.blur(sigmaX: r * 0.16, sigmaY: r * 0.16),
    );
    for (var i = 0; i < _orbColors.length; i++) {
      final (fx, fy, ph, orf) = _orbits[i];
      // Integer frequencies → closed, seamless loop. The constant phase
      // offsets (ph, ph*1.3) only shift where each blob sits, never the period.
      final cx = c.dx + math.cos(angle * fx + ph) * r * orf;
      final cy = c.dy + math.sin(angle * fy + ph * 1.3) * r * orf;
      // Breathing at an integer frequency (2) stays periodic too.
      final br = r * (0.66 + 0.12 * math.sin(angle * 2 + ph));
      final centre = Offset(cx, cy);
      canvas.drawCircle(
        centre,
        br,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _orbColors[i].withValues(alpha: 0.92),
              _orbColors[i].withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: centre, radius: br)),
      );
    }
    canvas.restore();

    // 3) Centre luminosity — a soft light bloom so the core glows, kept sheer
    //    so it lifts the colour rather than washing it to white.
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
    );

    // 4) Spherical depth — a gentle cool shade toward the bottom-right rim
    //    (deepens the colour for volume; never white).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.35, 0.42),
          radius: 1.15,
          colors: [Color(0x00123A44), Color(0x2E0E2E3A)],
          stops: [0.55, 1.0],
        ).createShader(rect),
    );

    // 5) Glass gloss — a broad specular sheen plus a bright hotspot in the
    //    top-left, so the orb reads as a glossy glass ball.
    final gloss = Offset(c.dx - r * 0.3, c.dy - r * 0.4);
    canvas.drawCircle(
      gloss,
      r * 0.7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.68),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: gloss, radius: r * 0.7)),
    );
    final hotspot = Offset(c.dx - r * 0.32, c.dy - r * 0.44);
    canvas.drawCircle(
      hotspot,
      r * 0.18,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: hotspot, radius: r * 0.18)),
    );

    canvas.restore(); // undo the circle clip

    // 6) A crisp thin rim light along the top edge — the glass catch.
    canvas.drawArc(
      rect.deflate(0.7),
      math.pi * 1.15,
      math.pi * 0.72,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbSwirlPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.dark != dark;
}
