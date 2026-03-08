// Unit tests for Debouncer and SimulationTrigger.
//
// Uses fakeAsync to control the passage of time without real wall-clock delays.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/services/simulation/debouncer.dart';
import 'package:ride_metric_x/services/simulation/simulation_trigger.dart';

void main() {
  // ── Debouncer ──────────────────────────────────────────────────────────────
  group('Debouncer', () {
    test('action is NOT called before delay elapses', () {
      fakeAsync((fake) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);

        fake.elapse(const Duration(milliseconds: 499));
        expect(callCount, 0);

        debouncer.dispose();
      });
    });

    test('action IS called after delay elapses', () {
      fakeAsync((fake) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);

        fake.elapse(const Duration(milliseconds: 500));
        expect(callCount, 1);

        debouncer.dispose();
      });
    });

    test('rapid calls coalesce into a single invocation', () {
      fakeAsync((fake) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 500));

        debouncer.run(() => callCount++);
        fake.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => callCount++);
        fake.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => callCount++);

        // 600 ms total; only the last run() schedule should fire.
        fake.elapse(const Duration(milliseconds: 500));
        expect(callCount, 1);

        debouncer.dispose();
      });
    });

    test('isPending is true while timer is active', () {
      fakeAsync((fake) {
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        expect(debouncer.isPending, isFalse);
        debouncer.run(() {});
        expect(debouncer.isPending, isTrue);

        fake.elapse(const Duration(milliseconds: 300));
        expect(debouncer.isPending, isFalse);

        debouncer.dispose();
      });
    });

    test('cancel prevents the action from being invoked', () {
      fakeAsync((fake) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        debouncer.run(() => callCount++);
        debouncer.cancel();

        fake.elapse(const Duration(milliseconds: 300));
        expect(callCount, 0);
        expect(debouncer.isPending, isFalse);

        debouncer.dispose();
      });
    });

    test('dispose cancels pending action', () {
      fakeAsync((fake) {
        int callCount = 0;
        final debouncer = Debouncer(delay: const Duration(milliseconds: 300));

        debouncer.run(() => callCount++);
        debouncer.dispose();

        fake.elapse(const Duration(milliseconds: 300));
        expect(callCount, 0);
      });
    });

    test('a second run() replaces the pending action', () {
      fakeAsync((fake) {
        final calls = <String>[];
        final debouncer = Debouncer(delay: const Duration(milliseconds: 200));

        debouncer.run(() => calls.add('first'));
        fake.elapse(const Duration(milliseconds: 100));
        debouncer.run(() => calls.add('second'));

        fake.elapse(const Duration(milliseconds: 200));
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
      fakeAsync((fake) {
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async {},
        );

        trigger.trigger();
        expect(trigger.state, SimulationState.pending);

        fake.elapse(const Duration(milliseconds: 299));
        expect(trigger.state, SimulationState.pending);

        trigger.dispose();
      });
    });

    test('state transitions idle → pending → running → idle', () {
      fakeAsync((fake) {
        final states = <SimulationState>[];
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 200),
          onRun: () async {},
        );
        trigger.addListener(() => states.add(trigger.state));

        trigger.trigger();
        fake.elapse(const Duration(milliseconds: 200));
        fake.flushMicrotasks();

        expect(states, [
          SimulationState.pending,
          SimulationState.running,
          SimulationState.idle,
        ]);

        trigger.dispose();
      });
    });

    test('notifyListeners is called on each state change', () {
      fakeAsync((fake) {
        int notifyCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 100),
          onRun: () async {},
        );
        trigger.addListener(() => notifyCount++);

        trigger.trigger(); // idle → pending
        fake.elapse(const Duration(milliseconds: 100)); // pending → running
        fake.flushMicrotasks(); // running → idle
        // 3 transitions: pending, running, idle.
        expect(notifyCount, 3);

        trigger.dispose();
      });
    });

    test('rapid trigger() calls coalesce to a single run', () {
      fakeAsync((fake) {
        int runCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async => runCount++,
        );

        trigger.trigger();
        fake.elapse(const Duration(milliseconds: 100));
        trigger.trigger();
        fake.elapse(const Duration(milliseconds: 100));
        trigger.trigger();

        fake.elapse(const Duration(milliseconds: 300));
        fake.flushMicrotasks();

        expect(runCount, 1);
        trigger.dispose();
      });
    });

    test('trigger() while running is a no-op', () {
      fakeAsync((fake) {
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
        fake.elapse(const Duration(milliseconds: 100));
        fake.flushMicrotasks();
        expect(trigger.state, SimulationState.running);

        // Calling trigger() while running should be ignored.
        trigger.trigger();
        expect(trigger.state, SimulationState.running);

        runCompleter.complete();
        fake.flushMicrotasks();

        expect(trigger.state, SimulationState.idle);
        expect(runCount, 1);
        trigger.dispose();
      });
    });

    test('onRun exception still transitions state back to idle', () {
      fakeAsync((fake) {
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 100),
          onRun: () async => throw Exception('sim error'),
        );

        trigger.trigger();
        fake.elapse(const Duration(milliseconds: 100));
        fake.flushMicrotasks();

        expect(trigger.state, SimulationState.idle);
        trigger.dispose();
      });
    });

    test('dispose cancels pending run', () {
      fakeAsync((fake) {
        int runCount = 0;
        final trigger = SimulationTrigger(
          debounceDuration: const Duration(milliseconds: 300),
          onRun: () async => runCount++,
        );

        trigger.trigger();
        trigger.dispose();

        fake.elapse(const Duration(milliseconds: 300));
        expect(runCount, 0);
      });
    });
  });
}
