"""
Tests for tool/generate_imu_data.py

Validates:
  - CSV schema (correct header comments + column names)
  - Row counts (duration * rate)
  - Determinism (same seed + params → identical output)
  - All scenario presets produce valid output
  - Fault injection: dropout removes rows, NaN rows have empty sensor values,
    spike rows have outlier values
  - Timestamp jitter produces non-uniform intervals
  - Time offset shifts rear timestamps
  - Metadata sidecar is written when requested
  - Batch generation creates N session pairs
  - CLI argument validation (bad duration/rate/noise/dropout)
"""

import csv
import io
import os
import sys
import tempfile
import unittest

# Ensure the repo root is on the path so we can import the tool module.
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(_REPO_ROOT, "tool"))

from generate_imu_data import (  # noqa: E402
    CSV_HEADER_FIELDS,
    generate_imu_stream,
    main,
    write_csv,
    write_metadata,
)

# ── Helpers ───────────────────────────────────────────────────────────────────

_COMMENT_PREFIX = "# RideMetricX"

_BASE_KWARGS = dict(
    position="front",
    duration_s=0.5,
    rate_hz=200.0,
    scenario="smooth",
    seed=0,
    noise=0.1,
    bias_drift=0.0,
    time_offset_ms=0.0,
    start_iso="2025-06-01T10:00:00Z",
    dropout_fraction=0.0,
    nan_rows=0,
    spike_rows=0,
    jitter_ms=0.0,
)


def _stream(**overrides):
    kwargs = {**_BASE_KWARGS, **overrides}
    return generate_imu_stream(**kwargs)


def _run_cli(*args):
    """Run main() with given argv; returns exit code."""
    return main(list(args))


def _read_csv_rows(path):
    """Read CSV, skipping comment lines starting with '#'."""
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(
            (line for line in fh if not line.startswith("#"))
        )
        for row in reader:
            rows.append(row)
    return rows


def _csv_string_to_rows(text):
    """Parse CSV text (with # comments) into list of dicts."""
    lines = [l for l in text.splitlines() if not l.startswith("#")]
    reader = csv.DictReader(lines)
    return list(reader)


# ── Schema tests ──────────────────────────────────────────────────────────────


class TestSchema(unittest.TestCase):
    def setUp(self):
        self.rows = _stream()

    def test_returns_list(self):
        self.assertIsInstance(self.rows, list)

    def test_row_is_dict(self):
        self.assertIsInstance(self.rows[0], dict)

    def test_all_fields_present(self):
        for field in CSV_HEADER_FIELDS:
            self.assertIn(field, self.rows[0], f"Missing field: {field}")

    def test_no_extra_fields(self):
        extra = set(self.rows[0].keys()) - set(CSV_HEADER_FIELDS)
        self.assertEqual(extra, set(), f"Unexpected extra fields: {extra}")

    def test_timestamp_is_int(self):
        self.assertIsInstance(self.rows[0]["timestamp_ms"], int)

    def test_sample_count_is_int(self):
        self.assertIsInstance(self.rows[0]["sample_count"], int)

    def test_accel_z_near_gravity(self):
        """At rest (smooth scenario) accel_z should be close to 1 g."""
        az_values = [r["accel_z_g"] for r in self.rows if r["accel_z_g"] != ""]
        mean_az = sum(az_values) / len(az_values)
        self.assertAlmostEqual(mean_az, 1.0, delta=0.05)

    def test_timestamps_non_negative(self):
        for r in self.rows:
            self.assertGreaterEqual(r["timestamp_ms"], 0)

    def test_sample_count_sequential(self):
        counts = [r["sample_count"] for r in self.rows]
        self.assertEqual(counts, list(range(len(self.rows))))


# ── Row count tests ───────────────────────────────────────────────────────────


