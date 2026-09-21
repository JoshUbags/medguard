import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/severity.dart';
import 'ml_prediction_service.dart';

/// Real on-device severity predictor backed by `tflite_flutter`.
///
/// Loads `assets/ml/severity_mlp.tflite` (produced by
/// `ml_pipeline.src.inference.convert_tflite`) and the matching
/// `feature_columns.json` so callers can build a feature vector in the right
/// order. When the model assets aren't bundled the predictor silently degrades
/// to the [NoopMlPredictionService] behaviour — returning null — so the rest
/// of the app keeps building and the rule DB stays in charge.
class TfLiteSeverityPredictor implements MlPredictionService {
  TfLiteSeverityPredictor({this.modelAsset = _defaultModelAsset});

  static const _defaultModelAsset = 'assets/ml/severity_mlp.tflite';
  static const _columnsAsset = 'assets/ml/feature_columns.json';

  // Safety-oriented decision thresholds — keep in sync with the backend's
  // model_meta.json `decision_thresholds`. Flag HIGH whenever P(high) clears
  // the sensitivity threshold; only call a pair LOW when highly confident;
  // otherwise default to MODERATE rather than give false reassurance.
  static const _highThreshold = 0.40;
  static const _lowThreshold = 0.75;

  final String modelAsset;

  Interpreter? _interpreter;
  List<String>? _featureColumns;
  List<int>? _classes;
  Completer<bool>? _loading;

  @override
  Future<void> ensureLoaded() async {
    if (_interpreter != null) return;
    final inFlight = _loading;
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final completer = Completer<bool>();
    _loading = completer;
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
      final raw = await rootBundle.loadString(_columnsAsset);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _featureColumns = (decoded['feature_columns'] as List<dynamic>)
            .cast<String>();
        _classes = (decoded['classes'] as List<dynamic>)
            .map((c) => (c as num).toInt())
            .toList();
      } else if (decoded is List) {
        _featureColumns = decoded.cast<String>();
        // Bare-list metadata (no classes block): assume the three deployed
        // tiers 0 = low, 1 = moderate, 2 = high.
        _classes = const [0, 1, 2];
      }
      completer.complete(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('TFLite predictor disabled: $e\n$st');
      }
      _interpreter = null;
      completer.complete(false);
    } finally {
      _loading = null;
    }
  }

  List<String>? get featureColumns => _featureColumns;

  @override
  Future<MlPrediction?> predict(List<double> features) async {
    await ensureLoaded();
    final interpreter = _interpreter;
    final classes = _classes;
    if (interpreter == null || classes == null) return null;
    if (_featureColumns != null && features.length != _featureColumns!.length) {
      if (kDebugMode) {
        debugPrint(
          'TFLite predictor: expected ${_featureColumns!.length} features, '
          'got ${features.length}',
        );
      }
      return null;
    }

    try {
      final input = [Float32List.fromList(features)];
      final output = List.generate(
        1,
        (_) => List.filled(classes.length, 0.0),
      );
      interpreter.run(input, output);
      final probs = output.first;
      final iLow = classes.indexOf(0);
      final iHigh = classes.indexOf(2);
      final pLow = iLow >= 0 ? probs[iLow] : 0.0;
      final pHigh = iHigh >= 0 ? probs[iHigh] : 0.0;
      final int severityInt;
      if (pHigh >= _highThreshold) {
        severityInt = 2;
      } else if (pLow >= _lowThreshold) {
        severityInt = 0;
      } else {
        severityInt = 1;
      }
      final idx = classes.indexOf(severityInt);
      return MlPrediction(
        severity: _severityForTier(severityInt),
        severityInt: severityInt,
        confidence: idx >= 0 ? probs[idx] : probs[0],
        features: {
          if (_featureColumns != null)
            for (var i = 0; i < _featureColumns!.length; i++)
              _featureColumns![i]: features[i],
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('TFLite predict failed: $e');
      return null;
    }
  }

  /// Maps a predicted tier index (0 = low, 1 = moderate, 2 = high) to a
  /// representative [Severity] so the on-device estimate round-trips to the
  /// right [RiskLevel]: 0 → minor (Low), 1 → moderate (Moderate), 2 → major
  /// (High). This only affects pairs not catalogued in the bundled DB, where
  /// the model is a fallback estimate.
  static Severity _severityForTier(int tier) {
    return switch (tier) {
      2 => Severity.major,
      1 => Severity.moderate,
      _ => Severity.minor,
    };
  }
}
