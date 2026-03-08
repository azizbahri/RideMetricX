#!/usr/bin/env python3
"""
RideMetricX – Synthetic IMU Data Generator
===========================================
Generates deterministic, app-compatible front/rear IMU CSV files for import
validation, regression testing, and benchmarking.

CSV schema (matches app's canonical IMU format):
  # RideMetricX – <Position> Suspension IMU Sample Data
  # Position: <front|rear> | Session: <ISO-8601> | Rate: <N> Hz
  # Sensor: Bosch BMI088 | Bike: Yamaha Tenere 700 (2025)
  timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count

Usage examples
--------------
  # Small smooth-road session (default, ~2 s)
  python tool/generate_imu_data.py

  # 10 s bumpy road, 200 Hz, seed 42
  python tool/generate_imu_data.py --scenario bumpy --duration 10 --rate 200 --seed 42

  # Single impact event, with metadata sidecar
  python tool/generate_imu_data.py --scenario impact --metadata

  # Batch: 5 dropout sessions
  python tool/generate_imu_data.py --scenario dropout --batch 5

  # Full edge-case: jitter + NaN + spikes
  python tool/generate_imu_data.py --scenario bumpy --noise 0.3 --jitter 2 --nan-rows 3 --spike-rows 2

See tool/README.md for full parameter reference.
"""

import argparse
import csv
import json
import math
import os
import random
import sys
from datetime import datetime, timezone

# ── Constants ────────────────────────────────────────────────────────────────

CSV_HEADER_FIELDS = [
    "timestamp_ms",
    "accel_x_g",
    "accel_y_g",
    "accel_z_g",
    "gyro_x_dps",
    "gyro_y_dps",
    "gyro_z_dps",
    "temp_c",
    "sample_count",
]

# Gravity baseline (1 g along Z).
_GRAVITY_Z = 1.0

# Temperature drift per second (°C/s).
_TEMP_DRIFT = 0.01


# ── Ride-profile signal generators ───────────────────────────────────────────

def _smooth_signal(t: float, rng: random.Random, noise: float) -> dict:
    """Barely any vibration – just gravity + tiny noise."""
    ax = rng.gauss(0.0, 0.005 * (noise + 0.01))
    ay = rng.gauss(0.0, 0.005 * (noise + 0.01))
    az = _GRAVITY_Z + rng.gauss(0.0, 0.003 * (noise + 0.01))
    gx = rng.gauss(0.0, 0.1 * (noise + 0.01))
    gy = rng.gauss(0.0, 0.1 * (noise + 0.01))
    gz = rng.gauss(0.0, 0.05 * (noise + 0.01))
    return dict(ax=ax, ay=ay, az=az, gx=gx, gy=gy, gz=gz)


def _bumpy_signal(t: float, rng: random.Random, noise: float) -> dict:
    """Road roughness modelled as sum of sine waves + noise."""
    bump = (
        0.12 * math.sin(2 * math.pi * 8 * t)
        + 0.08 * math.sin(2 * math.pi * 14 * t + 0.7)
        + 0.05 * math.sin(2 * math.pi * 22 * t + 1.3)
    )
    ax = bump * 0.4 + rng.gauss(0.0, 0.02 * (noise + 0.05))
    ay = bump * 0.6 + rng.gauss(0.0, 0.02 * (noise + 0.05))
    az = _GRAVITY_Z + abs(bump) * 0.8 + rng.gauss(0.0, 0.01 * (noise + 0.05))
    gx = bump * 3.5 + rng.gauss(0.0, 0.3 * (noise + 0.05))
    gy = bump * 5.2 + rng.gauss(0.0, 0.4 * (noise + 0.05))
    gz = bump * 1.1 + rng.gauss(0.0, 0.2 * (noise + 0.05))
    return dict(ax=ax, ay=ay, az=az, gx=gx, gy=gy, gz=gz)


