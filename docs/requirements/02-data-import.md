# Component 2: Data Import & Processing Requirements (Flutter/Dart)

## Overview
The Data Import module reads telemetry files from IMU dataloggers, validates data integrity, synchronizes front/rear sensor streams, and prepares data for physics simulation. Implemented in Dart for cross-platform operation on Windows, Android, and iOS.

---

## 1. Functional Requirements

### FR-DI-001: Multi-Format Support
**Priority**: CRITICAL  
**Description**: Import telemetry data from various file formats

**Supported Input Formats**:
1. **CSV** (Comma-Separated Values)
   - Standard delimiters: comma, tab, semicolon
   - Header row with column names
   - Flexible column ordering
   - Support for quoted fields

2. **Binary** 
   - Fixed-width struct format
   - HDF5 format
   - Custom binary with documented structure

3. **JSON/JSONL**
   - JSON array of samples
   - JSON Lines (newline-delimited)

**Requirements**:
- Auto-detect format from file extension
- Fallback to content-based detection
- Support compressed files (.gz, .zip)
- Detailed error messages for parsing failures

---

### FR-DI-002: Data Validation
**Priority**: CRITICAL  
**Description**: Validate imported data for completeness and correctness

**Validation Checks**:
1. **Required Fields**:
   - Timestamp present and monotonically increasing
   - All sensor axes present (accel_x/y/z, gyro_x/y/z)
   - No null/NaN values in critical fields

2. **Range Validation**:
   - Accelerometer: -50g to +50g (configurable)
   - Gyroscope: -2000°/s to +2000°/s (configurable)
   - Temperature: -40°C to +85°C
   - Timestamp gaps <1 second (detect recording interruptions)

3. **Statistical Validation**:
   - Detect constant values (sensor stuck)
   - Detect outliers (>5σ from mean)
   - Verify expected sampling rate (±5% tolerance)

**Error Handling**:
- Generate validation report with warnings/errors
- Option to auto-correct minor issues (interpolate gaps)
- Option to proceed with warnings or abort on errors

---

### FR-DI-003: Time Synchronization
**Priority**: HIGH  
**Description**: Align front and rear sensor data to common timeline

**Synchronization Methods**:

1. **Manual Offset**:
   - User specifies time offset between front/rear
   - Apply constant offset to align streams

2. **Event-Based Alignment**:
   - Detect common events (e.g., large bump, hard braking)
   - Cross-correlate acceleration signals
   - Auto-calculate optimal time offset

3. **GPS Time Sync** (if available):
   - Use GPS timestamps as absolute reference
   - Align both sensors to GPS time

**Requirements**:
- Support sub-millisecond alignment precision
- Visual verification of alignment quality
- Save alignment parameters for reproducibility

---

### FR-DI-004: Data Preprocessing
**Priority**: HIGH  
**Description**: Clean and prepare data for simulation

**Preprocessing Steps**:

1. **Filtering**:
   - Low-pass filter to remove sensor noise (configurable cutoff)
   - High-pass filter to remove drift/offset
   - Butterworth filter (default: 4th order, 50Hz cutoff)

2. **Resampling**:
   - Resample to uniform sampling rate if irregular
   - Interpolation methods: linear, cubic spline
   - Target rate: 100Hz, 200Hz, or custom

3. **Coordinate Transformation**:
   - Rotate sensor axes to motorcycle frame
   - X: Forward, Y: Left, Z: Up
   - Compensate for mounting angle offsets

4. **Gravity Removal**:
   - Separate static gravity from dynamic acceleration
   - Use complementary filter or Kalman filter
   - Output linear acceleration (no gravity)

5. **Integration**:
   - Optional: Integrate acceleration to velocity
   - Optional: Integrate velocity to position
   - Apply drift correction

---

### FR-DI-005: Session Metadata
**Priority**: MEDIUM  
**Description**: Extract and store ride session information

**Metadata Fields**:
- Session ID (unique identifier)
- Recording date/time
- Duration (total time, riding time)
- File source paths (front/rear)
- Motorcycle model (default: Tenere 700 2025)
- Rider weight (for sag calculations)
- Terrain type (road, gravel, off-road, mixed)
- Notes/description (user-entered)

**Storage**:
- Save metadata alongside processed data
- JSON or YAML format preferred
- Enable search/filter by metadata

---

### FR-DI-006: Data Quality Scoring
**Priority**: MEDIUM  
**Description**: Assess overall data quality for each session

**Quality Metrics**:
- Completeness: % of expected samples present
- Sample rate consistency: % samples within ±5% of nominal rate
- Synchronization quality: Cross-correlation coefficient (front/rear)
- Signal-to-noise ratio: RMS signal / RMS noise
- Outlier percentage: % samples beyond 3σ

**Quality Score**:
- 0-100 scale
- <60: Poor (warn user)
- 60-85: Fair (usable with caution)
- 85-95: Good
- >95: Excellent

---

