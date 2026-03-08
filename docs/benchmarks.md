# Data Import Benchmarks

Performance, memory-efficiency, and reliability benchmark documentation for the RideMetricX data-import pipeline.

## Overview

The benchmark harness lives in `test/benchmark/data_import_benchmark_test.dart`.
It covers four areas:

| Area | Dataset size | CI gated? |
|---|---|---|
| CI smoke – performance thresholds | 6 000 samples (≈ 30 s @ 200 Hz) | Yes – hard thresholds |
| Full 1 h @ 200 Hz benchmark | 720 000 samples | No – opt-in via `--dart-define` |
| Large-file processing (correctness) | 60 000 samples (5 min @ 200 Hz) | Yes – correctness only |
| Idempotency & resilience | 6 000 / small | Yes – correctness |

---

## Running the Benchmarks

### CI smoke tests (run automatically on every PR)

```bash
flutter test test/benchmark/data_import_benchmark_test.dart \
  --name "CI smoke"
```

### Full 1-hour benchmark (run locally for representative numbers)

The 1 h @ 200 Hz group allocates ~720 000 samples in memory and is **skipped by
default** to avoid CI slowdown and OOM.  Enable it with the `--dart-define` flag:

```bash
flutter test test/benchmark/data_import_benchmark_test.dart \
  --dart-define=RUN_FULL_BENCHMARK=true \
  --timeout 600
```

### All benchmark tests (excluding 1h group)

```bash
flutter test test/benchmark/data_import_benchmark_test.dart
```

---

## Performance Targets

Targets are measured against a **1-hour session at 200 Hz** (720 000 IMU samples).

| Stage | Desktop target | Mobile target |
|---|---|---|
| CSV parse (720 000 rows) | ≤ 30 000 ms | ≤ 60 000 ms |
| ImportService end-to-end | ≤ 30 000 ms | ≤ 60 000 ms |
| PreprocessingPipeline | ≤ 30 000 ms | ≤ 60 000 ms |

**CI smoke thresholds** (6 000 samples, ubuntu-latest GitHub Actions runner):

| Stage | Threshold |
|---|---|
| CSV parse | < 2 000 ms |
| JSONL parse | < 2 000 ms |
| ImportService e2e | < 3 000 ms |
| PreprocessingPipeline | < 1 000 ms |

---

## Dataset Generation

Synthetic data is generated in-process by `_generateCsv` / `_generateJsonl`
helpers in the test file.  Values are **deterministic functions of the sample
index** (sine/cosine patterns with a 1-second cycle at the given sample rate),
ensuring idempotency checks are meaningful without requiring fixture files.

A 1-hour session at 200 Hz:
- **720 000 rows**, ≈ 43 MB of raw CSV text (≈ 60 bytes/row).
- Timestamp spacing: 5 ms (200 Hz).
- Fields: `timestamp_ms`, `accel_x_g`, `accel_y_g`, `accel_z_g`,
  `gyro_x_dps`, `gyro_y_dps`, `gyro_z_dps`, `temp_c`, `sample_count`.

---

## Idempotency Guarantees

The benchmark verifies that running the same import three times in sequence:

1. Always returns `ImportSuccess` (not flakily fails).
2. Returns the **same sample count** each run.
3. Returns bit-identical **first and last sample** field maps.
4. Returns the same **`ValidationReport.passed`** flag.
5. Produces **identical `ProcessedSample.toMap()` output** for all samples
   across all three `PreprocessingPipeline` runs (IEEE 754 determinism verified
   across all derived fields).

---

## Corrupted-Input Resilience

The resilience suite verifies that every form of malformed input consistently
produces `ImportError` with a non-empty message.  Variants tested:

- Empty / whitespace-only content
- Header row only (no data)
- All-comment content (`#`-prefixed lines)
- Non-numeric field (timestamp or sensor value)
- Truncated last row (too few columns)
- Row with extra columns
- Missing required column (`accel_z_g`)
- Unknown file extension
- Invalid JSON / JSONL syntax
- Mixed valid + invalid rows
- Repeated import of a corrupted file (consistency check)

---

## Memory Considerations

The current import pipeline is **fully in-memory**: the file content is held as
a `String`, the parser materialises all rows as an intermediate
`List<Map<String, dynamic>>`, and the mapped domain objects are kept as
`List<ImuSample>`.  For a 720 000-sample session this amounts to approximately:

- CSV string: ≈ 43 MB (≈ 60 bytes/row × 720 000 rows)
- Intermediate parsed records (`List<Map<String, dynamic>>`): same order of
  magnitude as the final list; peak heap usage during import is roughly the sum
  of these structures plus normal Dart runtime overhead.
- Final `List<ImuSample>` (9 doubles + 2 ints per sample):
  ~720 000 × ~112 bytes ≈ 80 MB

The benchmark suite verifies functional correctness for this size but does not
enforce an explicit memory ceiling.  For memory-constrained targets (mobile)
consider streaming / chunked import via a future API extension to avoid
materialising the entire `List<Map<String, dynamic>>` at once.

