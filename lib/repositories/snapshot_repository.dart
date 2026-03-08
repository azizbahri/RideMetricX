import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/tuning_snapshot.dart';

/// In-memory repository for [TuningSnapshot] records (FR-UI-007).
///
/// Notifies registered listeners whenever the snapshot list changes (add /
/// remove).  Intended to be long-lived (app-scoped) and injected into widgets
/// via constructor for testability.
///
/// Snapshots are ordered by insertion time; the first snapshot in [snapshots]
/// is treated as the baseline for delta comparisons in [ComparisonScreen].
class SnapshotRepository extends ChangeNotifier {
  final List<TuningSnapshot> _snapshots = [];

  /// A live, unmodifiable view of the current snapshot list.
  ///
  /// The list preserves insertion order; index 0 is the oldest / baseline
  /// snapshot.  Callers should not cache the reference across mutations—use
  /// [addListener] to react to changes instead.
  UnmodifiableListView<TuningSnapshot> get snapshots =>
      UnmodifiableListView(_snapshots);

  /// Whether the repository contains no snapshots.
  bool get isEmpty => _snapshots.isEmpty;

  /// Number of snapshots currently stored.
  int get length => _snapshots.length;

  // ── Mutators ───────────────────────────────────────────────────────────────

  /// Adds [snapshot] to the repository and notifies listeners.
  ///
  /// If a snapshot with the same [TuningSnapshot.id] already exists it is
  /// replaced in-place to maintain uniqueness by ID.
  void add(TuningSnapshot snapshot) {
    final index = _snapshots.indexWhere((s) => s.id == snapshot.id);
    if (index >= 0) {
      _snapshots[index] = snapshot;
    } else {
      _snapshots.add(snapshot);
    }
    notifyListeners();
  }

  /// Removes the snapshot with the given [id] and notifies listeners.
  ///
  /// Does nothing if no snapshot with that ID exists.
  void remove(String id) {
    final before = _snapshots.length;
    _snapshots.removeWhere((s) => s.id == id);
    if (_snapshots.length != before) notifyListeners();
  }

  /// Removes all snapshots and notifies listeners.
  void clear() {
    if (_snapshots.isEmpty) return;
    _snapshots.clear();
    notifyListeners();
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Returns the snapshot with the given [id], or `null` if not found.
  TuningSnapshot? findById(String id) {
    for (final s in _snapshots) {
      if (s.id == id) return s;
    }
    return null;
  }
}
