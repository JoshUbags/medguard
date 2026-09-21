import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../models/drug.dart';
import 'database_service.dart';

/// Order **must** match `feature_columns.json` produced by
/// `ml_pipeline.src.features.build_features`. 22 structural / mechanistic
/// features + 5 drug-level risk features = 27, computed on-device from the
/// bundled SQLite DB so the TFLite model sees the same inputs it was trained on.
const interactionFeatureColumns = <String>[
  'atc_overlap_1',
  'atc_overlap_3',
  'atc_overlap_4',
  'atc_overlap_5',
  'atc_missing_either',
  'shared_cyp_count',
  'inhibitor_substrate_count',
  'inducer_substrate_count',
  'both_substrates',
  'inhibitor_substrate',
  'inducer_substrate',
  'category_overlap',
  'drug_type_match',
  'half_life_ratio',
  'half_life_missing',
  'both_qt_prolong',
  'both_serotonergic',
  'both_cns_depressant',
  'both_nephrotoxic',
  'bleeding_risk_combo',
  'nti_either',
  'nti_both',
  'drug_risk_a',
  'drug_risk_b',
  'drug_risk_prod',
  'drug_risk_max',
  'drug_risk_min',
];

/// Builds the 27-feature vector for a drug pair, byte-for-byte compatible with
/// the Python training pipeline. Returns null when either drug isn't found.
class InteractionFeatureBuilder {
  InteractionFeatureBuilder({DatabaseService? database})
    : _db = database ?? DatabaseService.instance;

  final DatabaseService _db;

  static const _riskAsset = 'assets/ml/drug_risk_lookup.json';
  static const _enzymeAsset = 'assets/ml/enzyme_index.json';
  static const _pdAsset = 'assets/ml/pd_class_meta.json';
  static const _ntiAsset = 'assets/ml/nti_list.json';