class TestRowCount(unittest.TestCase):
    def test_row_count_equals_duration_times_rate(self):
        rows = _stream(duration_s=1.0, rate_hz=100.0)
        self.assertEqual(len(rows), 100)

    def test_row_count_200hz_half_second(self):
        rows = _stream(duration_s=0.5, rate_hz=200.0)
        self.assertEqual(len(rows), 100)

    def test_row_count_50hz_two_seconds(self):
        rows = _stream(duration_s=2.0, rate_hz=50.0)
        self.assertEqual(len(rows), 100)

    def test_minimal_one_row(self):
        """duration < 1/rate should still produce at least 1 row."""
        rows = _stream(duration_s=0.001, rate_hz=200.0)
        self.assertGreaterEqual(len(rows), 1)


# ── Determinism tests ─────────────────────────────────────────────────────────


class TestDeterminism(unittest.TestCase):
    def test_same_seed_identical_rows(self):
        rows_a = _stream(seed=42)
        rows_b = _stream(seed=42)
        self.assertEqual(rows_a, rows_b)

    def test_different_seed_different_rows(self):
        rows_a = _stream(seed=0)
        rows_b = _stream(seed=1)
        # At least one row should differ (noise differs).
        self.assertNotEqual(rows_a, rows_b)

    def test_front_rear_differ(self):
        """front and rear should produce different data for same seed."""
        base = {k: v for k, v in _BASE_KWARGS.items() if k != "position"}
        front = generate_imu_stream(position="front", **base)
        rear = generate_imu_stream(position="rear", **base)
        self.assertNotEqual(front, rear)

    def test_write_csv_deterministic(self):
        """Two write_csv calls with same data produce identical content."""
        rows = _stream(seed=7)
        buf1 = io.StringIO()
        buf2 = io.StringIO()
        # write_csv uses open(); use a temp file to compare bytes.
        with tempfile.TemporaryDirectory() as d:
            p1 = os.path.join(d, "a.csv")
            p2 = os.path.join(d, "b.csv")
            write_csv(rows, p1, "front", "2025-06-01T10:00:00Z", 200.0)
            write_csv(rows, p2, "front", "2025-06-01T10:00:00Z", 200.0)
            self.assertEqual(open(p1).read(), open(p2).read())


# ── Scenario tests ────────────────────────────────────────────────────────────


class TestScenarios(unittest.TestCase):
    SCENARIOS = ["smooth", "bumpy", "impact", "washboard", "dropout"]

    def _check_scenario(self, scenario):
        rows = _stream(scenario=scenario, duration_s=0.5, dropout_fraction=0.0)
        self.assertGreater(len(rows), 0)
        for field in CSV_HEADER_FIELDS:
            self.assertIn(field, rows[0])

    def test_smooth(self):
        self._check_scenario("smooth")

    def test_bumpy(self):
        self._check_scenario("bumpy")

    def test_impact(self):
        self._check_scenario("impact")

    def test_washboard(self):
        self._check_scenario("washboard")

    def test_dropout_base_signal(self):
        # dropout scenario without dropout_fraction still returns rows
        self._check_scenario("dropout")

    def test_impact_peak_above_smooth(self):
        """impact scenario should have higher peak accel_z than smooth."""
        impact_rows = _stream(scenario="impact", duration_s=2.0, seed=0)
        smooth_rows = _stream(scenario="smooth", duration_s=2.0, seed=0)
        impact_peak = max(r["accel_z_g"] for r in impact_rows if r["accel_z_g"] != "")
        smooth_peak = max(r["accel_z_g"] for r in smooth_rows if r["accel_z_g"] != "")
        self.assertGreater(impact_peak, smooth_peak)


# ── Fault injection tests ─────────────────────────────────────────────────────


