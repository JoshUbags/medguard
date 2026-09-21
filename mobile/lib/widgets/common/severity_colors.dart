import 'package:flutter/material.dart';

import '../../models/severity.dart';
import '../../theme/medguard_palette.dart';

/// Canonical colour, icon, and label system for the app's three risk tiers
/// (Low / Moderate / High). Colours come from the app palette so every surface
/// reads consistently. The four-level [Severity] helpers delegate through
/// [Severity.riskLevel], so older call sites keep working unchanged.
class SeverityColors {
  const SeverityColors._();

  /// High risk — app ruby (the boundary previously labelled "dangerous").
  static const high = MedGuardPalette.rubyDeep;

  /// Moderate risk — a warm amber reserved for the middle tier.
  static const moderate = Color(0xFFB45309);

  /// Low risk — app teal.
  static const low = MedGuardPalette.teal;

  /// Neutral grey for an indeterminate / not-yet-computed tier.
  static const unknown = Color(0xFF64748B);

  static Color colorForLevel(RiskLevel level) => switch (level) {
    RiskLevel.high => high,
    RiskLevel.moderate => moderate,
    RiskLevel.low => low,
  };

  // ── Dark-mode foreground tones ───────────────────────────────────────────
  // The base tiers are tuned for FILLS (a badge with white text) and for light
  // surfaces. Used as a FOREGROUND on the dark surface — a gauge needle, tier
  // text/icon, a thin accent — low (teal, ~2.5:1) and moderate fall below WCAG,
  // so brighten them. Ruby is already legible but softened for comfort.
  static const _highDark = Color(0xFFFF8A8C);
  static const _moderateDark = Color(0xFFFBBF24);
  static const _lowDark = Color(0xFF4FD1C5);
  static const _unknownDark = Color(0xFF94A3B8);

  /// Foreground-safe tier colour for [brightness]. Light is unchanged.
  static Color foregroundForLevel(RiskLevel level, Brightness brightness) {
    if (brightness == Brightness.light) return colorForLevel(level);
    return switch (level) {
      RiskLevel.high => _highDark,
      RiskLevel.moderate => _moderateDark,
      RiskLevel.low => _lowDark,
    };
  }

  /// Brightens an already-resolved tier [tier] for dark foregrounds; passes any
  /// non-tier colour through untouched. Light returns [tier] unchanged.
  static Color foreground(Color tier, Brightness brightness) {
    if (brightness == Brightness.light) return tier;
    if (tier == high) return _highDark;
    if (tier == moderate) return _moderateDark;
    if (tier == low) return _lowDark;
    if (tier == unknown) return _unknownDark;
    return tier;
  }

  static IconData iconForLevel(RiskLevel level) => switch (level) {
    RiskLevel.high => Icons.priority_high_rounded,
    RiskLevel.moderate => Icons.warning_amber_rounded,
    RiskLevel.low => Icons.check_circle_rounded,
  };

  /// Short title-case tier label for inline use: "Low" / "Moderate" / "High".
  /// Delegates to [RiskLevel.label] so wording has a single source of truth.
  static String labelForLevel(RiskLevel level) => level.label;

  /// One-line, plain-language meaning of each tier.
  static String meaningForLevel(RiskLevel level) => switch (level) {
    RiskLevel.high => 'Serious — avoid or get advice before combining.',
    RiskLevel.moderate => 'Use with care — worth monitoring.',
    RiskLevel.low => 'No significant interaction expected.',
  };

  // ── Severity-typed convenience (delegates through riskLevel) ──
  static Color colorFor(Severity severity) => colorForLevel(severity.riskLevel);

  static IconData iconFor(Severity severity) =>
      iconForLevel(severity.riskLevel);
}
