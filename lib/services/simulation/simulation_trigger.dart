import 'package:flutter/foundation.dart';

import 'debouncer.dart';

/// Lifecycle state of a [SimulationTrigger].
enum SimulationState {
  /// No run is scheduled or executing.
  idle,

  /// A run has been requested and is waiting for the debounce delay to elapse.
  pending,

  /// The simulation callback is currently executing.
  running,
}

/// A [ChangeNotifier] that manages a debounced, non-blocking simulation run
/// lifecycle.
///
/// Calling [trigger] schedules the [onRun] callback to execute after
/// [debounceDuration] of inactivity. Rapid calls to [trigger] coalesce into a
/// single execution, keeping the UI responsive (NFR-UI-002).
///
/// Listen to this notifier to reflect [state] changes in the UI:
/// ```dart
/// _trigger = SimulationTrigger(onRun: _simulate);
/// _trigger.addListener(() => setState(() {}));
/// ```
class SimulationTrigger extends ChangeNotifier {
  SimulationTrigger({
    Duration debounceDuration = const Duration(milliseconds: 500),
    required Future<void> Function() onRun,
  })  : _onRun = onRun,
        _debouncer = Debouncer(delay: debounceDuration);

  final Future<void> Function() _onRun;
  final Debouncer _debouncer;

  SimulationState _state = SimulationState.idle;

  /// Current lifecycle state of this trigger.
  SimulationState get state => _state;

  /// Whether [onRun] is currently executing.
  bool get isRunning => _state == SimulationState.running;

  /// Whether a run is scheduled but not yet started.
  bool get isPending => _state == SimulationState.pending;

  /// Schedules a simulation run, debounced by [debounceDuration].
  ///
  /// If a run is already in progress the new request is silently coalesced;
  /// [trigger] is a no-op while [isRunning] is true.
  void trigger() {
    if (_state == SimulationState.running) return;
    _setState(SimulationState.pending);
    _debouncer.run(_execute);
  }

  Future<void> _execute() async {
    _setState(SimulationState.running);
    try {
      await _onRun();
    } finally {
      _setState(SimulationState.idle);
    }
  }

  void _setState(SimulationState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }
}