class TestFaultInjection(unittest.TestCase):
    def test_dropout_removes_rows(self):
        full = _stream(duration_s=1.0, rate_hz=200.0, dropout_fraction=0.0)
        dropped = _stream(duration_s=1.0, rate_hz=200.0, dropout_fraction=0.5)
        self.assertLess(len(dropped), len(full))

    def test_dropout_keeps_at_least_one_row(self):
        rows = _stream(duration_s=0.1, rate_hz=10.0, dropout_fraction=0.999)
        self.assertGreaterEqual(len(rows), 1)

    def test_nan_rows_empty_sensor_values(self):
        rows = _stream(duration_s=1.0, rate_hz=200.0, nan_rows=5)
        empty_count = sum(
            1 for r in rows
            if r["accel_x_g"] == "" or r["accel_z_g"] == ""
        )
        self.assertEqual(empty_count, 5)

    def test_spike_rows_large_values(self):
        rows = _stream(duration_s=1.0, rate_hz=200.0, spike_rows=3, seed=10)
        spike_count = sum(1 for r in rows if abs(r["accel_z_g"]) > 10.0)
        self.assertEqual(spike_count, 3)

    def test_jitter_produces_non_uniform_intervals(self):
        rows_no_jitter = _stream(duration_s=0.5, rate_hz=200.0, jitter_ms=0.0)
        rows_jitter = _stream(duration_s=0.5, rate_hz=200.0, jitter_ms=4.0)
        intervals_no = [
            rows_no_jitter[i + 1]["timestamp_ms"] - rows_no_jitter[i]["timestamp_ms"]
            for i in range(len(rows_no_jitter) - 1)
        ]
        intervals_j = [
            rows_jitter[i + 1]["timestamp_ms"] - rows_jitter[i]["timestamp_ms"]
            for i in range(len(rows_jitter) - 1)
        ]
        # Without jitter every interval is exactly 5 ms (200 Hz).
        self.assertTrue(all(d == 5 for d in intervals_no))
        # With jitter at least some intervals differ.
        self.assertFalse(all(d == 5 for d in intervals_j))

    def test_time_offset_shifts_rear_timestamps(self):
        base = {k: v for k, v in _BASE_KWARGS.items() if k not in ("position", "time_offset_ms")}
        front = generate_imu_stream(position="front", time_offset_ms=0.0, **base)
        rear = generate_imu_stream(position="rear", time_offset_ms=50.0, **base)
        front_ts0 = front[0]["timestamp_ms"]
        rear_ts0 = rear[0]["timestamp_ms"]
        self.assertEqual(rear_ts0 - front_ts0, 50)

    def test_bias_drift_increases_accel_z(self):
        base = _stream(duration_s=2.0, rate_hz=50.0, bias_drift=0.0)
        drifted = _stream(duration_s=2.0, rate_hz=50.0, bias_drift=0.1)
        # Last sample's accel_z should be higher with drift.
        self.assertGreater(drifted[-1]["accel_z_g"], base[-1]["accel_z_g"])


# ── write_csv / file format tests ─────────────────────────────────────────────


