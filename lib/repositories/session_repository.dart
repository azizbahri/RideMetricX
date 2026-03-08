import 'package:flutter/foundation.dart';

import '../models/session_metadata.dart';

/// In-memory repository for [SessionMetadata] records.
///
/// Notifies registered listeners whenever the session list changes (add /
/// delete).  Intended to be long-lived (app-scoped) and injected into widgets
/// via constructor for testability.
class SessionRepository extends ChangeNotifier {
  final List<SessionMetadata> _sessions = [];

  /// An unmodifiable snapshot of the current session list.
  List<SessionMetadata> get sessions => List.unmodifiable(_sessions);

  /// Whether the repository contains no sessions.
  bool get isEmpty => _sessions.isEmpty;

  /// Adds [session] to the repository and notifies listeners.
  void add(SessionMetadata session) {
    _sessions.add(session);
    notifyListeners();
  }

  /// Removes the session with the given [sessionId] and notifies listeners.
  ///
  /// Does nothing if no session with that ID exists.
  void delete(String sessionId) {
    final before = _sessions.length;
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    if (_sessions.length != before) notifyListeners();
  }

  /// Returns the session with [sessionId], or `null` if not found.
  SessionMetadata? findById(String sessionId) {
    for (final s in _sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }
}
