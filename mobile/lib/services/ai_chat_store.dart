import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../screens/ai/ai_conversation.dart';

/// One saved conversation with MedGuard AI.
///
/// A session is only ever persisted once it has at least one user turn — an
/// empty thread is a blank page, not a chat, and listing blank pages under
/// "Recents" is how a history list turns into noise.
class AiChatSession {
  AiChatSession({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiChatSession.fresh() {
    final now = DateTime.now();
    // A timestamp alone is NOT unique: two sessions created in the same
    // microsecond (a "New chat" tapped straight after another, or anything at
    // all under test) would share an id, and the store keys on id — so the
    // second would silently overwrite the first in Recents. The sequence
    // number is what makes the id actually identify one conversation.
    return AiChatSession(
      id: '${now.microsecondsSinceEpoch}-${_sequence++}',
      messages: <AiMessage>[],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Monotonic tiebreaker for [AiChatSession.fresh] ids.
  static int _sequence = 0;

  factory AiChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiMessage.fromJson)
        // A pending turn is a UI state, never history — if the app died
        // mid-answer the placeholder must not come back as a blank reply.
        .where((m) => !m.pending && m.text.trim().isNotEmpty)
        .toList();
    return AiChatSession(
      id: json['id'] as String? ?? '0',
      messages: rawMessages,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final List<AiMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  /// The first thing the user actually asked, trimmed to a single line — the
  /// only honest title for a conversation nobody named.
  String get title {
    for (final message in messages) {
      if (!message.isUser) continue;
      final line = message.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (line.isEmpty) continue;
      return line.length <= 46 ? line : '${line.substring(0, 45)}…';
    }
    return 'New conversation';
  }

  /// Turns worth listing. Pending placeholders never count.
  bool get hasContent => messages.any((m) => m.isUser && m.text.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
    'id': id,
    'messages': [
      for (final m in messages)
        if (!m.pending) m.toJson(),
    ],
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Local, on-device history for the AI tab.
///
/// Deliberately device-local: these are health questions, and until there is a
/// conversational backend to sync them to there is no reason for them to leave
/// the phone. [SharedPreferences] holds one JSON array, newest first, capped at
/// [_maxSessions] so the list stays a *recents* list rather than an archive.
class AiChatStore {
  AiChatStore._();

  static final AiChatStore instance = AiChatStore._();

  static const String _key = 'ai_chat_sessions_v1';
  static const int _maxSessions = 30;

  final List<AiChatSession> _sessions = <AiChatSession>[];
  bool _loaded = false;

  /// Fires whenever the stored list changes, so an open drawer refreshes
  /// without the screen having to poll it.
  final StreamController<List<AiChatSession>> _changes =
      StreamController<List<AiChatSession>>.broadcast();

  Stream<List<AiChatSession>> get changes => _changes.stream;

  /// The sessions held in memory — newest first. Empty until [load] resolves.
  List<AiChatSession> get sessions => List.unmodifiable(_sessions);

  bool get isLoaded => _loaded;

  Future<List<AiChatSession>> load() async {
    if (_loaded) return sessions;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _sessions
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(AiChatSession.fromJson)
                  .where((s) => s.hasContent),
            );
        }
      }
    } catch (_) {
      // A corrupt history must never keep the assistant from opening.
      _sessions.clear();
    }
    _loaded = true;
    _emit();
    return sessions;
  }

  /// Inserts or updates [session], keeping the list newest-first. A session
  /// with no user turn is ignored rather than saved as an empty row.
  Future<void> save(AiChatSession session) async {
    if (!session.hasContent) return;
    session.updatedAt = DateTime.now();
    _sessions.removeWhere((s) => s.id == session.id);
    _sessions.insert(0, session);
    if (_sessions.length > _maxSessions) {
      _sessions.removeRange(_maxSessions, _sessions.length);
    }
    _emit();
    await _persist();
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    _emit();
    await _persist();
  }

  Future<void> clear() async {
    _sessions.clear();
    _emit();
    await _persist();
  }

  void _emit() {
    if (_changes.isClosed) return;
    _changes.add(sessions);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final s in _sessions) s.toJson()]),
      );
    } catch (_) {
      // Losing a history write is survivable; crashing the chat is not.
    }
  }
}