class TestWriteCsv(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.rows = _stream(duration_s=0.1, rate_hz=100.0)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_file_created(self):
        path = os.path.join(self.tmp, "test.csv")
        write_csv(self.rows, path, "front", "2025-06-01T10:00:00Z", 200.0)
        self.assertTrue(os.path.exists(path))

    def test_first_line_is_comment(self):
        path = os.path.join(self.tmp, "test.csv")
        write_csv(self.rows, path, "front", "2025-06-01T10:00:00Z", 200.0)
        with open(path) as f:
            first_line = f.readline()
        self.assertTrue(first_line.startswith(_COMMENT_PREFIX))

    def test_header_row_after_comments(self):
        path = os.path.join(self.tmp, "test.csv")
        write_csv(self.rows, path, "front", "2025-06-01T10:00:00Z", 200.0)
        with open(path) as f:
            lines = f.readlines()
        header_line = next(l for l in lines if not l.startswith("#"))
        fields = [f.strip() for f in header_line.split(",")]
        self.assertEqual(fields, CSV_HEADER_FIELDS)

    def test_data_row_count(self):
        path = os.path.join(self.tmp, "test.csv")
        write_csv(self.rows, path, "front", "2025-06-01T10:00:00Z", 200.0)
        data_rows = _read_csv_rows(path)
        self.assertEqual(len(data_rows), len(self.rows))

    def test_position_in_comment(self):
        for pos in ("front", "rear"):
            path = os.path.join(self.tmp, f"{pos}.csv")
            write_csv(self.rows, path, pos, "2025-06-01T10:00:00Z", 200.0)
            with open(path) as f:
                content = f.read()
            self.assertIn(f"Position: {pos}", content)

    def test_rate_in_comment(self):
        path = os.path.join(self.tmp, "rate.csv")
        write_csv(self.rows, path, "front", "2025-06-01T10:00:00Z", 100.0)
        with open(path) as f:
            content = f.read()
        self.assertIn("Rate: 100 Hz", content)


# ── write_metadata tests ──────────────────────────────────────────────────────


class TestWriteMetadata(unittest.TestCase):
    def test_metadata_file_created(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "meta.json")
            write_metadata(path, {"scenario": "smooth", "seed": 0})
            self.assertTrue(os.path.exists(path))
            with open(path) as f:
                data = json.load(f)
            self.assertEqual(data["scenario"], "smooth")
            self.assertEqual(data["seed"], 0)


# ── CLI integration tests ─────────────────────────────────────────────────────


class TestCLI(unittest.TestCase):
    def test_default_run_creates_files(self):
        with tempfile.TemporaryDirectory() as d:
            rc = _run_cli("--output-dir", d)
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(os.path.join(d, "front_imu.csv")))
            self.assertTrue(os.path.exists(os.path.join(d, "rear_imu.csv")))

    def test_all_scenarios_exit_zero(self):
        scenarios = ["smooth", "bumpy", "impact", "washboard", "dropout"]
        with tempfile.TemporaryDirectory() as d:
            for scenario in scenarios:
                rc = _run_cli(
                    "--scenario", scenario,
                    "--duration", "0.2",
                    "--output-dir", d,
                    "--prefix", f"{scenario}_",
                )
                self.assertEqual(rc, 0, f"Scenario {scenario} failed")

    def test_seed_determinism_via_cli(self):
        with tempfile.TemporaryDirectory() as d:
            _run_cli("--seed", "77", "--output-dir", d, "--prefix", "a_")
            _run_cli("--seed", "77", "--output-dir", d, "--prefix", "b_")
            with open(os.path.join(d, "a_front_imu.csv")) as fa, \
                 open(os.path.join(d, "b_front_imu.csv")) as fb:
                a = fa.read()
                b = fb.read()
            self.assertEqual(a, b)

    def test_different_seeds_different_files(self):
        with tempfile.TemporaryDirectory() as d:
            _run_cli("--seed", "1", "--output-dir", d, "--prefix", "s1_")
            _run_cli("--seed", "2", "--output-dir", d, "--prefix", "s2_")
            with open(os.path.join(d, "s1_front_imu.csv")) as f1, \
                 open(os.path.join(d, "s2_front_imu.csv")) as f2:
                c1 = f1.read()
                c2 = f2.read()
            self.assertNotEqual(c1, c2)

    def test_batch_creates_multiple_files(self):
        with tempfile.TemporaryDirectory() as d:
            rc = _run_cli("--batch", "3", "--output-dir", d)
            self.assertEqual(rc, 0)
            for i in range(1, 4):
                self.assertTrue(
                    os.path.exists(os.path.join(d, f"session_{i:03d}_front_imu.csv")),
                    f"Missing session_{i:03d}_front_imu.csv",
                )

    def test_metadata_flag_writes_sidecar(self):
        with tempfile.TemporaryDirectory() as d:
            rc = _run_cli("--metadata", "--output-dir", d)
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(os.path.join(d, "imu_metadata.json")))

    def test_prefix_applied_to_filenames(self):
        with tempfile.TemporaryDirectory() as d:
            rc = _run_cli("--prefix", "mytest_", "--output-dir", d)
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(os.path.join(d, "mytest_front_imu.csv")))
            self.assertTrue(os.path.exists(os.path.join(d, "mytest_rear_imu.csv")))

    def test_row_count_via_cli(self):
        with tempfile.TemporaryDirectory() as d:
            rc = _run_cli(
                "--duration", "1.0",
                "--rate", "100",
                "--output-dir", d,
            )
            self.assertEqual(rc, 0)
            rows = _read_csv_rows(os.path.join(d, "front_imu.csv"))
            self.assertEqual(len(rows), 100)

    def test_invalid_duration_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            main(["--duration", "0", "--output-dir", "/tmp"])
        self.assertNotEqual(ctx.exception.code, 0)

    def test_invalid_noise_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            main(["--noise", "2.0", "--output-dir", "/tmp"])
        self.assertNotEqual(ctx.exception.code, 0)

    def test_invalid_dropout_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            main(["--dropout", "1.5", "--output-dir", "/tmp"])
        self.assertNotEqual(ctx.exception.code, 0)


