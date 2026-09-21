// Part of `home_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../home_screen.dart';

// ── Status Alerts — MedGuard's live safety monitor ───────────────────────────
// Built as a bespoke monitoring board rather than a generic alert list: a
// tone-keyed status masthead with a gauge emblem carries the live verdict, a
// slim coverage meter shows how much of the safety net is active, and the
// account signals read as a calm status list. Colour is earned — ruby for a real
// severity, amber for a setup gap, teal for a positive all-clear.
const _alertOk = MedGuardPalette.teal;
const _alertCaution = Color(0xFFB45309);

class _HomeAlertsSection extends StatelessWidget {
  const _HomeAlertsSection({
    required this.profileComplete,
    required this.allergyCount,
    required this.allergyLoaded,
    required this.scheduleCount,
    required this.scheduleLoaded,
    required this.onCompleteProfile,
    required this.onManageAllergies,
    required this.onSetReminder,
    required this.onOpenNotifications,
  });

  final bool profileComplete;
  final int allergyCount;
  final bool allergyLoaded;
  final int scheduleCount;
  final bool scheduleLoaded;
  final VoidCallback onCompleteProfile;
  final VoidCallback onManageAllergies;
  final VoidCallback onSetReminder;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    // Coverage states share the same semantics as the rows below: a gap only
    // counts once its data has actually loaded (optimistic while loading).
    final profileActive = profileComplete;
    final allergiesActive = !allergyLoaded || allergyCount > 0;
    final remindersActive = !scheduleLoaded || scheduleCount > 0;
    final attention = [
      if (!profileComplete) 1,
      if (allergyLoaded && allergyCount == 0) 1,
      if (scheduleLoaded && scheduleCount == 0) 1,
    ].length;

    // The readiness ring reports a real, actionable metric: how many of the
    // three account protections (profile, allergies, reminders) are active.
    final states = [profileActive, allergiesActive, remindersActive];
    final covered = states.where((active) => active).length;
    // The first settled gap drives the panel's "set up next" prompt + action.
    String? nextGapLabel;
    VoidCallback? nextGapOnFix;
    if (!profileComplete) {
      nextGapLabel = 'name';
      nextGapOnFix = onCompleteProfile;
    } else if (allergyLoaded && allergyCount == 0) {
      nextGapLabel = 'allergies';
      nextGapOnFix = onManageAllergies;
    } else if (scheduleLoaded && scheduleCount == 0) {
      nextGapLabel = 'reminders';
      nextGapOnFix = onSetReminder;
    }

    // Each account signal reads as a status line — a tone pip, a title, a live
    // detail, and an inline action only when something genuinely needs doing.
    final signals = <Widget>[
      _AlertSignalRow(
        active: profileActive,
        icon: Icons.badge_rounded,
        title: 'Profile',
        detail: profileComplete
            ? 'Personalises every check'
            : 'Add your name to personalise',
        actionLabel: profileComplete ? null : 'Complete',
        onTap: profileComplete ? null : onCompleteProfile,
      ),
      _AlertSignalRow(
        active: allergiesActive,
        icon: Icons.coronavirus_rounded,
        title: 'Allergies',
        detail: !allergyLoaded
            ? 'Loading'
            : allergyCount == 0
            ? 'Add to screen every medicine'
            : allergyCount == 1
            ? '1 allergy screened'
            : '$allergyCount allergies screened',
        actionLabel: allergyLoaded && allergyCount == 0 ? 'Add' : null,
        onTap: allergyLoaded && allergyCount == 0 ? onManageAllergies : null,
      ),
      _AlertSignalRow(
        active: remindersActive,
        icon: Icons.alarm_rounded,
        title: 'Reminders',
        detail: !scheduleLoaded
            ? 'Loading'
            : scheduleCount == 0
            ? 'Set one to never miss a dose'
            : scheduleCount == 1
            ? '1 dose reminder active'
            : '$scheduleCount dose reminders active',
        actionLabel: scheduleLoaded && scheduleCount == 0 ? 'Set up' : null,
        onTap: scheduleLoaded && scheduleCount == 0 ? onSetReminder : null,
      ),
      _AlertSignalRow(
        active: true,
        linkOnly: true,
        icon: Icons.notifications_rounded,
        title: 'Notifications',
        detail: 'Reminders & messages',
        onTap: onOpenNotifications,
      ),
    ];

