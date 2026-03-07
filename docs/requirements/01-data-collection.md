# Component 1: Data Collection Requirements

## Overview
Physical IMU dataloggers mounted on the front and rear suspension of a Yamaha Tenere 700 (2025) to capture real-world telemetry during rides. Data files from these dataloggers will be imported into the RideMetricX cross-platform application (Windows, Android, iOS) for analysis and visualization.

---

## Platform Integration Notes

**Cross-Platform Data Import**:
- The RideMetricX Flutter application supports importing datalogger files on all platforms
- **Windows**: Use standard file dialog to select CSV/binary files from USB-connected dataloggers
- **Android**: Import files via USB OTG, cloud storage (Google Drive, Dropbox), or direct device storage
- **iOS**: Import via Files app, cloud storage (iCloud Drive), or AirDrop from connected devices
- **File Sharing**: All platforms support sharing session files between devices via cloud storage or export/import

---

## 1. Functional Requirements

### FR-DC-001: IMU Sensor Specifications
**Priority**: CRITICAL  
**Description**: Each datalogger must capture minimum required sensor data

**Requirements**:
- 3-axis accelerometer with minimum ±16g range (preferably ±50g for impacts)
- 3-axis gyroscope with minimum ±2000°/s range
- Minimum sampling rate: 100 Hz (preferably 200-500 Hz)
- 16-bit resolution minimum for all sensors
- Temperature sensor for temperature compensation

**Rationale**: Suspension events can generate high G-forces; adequate sampling rate captures fast compression/rebound events

---

### FR-DC-002: Mounting Locations
**Priority**: CRITICAL  
**Description**: Dataloggers must be mounted to accurately capture suspension movement

**Front Suspension Mounting**:
- Location: Fork lower leg or front axle
- Mounting: Secure, vibration-resistant bracket
- Orientation: Z-axis aligned with suspension travel (vertical)
- Protection: Weatherproof, impact-resistant housing

**Rear Suspension Mounting**:
- Location: Swingarm near rear axle or shock linkage
- Mounting: Secure, vibration-resistant bracket
- Orientation: Z-axis aligned with suspension travel
- Protection: Weatherproof, impact-resistant housing

**Rationale**: Mounting near axles minimizes sprung mass interference; alignment critical for accurate measurements

---

### FR-DC-003: Data Storage
**Priority**: CRITICAL  
**Description**: Dataloggers must reliably store telemetry data

**Requirements**:
- Minimum 8GB storage capacity (supports ~4-6 hours at 200Hz)
- Support for SD card or internal flash memory
- Automatic file segmentation (e.g., 100MB segments)
- Power-loss data protection (write buffering)
- Timestamped file naming convention

**Rationale**: Long ride sessions require substantial storage; segmentation prevents data loss on corruption

---

### FR-DC-004: Data Format
**Priority**: HIGH  
**Description**: Recorded data must be in accessible, parseable format

**Supported Formats** (in order of preference):
1. **CSV**: Human-readable, widely compatible
2. **Binary**: Compact, fast (struct-based or HDF5)
3. **Custom**: Documented proprietary format with parser

**Required Fields Per Sample**:
- Timestamp (milliseconds since start or Unix epoch)
- Accelerometer X, Y, Z (m/s² or g)
- Gyroscope X, Y, Z (°/s or rad/s)
- Temperature (°C)
- Sample counter (for detecting dropped samples)

**Optional Fields**:
- GPS coordinates (latitude, longitude)
- GPS speed
- GPS altitude
- Battery voltage

**Rationale**: Standard formats ease development; timestamp and counter ensure data integrity

---

### FR-DC-005: Time Synchronization
**Priority**: HIGH  
**Description**: Front and rear dataloggers must have synchronized timestamps

**Requirements**:
- Manual timestamp alignment acceptable (record start time)
- GPS time synchronization preferred (if GPS available)
- Clock drift <1% over 2-hour session
- Synchronization event marker (e.g., trigger button)

**Rationale**: Comparing front/rear data requires accurate time alignment

---

### FR-DC-006: Power Management
**Priority**: HIGH  
**Description**: Dataloggers must operate for duration of typical ride

**Requirements**:
- Battery life: Minimum 3 hours continuous recording
- Low battery warning (LED or file marker)
- Automatic shutdown when battery critical
- USB charging capability
- Power switch for manual on/off

**Rationale**: Tenere 700 riders often do 2-3 hour ride sessions

---

## 2. Non-Functional Requirements

### NFR-DC-001: Durability
**Priority**: CRITICAL
- Operating temperature: -10°C to +60°C
- Vibration resistance: Motorcycle-grade (20+ G random vibration)
- Water resistance: IP67 minimum (dust-tight, waterproof)
- Impact resistance: Survive 1-meter drops

