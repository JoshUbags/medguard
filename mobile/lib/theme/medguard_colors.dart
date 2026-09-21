import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'medguard_palette.dart';

/// Theme-resolved semantic colours.
///
/// [MedGuardPalette] holds the brand's *static* light values and stays the
/// single source of truth for brand fills (the teal a primary button is painted
/// with is teal in light AND dark). [MedGuardColors] is the brightness-aware
/// layer for everything that must FLIP between light and dark: page/canvas
/// backgrounds, card and sheet surfaces, hairline borders, and the three text
/// inks. Read it through [BuildContextColors.colors] (i.e. `context.colors`).
///
/// IMPORTANT: the [light] values are byte-identical to the historical
/// [MedGuardPalette] constants, so migrating a call site from
/// `MedGuardPalette.ink` to `context.colors.ink` is a no-op in light mode — it
/// only adds the dark behaviour. That invariant is what makes the migration
/// safe to do incrementally without ever regressing the shipping light theme.
@immutable
class MedGuardColors extends ThemeExtension<MedGuardColors> {
  const MedGuardColors({
    required this.scaffold,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.ink,
    required this.inkSoft,
    required this.inkMute,
    required this.accent,
    required this.danger,
    required this.warning,
    required this.shadow,
    required this.brightness,
  });

  /// Page / canvas background (was `MedGuardPalette.scaffold`).
  final Color scaffold;

  /// Raised surfaces — cards, sheets, dialogs (was `pureWhite` used as a fill).
  final Color surface;

  /// A subtly tinted surface for nested fills (was `surfaceTint`).
  final Color surfaceAlt;

  /// Hairline dividers / card outlines (was `0xFFE1EEEC` / `tealFaint`).
  final Color border;

  /// Primary text + icons (was `ink`).
  final Color ink;

  /// Secondary text (was `inkSoft`).
  final Color inkSoft;

  /// Tertiary / muted text (was `inkMute`).
  final Color inkMute;

  /// Teal used as a FOREGROUND on a surface — links, icons, emphasis text.
  /// Brightens in dark mode so it keeps WCAG contrast (was `teal` as text).
  final Color accent;

  /// Ruby used as a FOREGROUND (danger text / icons). Softens in dark.
  final Color danger;

  /// Amber used as a FOREGROUND / caution accent (the "moderate" tier, alerts).
  /// Brightens in dark so it clears WCAG on the dark surface.
  final Color warning;

  /// Elevation shadow colour. Kept black, but a touch stronger in dark where
  /// soft shadows otherwise vanish against the dark canvas.
  final Color shadow;

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Teal foreground at [a] opacity (chip tints, faint fills on a surface).
  Color accentAlpha(double a) => accent.withValues(alpha: a);

  /// Danger foreground at [a] opacity (ruby chip tints / faint fills).
  Color dangerAlpha(double a) => danger.withValues(alpha: a);

  /// Caution foreground at [a] opacity (amber chip tints / faint fills).
  Color warningAlpha(double a) => warning.withValues(alpha: a);

  /// Primary ink at [a] opacity (faint borders / overlays that track the text).
  Color inkAlpha(double a) => ink.withValues(alpha: a);

  static const MedGuardColors light = MedGuardColors(
    scaffold: MedGuardPalette.scaffold, // #FAFCFC
    surface: MedGuardPalette.pureWhite, // #FFFFFF
    surfaceAlt: MedGuardPalette.surfaceTint, // #F2F7F7
    border: Color(0xFFE1EEEC),
    ink: MedGuardPalette.ink, // #152428
    inkSoft: MedGuardPalette.inkSoft, // #33464B
    inkMute: MedGuardPalette.inkMute, // #6F7D81
    accent: MedGuardPalette.teal, // #016359
    danger: MedGuardPalette.ruby, // #FF4C4F
    warning: Color(0xFFB45309), // amber, AA on white (matches moderate tier)
    shadow: Color(0xFF000000),
    brightness: Brightness.light,
  );

  /// Standard dark surfaces. [trueBlack] swaps the canvas + nearest surfaces for
  /// near-black so OLED screens save power and read deeper.
  static MedGuardColors dark({bool trueBlack = false}) {
    return MedGuardColors(
      scaffold: trueBlack ? const Color(0xFF000000) : const Color(0xFF0E1517),
      surface: trueBlack ? const Color(0xFF0A1213) : const Color(0xFF152024),
      surfaceAlt: trueBlack ? const Color(0xFF121C1E) : const Color(0xFF1C2A2E),
      border: const Color(0x24FFFFFF), // white @ ~14%
      ink: const Color(0xFFEAF2F0),
      inkSoft: const Color(0xFFC2CFCD),
      inkMute: const Color(0xFF93A3A6),
      accent: const Color(0xFF4FD1C5),
      danger: const Color(0xFFFF8A8C),
      warning: const Color(0xFFFBBF24), // bright amber, ~10.6:1 on the surface
      shadow: const Color(0xFF000000),
      brightness: Brightness.dark,
    );
  }

  @override
  MedGuardColors copyWith({
    Color? scaffold,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? ink,
    Color? inkSoft,
    Color? inkMute,
    Color? accent,
    Color? danger,
    Color? warning,
    Color? shadow,
    Brightness? brightness,
  }) {
    return MedGuardColors(
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkMute: inkMute ?? this.inkMute,
      accent: accent ?? this.accent,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      shadow: shadow ?? this.shadow,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  MedGuardColors lerp(ThemeExtension<MedGuardColors>? other, double t) {
    if (other is! MedGuardColors) return this;
    return MedGuardColors(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkMute: Color.lerp(inkMute, other.inkMute, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

/// `context.colors` — the ergonomic accessor used everywhere instead of reading
/// the theme extension by hand. Falls back to [MedGuardColors.light] if the
/// extension somehow isn't registered, so a call site can never crash.
extension BuildContextColors on BuildContext {
  MedGuardColors get colors =>
      Theme.of(this).extension<MedGuardColors>() ?? MedGuardColors.light;
}

/// A status/navigation-bar overlay style that tracks the active theme: the
/// canvas-matching nav bar plus icon brightness that stays legible in both
/// modes. Screens previously each hard-coded a `const` light-only style, which
/// left the status-bar icons invisible (dark-on-dark) under the dark theme.
SystemUiOverlayStyle medGuardSystemUi(MedGuardColors colors) {
  final dark = colors.isDark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    // TRANSPARENT, not the scaffold colour. On a three-button Android device
    // the system bar is painted OVER the app, so an opaque colour here sliced
    // the bottom off anything the app draws near the edge — most visibly the
    // AI orb's glow, which stopped dead in a straight line across the nav
    // buttons. Transparent lets the app's own pixels run to the true bottom of
    // the screen and the glow fade out naturally behind the buttons.
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    // Stops Android from helpfully re-adding a translucent scrim behind the
    // buttons, which would undo the above.
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}
