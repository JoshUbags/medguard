import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'medguard_colors.dart';
import 'medguard_palette.dart';
import 'page_transitions.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    // Every app surface uses Inter.
    final bodyTextTheme = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: MedGuardPalette.ink, displayColor: MedGuardPalette.ink);

    // Keep established weights while using the same family everywhere.
    final textTheme = bodyTextTheme.copyWith(
      displayLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.displayLarge,
        fontWeight: FontWeight.w600,
      ),
      displayMedium: GoogleFonts.inter(
        textStyle: bodyTextTheme.displayMedium,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: GoogleFonts.inter(
        textStyle: bodyTextTheme.displaySmall,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.headlineLarge,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.inter(
        textStyle: bodyTextTheme.headlineMedium,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.inter(
        textStyle: bodyTextTheme.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.titleLarge,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.04,
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: bodyTextTheme.bodyMedium,
        color: MedGuardPalette.inkSoft,
        fontSize: 13.2,
        fontWeight: FontWeight.w400,
        height: 1.46,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.labelLarge,
        fontSize: 13.2,
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: MedGuardPalette.scaffold,
      colorScheme: base.colorScheme.copyWith(
        primary: MedGuardPalette.teal,
        onPrimary: MedGuardPalette.pureWhite,
        secondary: MedGuardPalette.ruby,
        onSecondary: MedGuardPalette.pureWhite,
        surface: MedGuardPalette.scaffold,
        onSurface: MedGuardPalette.ink,
      ),
      textTheme: textTheme,
      pageTransitionsTheme: kMedGuardPageTransitions,
      extensions: const [MedGuardColors.light],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: MedGuardPalette.ink,
        elevation: 0,
        centerTitle: false,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }

  /// Material 3 dark theme. [trueBlack] swaps the scaffold for `#000000` for
  /// AMOLED screens. Severity foregrounds are nudged lighter so they still
  /// hit WCAG AA contrast on the dark surface.
  static ThemeData darkTheme({bool trueBlack = false}) {
    final base = ThemeData.dark(useMaterial3: true);

    final scaffold = trueBlack
        ? const Color(0xFF000000)
        : const Color(0xFF0E1517);
    final surface = trueBlack
        ? const Color(0xFF0A1213)
        : const Color(0xFF152024);
    const onSurface = Color(0xFFEAF2F0);
    const onSurfaceMute = Color(0xFF93A3A6);

    final bodyTextTheme = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: onSurface, displayColor: onSurface);

    final textTheme = bodyTextTheme.copyWith(
      titleLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.titleLarge,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.04,
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: bodyTextTheme.bodyMedium,
        color: onSurfaceMute,
        fontSize: 13.2,
        fontWeight: FontWeight.w400,
        height: 1.46,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: bodyTextTheme.labelLarge,
        fontSize: 13.2,
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: const Color(0xFF4FD1C5),
        onPrimary: const Color(0xFF052621),
        secondary: const Color(0xFFFF8A8C),
        onSecondary: const Color(0xFF3A0707),
        surface: surface,
        onSurface: onSurface,
      ),
      textTheme: textTheme,
      pageTransitionsTheme: kMedGuardPageTransitions,
      extensions: [MedGuardColors.dark(trueBlack: trueBlack)],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
