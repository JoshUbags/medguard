import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/severity.dart';
import 'tflite_severity_predictor.dart';

/// One prediction from the on-device severity model — used as a fallback when
/// the bundled rule-based DB doesn't have the pair on record.
class MlPrediction {
  const MlPrediction({
    required this.severity,
    required this.severityInt,
    required this.confidence,
    this.features = const {},
  });

  final Severity severity;
  final int severityInt;
  final double confidence;
  final Map<String, double> features;
}

/// Pluggable interaction-severity predictor. The default implementation is a
/// no-op so the app still builds when the TFLite asset hasn't been bundled;
/// in production the [TfLitePredictor] implementation (separate from this
/// file to keep the heavy native dependency optional) loads
/// ``assets/ml/severity_mlp.tflite`` and predicts on the feature vector
/// computed for a pair.
///
/// The fallback chain is: bundled rule DB → this predictor → "unknown —
/// consult a pharmacist".
abstract class MlPredictionService {
  Future<void> ensureLoaded();

  /// Predicts the severity for the supplied feature vector. The vector layout
  /// must match the order in ``ml_pipeline/models/feature_columns.json``.
  /// Returns null when the predictor isn't available or the feature vector is
  /// rejected.
  Future<MlPrediction?> predict(List<double> features);

  static MlPredictionService instance = _defaultInstance();

  static MlPredictionService _defaultInstance() {
    // tflite_flutter is only wired up for Android + iOS today. On every other
    // surface (Windows / macOS / Linux / web / unit-test VMs) we degrade to
    // the [NoopMlPredictionService] so the rest of the app keeps working.
    if (kIsWeb) return const NoopMlPredictionService();
    final platform = defaultTargetPlatform;
    final mobile = platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;
    return mobile
        ? TfLiteSeverityPredictor()
        : const NoopMlPredictionService();
  }
}

/// Default predictor — always returns null. Selected when the app ships
/// without the bundled TFLite model.
class NoopMlPredictionService implements MlPredictionService {
  const NoopMlPredictionService();

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<MlPrediction?> predict(List<double> features) async => null;
}
