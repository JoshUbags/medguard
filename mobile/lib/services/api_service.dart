import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import '../models/severity.dart';
import 'connectivity_service.dart';
import 'user_data_service.dart';

/// Default bearer-token source: the signed-in user's Firebase ID token.
/// Returns null when Firebase isn't available (e.g. in unit tests), in which
/// case no Authorization header is sent.
Future<String?> _firebaseIdToken() async {
  try {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (_) {
    return null;
  }
}

/// The backend's base URL, set at build time:
///
///     flutter build apk --dart-define=MEDGUARD_API_BASE_URL=https://your-host
///
/// Empty by default, which turns the remote assist off: every prediction then
/// comes from the on-device model. There is deliberately no built-in host — a
/// signed-in user's ID token is attached to each request, so the app must only
/// ever talk to a server its builder has chosen and controls.
const _defaultBaseUrl = String.fromEnvironment('MEDGUARD_API_BASE_URL');

/// Response from `POST /api/v1/predict`. Mirrors the JSON shape documented
/// in `backend/app/routes/predict.py`.
class RemotePrediction {
  const RemotePrediction({
    required this.drugAId,
    required this.drugBId,
    required this.severity,
    required this.severityInt,
    required this.confidence,
    required this.features,
    required this.explanation,
  });

  final String drugAId;
  final String drugBId;
  final Severity severity;
  final int severityInt;
  final double confidence;
  final Map<String, double> features;
  final List<String> explanation;

  factory RemotePrediction.fromJson(
    Map<String, dynamic> body, {
    required String drugAId,
    required String drugBId,
  }) {
    final featuresMap = (body['features_used'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    final explanation = (body['explanation'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    final severityInt = (body['severity_int'] as num).toInt();
    // The deployed backend model is three-class: it returns a `risk_level` /
    // `severity` of low / moderate / high. Map that tier to the four-level
    // display enum so it round-trips to the right RiskLevel: high → major,
    // moderate → moderate, low → minor. `severity_int` (0/1/2) is the resilient
    // fallback if the tier string is ever absent.
    final severity =
        _severityFromTier(body['risk_level']) ??
        _severityFromTier(body['severity']) ??
        _severityFromTierInt(severityInt);
    return RemotePrediction(
      drugAId: drugAId,
      drugBId: drugBId,
      severity: severity,
      severityInt: severityInt,
      confidence: (body['confidence'] as num).toDouble(),
      features: featuresMap,
      explanation: explanation,
    );
  }
}

/// Maps the deployed three-class tier string (low / moderate / high) to the
/// four-level display enum so it round-trips to the right [Severity.riskLevel].
/// Returns null when [value] isn't one of the three tier names, so the caller
/// can fall through to the numeric `severity_int` fallback.
Severity? _severityFromTier(Object? value) {
  if (value is! String) return null;
  return switch (value.trim().toLowerCase()) {
    'high' => Severity.major,
    'moderate' => Severity.moderate,
    'low' => Severity.minor,
    _ => null,
  };
}

/// Maps the model's tier index (`severity_int` 0 / 1 / 2 = low / moderate /
/// high) to the four-level display enum: 2 → major (High), 1 → moderate,
/// 0 → minor (Low).
Severity _severityFromTierInt(int tier) {
  return switch (tier) {
    2 => Severity.major,
    1 => Severity.moderate,
    _ => Severity.minor,
  };
}

/// Thin HTTP client + offline queue + persistent cache for the MedGuard
/// backend API.
///
/// Fallback chain:
///   1. `predictPair` checks the SQLite `ml_predictions` cache first — every
///      successful API/TFLite response is persisted there so identical
///      regimens never re-hit the wire.
///   2. If the user is offline, the request is enqueued in
///      `pending_api_requests` and the caller gets `null`. `flush()` retries
///      whatever was queued once connectivity is restored.
///   3. If the API call fails (5xx, timeout, etc.) the request is queued too
///      so it'll retry later instead of being lost.
///   4. Callers (typically [InteractionChecker]) fall through to the
///      on-device TFLite predictor when this service returns null.
class ApiService {
  ApiService({
    String? baseUrl,
    http.Client? client,
    UserDataService? userData,
    ConnectivityService? connectivity,
    Future<String?> Function()? idTokenProvider,
    Duration timeout = const Duration(seconds: 8),
  })  : _baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client ?? http.Client(),
        _userData = userData ?? UserDataService.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken,
        _timeout = timeout;

  static final ApiService instance = ApiService();

  static const _cacheSource = 'api';

  final String _baseUrl;
  final http.Client _client;
  final UserDataService _userData;
  final ConnectivityService _connectivity;
  final Future<String?> Function() _idTokenProvider;
  final Duration _timeout;

  StreamSubscription<bool>? _connectivitySub;

  /// Whether a backend was configured at build time. When it was not, the
  /// service stays silent: nothing is sent, and nothing is queued.
  bool get isConfigured => _baseUrl.isNotEmpty;

  /// JSON headers plus a Firebase bearer token when the user is signed in.
  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await _idTokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Begins listening for connectivity transitions; when the device comes
  /// back online any queued requests are flushed.
  void start() {
    if (!isConfigured) return;
    _connectivitySub ??= _connectivity.watch().listen((online) {
      if (online) unawaited(flush());
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Returns the cached or freshly-fetched prediction for the DrugBank pair.
  /// Returns null when the request was deferred (offline / API error queued)
  /// — callers should then ask the on-device TFLite predictor.
  Future<RemotePrediction?> predictPair({
    required String drugAId,
    required String drugBId,
  }) async {
    if (!isConfigured) return null;
    final cached = await _readCache(drugAId, drugBId);
    if (cached != null) return cached;
    final endpoint = '/api/v1/predict';
    final body = {'drug_a_id': drugAId, 'drug_b_id': drugBId};

    // Known-offline: queue and hand straight back, without touching the wire.
    //
    // This is the difference between an offline-first app and one that merely
    // survives being offline. [InteractionChecker] asks about every unrecognised
    // pair in the regimen, one after another, so a five-medicine review can make
    // ten of these calls — and a request that fails only on [_timeout] turns a
    // review a user expects to be instant into over a minute of waiting for
    // answers the on-device predictor was always going to give. A failed socket
    // usually errors immediately, but a captive portal or a stalled DNS lookup
    // does not, and that is precisely the network a phone is on when this
    // matters most.
    //
    // `null` means "not probed yet", not "offline" — an unknown state still
    // tries, so a genuinely online user on a cold start is never downgraded.
    if (_connectivity.status.value == false) {
      await _enqueue(endpoint, body, 'offline');
      return null;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final prediction = RemotePrediction.fromJson(
          decoded,
          drugAId: drugAId,
          drugBId: drugBId,
        );
        await _writeCache(prediction);
        return prediction;
      }
      if (response.statusCode == 404) {
        return null; // unknown DrugBank id, retry won't help
      }
      // Any other status (5xx / 429 / network blip) → queue for retry.
      await _enqueue(endpoint, body, response.statusCode.toString());
      return null;
    } on TimeoutException catch (e) {
      await _enqueue(endpoint, body, e.toString());
      return null;
    } catch (e) {
      await _enqueue(endpoint, body, e.toString());
      return null;
    }
  }

  /// Retries every queued request once. Successful retries get cached and
  /// dropped from the queue; persistent failures stay queued with a bumped
  /// attempt counter.
  Future<void> flush() async {
    if (!isConfigured) return;
    final db = await _userData.database;
    final rows = await db.query(
      'pending_api_requests',
      orderBy: 'queued_at ASC',
      limit: 20,
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final endpoint = row['endpoint'] as String;
      final payload = jsonDecode(row['payload_json'] as String)
          as Map<String, dynamic>;
      try {
        final response = await _client
            .post(
              Uri.parse('$_baseUrl$endpoint'),
              headers: await _headers(),
              body: jsonEncode(payload),
            )
            .timeout(_timeout);
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final prediction = RemotePrediction.fromJson(
            decoded,
            drugAId: payload['drug_a_id'] as String,
            drugBId: payload['drug_b_id'] as String,
          );
          await _writeCache(prediction);
          await db.delete('pending_api_requests', where: 'id = ?', whereArgs: [id]);
          continue;
        }
        if (response.statusCode == 404) {
          // Unknown drug — drop instead of retrying forever.
          await db.delete('pending_api_requests', where: 'id = ?', whereArgs: [id]);
          continue;
        }
      } catch (_) {
        // Fall through and bump the attempt counter.
      }
      await db.update(
        'pending_api_requests',
        {
          'attempts': (row['attempts'] as int? ?? 0) + 1,
          'last_error': 'retry_failed',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Total number of queued offline requests.
  Future<int> queuedRequests() async {
    final db = await _userData.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM pending_api_requests',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<RemotePrediction?> _readCache(
    String drugAId,
    String drugBId,
  ) async {
    final db = await _userData.database;
    final rows = await db.query(
      'ml_predictions',
      where:
          '((drug_a_drugbank_id = ? AND drug_b_drugbank_id = ?) OR '
          '(drug_a_drugbank_id = ? AND drug_b_drugbank_id = ?)) AND '
          'source = ?',
      whereArgs: [drugAId, drugBId, drugBId, drugAId, _cacheSource],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final featuresJson = row['features_json'] as String?;
    final explanationJson = row['explanation_json'] as String?;
    final features = featuresJson == null
        ? const <String, double>{}
        : (jsonDecode(featuresJson) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble()));
    final explanation = explanationJson == null
        ? const <String>[]
        : (jsonDecode(explanationJson) as List<dynamic>)
            .map((e) => e.toString())
            .toList(growable: false);
    final severityInt = (row['severity_int'] as int);
    // The cache row stores the already-mapped severity wire name; fall back to
    // the tier index (0/1/2) when an older row predates that column.
    final storedSeverity = row['severity'] as String?;
    return RemotePrediction(
      drugAId: drugAId,
      drugBId: drugBId,
      severity: storedSeverity != null
          ? Severity.fromString(storedSeverity)
          : _severityFromTierInt(severityInt),
      severityInt: severityInt,
      confidence: (row['confidence'] as num).toDouble(),
      features: features,
      explanation: explanation,
    );
  }

  Future<void> _writeCache(RemotePrediction prediction) async {
    final db = await _userData.database;
    await db.insert(
      'ml_predictions',
      {
        'drug_a_drugbank_id': prediction.drugAId,
        'drug_b_drugbank_id': prediction.drugBId,
        'severity': prediction.severity.wireName,
        'severity_int': prediction.severityInt,
        'confidence': prediction.confidence,
        'source': _cacheSource,
        'features_json': jsonEncode(prediction.features),
        'explanation_json': jsonEncode(prediction.explanation),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _enqueue(
    String endpoint,
    Map<String, dynamic> payload,
    String reason,
  ) async {
    final db = await _userData.database;
    await db.insert('pending_api_requests', {
      'endpoint': endpoint,
      'payload_json': jsonEncode(payload),
      'attempts': 0,
      'last_error': reason,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
