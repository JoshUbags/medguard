import 'package:flutter/material.dart';

class MedGuardPalette {
  MedGuardPalette._();

  static const Color teal = Color(0xFF016359);
  static const Color tealDeep = Color(0xFF003F39);
  static const Color tealLight = Color(0xFF0C7A70);
  static const Color tealFaint = Color(0xFFD1E8E5);

  static const Color ruby = Color(0xFFFF4C4F);
  static const Color rubyDeep = Color(0xFFD93639);

  // Near-white app background: a barely-there cool tint keeps white cards,
  // borders, and shadows legible while the canvas itself reads as white.
  static const Color scaffold = Color(0xFFFAFCFC);
  static const Color white = Color(0xFFFFFFFF);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color surfaceTint = Color(0xFFF2F7F7);

  static const Color ink = Color(0xFF152428);
  static const Color inkSoft = Color(0xFF33464B);
  static const Color inkMute = Color(0xFF6F7D81);

  static Color whiteAlpha(double a) => pureWhite.withValues(alpha: a);
  static Color tealAlpha(double a) => teal.withValues(alpha: a);
  static Color inkAlpha(double a) => ink.withValues(alpha: a);
  static Color blackAlpha(double a) => Colors.black.withValues(alpha: a);

  static const LinearGradient tealSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealLight, teal, tealDeep],
    stops: [0.0, 0.55, 1.0],
  );

  static const Color emerald = teal;
  static const Color emeraldDeep = tealDeep;
  static const Color emeraldLight = tealLight;
  static const LinearGradient emeraldSheen = tealSheen;
}