## 2. Non-Functional Requirements

### NFR-DI-001: Performance
**Priority**: HIGH
- Import 1 hour of data (720,000 samples @ 200Hz) in <10 seconds on desktop, <30 seconds on mobile
- Support files up to 5GB (2GB recommended on mobile devices)
- Lazy loading for very large files
- Progress indication for long operations (Stream-based progress updates)

---

### NFR-DI-002: Memory Efficiency
**Priority**: MEDIUM
- Streaming import for files larger than available RAM
- Chunk-based processing (process in 1-minute segments)
- Automatic garbage collection of unused data

---

### NFR-DI-003: Reliability
**Priority**: HIGH
- Graceful handling of corrupted files
- No data loss during processing
- Idempotent operations (same input → same output)
- Automatic backup of raw data

---

### NFR-DI-004: Usability
**Priority**: MEDIUM
- Simple API for common import tasks
- Detailed logging of all processing steps
- Exportable processing pipeline configuration
- Undo/redo capability for preprocessing steps

### NFR-DI-005: Cross-Platform Compatibility
**Priority**: CRITICAL
- File picker integration: file_picker package for all platforms
- Platform-specific storage: path_provider for documents/cache directories
- Platform permissions: Handle Android/iOS storage permissions
- Desktop file paths: Support Windows (C:\), Linux (/home), iOS/Android app sandboxing

---

## 3. Data Structures

### Input Data Schema (Raw)
```dart
class RawSensorData {
  final String sessionId;  // UUID v4
  final SensorLocation source;  // enum: front, rear
  final DataFormat format;  // enum: csv, binary, json
  final List<SensorSample> samples;
  
  RawSensorData({required this.sessionId, required this.source, 
                 required this.format, required this.samples});
}

class SensorSample {
  final int timestampMs;
  final Vector3 accel;  // g units
  final Vector3 gyro;   // deg/s
  final double temperature;  // celsius
  final int sampleCount;
  
  SensorSample({required this.timestampMs, required this.accel, 
                required this.gyro, required this.temperature, 
                required this.sampleCount});
}

class Vector3 {
  final double x, y, z;
  Vector3(this.x, this.y, this.z);
}
```

### Processed Data Schema
```dart
class RideSession {
  final String sessionId;
  final SessionMetadata metadata;
  final ProcessedSensorData frontSensor;
  final ProcessedSensorData rearSensor;
  final double syncOffsetMs;
  final double qualityScore;  // 0-100
  
  RideSession({required this.sessionId, required this.metadata,
               required this.frontSensor, required this.rearSensor,
               required this.syncOffsetMs, required this.qualityScore});
}

class SessionMetadata {
  final DateTime date;
  final double durationSeconds;
  final String motorcycle;
  final double riderWeightKg;
  final TerrainType terrain;
  final String notes;
  
  SessionMetadata({required this.date, required this.durationSeconds,
                   this.motorcycle = 'Tenere 700 2025', 
                   required this.riderWeightKg, required this.terrain,
                   this.notes = ''});
}

class ProcessedSensorData {
  final double samplingRateHz;
  final int numSamples;
  final List<double> time;  // seconds from start
  final AxisData accelLinear;  // gravity removed
  final AxisData gyro;
  final AxisData? velocity;  // optional, integrated from accel
  
  ProcessedSensorData({required this.samplingRateHz, required this.numSamples,
                       required this.time, required this.accelLinear,
                       required this.gyro, this.velocity});
}

class AxisData {
  final List<double> x, y, z;
  AxisData({required this.x, required this.y, required this.z});
}
```

---

## 4. API Specification

### Core Import Service
```dart
class DataImportService {
  /// Import and process a ride session from front/rear datalogger files.
  /// 
  /// Returns a Stream for progress updates during import.
  Stream<ImportProgress> importSession({
    required File frontFile,
    required File rearFile,
    DataFormat format = DataFormat.auto,
    SyncMethod syncMethod = SyncMethod.auto,
    FilterConfig? filterConfig,
    bool validate = true,
  });
  
  /// Get the final RideSession after import completes
  Future<RideSession> getImportedSession(String sessionId);
}

class ImportProgress {
  final double percent;  // 0-100
  final String stage;    // 'parsing', 'validating', 'processing'
  final String? message;
  
  ImportProgress(this.percent, this.stage, [this.message]);
}
```

### Validation Service
```dart
class ValidationService {
  /// Validate sensor data against quality rules.
  ValidationReport validateData(
    RawSensorData data, {
    ValidationRules? rules,
  });
}

class ValidationReport {
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;
  final QualityMetrics metrics;
  final bool isPassed;
  
  ValidationReport({required this.errors, required this.warnings,
                    required this.metrics, required this.isPassed});
}
```