def _impact_signal(t: float, rng: random.Random, noise: float,
                   impact_time: float = 0.5, impact_dur: float = 0.05) -> dict:
    """Single large impact at `impact_time` seconds, decays exponentially."""
    dt = t - impact_time
    if 0 <= dt < impact_dur * 6:
        envelope = math.exp(-dt / impact_dur)
    else:
        envelope = 0.0

    ax = envelope * 0.8 + rng.gauss(0.0, 0.01 * (noise + 0.02))
    ay = envelope * 1.2 + rng.gauss(0.0, 0.01 * (noise + 0.02))
    az = _GRAVITY_Z + envelope * 2.5 + rng.gauss(0.0, 0.008 * (noise + 0.02))
    gx = envelope * 18.0 + rng.gauss(0.0, 0.2 * (noise + 0.02))
    gy = envelope * 25.0 + rng.gauss(0.0, 0.3 * (noise + 0.02))
    gz = envelope * 6.0 + rng.gauss(0.0, 0.1 * (noise + 0.02))
    return dict(ax=ax, ay=ay, az=az, gx=gx, gy=gy, gz=gz)


def _washboard_signal(t: float, rng: random.Random, noise: float) -> dict:
    """Repeated hits at ~4 Hz (washboard / corrugated road)."""
    period = 0.25  # 4 Hz
    phase = (t % period) / period
    hit = math.exp(-((phase - 0.1) ** 2) / (2 * 0.01 ** 2)) * 0.5

    ax = hit * 0.3 + rng.gauss(0.0, 0.015 * (noise + 0.04))
    ay = hit * 0.5 + rng.gauss(0.0, 0.015 * (noise + 0.04))
    az = _GRAVITY_Z + hit * 1.2 + rng.gauss(0.0, 0.01 * (noise + 0.04))
    gx = hit * 8.0 + rng.gauss(0.0, 0.25 * (noise + 0.04))
    gy = hit * 12.0 + rng.gauss(0.0, 0.35 * (noise + 0.04))
    gz = hit * 3.0 + rng.gauss(0.0, 0.15 * (noise + 0.04))
    return dict(ax=ax, ay=ay, az=az, gx=gx, gy=gy, gz=gz)


_SCENARIO_FN = {
    "smooth": _smooth_signal,
    "bumpy": _bumpy_signal,
    "impact": _impact_signal,
    "washboard": _washboard_signal,
    "dropout": _bumpy_signal,  # base signal; rows removed later
}


# ── Core generator ────────────────────────────────────────────────────────────

def generate_imu_stream(
    *,
    position: str,
    duration_s: float,
    rate_hz: float,
    scenario: str,
    seed: int,
    noise: float,
    bias_drift: float,
    time_offset_ms: float,
    start_iso: str,
    dropout_fraction: float,
    nan_rows: int,
    spike_rows: int,
    jitter_ms: float,
) -> list[dict]:
    """
    Generate a list of IMU sample dicts for one sensor position.

    All randomness is seeded via `seed` (combined with `position` for
    front/rear independence while remaining reproducible).

    Parameters
    ----------
    position        : 'front' or 'rear'
    duration_s      : total recording duration in seconds
    rate_hz         : nominal sampling frequency in Hz
    scenario        : 'smooth' | 'bumpy' | 'impact' | 'washboard' | 'dropout'
    seed            : RNG seed for determinism
    noise           : noise scale factor (0.0 = noiseless, 1.0 = very noisy)
    bias_drift      : linear accel bias drift magnitude (g/s)
    time_offset_ms  : add this constant offset to all timestamps (ms)
    start_iso       : ISO-8601 string (used in header comment only)
    dropout_fraction: fraction of rows to randomly drop (0.0–1.0)
    nan_rows        : number of rows whose sensor values are replaced with NaN
    spike_rows      : number of rows with large outlier spikes injected
    jitter_ms       : max timestamp jitter in ms (±jitter_ms/2)
    """
    pos_seed = seed ^ (0xF001 if position == "rear" else 0xA001)
    rng = random.Random(pos_seed)

    n_samples = max(1, int(duration_s * rate_hz))
    dt_s = 1.0 / rate_hz
    signal_fn = _SCENARIO_FN[scenario]

    rows = []
    for i in range(n_samples):
        t = i * dt_s
        sig = signal_fn(t, rng, noise)

        # Linear bias drift on accel_z.
        drift = bias_drift * t
        sig["az"] += drift

        # Timestamp: nominal + offset + optional jitter.
        ts_ms = round(t * 1000.0 + time_offset_ms)
        if jitter_ms > 0.0:
            ts_ms += round(rng.uniform(-jitter_ms / 2, jitter_ms / 2))

        # Temperature: base + small per-sample drift.
        base_temp = 25.0 + (0.3 if position == "rear" else 0.0)
        temp = base_temp + _TEMP_DRIFT * t + rng.gauss(0.0, 0.05)

        rows.append({
            "timestamp_ms": ts_ms,
            "accel_x_g": round(sig["ax"], 4),
            "accel_y_g": round(sig["ay"], 4),
            "accel_z_g": round(sig["az"], 4),
            "gyro_x_dps": round(sig["gx"], 2),
            "gyro_y_dps": round(sig["gy"], 2),
            "gyro_z_dps": round(sig["gz"], 2),
            "temp_c": round(temp, 2),
            "sample_count": i,
        })

    # ── Fault injection ───────────────────────────────────────────────────────

    # Spikes: replace sensor values with large outliers.
    if spike_rows > 0 and rows:
        spike_indices = rng.sample(range(len(rows)), min(spike_rows, len(rows)))
        for idx in spike_indices:
            rows[idx]["accel_z_g"] = round(rng.choice([-15.0, 15.0]) + rng.gauss(0, 0.5), 4)
            rows[idx]["gyro_x_dps"] = round(rng.choice([-200.0, 200.0]) + rng.gauss(0, 1.0), 2)

    # NaN rows: replace values with empty string (CSV NaN representation).
    if nan_rows > 0 and rows:
        nan_indices = rng.sample(range(len(rows)), min(nan_rows, len(rows)))
        for idx in nan_indices:
            for field in ("accel_x_g", "accel_y_g", "accel_z_g",
                          "gyro_x_dps", "gyro_y_dps", "gyro_z_dps"):
                rows[idx][field] = ""  # CSV-level NaN/missing

    # Dropout: remove a fraction of rows (simulates packet loss).
    if dropout_fraction > 0.0:
        keep = [r for r in rows if rng.random() >= dropout_fraction]
        rows = keep if keep else rows[:1]  # always keep at least one row

    return rows


