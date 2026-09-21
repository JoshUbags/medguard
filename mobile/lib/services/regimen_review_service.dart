import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the user has completed the interaction review for the
/// regimen they currently have.
///
/// The rule the app enforces: a regimen is not "active" — and none of its
/// analysis (risk verdict, safety alerts, timing conflicts, derived insights)
/// is shown — until the user has actually seen and acknowledged the interaction
/// review for that exact set of medicines. Analysis appearing on its own the
/// moment a second medicine is saved is what this exists to prevent.
///
/// Reviews are keyed by a fingerprint of the regimen's drug ids, not by a
/// single boolean, which gives the behaviour that matters clinically: adding or
/// removing a medicine produces a different regimen, so its previous approval
/// does not carry over and the user is asked to review again. The acknowledged
/// fingerprint is persisted per user, so the gate survives a refresh, a tab
/// change, a cold start and a sign-out/sign-in cycle.
class RegimenReviewService {
  RegimenReviewService._();

  static final RegimenReviewService instance = RegimenReviewService._();

  /// Overridable for tests, so a fake can be substituted without touching
  /// shared preferences.
  @visibleForTesting
  static RegimenReviewService? debugOverride;

  static RegimenReviewService get current => debugOverride ?? instance;

  static const String _keyPrefix = 'regimen_review_ack_';

  /// Bumped whenever an acknowledgement is written or cleared, so screens
  /// listening to it re-evaluate the gate exactly like they do for medication
  /// and dose changes.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// In-memory mirror of the persisted acknowledgement, so a widget can decide
  /// synchronously on its first build instead of flashing ungated content for a
  /// frame while a future resolves.
  final Map<String, String> _acknowledged = <String, String>{};
  final Set<String> _loaded = <String>{};

  /// A stable identity for a regimen: its drug ids, de-duplicated and sorted so
  /// the same medicines in a different order are the same regimen.
  static String fingerprintOf(Iterable<int> drugIds) {
    final ids = drugIds.toSet().toList()..sort();
    return ids.join(',');
  }

  /// The smallest regimen that can produce a drug-drug interaction. Below this
  /// there is nothing to review, so the gate stands down rather than blocking
  /// on a review that would have no content.
  static const int minimumReviewableSize = 2;

  /// Whether [drugIds] is large enough for a review to be meaningful.
  static bool isReviewable(Iterable<int> drugIds) =>
      drugIds.toSet().length >= minimumReviewableSize;

  String _key(String userId) => '$_keyPrefix$userId';

  /// Loads the persisted acknowledgement for [userId] into memory. Safe to call
  /// repeatedly; the read happens once per user per session.
  Future<void> load(String userId) async {
    if (_loaded.contains(userId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key(userId));
      if (stored != null) _acknowledged[userId] = stored;
    } catch (_) {
      // No store (fresh install, tests) — the gate simply stays closed, which
      // is the safe direction to fail in.
    }
    _loaded.add(userId);
    revision.value++;
  }

  /// Whether the review is satisfied for this exact regimen, decided from the
  /// in-memory mirror. Returns false until [load] has run for the user, so a
  /// first build never leaks ungated analysis.
  ///
  /// A regimen too small to review ([isReviewable]) passes automatically: one
  /// medicine cannot interact with anything, so there is nothing to gate.
  bool isReviewed(String userId, Iterable<int> drugIds) {
    if (!isReviewable(drugIds)) return true;
    final ack = _acknowledged[userId];
    if (ack == null) return false;
    return ack == fingerprintOf(drugIds);
  }

  /// Whether this regimen is waiting on a review the user has not done yet —
  /// the condition the Interactions screen prompts on and every gated surface
  /// shows its "review needed" state for.
  bool needsReview(String userId, Iterable<int> drugIds) =>
      isReviewable(drugIds) && !isReviewed(userId, drugIds);

  /// Records that the user has seen and completed the review for this regimen.
  /// Only then does the regimen become active.
  Future<void> markReviewed(String userId, Iterable<int> drugIds) async {
    final fingerprint = fingerprintOf(drugIds);
    _acknowledged[userId] = fingerprint;
    _loaded.add(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), fingerprint);
    } catch (_) {
      // The in-memory value still holds for this session.
    }
    revision.value++;
  }

  /// Drops the acknowledgement, sending the regimen back behind the gate.
  Future<void> clear(String userId) async {
    _acknowledged.remove(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
    revision.value++;
  }

  @visibleForTesting
  void resetForTest() {
    _acknowledged.clear();
    _loaded.clear();
    revision.value = 0;
  }
}
