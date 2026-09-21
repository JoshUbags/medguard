import 'dart:math' as math;

import 'package:flutter/material.dart';

class MedGuardResponsive {
  const MedGuardResponsive._({
    required this.size,
    required this.textScale,
    required this.scale,
    required this.isCompactPhone,
    required this.isTablet,
  });

  final Size size;
  final double textScale;
  final double scale;
  final bool isCompactPhone;
  final bool isTablet;

  static MedGuardResponsive of(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final isTablet = shortest >= 600;
    // Big phones (430–480 dp shortest side) must genuinely scale UP — the old
    // 1.08 ceiling made everything read tiny on large Androids. Layout tracks
    // the screen almost linearly; text follows below with its own curve.
    final baseScale = (shortest / 390).clamp(0.88, isTablet ? 1.30 : 1.18);

    return MedGuardResponsive._(
      size: media.size,
      textScale: media.textScaler.scale(1),
      scale: baseScale.toDouble(),
      isCompactPhone: media.size.height < 620 || shortest < 350,
      isTablet: isTablet,
    );
  }

  double s(double value) {
    return (value * scale).toDouble();
  }

  double font(double value) {
    // Text grows with the screen at 70% of the layout rate — enough that a
    // 6.8-inch phone reads comfortably larger, damped enough that headlines
    // never balloon. (System accessibility text scaling stacks on top via
    // MediaQuery as usual.)
    final responsive = value * (1 + ((scale - 1) * 0.7));
    return responsive.clamp(value * 0.92, value * (isTablet ? 1.28 : 1.18));
  }

  double radius(double value) {
    return (value * scale).clamp(value * 0.92, value * 1.22).toDouble();
  }

  double icon(double value) {
    return (value * scale).clamp(value * 0.90, value * 1.20).toDouble();
  }

  double get pageX {
    if (isTablet) return math.min(size.width * 0.07, 48);
    return (size.width * 0.052).clamp(18.0, 24.0).toDouble();
  }

  double get contentMaxWidth => isTablet ? 620 : double.infinity;

  EdgeInsets pagePadding({double top = 0, double bottom = 0}) {
    return EdgeInsets.fromLTRB(pageX, s(top), pageX, s(bottom));
  }

  Widget constrain(Widget child) {
    if (!isTablet) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        child: child,
      ),
    );
  }
}