### Synchronization Service
```dart
class SynchronizationService {
  /// Synchronize front and rear sensor timelines.
  /// 
  /// Returns synchronized data and the calculated time offset.
  Future<SyncResult> synchronizeSensors({
    required ProcessedSensorData front,
    required ProcessedSensorData rear,
    SyncMethod method = SyncMethod.auto,
  });
}

class SyncResult {
  final ProcessedSensorData frontAligned;
  final ProcessedSensorData rearAligned;
  final double offsetMs;
  final double correlationCoefficient;
  
  SyncResult({required this.frontAligned, required this.rearAligned,
              required this.offsetMs, required this.correlationCoefficient});
}
```

---

## 5. Configuration

### Default Filter Configuration
```dart
class FilterConfig {
  final AccelFilterConfig accelLowpass;
  final GyroFilterConfig gyroLowpass;
  final GravityRemovalConfig gravityRemoval;
  final ResamplingConfig? resampling;
  final IntegrationConfig integration;
  
  FilterConfig({
    this.accelLowpass = const AccelFilterConfig(),
    this.gyroLowpass = const GyroFilterConfig(),
    this.gravityRemoval = const GravityRemovalConfig(),
    this.resampling,
    this.integration = const IntegrationConfig(),
  });
}

class AccelFilterConfig {
  final bool enabled;
  final FilterType type;
  final int order;
  final double cutoffHz;
  
  const AccelFilterConfig({
    this.enabled = true,
    this.type = FilterType.butterworth,
    this.order = 4,
    this.cutoffHz = 50,
  });
}

class ValidationRules {
  final RangeRule accelRange;
  final RangeRule gyroRange;
  final RangeRule tempRange;
  final double maxGapSeconds;
  final double outlierSigma;
  final double minQualityScore;
  
  const ValidationRules({
    this.accelRange = const RangeRule(-50, 50),
    this.gyroRange = const RangeRule(-2000, 2000),
    this.tempRange = const RangeRule(-40, 85),
    this.maxGapSeconds = 1.0,
    this.outlierSigma = 5.0,
    this.minQualityScore = 60,
  });
}
```

### Platform-Specific Packages
```yaml
# pubspec.yaml dependencies
dependencies:
  file_picker: ^6.0.0        # Cross-platform file selection
  path_provider: ^2.1.0      # Platform-specific directories
  permission_handler: ^11.0.0 # Android/iOS permissions
  csv: ^5.0.0                # CSV parsing
  archive: ^3.4.0            # .gz, .zip support
  uuid: ^4.0.0               # Session ID generation
```

---

## 6. Error Handling

### Error Types
```dart
abstract class DataImportException implements Exception {
  final String message;
  DataImportException(this.message);
  
  @override
  String toString() => 'DataImportException: $message';
}

class FileFormatException extends DataImportException {
  FileFormatException(String message) : super(message);
}

class ValidationException extends DataImportException {
  final ValidationReport report;
  ValidationException(this.report) : super('Data validation failed');
}

class SynchronizationException extends DataImportException {
  SynchronizationException(String message) : super(message);
}

class CorruptedDataException extends DataImportException {
  CorruptedDataException(String message) : super(message);
}

class PlatformPermissionException extends DataImportException {
  PlatformPermissionException(String message) : super(message);
}
```

---

## 7. Testing & Validation

### Unit Tests
- **UT-DI-001**: Parse valid CSV file
- **UT-DI-002**: Parse valid binary file
- **UT-DI-003**: Detect and reject invalid format
- **UT-DI-004**: Handle missing required fields
- **UT-DI-005**: Validate sensor value ranges
- **UT-DI-006**: Detect timestamp gaps
- **UT-DI-007**: Apply low-pass filter correctly
- **UT-DI-008**: Synchronize with manual offset
- **UT-DI-009**: Auto-detect sync offset via cross-correlation
- **UT-DI-010**: Calculate quality score

### Integration Tests
- **IT-DI-001**: Import complete session (front + rear)
- **IT-DI-002**: Process large file (1+ hour)
- **IT-DI-003**: Handle corrupted file gracefully
- **IT-DI-004**: Export and re-import processed data

### Test Data
- Sample CSV files (valid, invalid, edge cases)
- Sample binary files
- Synthetic data with known properties
- Real-world ride data (clean and noisy)

---

## 8. Acceptance Criteria

- [ ] Successfully import CSV, binary, and JSON formats
- [ ] Validate data and generate quality report
- [ ] Synchronize front/rear sensors with <10ms error
- [ ] Apply configurable preprocessing filters
- [ ] Process 1-hour session in <10 seconds
- [ ] Handle files with missing/corrupt data gracefully
- [ ] Export processed data for future use
- [ ] Quality score accurately reflects data usability

---

## 9. Future Enhancements

- Real-time streaming import (for live data)
- Machine learning-based anomaly detection
- Automatic terrain classification from IMU patterns
- Integration with weather data (temperature, pressure)
- Support for additional sensor types (GPS, CAN bus)
- Cloud storage integration (import from S3, Google Drive)
- Batch processing for multiple sessions
- Data anonymization for sharing
