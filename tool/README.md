# IMU Test-Data Generator

A deterministic Python CLI tool that generates synthetic front/rear IMU CSV
files compatible with the RideMetricX import pipeline.

## Requirements

Python 3.10 or later (standard library only – no extra packages needed).

## Quick start

```bash
# Minimal session (1 s, 200 Hz, smooth, seed 0) written to current directory
python tool/generate_imu_data.py

# 10-second bumpy ride, 200 Hz, reproducible seed
python tool/generate_imu_data.py --scenario bumpy --duration 10 --rate 200 --seed 42

# Single large-impact event with metadata sidecar
python tool/generate_imu_data.py --scenario impact --duration 2 --metadata

# Washboard road, custom output directory
python tool/generate_imu_data.py --scenario washboard --output-dir /tmp/imu_data

# Dropout (15 % row loss by default), 5-second session
python tool/generate_imu_data.py --scenario dropout --duration 5

# Edge-case: jitter + NaN + outlier spikes
python tool/generate_imu_data.py --scenario bumpy --jitter 2 --nan-rows 5 --spike-rows 3

# Batch: 10 bumpy sessions, 30 s each, seeds 100–109
python tool/generate_imu_data.py --scenario bumpy --duration 30 --batch 10 --seed 100
```

## Output files

Each invocation writes (by default to the current directory):

| File | Description |
|------|-------------|
| `{prefix}front_imu.csv` | Front-sensor IMU data |
| `{prefix}rear_imu.csv`  | Rear-sensor IMU data  |
| `{prefix}imu_metadata.json` | Generation parameters *(only with `--metadata`)* |

For batch runs (`--batch N > 1`) the prefix is automatically extended with
`session_001_`, `session_002_`, etc.

### CSV schema

```
# RideMetricX – Front Suspension IMU Sample Data
# Position: front | Session: 2025-06-01T10:00:00Z | Rate: 200 Hz
# Sensor: Bosch BMI088 | Bike: Yamaha Tenere 700 (2025)
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.0012,-0.0008,1.0003,0.08,-0.06,0.02,25.01,0
5,…
```

| Column | Type | Unit | Description |
|--------|------|------|-------------|
| `timestamp_ms` | int | ms | Sample timestamp relative to session start |
| `accel_x_g` | float | g | Lateral acceleration |
| `accel_y_g` | float | g | Longitudinal acceleration |
| `accel_z_g` | float | g | Vertical acceleration (≈1 g at rest) |
| `gyro_x_dps` | float | °/s | Roll rate |
| `gyro_y_dps` | float | °/s | Pitch rate |
| `gyro_z_dps` | float | °/s | Yaw rate |
| `temp_c` | float | °C | Sensor temperature |
| `sample_count` | int | – | Sequential sample index |

## Parameters

| Flag | Default | Description |
|------|---------|-------------|
| `--scenario` | `smooth` | Ride profile: `smooth` \| `bumpy` \| `impact` \| `washboard` \| `dropout` |
| `--duration SECONDS` | `1.0` | Recording duration in seconds |
| `--rate HZ` | `200` | Nominal sampling frequency (Hz) |
| `--seed N` | `0` | RNG seed – same seed + params ⇒ identical output |
| `--noise LEVEL` | `0.1` | Noise scale factor [0.0 – 1.0] |
| `--bias-drift G_PER_S` | `0.0` | Linear accel_z drift in g/s |
| `--time-offset MS` | `0.0` | Constant timestamp offset added to **rear** sensor |
| `--start-time ISO8601` | `2025-06-01T10:00:00Z` | Session start (used in header comment) |
| `--output-dir DIR` | `.` | Destination directory |
| `--prefix TEXT` | _(none)_ | Filename prefix |
| `--dropout FRACTION` | `0.0` | Fraction of rows to drop [0.0 – 1.0] (`dropout` scenario defaults to 0.15) |
| `--nan-rows N` | `0` | Rows whose sensor values are replaced with empty/NaN |
| `--spike-rows N` | `0` | Rows with large outlier spikes injected |
| `--jitter MS` | `0.0` | Max timestamp jitter ± ms per sample |
| `--batch N` | `1` | Generate N session pairs |
| `--metadata` | _(off)_ | Write JSON sidecar describing generation parameters |

## Scenario presets

| Preset | Description |
|--------|-------------|
| `smooth` | Minimal vibration – just gravity + tiny noise |
| `bumpy` | Road roughness modelled as overlapping sine waves |
| `impact` | Single large impact at t=0.5 s, exponential decay |
| `washboard` | Repeated ~4 Hz hits (corrugated road) |
| `dropout` | Bumpy road base signal + 15 % row dropout |

## Fault injection

| Option | Effect |
|--------|--------|
| `--dropout` | Randomly removes the specified fraction of rows |
| `--nan-rows N` | Replaces sensor columns in N rows with empty strings |
| `--spike-rows N` | Injects ±15 g / ±200 °/s outliers in N rows |
| `--jitter MS` | Adds ±jitter/2 ms random offset to each timestamp |

## Determinism

The tool is fully deterministic: given the same `--seed` and parameters it
always produces **byte-identical** CSV files. Wall-clock time is **never**
used as an input to the RNG. The `generated_at` field in the JSON sidecar
is the only non-deterministic output.

## Running the tests

```bash
python -m pytest test/fixtures/test_generator.py -v
# or
python test/fixtures/test_generator.py
```

## Using fixtures in Flutter tests

The `test/fixtures/` directory contains pre-generated small and medium CSV
files. Reference them in Dart tests via `rootBundle` or `File` (VM tests):

```dart
// dart:io only – safe for flutter test (VM)
final csv = File('test/fixtures/smooth_front_imu.csv').readAsStringSync();
```

## Using in CI

```yaml
# .github/workflows/ci.yml  (example snippet)
- name: Re-generate fixtures
  run: python tool/generate_imu_data.py --output-dir test/fixtures --prefix smooth_
- name: Run Flutter tests
  run: flutter test
```
