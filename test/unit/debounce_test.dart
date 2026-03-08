// Unit tests for Debouncer and SimulationTrigger.
//
// Uses fakeAsync to control the passage of time without real wall-clock delays.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/services/simulation/debouncer.dart';
import 'package:ride_metric_x/services/simulation/simulation_trigger.dart';

void main() {
  // ── Debouncer ──────────────────────────────────────────────────────────────
  group('Debouncer', () {
    test('action is NOT called before delay elapses', () {
      fakeAsync((async) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);

        async.elapse(const Duration(milliseconds: 499));
        expect(callCount, 0);

        debouncer.dispose();
      });
    });

    test('action IS called after delay elapses', () {
      fakeAsync((async) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);

        async.elapse(const Duration(milliseconds: 500));
        expect(callCount, 1);

        debouncer.dispose();
      });
    });

    test('rapid calls coalesce into a single invocation', () {
      fakeAsync((async) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);
        async.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => callCount++);
        async.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => callCount++);

        // 600 ms total; only the last run() schedule should fire.
        async.elapse(const Duration(milliseconds: 500));
        expect(callCount, 1);

        debouncer.dispose();
      });
    });

    test('isPending is true while timer is active', () {
      fakeAsync((async) {
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        expect(debouncer.isPending, isFalse);
        debouncer.run(() {});
        expect(debouncer.isPending, isTrue);

        async.elapse(const Duration(milliseconds: 300));
        expect(debouncer.isPending, isFalse);

        debouncer.dispose();
      });
    });

    test('cancel prevents the action from being invoked', () {
      fakeAsync((async) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        debouncer.run(() => callCount++);
        debouncer.cancel();

        async.elapse(const Duration(milliseconds: 300));
        expect(callCount, 0);
        expect(debouncer.isPending, isFalse);

        debouncer.dispose();
      });
    });

    test('dispose cancels pending action', () {
      fakeAsync((async) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        debouncer.run(() => callCount++);
        debouncer.dispose();

        async.elapse(const Duration(milliseconds: 300));
        expect(callCount, 0);
      });
    });

    test('a second run() replaces the pending action', () {
      fakeAsync((async) {
        final calls = <String>[];
        final debouncer = Debouncer(delay: const Duration(milliseconds: 200));

        debouncer.run(() => calls.add('first'));
        async.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => calls.add('second'));

        async.elapse(const Duration(milliseconds: 200));
        expect(calls, ['second']);

        debouncer.dispose();
      });
    });
  });

  // ── SimulationTrigger ──────────────────────────────────────────────────────
  group('SimulationTrigger', () {
    test('initial state is idle', () {
      final trigger = SimulationTrigger(onRun: () async {});
      expect(trigger.state, SimulationState.idle);
      expect(trigger.isRunning, isFalse);
      expect(trigger.isPending, isFalse);
      trigger.dispose();
    });

    test('trigger() moves state to pending before delay elapses', () {
      fakeAsync((async) {
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async {},
        );

        trigger.trigger();
        expect(trigger.state, SimulationState.pending);

        async.elapse(const Duration(milliseconds: 299));
        expect(trigger.state, SimulationState.pending);

        trigger.dispose();
      });
    });

    test('state transitions idle → pending → running → idle', () {
      fakeAsync((async) {
        final states = <SimulationState>[];
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 200),
          onRun: () async {},
        );
        trigger.addListener(() => states.add(trigger.state));

        trigger.trigger();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        expect(states, [
          SimulationState.pending,
          SimulationState.running,
          SimulationState.idle,
        ]);

        trigger.dispose();
      });
    });

    test('notifyListeners is called on each state change', () {
      fakeAsync((async) {
        int notifyCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 100),
          onRun: () async {},
        );
        trigger.addListener(() => notifyCount++);

        trigger.trigger(); // idle → pending
        async.elapse(const Duration(milliseconds: 100)); // pending → running
        async.flushMicrotasks(); // running → idle
        // 3 transitions: pending, running, idle.
        expect(notifyCount, 3);

        trigger.dispose();
      });
    });

    test('rapid trigger() calls coalesce to a single run', () {
      fakeAsync((async) {
        int runCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async => runCount++,
        );

        trigger.trigger();
        async.elapse(const Duration(milliseconds: 100));
        trigger.trigger();
        async.elapse(const Duration(milliseconds: 100));
        trigger.trigger();

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(runCount, 1);
        trigger.dispose();
      });
    });

    test('trigger() while running is a no-op', () {
      fakeAsync((async) {
        final runCompleter = Completer<void>();
        int runCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 100),
          onRun: () async {
            runCount++;
            await runCompleter.future;
          },
        );

        trigger.trigger();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(trigger.state, SimulationState.running);

        // Calling trigger() while running should be ignored.
        trigger.trigger();
        expect(trigger.state, SimulationState.running);

        runCompleter.complete();
        async.flushMicrotasks();

        expect(trigger.state, SimulationState.idle);
        expect(runCount, 1);
        trigger.dispose();
      });
    });

    test('onRun exception still transitions state back to idle', () {
      fakeAsync((async) {
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 100),
          onRun: () async => throw Exception('sim error'),
        );

        trigger.trigger();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();

        expect(trigger.state, SimulationState.idle);
        trigger.dispose();
      });
    });

    test('dispose cancels pending run', () {
      fakeAsync((async) {
        int runCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async => runCount++,
        );

        trigger.trigger();
        trigger.dispose();

        async.elapse(const Duration(milliseconds: 300));
        expect(runCount, 0);
      });
    });
  });
}
