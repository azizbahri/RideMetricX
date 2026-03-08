import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coalesces rapid successive calls to [run] into a single invocation, fired
/// once [delay] elapses with no further calls.
///
/// Typical usage — debounce slider changes to avoid spamming a heavy
/// computation:
/// ```dart
/// final _debouncer = Debouncer(delay: const Duration(milliseconds: 500));
///
/// void _onSliderChanged(double v) {
///   _debouncer.run(() => _runSimulation(v));
/// }
/// ```
class Debouncer {
  Debouncer({required this.delay});

  /// Time to wait after the last [run] call before invoking the action.
  final Duration delay;

  Timer? _timer;

  /// Whether an action is currently scheduled but not yet invoked.
  bool get isPending => _timer?.isActive ?? false;

  /// Cancels any pending timer and schedules [action] to run after [delay].
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancels the pending invocation, if any, without invoking it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cancels any pending invocation and releases the underlying [Timer].
  ///
  /// Must be called when the [Debouncer] is no longer needed to avoid leaks.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