def _csv_comments(position: str, start_iso: str, rate_hz: float) -> str:
    pos_label = position.capitalize()
    return (
        f"# RideMetricX – {pos_label} Suspension IMU Sample Data\n"
        f"# Position: {position} | Session: {start_iso} | Rate: {int(rate_hz)} Hz\n"
        f"# Sensor: Bosch BMI088 | Bike: Yamaha Tenere 700 (2025)\n"
    )


def write_csv(rows: list[dict], path: str, position: str,
              start_iso: str, rate_hz: float) -> None:
    """Write rows to a CSV file with app-compatible header comments."""
    with open(path, "w", newline="", encoding="utf-8") as fh:
        fh.write(_csv_comments(position, start_iso, rate_hz))
        writer = csv.DictWriter(fh, fieldnames=CSV_HEADER_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def write_metadata(path: str, params: dict) -> None:
    """Write a JSON sidecar describing the generation parameters."""
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(params, fh, indent=2)
        fh.write("\n")


# ── CLI ───────────────────────────────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Generate synthetic IMU CSV files for RideMetricX testing.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument(
        "--scenario",
        choices=list(_SCENARIO_FN.keys()),
        default="smooth",
        help="Ride-profile preset (default: smooth).",
    )
    p.add_argument(
        "--duration",
        type=float,
        default=1.0,
        metavar="SECONDS",
        help="Recording duration in seconds (default: 1.0).",
    )
    p.add_argument(
        "--rate",
        type=float,
        default=200.0,
        metavar="HZ",
        help="Nominal sampling frequency in Hz (default: 200).",
    )
    p.add_argument(
        "--seed",
        type=int,
        default=0,
        help="RNG seed for deterministic output (default: 0).",
    )
    p.add_argument(
        "--noise",
        type=float,
        default=0.1,
        metavar="LEVEL",
        help="Noise scale factor 0.0–1.0 (default: 0.1).",
    )
    p.add_argument(
        "--bias-drift",
        type=float,
        default=0.0,
        metavar="G_PER_S",
        help="Linear accel_z bias drift in g/s (default: 0.0).",
    )
    p.add_argument(
        "--time-offset",
        type=float,
        default=0.0,
        metavar="MS",
        help="Constant timestamp offset applied to the REAR sensor in ms (default: 0).",
    )
    p.add_argument(
        "--start-time",
        default="2025-06-01T10:00:00Z",
        metavar="ISO8601",
        help="Session start timestamp for header comment (default: 2025-06-01T10:00:00Z).",
    )
    p.add_argument(
        "--output-dir",
        default=".",
        metavar="DIR",
        help="Directory for output files (default: current directory).",
    )
    p.add_argument(
        "--prefix",
        default="",
        metavar="PREFIX",
        help="Filename prefix, e.g. 'session_001_' (default: none).",
    )
    p.add_argument(
        "--dropout",
        type=float,
        default=0.0,
        metavar="FRACTION",
        help="Fraction of rows to drop (0.0–1.0). Overridden to 0.15 for 'dropout' scenario unless set.",
    )
    p.add_argument(
        "--nan-rows",
        type=int,
        default=0,
        metavar="N",
        help="Number of rows to replace with NaN/empty sensor values (default: 0).",
    )
    p.add_argument(
        "--spike-rows",
        type=int,
        default=0,
        metavar="N",
        help="Number of rows to inject large outlier spikes into (default: 0).",
    )
    p.add_argument(
        "--jitter",
        type=float,
        default=0.0,
        metavar="MS",
        help="Max timestamp jitter ±ms per sample (default: 0).",
    )
    p.add_argument(
        "--batch",
        type=int,
        default=1,
        metavar="N",
        help="Number of sessions to generate (default: 1).",
    )
    p.add_argument(
        "--metadata",
        action="store_true",
        help="Write a JSON sidecar file alongside each CSV pair.",
    )
    return p


