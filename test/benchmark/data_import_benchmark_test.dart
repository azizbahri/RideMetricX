// Tests for Data Import: Performance, Memory, and Reliability Benchmarks.
//
// Acceptance criteria (issue #12):
//   AC-1  Benchmark harness for 1 h @ 200 Hz import timing.
//   AC-2  CI-friendly smoke tests with measurable performance thresholds.
//   AC-3  Large-file processing completeness and correctness verification.
//   AC-4  Idempotency: repeated imports of the same data produce identical
//         results.
//   AC-5  Corrupted-input resilience: all corrupt variants surface an
//         ImportError with a non-empty message.
//
// Smoke-benchmark thresholds (CI, ubuntu-latest):
//   - CSV parse 6 000 samples   < 2 000 ms
//   - JSONL parse 6 000 samples < 2 000 ms
//   - ImportService e2e 6 000   < 3 000 ms
//   - Preprocessing 6 000       < 1 000 ms
//
// Full 1 h @ 200 Hz benchmark (720 000 samples):
//   Skipped by default to avoid CI slowdown / OOM. Enable with:
//
//     flutter test test/benchmark/data_import_benchmark_test.dart \
//         --dart-define=RUN_FULL_BENCHMARK=true
//
// Run all benchmark tests (smoke + large-file + idempotency + resilience):
//
//     flutter test test/benchmark/data_import_benchmark_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/services/data_import/csv_import_parser.dart';
import 'package:ride_metric_x/services/data_import/import_service.dart';
import 'package:ride_metric_x/services/data_import/jsonl_parser.dart';
import 'package:ride_metric_x/services/data_import/preprocessing_pipeline.dart';

// ── Compile-time flag ─────────────────────────────────────────────────────────

/// Set to `true` via `--dart-define=RUN_FULL_BENCHMARK=true` to enable the
/// 1-hour / 720 000-sample full benchmark group.  Disabled by default so that
/// CI is never gated by machine speed or OOM from very large allocations.
const bool _runFullBenchmark =
    bool.fromEnvironment('RUN_FULL_BENCHMARK', defaultValue: false);

// ── Synthetic-data generators ─────────────────────────────────────────────────

/// Canonical IMU CSV header.
const _csvHeader =
    'timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count';

/// Generates a synthetic CSV string for [count] samples at [rateHz].
///
/// Values are deterministic functions of the sample index so that idempotency
/// checks can compare fields directly.
String _generateCsv(int count, {double rateHz = 200.0}) {
  final intervalMs = (1000.0 / rateHz).round();
  final buf = StringBuffer()..writeln(_csvHeader);
  for (int i = 0; i < count; i++) {
    final t = i * intervalMs;
    final angle =
        (i * math.pi * 2) / rateHz; // 1-second cycle at rateHz samples/s
    final ax = (math.sin(angle) * 0.1 * 1000).round() / 1000;
    final ay = (math.cos(angle) * 0.05 * 1000).round() / 1000;
    buf.write('$t,$ax,$ay,1.000,0.500,-0.300,0.100,25.300,$i\n');
  }
  return buf.toString();
}

/// Generates a synthetic JSONL string for [count] samples at [rateHz].
String _generateJsonl(int count, {double rateHz = 200.0}) {
  final intervalMs = (1000.0 / rateHz).round();
  final buf = StringBuffer();
  for (int i = 0; i < count; i++) {
    final t = i * intervalMs;
    final angle = (i * math.pi * 2) / rateHz;
    final ax = (math.sin(angle) * 0.1 * 1000).round() / 1000;
    final ay = (math.cos(angle) * 0.05 * 1000).round() / 1000;
    buf.write(
      '{"timestamp_ms":$t,"accel_x_g":$ax,"accel_y_g":$ay,'
      '"accel_z_g":1.0,"gyro_x_dps":0.5,"gyro_y_dps":-0.3,'
      '"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":$i}\n',
    );
  }
  return buf.toString();
}

