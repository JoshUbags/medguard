import 'dart:async';

import '../models/interaction_result.dart';
import '../models/safety_report.dart';
import '../models/severity.dart';
import '../utils/lru_cache.dart';
import 'allergy_checker.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'interaction_feature_builder.dart';
import 'ml_prediction_service.dart';
import 'user_data_service.dart';

/// Runs the app's medication safety checks and aggregates the result.
///
/// SafetyReports are cached by sorted drug-id signature: the same regimen
/// (regardless of insertion order) only hits the database once until the user
/// changes their medication list, at which point [invalidateCache] clears the
/// entries. Allergy hits are computed live when [userId] + [drugs] are
/// supplied so the report can flag class-level conflicts on top of the
/// pairwise interaction checks.
class InteractionChecker {
  InteractionChecker({
    DatabaseService? database,
    AllergyChecker? allergies,
    MlPredictionService? predictor,
    InteractionFeatureBuilder? featureBuilder,
    ApiService? api,
  }) : _db = database ?? DatabaseService.instance,
       _allergies = allergies ?? AllergyChecker(database: database),
       _predictor = predictor ?? MlPredictionService.instance,
       _featureBuilder =
           featureBuilder ?? InteractionFeatureBuilder(database: database),
       _api = api ?? ApiService.instance;

  final DatabaseService _db;
  final AllergyChecker _allergies;
  final MlPredictionService _predictor;
  final InteractionFeatureBuilder _featureBuilder;
  final ApiService _api;

  static final LruCache<String, SafetyReport> _cache = LruCache(capacity: 32);

  static String _key(
    List<int> drugIds, {
    String? userId,
    bool recordHistory = true,
  }) {
    final sorted = [...drugIds]..sort();
    final base = userId == null ? sorted.join(',') : '$userId|${sorted.join(',')}';
    // A non-recording run (e.g. the home regimen gauge) is cached separately
    // so it never short-circuits the recording run's audit-log write, while
    // still computing the identical report from the identical inputs.
    return recordHistory ? base : '$base|norec';
  }

  /// Clears the cache. Called when the user's medication list changes so the
  /// next analysis sees the updated set.
  static void invalidateCache() => _cache.clear();

  /// Runs the full safety analysis.
  ///
  /// Pass [userId] + [drugs] so the ML fallback predictor and allergy checks
  /// run — both the home regimen gauge and the Safety Report screen must pass
  /// these so they compute an identical report and never disagree on the
  /// "dangerous" verdict. Set [recordHistory] to false for passive/background
  /// runs (the home dashboard) so only an explicit check writes to the log.
  static Future<SafetyReport> analyze(
    List<int> drugIds, {
    String? userId,
    List<({int id, String name})>? drugs,
    bool recordHistory = true,
  }) {
    return InteractionChecker().run(
      drugIds,
      userId: userId,
      drugs: drugs,
      recordHistory: recordHistory,
    );
  }

  Future<SafetyReport> run(
    List<int> drugIds, {
    String? userId,
    List<({int id, String name})>? drugs,
    bool recordHistory = true,
  }) async {
    final key = _key(drugIds, userId: userId, recordHistory: recordHistory);
    final cached = _cache.get(key);
    if (cached != null) return cached;
    final result = await _runUncached(drugIds, userId: userId, drugs: drugs);
    _cache.put(key, result);
    // Persist the audit trail only for an explicit, recording run that has user
    // identity AND labelled drugs — passive runs (the home gauge) skip the log
    // to keep the history meaningful.
    if (recordHistory && userId != null && drugs != null && drugs.isNotEmpty) {
      unawaited(
        UserDataService.instance
            .recordCheck(userId: userId, drugs: drugs, report: result)
            .catchError((_) => 0),
      );
    }
    return result;
  }