def _generate_session(args: argparse.Namespace, session_idx: int) -> tuple[str, str]:
    """
    Generate one front+rear CSV pair.  Returns the two file paths created.
    """
    seed = args.seed + session_idx
    dropout = args.dropout
    if args.scenario == "dropout" and dropout == 0.0:
        dropout = 0.15  # default dropout fraction for the dropout scenario

    prefix = args.prefix
    if args.batch > 1:
        prefix = f"{prefix}session_{session_idx + 1:03d}_"

    os.makedirs(args.output_dir, exist_ok=True)

    front_path = os.path.join(args.output_dir, f"{prefix}front_imu.csv")
    rear_path = os.path.join(args.output_dir, f"{prefix}rear_imu.csv")

    common_kwargs = dict(
        duration_s=args.duration,
        rate_hz=args.rate,
        scenario=args.scenario,
        seed=seed,
        noise=args.noise,
        bias_drift=args.bias_drift,
        start_iso=args.start_time,
        dropout_fraction=dropout,
        nan_rows=args.nan_rows,
        spike_rows=args.spike_rows,
        jitter_ms=args.jitter,
    )

    front_rows = generate_imu_stream(position="front", time_offset_ms=0.0, **common_kwargs)
    rear_rows = generate_imu_stream(position="rear", time_offset_ms=args.time_offset, **common_kwargs)

    write_csv(front_rows, front_path, "front", args.start_time, args.rate)
    write_csv(rear_rows, rear_path, "rear", args.start_time, args.rate)

    if args.metadata:
        meta = {
            "session_index": session_idx,
            "seed": seed,
            "scenario": args.scenario,
            "duration_s": args.duration,
            "rate_hz": args.rate,
            "noise": args.noise,
            "bias_drift_g_per_s": args.bias_drift,
            "time_offset_ms": args.time_offset,
            "start_time": args.start_time,
            "dropout_fraction": dropout,
            "nan_rows": args.nan_rows,
            "spike_rows": args.spike_rows,
            "jitter_ms": args.jitter,
            "front_row_count": len(front_rows),
            "rear_row_count": len(rear_rows),
            "front_file": os.path.basename(front_path),
            "rear_file": os.path.basename(rear_path),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        meta_path = os.path.join(
            args.output_dir, f"{prefix}imu_metadata.json"
        )
        write_metadata(meta_path, meta)
        print(f"  metadata → {meta_path}")

    return front_path, rear_path


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.duration <= 0:
        parser.error("--duration must be positive")
    if args.rate <= 0:
        parser.error("--rate must be positive")
    if not (0.0 <= args.noise <= 1.0):
        parser.error("--noise must be in [0.0, 1.0]")
    if not (0.0 <= args.dropout <= 1.0):
        parser.error("--dropout must be in [0.0, 1.0]")
    if args.batch < 1:
        parser.error("--batch must be ≥ 1")

    for i in range(args.batch):
        front_path, rear_path = _generate_session(args, i)
        print(f"  front → {front_path}")
        print(f"  rear  → {rear_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
