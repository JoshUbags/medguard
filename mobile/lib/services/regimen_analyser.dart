import '../models/regimen_analysis.dart';
import '../models/safety_report.dart';
import '../models/severity.dart';
import '../models/user_medication.dart';

/// Pure analyser that treats the entire medication list as a single
/// pharmacological system. Combines the pairwise [SafetyReport] with the
/// bundled CYP450 metabolism data to derive a composite risk score, a banded
/// label, and a list of human-readable contributors.
class RegimenAnalyser {
  RegimenAnalyser._();

  /// CYP450 enzymes tracked by the cascade detector, mapped to their short
  /// names ('CYP3A4', 'CYP2D6', …) used in the UI summary.
  static const _trackedEnzymes = <String, String>{
    'Cytochrome P450 3A4': 'CYP3A4',
    'Cytochrome P450 3A5': 'CYP3A5',
    'Cytochrome P450 2D6': 'CYP2D6',
    'Cytochrome P450 2C9': 'CYP2C9',
    'Cytochrome P450 2C19': 'CYP2C19',
    'Cytochrome P450 2C8': 'CYP2C8',
    'Cytochrome P450 1A2': 'CYP1A2',
    'Cytochrome P450 2B6': 'CYP2B6',
  };

  static RegimenAnalysis analyze({
    required List<UserMedication> medications,
    required SafetyReport report,
    required List<DrugEnzymeRecord> enzymeRecords,
  }) {
    if (medications.isEmpty) {
      return RegimenAnalysis.empty;
    }

    final cascades = _detectCascades(enzymeRecords);
    final scoreBreakdown = _scoreFromReport(report);
    final cascadeScore = cascades.length * 6;
    final raw = (scoreBreakdown.total + cascadeScore).clamp(0, 100);
    final band = _bandFor(raw);
    final contributors = _buildContributors(
      report: report,
      cascades: cascades,
      breakdown: scoreBreakdown,
    );

    return RegimenAnalysis(
      medicationCount: medications.length,
      flaggedPairs: report.drugInteractions.length,
      duplicateTherapies: report.duplicateTherapies.length,
      foodInteractions: report.foodInteractions.length,
      cascades: cascades,
      cumulativeScore: raw,
      band: band,
      contributors: contributors,
    );
  }

  static _ScoreBreakdown _scoreFromReport(SafetyReport report) {
    final severityScore = report.drugInteractions.fold<int>(
      0,
      (sum, i) => sum + _severityWeight(i.severityLevel),
    );
    // openfda_coreport_count isn't surfaced on InteractionResult yet — once
    // it threads through the model it would add a co-report term here.
    const coReportScore = 0;
    final duplicateScore = report.duplicateTherapies.length * 4;
    final foodScore = report.foodInteractions.length;
    return _ScoreBreakdown(
      severity: severityScore,
      coReport: coReportScore,
      duplicate: duplicateScore,
      food: foodScore,
    );
  }

  static int _severityWeight(Severity severity) {
    return switch (severity) {
      Severity.contraindicated => 30,
      Severity.major => 18,
      Severity.moderate => 8,
      Severity.minor => 2,
    };
  }

  static RegimenRiskBand _bandFor(int score) {
    if (score >= 60) return RegimenRiskBand.critical;
    if (score >= 35) return RegimenRiskBand.elevated;
    // A single moderate-risk interaction weighs 8 (see [_severityWeight]), so the
    // watch floor sits at 8 — never higher. A Moderate finding is a meaningful
    // concern and must clear the "Calm" band, so it is never bucketed alongside
    // a lone Minor interaction (weight 2), which correctly stays Calm.
    if (score >= 8) return RegimenRiskBand.watch;
    return RegimenRiskBand.calm;
  }

  static List<CypCascade> _detectCascades(List<DrugEnzymeRecord> records) {
    final grouped = <String, List<DrugEnzymeRecord>>{};
    for (final record in records) {
      if (!_trackedEnzymes.containsKey(record.enzymeName)) continue;
      grouped.putIfAbsent(record.enzymeName, () => []).add(record);
    }

    final cascades = <CypCascade>[];
    grouped.forEach((enzyme, rows) {
      final inhibitors = <String>{};
      final substrates = <String>{};
      final inducers = <String>{};
      for (final row in rows) {
        if (row.isInhibitor) inhibitors.add(row.drugName);
        if (row.isInducer) inducers.add(row.drugName);
        if (row.isSubstrate) substrates.add(row.drugName);
      }
      // Don't flag a single drug that is both modulator and substrate — that
      // is just normal autoinduction, not a regimen-level cascade.
      final modulators = {...inhibitors, ...inducers}..removeAll(substrates);
      final affectedSubstrates = {...substrates}..removeAll(modulators);
      final cascade = CypCascade(
        enzymeName: enzyme,
        shortName: _trackedEnzymes[enzyme] ?? enzyme,
        inhibitors: inhibitors.intersection(modulators).toList()..sort(),
        substrates: affectedSubstrates.toList()..sort(),
        inducers: inducers.intersection(modulators).toList()..sort(),
      );
      if (cascade.isCascade) cascades.add(cascade);
    });

    cascades.sort((a, b) => a.shortName.compareTo(b.shortName));
    return cascades;
  }

  static List<String> _buildContributors({
    required SafetyReport report,
    required List<CypCascade> cascades,
    required _ScoreBreakdown breakdown,
  }) {
    final lines = <String>[];
    // Three-tier roll-up for display: count interactions per risk tier so the
    // contributor list speaks the same Low / Moderate / High language as the
    // rest of the app.
    final tierCounts = <RiskLevel, int>{};
    for (final interaction in report.drugInteractions) {
      final tier = interaction.riskLevel;
      tierCounts[tier] = (tierCounts[tier] ?? 0) + 1;
    }
    for (final tier in [RiskLevel.high, RiskLevel.moderate, RiskLevel.low]) {
      final count = tierCounts[tier] ?? 0;
      if (count > 0) {
        lines.add(
          '$count ${tier.label.toLowerCase()}-risk '
          'interaction${count == 1 ? '' : 's'}',
        );
      }
    }
    if (report.duplicateTherapies.isNotEmpty) {
      final n = report.duplicateTherapies.length;
      lines.add('$n duplicate therap${n == 1 ? 'y' : 'ies'}');
    }
    for (final cascade in cascades) {
      lines.add('${cascade.shortName} metabolism cascade');
    }
    if (report.foodInteractions.isNotEmpty) {
      lines.add('${report.foodInteractions.length} food advisories');
    }
    return lines;
  }
}

class _ScoreBreakdown {
  const _ScoreBreakdown({
    required this.severity,
    required this.coReport,
    required this.duplicate,
    required this.food,
  });

  final int severity;
  final int coReport;
  final int duplicate;
  final int food;

  int get total => severity + coReport + duplicate + food;
}