# ── Fixture file tests ────────────────────────────────────────────────────────


class TestFixtureFiles(unittest.TestCase):
    """Validate the pre-generated fixture files in test/fixtures/."""

    FIXTURES_DIR = os.path.join(
        os.path.dirname(__file__)
    )

    FIXTURE_PAIRS = [
        ("smooth_front_imu.csv", "smooth_rear_imu.csv"),
        ("bumpy_front_imu.csv", "bumpy_rear_imu.csv"),
        ("impact_front_imu.csv", "impact_rear_imu.csv"),
        ("washboard_front_imu.csv", "washboard_rear_imu.csv"),
        ("dropout_front_imu.csv", "dropout_rear_imu.csv"),
        ("medium_front_imu.csv", "medium_rear_imu.csv"),
    ]

    def _fixture_path(self, name):
        return os.path.join(self.FIXTURES_DIR, name)

    def test_all_fixture_files_exist(self):
        for front, rear in self.FIXTURE_PAIRS:
            self.assertTrue(
                os.path.exists(self._fixture_path(front)),
                f"Missing fixture: {front}",
            )
            self.assertTrue(
                os.path.exists(self._fixture_path(rear)),
                f"Missing fixture: {rear}",
            )

    def test_fixture_headers_match_schema(self):
        for front, _ in self.FIXTURE_PAIRS:
            rows = _read_csv_rows(self._fixture_path(front))
            self.assertGreater(len(rows), 0, f"{front} is empty")
            for field in CSV_HEADER_FIELDS:
                self.assertIn(field, rows[0], f"{front} missing field {field}")

    def test_fixture_comment_line_present(self):
        for front, _ in self.FIXTURE_PAIRS:
            with open(self._fixture_path(front)) as f:
                first_line = f.readline()
            self.assertTrue(
                first_line.startswith(_COMMENT_PREFIX),
                f"{front}: first line should be a comment",
            )

    def test_medium_fixture_has_1000_rows(self):
        rows = _read_csv_rows(self._fixture_path("medium_front_imu.csv"))
        self.assertEqual(len(rows), 1000)  # 5s @ 200 Hz

    def test_dropout_fixture_fewer_rows_than_full(self):
        """Dropout fixture should have fewer rows than a full 1 s session."""
        dropout_rows = _read_csv_rows(self._fixture_path("dropout_front_imu.csv"))
        # 1 s @ 200 Hz = 200 rows max; dropout should remove ~15%
        self.assertLess(len(dropout_rows), 200)
        self.assertGreater(len(dropout_rows), 0)


if __name__ == "__main__":
    unittest.main()