---

### NFR-DC-002: Size and Weight
**Priority**: MEDIUM
- Maximum size: 80mm x 50mm x 30mm per datalogger
- Maximum weight: 200g per datalogger
- Rationale: Minimize unsprung mass impact on suspension dynamics

---

### NFR-DC-003: Data Integrity
**Priority**: CRITICAL
- Error detection: CRC or checksum per data record
- No data loss during normal operation
- Graceful handling of storage full condition (overwrite oldest or stop with warning)

---

### NFR-DC-004: Ease of Use
**Priority**: MEDIUM
- Single-button start/stop recording preferred
- LED status indicators (recording, battery, error)
- No calibration required before each ride
- USB data transfer to computer

---

## 3. Hardware Recommendations

### Recommended IMU Chips
1. **Bosch BMI088** (6-axis, high performance, motorcycle-grade)
2. **InvenSense ICM-20948** (9-axis with magnetometer)
3. **STM LSM6DS3** (6-axis, automotive grade)

### Recommended Development Boards / Dataloggers
1. **Custom Design**: ESP32 + BMI088 + SD card
2. **COTS Options**:
   - Seeed Studio Xiao nRF52840 Sense
   - Adafruit Feather M4 Express + IMU breakout
   - Stand-alone: Garmin VIRB (action camera with telemetry)
   - MyLaps Power2Max datalogger

### GPS Module (Optional)
- U-blox NEO-M9N or similar
- 10Hz update rate minimum

---

## 4. Calibration Requirements

### FR-DC-007: Factory Calibration
**Priority**: HIGH
- Accelerometer bias calibration at rest
- Gyroscope zero-rate calibration
- Temperature compensation coefficients
- Store calibration data in non-volatile memory

### FR-DC-008: Field Calibration
**Priority**: MEDIUM
- User-triggered zero reference (motorcycle stationary, level ground)
- Axis alignment verification process
- Documentation of mounting orientation

---

## 5. Sample Data Specification

### Example CSV Format
```csv
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
10,0.15,0.20,1.35,5.2,3.1,1.5,25.4,2
...
```

### Example Binary Format (struct)
```
Struct format: <Q3f3fhH
Q: timestamp_ms (8 bytes, unsigned long long)
3f: accel_x, accel_y, accel_z (12 bytes, 3 floats)
3f: gyro_x, gyro_y, gyro_z (12 bytes, 3 floats)
h: temperature * 10 (2 bytes, signed short, divide by 10)
H: sample_count (2 bytes, unsigned short)
Total: 38 bytes per sample
```

---

## 6. Testing & Validation

### Test Cases
1. **TC-DC-001**: Verify 200Hz sampling rate accuracy (±2%)
2. **TC-DC-002**: Verify accelerometer accuracy with static 1G test
3. **TC-DC-003**: Verify gyroscope accuracy with known rotation
4. **TC-DC-004**: Verify data integrity after 3-hour recording
5. **TC-DC-005**: Verify waterproofing with water spray test
6. **TC-DC-006**: Verify mounting security with vibration test
7. **TC-DC-007**: Verify time sync drift between front/rear (<100ms over 2 hours)

---

## 7. Acceptance Criteria

- [ ] Two dataloggers (front + rear) successfully record synchronized data
- [ ] Sampling rate ≥100Hz with <2% jitter
- [ ] 3-hour battery life achieved
- [ ] Data format documented and parseable
- [ ] Survived 3 test rides without data loss or mounting failure
- [ ] Time synchronization error <100ms over 2-hour session
- [ ] Data files successfully transfer to computer via USB

---

## 8. Future Enhancements

### Hardware Enhancements
- Real-time wireless data streaming (Bluetooth/WiFi)
- Integrated GPS for every sample
- Magnetometer for absolute heading
- Barometric pressure sensor for altitude
- CAN bus integration for engine RPM, throttle position, brake pressure

### Cross-Platform Mobile Features
- **Live mobile app preview during rides**: 
  - Bluetooth LE connection from smartphone to dataloggers
  - Real-time suspension travel display on phone mount
  - Android/iOS apps for live monitoring
- **Mobile-first workflow**:
  - Import data directly from Bluetooth-enabled dataloggers to smartphone
  - On-bike analysis using tablet (Android/iOS)
  - Cloud sync between desktop and mobile devices
- **Platform-specific integrations**:
  - Android: Wear OS companion app for at-a-glance metrics
  - iOS: Apple Watch integration for ride tracking
  - Integration with popular motorcycle apps (Calimoto, Scenic, etc.)