  Map<String, double> _drugRisk = const {};
  double _globalRisk = 0.0;
  Map<String, int> _enzymeBit = const {};
  List<String> _pdGroups = const [];
  Map<String, List<String>> _pdPrefixes = const {};
  Map<String, List<String>> _pdKeywords = const {};
  Set<String> _nti = const {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final risk =
          jsonDecode(await rootBundle.loadString(_riskAsset))
              as Map<String, dynamic>;
      _globalRisk =
          ((risk['global_high_rate'] ?? risk['global_dangerous_rate']) as num?)
              ?.toDouble() ??
          0.0;
      _drugRisk = ((risk['drug_risk'] as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      _drugRisk = const {};
      _globalRisk = 0.0;
    }
    try {
      final e =
          jsonDecode(await rootBundle.loadString(_enzymeAsset))
              as Map<String, dynamic>;
      _enzymeBit = e.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _enzymeBit = const {};
    }
    try {
      final pd =
          jsonDecode(await rootBundle.loadString(_pdAsset))
              as Map<String, dynamic>;
      _pdGroups = (pd['groups'] as List).cast<String>();
      _pdPrefixes = (pd['atc_prefixes'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as List).cast<String>()),
      );
      _pdKeywords = (pd['name_keywords'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as List).cast<String>()),
      );
    } catch (_) {
      _pdGroups = const [];
    }
    try {
      _nti = (jsonDecode(await rootBundle.loadString(_ntiAsset)) as List)
          .cast<String>()
          .toSet();
    } catch (_) {
      _nti = const {};
    }
    _loaded = true;
  }

  static int _popcount(int x) {
    var v = x;
    var c = 0;
    while (v != 0) {
      c += v & 1;
      v >>= 1;
    }
    return c;
  }

  int _pdMask(Drug d) {
    final codes = <String>[];
    final primary = d.atcCode ?? '';
    if (primary.isNotEmpty) codes.add(primary);
    final all = d.allAtcCodes ?? '';
    if (all.isNotEmpty) {
      codes.addAll(all.split(RegExp(r'[|,;\s]+')).where((s) => s.isNotEmpty));
    }
    final name = d.name.toLowerCase();
    var mask = 0;
    for (var gi = 0; gi < _pdGroups.length; gi++) {
      final g = _pdGroups[gi];
      var hit = (_pdPrefixes[g] ?? const [])
          .any((p) => codes.any((c) => c.startsWith(p)));
      if (!hit && _pdKeywords.containsKey(g)) {
        hit = _pdKeywords[g]!.any((k) => name.contains(k));
      }
      if (hit) mask |= (1 << gi);
    }
    return mask;
  }

  Future<List<double>?> buildFeatures(int drugAId, int drugBId) async {
    final drugA = await _db.getDrugById(drugAId);
    final drugB = await _db.getDrugById(drugBId);
    if (drugA == null || drugB == null) return null;
    await _ensureLoaded();

    // ATC overlap + missingness
    final atcA = drugA.atcCode ?? '';
    final atcB = drugB.atcCode ?? '';
    double overlap(int n) =>
        (atcA.length >= n &&
            atcB.length >= n &&
            atcA.substring(0, n) == atcB.substring(0, n))
        ? 1.0
        : 0.0;
    final atcMissing = (atcA.isEmpty || atcB.isEmpty) ? 1.0 : 0.0;

    // CYP/UGT enzyme cascades (bitmask over the trained enzyme index)
    final enzA = await _db.getMetabolicEnzymes([drugAId]);
    final enzB = await _db.getMetabolicEnzymes([drugBId]);
    var subA = 0, inhA = 0, indA = 0, subB = 0, inhB = 0, indB = 0;
    for (final r in enzA) {
      final bitIndex = _enzymeBit[r.enzymeName];
      if (bitIndex == null) continue;
      final bit = 1 << bitIndex;
      if (r.actions.contains('substrate')) subA |= bit;
      if (r.actions.contains('inhibitor')) inhA |= bit;
      if (r.actions.contains('inducer')) indA |= bit;
    }
    for (final r in enzB) {
      final bitIndex = _enzymeBit[r.enzymeName];
      if (bitIndex == null) continue;
      final bit = 1 << bitIndex;
      if (r.actions.contains('substrate')) subB |= bit;
      if (r.actions.contains('inhibitor')) inhB |= bit;
      if (r.actions.contains('inducer')) indB |= bit;
    }
    final sharedCyp = _popcount(subA & subB);
    final inhSub = _popcount(inhA & subB) + _popcount(inhB & subA);
    final indSub = _popcount(indA & subB) + _popcount(indB & subA);

    // Category overlap (full therapeutic-category intersection)
    final catsA = (await _db.getDrugCategories(drugAId)).toSet();
    final catsB = (await _db.getDrugCategories(drugBId)).toSet();
    final categoryOverlap = catsA.intersection(catsB).length.toDouble();

    // Drug-type match
    final typeA = drugA.drugType ?? '';
    final typeB = drugB.drugType ?? '';
    final drugTypeMatch = (typeA.isNotEmpty && typeA == typeB) ? 1.0 : 0.0;

    // Half-life log-ratio + missingness
    final hlA = _parseHalfLife(drugA.halfLife);
    final hlB = _parseHalfLife(drugB.halfLife);
    var halfLifeRatio = 0.0;
    var halfLifeMissing = 1.0;
    if (hlA != null && hlB != null && hlA > 0 && hlB > 0) {
      final mx = hlA > hlB ? hlA : hlB;
      final mn = hlA < hlB ? hlA : hlB;
      halfLifeRatio = math.log(mx / mn);
      halfLifeMissing = 0.0;
    }

    // Pharmacodynamic additive-class pairs
    final mA = _pdMask(drugA);
    final mB = _pdMask(drugB);
    int idx(String g) => _pdGroups.indexOf(g);
    double both(String g) {
      final i = idx(g);
      if (i < 0) return 0.0;
      return (((mA >> i) & 1) == 1 && ((mB >> i) & 1) == 1) ? 1.0 : 0.0;
    }

    int inGroup(int mask, String g) {
      final i = idx(g);
      return i < 0 ? 0 : ((mask >> i) & 1);
    }

    final bleedA = inGroup(mA, 'anticoagulant') +
        inGroup(mA, 'antiplatelet') +
        inGroup(mA, 'nsaid');
    final bleedB = inGroup(mB, 'anticoagulant') +
        inGroup(mB, 'antiplatelet') +
        inGroup(mB, 'nsaid');
    final bleeding = (bleedA >= 1 && bleedB >= 1) ? 1.0 : 0.0;

    // Narrow therapeutic index
    final nameA = drugA.name.toLowerCase();
    final nameB = drugB.name.toLowerCase();
    final ntiA = _nti.any((k) => nameA.contains(k)) ? 1 : 0;
    final ntiB = _nti.any((k) => nameB.contains(k)) ? 1 : 0;

    // Drug-level risk features
    final riskA = _drugRisk[drugA.drugbankId] ?? _globalRisk;
    final riskB = _drugRisk[drugB.drugbankId] ?? _globalRisk;
    final riskMax = riskA > riskB ? riskA : riskB;
    final riskMin = riskA < riskB ? riskA : riskB;

    return [
      overlap(1),
      overlap(3),
      overlap(4),
      overlap(5),
      atcMissing,
      sharedCyp.toDouble(),
      inhSub.toDouble(),
      indSub.toDouble(),
      sharedCyp > 0 ? 1.0 : 0.0,
      inhSub > 0 ? 1.0 : 0.0,
      indSub > 0 ? 1.0 : 0.0,
      categoryOverlap,
      drugTypeMatch,
      halfLifeRatio,
      halfLifeMissing,
      both('qt_prolong'),
      both('serotonergic'),
      both('cns_depressant'),
      both('nephrotoxic'),
      bleeding,
      (ntiA | ntiB).toDouble(),
      (ntiA & ntiB).toDouble(),
      riskA,
      riskB,
      riskA * riskB,
      riskMax,
      riskMin,
    ];
  }

  /// Mirrors `_half_life_hours` in the Python pipeline: parse a single value or
  /// a low-high range, average it, and normalise minutes/days to hours.
  double? _parseHalfLife(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final text = raw.toLowerCase();
    final m = RegExp(r'(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?')
        .firstMatch(text);
    if (m == null) return null;
    final low = double.parse(m.group(1)!);
    final high = m.group(2) != null ? double.parse(m.group(2)!) : low;
    final avg = (low + high) / 2;
    if (text.contains('min')) return avg / 60;
    if (text.contains('day')) return avg * 24;
    return avg;
  }
}
