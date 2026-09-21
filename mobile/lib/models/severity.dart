/// Clinical severity levels used across the interaction data and UI.
///
/// The wire/database representation is a lowercase string (as stored in
/// DrugBank). This enum gives us type-safety and a canonical ordering
/// for sorting and risk aggregation.
///
/// ─ Ordering ─────────────────────────────────────────────────────────
/// Higher [rank] = more clinically severe. When sorting interaction
/// results for display, sort by rank DESCENDING so contraindicated
/// results surface first.
enum Severity {
  minor('minor', 1),
  moderate('moderate', 2),
  major('major', 3),
  contraindicated('contraindicated', 4);

  const Severity(this.wireName, this.rank);

  /// Canonical string used in the SQLite `severity` column.
  final String wireName;

  /// Monotonic severity rank. 1 = minor, 4 = contraindicated.
  final int rank;

  /// The three-tier [RiskLevel] this catalogued severity maps to. This is the
  /// canonical classification the whole app speaks in (Low / Moderate / High):
  /// minor → low, moderate → moderate, major + contraindicated → high. The four
  /// wire levels remain as the richer storage format of the reference DB.
  RiskLevel get riskLevel => switch (this) {
    Severity.minor => RiskLevel.low,
    Severity.moderate => RiskLevel.moderate,
    Severity.major => RiskLevel.high,
    Severity.contraindicated => RiskLevel.high,
  };

  /// Whether this pair sits in the app's HIGH-risk tier (major or
  /// contraindicated). Convenience over `riskLevel == RiskLevel.high`.
  bool get isHighRisk => riskLevel == RiskLevel.high;

  /// Parses a severity string from the database. Unknown values fall
  /// back to [Severity.minor] to avoid hiding a warning.
  static Severity fromString(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    for (final s in Severity.values) {
      if (s.wireName == v) return s;
    }
    return Severity.minor;
  }
}

/// The three-tier risk classification surfaced across the entire app:
/// LOW, MODERATE, HIGH. This is the canonical presentation grouping derived
/// from the richer four-level [Severity] stored in the reference database, and
/// the same three tiers the deployed ML model predicts (classes 0 / 1 / 2).
///
/// Mapping (locked): minor → low, moderate → moderate,
/// major + contraindicated → high. The HIGH tier is the most serious verdict,
/// so allergy / duplicate escalation and critical alerts target it, while
/// MODERATE is a real, distinct middle tier.
enum RiskLevel {
  low('low', 0),
  moderate('moderate', 1),
  high('high', 2);

  const RiskLevel(this.wireName, this.rank);

  /// Canonical lowercase string — matches the model/backend `risk_level`.
  final String wireName;

  /// Monotonic tier rank: 0 = low … 2 = high. Higher = more severe.
  final int rank;

  /// The HIGH tier (major / contraindicated) — the app's most serious verdict.
  bool get isHigh => this == RiskLevel.high;

  /// Title-case display label: "Low" / "Moderate" / "High". The single source
  /// of truth for tier wording across the UI and generated reports.
  String get label => switch (this) {
    RiskLevel.low => 'Low',
    RiskLevel.moderate => 'Moderate',
    RiskLevel.high => 'High',
  };

  /// Parses a tier string ("low" / "moderate" / "high"). Unknown values fall
  /// back to [RiskLevel.low].
  static RiskLevel fromString(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    for (final level in RiskLevel.values) {
      if (level.wireName == v) return level;
    }
    return RiskLevel.low;
  }

  /// Maps a model class index (0 / 1 / 2) to a tier. Out-of-range falls back to
  /// [RiskLevel.low].
  static RiskLevel fromClassIndex(int index) {
    return switch (index) {
      2 => RiskLevel.high,
      1 => RiskLevel.moderate,
      _ => RiskLevel.low,
    };
  }
}