/// Runs [ImportService.importFile] to completion and returns the terminal
/// [ImportState].
Future<ImportState> _runImport(String content, String fileName) async {
  const svc = ImportService();
  final sel = FileSelection(fileName: fileName, content: content);
  ImportState? last;
  await for (final s in svc.importFile(sel, SensorPosition.front)) {
    last = s;
  }
  return last!;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. CI smoke – performance thresholds (6 000 samples ≈ 30 s @ 200 Hz) ──

  group('CI smoke – performance thresholds (6 000 samples)', () {
    const smokeCount = 6000;

    test('CSV parse completes within 2 000 ms', () {
      final csv = _generateCsv(smokeCount);
      const parser = CsvImportParser();
      final sw = Stopwatch()..start();
      final records = parser.parse(csv);
      sw.stop();
      // ignore: avoid_print
      print('[BENCH] CSV parse $smokeCount rows: ${sw.elapsedMilliseconds} ms');
      expect(records.length, smokeCount);
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'CSV parse of $smokeCount rows must complete within 2 000 ms',
      );
    });

    test('JSONL parse completes within 2 000 ms', () {
      final jsonl = _generateJsonl(smokeCount);
      const parser = JsonlParser();
      final sw = Stopwatch()..start();
      final records = parser.parse(jsonl);
      sw.stop();
      // ignore: avoid_print
      print(
        '[BENCH] JSONL parse $smokeCount rows: ${sw.elapsedMilliseconds} ms',
      );
      expect(records.length, smokeCount);
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'JSONL parse of $smokeCount rows must complete within 2 000 ms',
      );
    });

    test('ImportService end-to-end (CSV) completes within 3 000 ms', () async {
      final csv = _generateCsv(smokeCount);
      final sw = Stopwatch()..start();
      final result = await _runImport(csv, 'smoke.csv');
      sw.stop();
      // ignore: avoid_print
      print(
        '[BENCH] ImportService e2e $smokeCount samples: '
        '${sw.elapsedMilliseconds} ms',
      );
      expect(result, isA<ImportSuccess>());
      expect(
        sw.elapsedMilliseconds,
        lessThan(3000),
        reason: 'End-to-end import of $smokeCount samples must complete '
            'within 3 000 ms',
      );
    });

    test('PreprocessingPipeline completes within 1 000 ms', () async {
      final csv = _generateCsv(smokeCount);
      final result = await _runImport(csv, 'smoke.csv') as ImportSuccess;
      const pipeline = PreprocessingPipeline();
      final sw = Stopwatch()..start();
      final processed = pipeline.process(result.samples);
      sw.stop();
      // ignore: avoid_print
      print(
        '[BENCH] Preprocessing $smokeCount samples: '
        '${sw.elapsedMilliseconds} ms',
      );
      expect(processed.length, smokeCount);
      expect(
        sw.elapsedMilliseconds,
        lessThan(1000),
        reason: 'Preprocessing of $smokeCount samples must complete '
            'within 1 000 ms',
      );
    });
  });

  // ── 2. Full 1 h @ 200 Hz benchmark (720 000 samples) ─────────────────────
  //
  // Skipped by default; opt-in via --dart-define=RUN_FULL_BENCHMARK=true.
  // Timing is measured and printed; no wall-clock threshold is asserted.
  // The tests assert correctness (right sample count, first/last sample values).

  group('1h @ 200Hz – full benchmark (desktop target)', () {
    // 1 h × 3 600 s/h × 200 Hz = 720 000 samples.
    // Each test generates its own data to keep tests independent and to
    // give each an explicit, generous timeout.
    const fullCount = 720000;

    setUp(() {
      if (!_runFullBenchmark) {
        // ignore: avoid_print
        print(
          '[BENCH] Skipping full 1h benchmark. '
          'Run with --dart-define=RUN_FULL_BENCHMARK=true to enable.',
        );
      }
    });

    test(
      'CSV parse 720 000 samples: measures timing and verifies correctness',
      () {
        if (!_runFullBenchmark) return;
        // Data generation is not timed; only the parser itself is benchmarked.
        final csv = _generateCsv(fullCount);
        const parser = CsvImportParser();
        final sw = Stopwatch()..start();
        final records = parser.parse(csv);
        sw.stop();
        final ms = sw.elapsedMilliseconds;
        // Use a sentinel of -1 to signal "instantaneous" (should never happen in
        // practice since 720 000-sample CSV parsing always takes measurable time).
        final throughput = ms > 0 ? (fullCount / (ms / 1000.0)).round() : -1;
        // ignore: avoid_print
        print(
          '[BENCH] 1h CSV parse: ${ms} ms  '
          '($throughput samples/s, '
          'target ≤ 30 000 ms desktop / ≤ 60 000 ms mobile)',
        );
        expect(records.length, fullCount);
        expect(records.first['timestamp_ms'], 0);
        expect(records.last['sample_count'], fullCount - 1);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'ImportService end-to-end 720 000 samples: measures timing and '
      'verifies correctness',
      () async {
        if (!_runFullBenchmark) return;
        final csv = _generateCsv(fullCount);
        final sw = Stopwatch()..start();
        final result = await _runImport(csv, 'full_1h.csv');
        sw.stop();
        final ms = sw.elapsedMilliseconds;
        // ignore: avoid_print
        print(
          '[BENCH] 1h ImportService e2e: ${ms} ms  '
          '(target ≤ 30 000 ms desktop / ≤ 60 000 ms mobile)',
        );
        expect(result, isA<ImportSuccess>());
        final success = result as ImportSuccess;
        expect(success.samples.length, fullCount);
        expect(success.samples.first.timestampMs, 0);
        expect(success.samples.last.sampleCount, fullCount - 1);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'PreprocessingPipeline 720 000 samples: measures timing and verifies '
      'output length',
      () async {
        if (!_runFullBenchmark) return;
        final csv = _generateCsv(fullCount);
        // Import is not timed; only the preprocessing stage is benchmarked.
        final result = await _runImport(csv, 'full_1h.csv') as ImportSuccess;
        const pipeline = PreprocessingPipeline();
        final sw = Stopwatch()..start();
        final processed = pipeline.process(result.samples);
        sw.stop();
        final ms = sw.elapsedMilliseconds;
        // ignore: avoid_print
        print(
          '[BENCH] 1h Preprocessing: ${ms} ms  '
          '(target ≤ 30 000 ms desktop / ≤ 60 000 ms mobile)',
        );
        expect(processed.length, fullCount);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // ── 3. Large-file processing – correctness verification ───────────────────

  group('Large-file processing', () {
    // Use a 5-minute session (60 000 samples) for dedicated correctness checks
    // to avoid duplicating the 720 000-sample work from the 1h group.
    const mediumCount = 60000; // 5 min @ 200 Hz (5 × 60 × 200)

    test('CSV parse returns correct sample count for large input', () {
      final csv = _generateCsv(mediumCount);
      const parser = CsvImportParser();
      final records = parser.parse(csv);
      expect(records.length, mediumCount);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('JSONL parse returns correct sample count for large input', () {
      final jsonl = _generateJsonl(mediumCount);
      const parser = JsonlParser();
      final records = parser.parse(jsonl);
      expect(records.length, mediumCount);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('ImportSuccess sample list has correct length for large input',
        () async {
      final csv = _generateCsv(mediumCount);
      final result = await _runImport(csv, 'large.csv');
      expect(result, isA<ImportSuccess>());
      expect((result as ImportSuccess).samples.length, mediumCount);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('two successive large-file imports complete without error', () async {
      final csv = _generateCsv(mediumCount);
      final r1 = await _runImport(csv, 'session.csv');
      final r2 = await _runImport(csv, 'session.csv');
      expect(r1, isA<ImportSuccess>());
      expect(r2, isA<ImportSuccess>());
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ── 4. Idempotency – repeated import produces identical results ───────────

  group('Idempotency – repeated import', () {
    const idempotencyCount = 6000;
    late String idempotencyCsv;

    setUp(() {
      idempotencyCsv = _generateCsv(idempotencyCount);
    });

    test('same CSV input always yields ImportSuccess', () async {
      for (int run = 0; run < 3; run++) {
        final result = await _runImport(idempotencyCsv, 'front.csv');
        expect(
          result,
          isA<ImportSuccess>(),
          reason: 'Run $run should succeed',
        );
      }
    });

    test('sample count is identical across repeated imports', () async {
      final counts = <int>[];
      for (int run = 0; run < 3; run++) {
        final result =
            await _runImport(idempotencyCsv, 'front.csv') as ImportSuccess;
        counts.add(result.samples.length);
      }
      expect(
        counts.toSet().length,
        1,
        reason: 'All runs must return same count',
      );
      expect(counts.first, idempotencyCount);
    });

    test('first sample is identical across repeated imports', () async {
      final firsts = <Map<String, dynamic>>[];
      for (int run = 0; run < 3; run++) {
        final result =
            await _runImport(idempotencyCsv, 'front.csv') as ImportSuccess;
        firsts.add(result.samples.first.toMap());
      }
      final ref = firsts.first;
      for (final m in firsts.skip(1)) {
        expect(
          m,
          equals(ref),
          reason: 'First sample must be identical each run',
        );
      }
    });

    test('last sample is identical across repeated imports', () async {
      final lasts = <Map<String, dynamic>>[];
      for (int run = 0; run < 3; run++) {
        final result =
            await _runImport(idempotencyCsv, 'front.csv') as ImportSuccess;
        lasts.add(result.samples.last.toMap());
      }
      final ref = lasts.first;
      for (final m in lasts.skip(1)) {
        expect(
          m,
          equals(ref),
          reason: 'Last sample must be identical each run',
        );
      }
    });

    test('validation report passed flag is stable across repeated imports',
        () async {
      final flags = <bool>[];
      for (int run = 0; run < 3; run++) {
        final result =
            await _runImport(idempotencyCsv, 'front.csv') as ImportSuccess;
        flags.add(result.report.passed);
      }
      expect(flags.toSet().length, 1);
    });

    test('preprocessing output is deterministic across repeated runs',
        () async {
      const pipeline = PreprocessingPipeline();
      final result =
          await _runImport(idempotencyCsv, 'front.csv') as ImportSuccess;
      final samples = result.samples;

      final out1 = pipeline.process(samples);
      final out2 = pipeline.process(samples);
      final out3 = pipeline.process(samples);

      expect(out1.length, out2.length);
      expect(out1.length, out3.length);

      // Compare the full canonical serialisation of every ProcessedSample so
      // that all derived fields (accelXLinear, accelYLinear, accelZLinear and,
      // when integration is enabled, velocity/position) are verified for
      // bit-for-bit equality across runs.
      for (int i = 0; i < out1.length; i++) {
        expect(
          out1[i].toMap(),
          equals(out2[i].toMap()),
          reason: 'ProcessedSample toMap() must be deterministic at index $i '
              '(run 1 vs run 2)',
        );
        expect(
          out1[i].toMap(),
          equals(out3[i].toMap()),
          reason: 'ProcessedSample toMap() must be deterministic at index $i '
              '(run 1 vs run 3)',
        );
      }
    });
  });

  // ── 5. Corrupted-input resilience ─────────────────────────────────────────

  group('Corrupted-input resilience', () {
    test('empty content emits ImportError', () async {
      final result = await _runImport('', 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('whitespace-only content emits ImportError', () async {
      final result = await _runImport('   \n\n\t  \n', 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('header-only (no data rows) emits ImportError', () async {
      final result = await _runImport('$_csvHeader\n', 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('all-comment content emits ImportError', () async {
      const content = '# line 1\n# line 2\n# line 3\n';
      final result = await _runImport(content, 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('non-numeric timestamp in first data row emits ImportError', () async {
      const bad = '$_csvHeader\n'
          'NOT_A_NUMBER,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0\n'
          '5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1\n';
      final result = await _runImport(bad, 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('non-numeric field in middle row emits ImportError', () async {
      // Insert a bad row in the middle of otherwise valid data.
      final lines = _generateCsv(10).split('\n').toList();
      // Index 5 is the 6th line overall (data row 5, after the header at
      // index 0 and 4 data rows at indices 1–4).
      lines[5] = '20,0.02,CORRUPT,1.00,0.5,-0.3,0.1,25.3,4';
      final result = await _runImport(lines.join('\n'), 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('truncated last row (too few columns) emits ImportError', () async {
      const truncated = '$_csvHeader\n'
          '0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0\n'
          '5,0.03'; // truncated – only 2 of 9 fields
      final result = await _runImport(truncated, 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('row with extra columns emits ImportError', () async {
      const extra = '$_csvHeader\n'
          '0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0,EXTRA\n';
      final result = await _runImport(extra, 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('missing required column (accel_z_g removed) emits ImportError',
        () async {
      // Build a header without accel_z_g and matching data rows.
      const badHeader =
          'timestamp_ms,accel_x_g,accel_y_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count';
      const bad = '$badHeader\n0,0.02,-0.01,0.5,-0.3,0.1,25.3,0\n';
      final result = await _runImport(bad, 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, contains('accel_z_g'));
    });

    test('unknown file extension emits ImportError', () async {
      final result = await _runImport('some content', 'data.unknown_fmt');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('invalid JSON content for .json file emits ImportError', () async {
      final result = await _runImport('{not: valid json', 'data.json');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('invalid JSONL line emits ImportError with non-empty message',
        () async {
      const bad = '{"timestamp_ms":0,"accel_x_g":0.02,"accel_y_g":-0.01,'
          '"accel_z_g":1.0,"gyro_x_dps":0.5,"gyro_y_dps":-0.3,'
          '"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":0}\n'
          'THIS IS NOT JSON\n';
      final result = await _runImport(bad, 'data.jsonl');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('CSV with mixed valid and invalid rows emits ImportError', () async {
      // 5 valid rows, then a broken one, then 5 more valid rows.
      final buf = StringBuffer()..writeln(_csvHeader);
      for (int i = 0; i < 5; i++) {
        buf.write('${i * 5},0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,$i\n');
      }
      buf.write('BAD_ROW,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,5\n');
      for (int i = 6; i < 11; i++) {
        buf.write('${i * 5},0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,$i\n');
      }
      final result = await _runImport(buf.toString(), 'data.csv');
      expect(result, isA<ImportError>());
      expect((result as ImportError).message, isNotEmpty);
    });

    test('repeated import of corrupted file consistently returns ImportError',
        () async {
      const bad =
          '$_csvHeader\nBAD_TIMESTAMP,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0\n';
      for (int run = 0; run < 3; run++) {
        final result = await _runImport(bad, 'data.csv');
        expect(
          result,
          isA<ImportError>(),
          reason: 'Run $run must consistently return ImportError',
        );
        expect(
          (result as ImportError).message,
          isNotEmpty,
          reason: 'Run $run error message must be non-empty',
        );
      }
    });
  });
}