    return Column(
      key: const ValueKey('home-alerts-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(
          title: 'Status Alerts',
          action: attention == 0 ? 'All clear' : '$attention to check',
          subtitle: 'Live safety status and account coverage.',
        ),
        SizedBox(height: responsive.s(14).clamp(12.0, 16.0).toDouble()),
        Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(responsive.radius(24)),
            border: Border.all(color: context.colors.border),
            boxShadow: _homeCardShadow(responsive),
          ),
          padding: EdgeInsets.all(responsive.s(16).clamp(14.0, 18.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Safety readiness — a real, actionable coverage metric ──
              _SafetyReadinessPanel(
                covered: covered,
                total: states.length,
                nextGapLabel: nextGapLabel,
                onFix: nextGapOnFix,
              ),
              SizedBox(height: responsive.s(14).clamp(12.0, 16.0)),
              Divider(
                height: 1,
                thickness: 1,
                color: context.colors.inkAlpha(0.06),
              ),
              SizedBox(height: responsive.s(2)),
              // ── Account signal list ──
              for (var i = 0; i < signals.length; i++) ...[
                signals[i],
                if (i != signals.length - 1)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: responsive.s(2)),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: context.colors.inkAlpha(0.06),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The Live Safety focal point: a circular **Safety Readiness** indicator that
/// reports a real, actionable metric — how many of the account's safety
/// protections (profile, allergies, reminders) are active — paired with a plain
/// verdict and the single next step to raise it. Replaces the old decorative
/// gauge whose arc measured nothing.
class _SafetyReadinessPanel extends StatelessWidget {
  const _SafetyReadinessPanel({
    required this.covered,
    required this.total,
    required this.nextGapLabel,
    required this.onFix,
  });

  final int covered;
  final int total;

  /// The next protection to set up (e.g. "allergies"), or null when fully
  /// covered. Drives the supporting line + the inline action.
  final String? nextGapLabel;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final full = covered >= total && total > 0;
    final fraction = total == 0 ? 0.0 : covered / total;
    final tone = full ? _alertOk : _alertCaution;
    final remaining = total - covered;
    final headline = full
        ? 'Fully protected'
        : covered == 0
        ? 'Not protected yet'
        : remaining == 1
        ? 'One step left'
        : '$remaining steps left';
    final detail = full
        ? 'Every safeguard is on.'
        : nextGapLabel != null
        ? 'Add your $nextGapLabel.'
        : 'Finish quick setup.';

    return Container(
      key: const ValueKey('home-safety-readiness'),
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(14).clamp(12.0, 16.0)),
      decoration: BoxDecoration(
        gradient: _homeFeaturedGradient(context.colors),
        borderRadius: BorderRadius.circular(responsive.radius(18)),
        border: Border.all(color: _homeFeaturedBorder(context.colors)),
        boxShadow: [
          BoxShadow(
            color: context.colors.accentAlpha(0.045),
            blurRadius: responsive.s(16),
            offset: Offset(0, responsive.s(6)),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ReadinessRing(fraction: fraction, tone: tone),
          SizedBox(width: responsive.s(14).clamp(12.0, 16.0)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAFETY READINESS',
                  style: GoogleFonts.inter(
                    color: tone.withValues(alpha: 0.9),
                    fontSize: responsive.font(10),
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: responsive.s(5)),
                Text(
                  headline,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: responsive.font(18),
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: responsive.s(5)),
                Text(
                  detail,
                  style: GoogleFonts.inter(
                    color: context.colors.inkSoft,
                    fontSize: responsive.font(12.4),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!full && onFix != null) ...[
            SizedBox(width: responsive.s(12)),
            _SafetyTextAction(
              label: 'Set up',
              tone: MedGuardPalette.teal,
              onTap: onFix!,
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact circular readiness gauge: a faint track with a tone arc swept to
/// [fraction] of a full circle, the active share rendered as a percentage in the
/// middle. The arc length is the metric — it grows as protections are switched
/// on. A soft tone "comet" orbits the track continuously, signalling that the
/// safety net is actively monitoring rather than sitting idle.
class _ReadinessRing extends StatefulWidget {
  const _ReadinessRing({required this.fraction, required this.tone});

  final double fraction;
  final Color tone;

  @override
  State<_ReadinessRing> createState() => _ReadinessRingState();
}

class _ReadinessRingState extends State<_ReadinessRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!_runningUnderFlutterTest()) _scan.repeat();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final size = responsive.s(56).clamp(50.0, 62.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.fraction.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => CustomPaint(
                  painter: _ReadinessRingPainter(
                    fraction: value,
                    tone: widget.tone,
                    track: context.colors.isDark
                        ? context.colors.inkAlpha(0.12)
                        : _riskInactiveTrack,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scan,
                builder: (context, _) => CustomPaint(
                  painter: _ReadinessScanPainter(
                    phase: _scan.value,
                    tone: widget.tone,
                  ),
                ),
              ),
            ),
            Text(
              '${(widget.fraction * 100).round()}%',
              style: GoogleFonts.inter(
                color: widget.tone,
                fontSize: responsive.font(15),
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the orbiting monitoring sweep over the readiness track: a soft trailing
/// arc behind a bright head, travelling once around per cycle like a radar scan.
class _ReadinessScanPainter extends CustomPainter {
  _ReadinessScanPainter({required this.phase, required this.tone});

  /// 0 → 1 around the full circle.
  final double phase;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.width * 0.10;
    final radius = (size.width - stroke) / 2;
    final head = phase * 2 * math.pi - math.pi / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Soft trailing comet tail behind the head.
    canvas.drawArc(
      rect,
      head - 0.85,
      0.85,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..strokeCap = StrokeCap.round
        ..color = tone.withValues(alpha: 0.16),
    );

    // Bright head with a soft glow, like an active scan point.
    final pos = Offset(
      centre.dx + radius * math.cos(head),
      centre.dy + radius * math.sin(head),
    );
    canvas.drawCircle(
      pos,
      stroke * 0.85,
      Paint()
        ..color = tone.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(pos, stroke * 0.46, Paint()..color = tone);
    canvas.drawCircle(
      pos,
      stroke * 0.20,
      Paint()..color = MedGuardPalette.pureWhite.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_ReadinessScanPainter old) =>
      old.phase != phase || old.tone != tone;
}

class _ReadinessRingPainter extends CustomPainter {
  const _ReadinessRingPainter({
    required this.fraction,
    required this.tone,
    required this.track,
  });

  final double fraction;
  final Color tone;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final stroke = size.width * 0.10;
    final radius = (size.width - stroke) / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = tone,
    );
  }

  @override
  bool shouldRepaint(_ReadinessRingPainter old) =>
      old.track != track || old.fraction != fraction || old.tone != tone;
}

/// A restrained inline text action — label + arrow in the given tone — used by
/// the masthead and the signal rows instead of a loud filled pill.
class _SafetyTextAction extends StatelessWidget {
  const _SafetyTextAction({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String label;

  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Pressable(
      onTap: onTap,
      pressScale: 0.97,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: responsive.s(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: tone,
                fontSize: responsive.font(12.8),
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            SizedBox(width: responsive.s(3)),
            Icon(
              Icons.arrow_forward_rounded,
              color: tone,
              size: responsive.icon(14),
            ),
          ],
        ),
      ),
    );
  }
}

/// One account signal as a status line: a tone pip carrying the signal's icon
/// (teal when covered, amber when a gap, neutral for a plain link), the title +
/// live detail, and a trailing affordance — an inline action, a chevron, or a
/// quiet check.
class _AlertSignalRow extends StatelessWidget {
  const _AlertSignalRow({
    required this.active,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onTap,
    this.linkOnly = false,
  });

  final bool active;
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onTap;
  final bool linkOnly;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final needsAction = actionLabel != null;
    final pip = responsive.s(38).clamp(34.0, 42.0).toDouble();
    // Tone encodes state: amber when something needs doing, neutral ink for a
    // plain link, teal when the signal is covered.
    final Color tone = needsAction
        ? _alertCaution
        : linkOnly
        ? context.colors.inkMute
        : _alertOk;

    final Widget trailing;
    if (needsAction) {
      trailing = _SafetyTextAction(
        label: actionLabel!,
        tone: MedGuardPalette.teal,
        onTap: onTap ?? () {},
      );
    } else if (linkOnly) {
      trailing = Icon(
        Icons.chevron_right_rounded,
        color: context.colors.inkMute,
        size: responsive.icon(22),
      );
    } else {
      trailing = Icon(
        Icons.check_circle_rounded,
        color: _alertOk,
        size: responsive.icon(18),
      );
    }

    final row = Padding(
      padding: EdgeInsets.symmetric(
        vertical: responsive.s(12).clamp(10.0, 14.0),
      ),
      child: Row(
        children: [
          // Tone pip — a tinted disc with the signal's icon; a setup gap also
          // carries a thin amber ring to draw the eye.
          Container(
            width: pip,
            height: pip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: needsAction
                  ? Border.all(color: tone.withValues(alpha: 0.30))
                  : null,
            ),
            child: Icon(icon, color: tone, size: responsive.icon(18)),
          ),
          SizedBox(width: responsive.s(13).clamp(11.0, 15.0)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: responsive.font(14.5),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: responsive.s(3)),
                Text(
                  detail,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                    color: context.colors.inkSoft,
                    fontSize: responsive.font(12.2),
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: responsive.s(10)),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return Pressable(onTap: onTap, pressScale: 0.99, child: row);
  }
}