  Future<SafetyReport> _runUncached(
    List<int> drugIds, {
    String? userId,
    List<({int id, String name})>? drugs,
  }) async {
    if (drugIds.isEmpty) return const SafetyReport.empty();

    if (drugIds.length == 1) {
      final foods = await _db.getAllFoodInteractions(drugIds);
      final allergyHits = await _allergyHits(userId, drugs);
      return SafetyReport.fromAnalysis(
        drugInteractions: const [],
        foodInteractions: foods,
        duplicateTherapies: const [],
        allergyHits: allergyHits,
      );
    }

    final (drugInteractions, foodInteractions, duplicateTherapies) = await (
      _db.checkAllInteractions(drugIds),
      _db.getAllFoodInteractions(drugIds),
      _db.checkDuplicateTherapy(drugIds),
    ).wait;
    final allergyHits = await _allergyHits(userId, drugs);

    // For any pair the rule DB had no row for, ask the on-device TFLite
    // predictor. If it returns moderate-or-worse, surface it as an ML-sourced
    // interaction so the safety report still flags it.
    final predicted = await _mlFallbackPredictions(
      drugIds,
      drugs,
      seen: drugInteractions,
    );

    return SafetyReport.fromAnalysis(
      drugInteractions: [...drugInteractions, ...predicted],
      foodInteractions: foodInteractions,
      duplicateTherapies: duplicateTherapies,
      allergyHits: allergyHits,
    );
  }

  /// Fallback chain for pairs the rule DB doesn't recognise:
  ///   1. Remote API (`/api/v1/predict`) — gets the freshest model + a
  ///      human-readable explanation. Cached locally so repeats are free.
  ///   2. If the API returns null (offline, queued, error) → on-device
  ///      TFLite predictor.
  ///   3. If neither produces a prediction → drop the pair from the report.
  Future<List<InteractionResult>> _mlFallbackPredictions(
    List<int> drugIds,
    List<({int id, String name})>? drugs,
    {required List<InteractionResult> seen}
  ) async {
    if (drugs == null || drugs.length < 2) return const [];
    final seenPairs = <String>{
      for (final i in seen) _pairKey(i.drugAId, i.drugBId),
    };
    final results = <InteractionResult>[];
    var predictorReady = true;
    try {
      await _predictor.ensureLoaded();
    } catch (_) {
      predictorReady = false;
    }
    for (var i = 0; i < drugs.length; i++) {
      for (var j = i + 1; j < drugs.length; j++) {
        final a = drugs[i];
        final b = drugs[j];
        if (seenPairs.contains(_pairKey(a.id, b.id))) continue;
        final drugA = await _db.getDrugById(a.id);
        final drugB = await _db.getDrugById(b.id);
        if (drugA == null || drugB == null) continue;

        // Layer 1 — remote API.
        final remote = await _api.predictPair(
          drugAId: drugA.drugbankId,
          drugBId: drugB.drugbankId,
        );
        if (remote != null) {
          // Surface Moderate-or-worse predictions; skip Low (advisory only).
          // Compare on the mapped Severity rank, not the raw class int: the
          // triclass model emits class 0/1/2, mapped to minor/moderate/major.
          if (remote.severity.rank < Severity.moderate.rank) continue;
          // The provenance + confidence now live in structured fields, so the
          // effect carries only the human-readable reason (if any).
          final reason = remote.explanation.isEmpty
              ? null
              : remote.explanation.first;
          results.add(
            InteractionResult(
              drugAId: a.id,
              drugBId: b.id,
              drugAName: a.name,
              drugBName: b.name,
              severity: remote.severity.wireName,
              effect: reason,
              source: InteractionSource.aiPrediction,
              confidence: remote.confidence,
            ),
          );
          continue;
        }

        // Layer 2 — on-device TFLite predictor.
        if (!predictorReady) continue;
        final features = await _featureBuilder.buildFeatures(a.id, b.id);
        if (features == null) continue;
        final prediction = await _predictor.predict(features);
        if (prediction == null) continue;
        if (prediction.severity.rank < Severity.moderate.rank) continue;
        results.add(
          InteractionResult(
            drugAId: a.id,
            drugBId: b.id,
            drugAName: a.name,
            drugBName: b.name,
            severity: prediction.severity.wireName,
            source: InteractionSource.aiPrediction,
            confidence: prediction.confidence,
          ),
        );
      }
    }
    return results;
  }

  static String _pairKey(int a, int b) => a <= b ? '$a|$b' : '$b|$a';

  Future<List<AllergyHit>> _allergyHits(
    String? userId,
    List<({int id, String name})>? drugs,
  ) async {
    if (userId == null || drugs == null || drugs.isEmpty) return const [];
    try {
      return await _allergies.checkDrugs(userId: userId, drugs: drugs);
    } catch (_) {
      // Allergy lookup is best-effort; never block the rest of the report.
      return const [];
    }
  }
}
