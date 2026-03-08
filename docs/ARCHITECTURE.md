# RideMetricX - System Architecture

## Project Overview
RideMetricX is a cross-platform motorcycle suspension tuning simulator for the Yamaha Tenere 700 (2025), built with Flutter to run on Windows, Android, and Web. The system ingests telemetry data from IMU dataloggers mounted on front and rear suspension, simulates suspension behavior under different tuning parameters, and provides visualization for suspension optimization.

---

## Architecture Components

### 1. Data Collection Layer
**Purpose**: Physical IMU dataloggers capture real-world suspension movement and forces
- Front suspension IMU datalogger
- Rear suspension IMU datalogger
- Data recording and storage on device

### 2. Data Import & Processing Layer
**Purpose**: Read, parse, validate, and normalize telemetry data from dataloggers
- Support multiple IMU data formats (CSV, binary, proprietary)
- Data validation and quality checks
- Time synchronization between front/rear sensors
- Data preprocessing and filtering

### 3. Suspension Physics Model
**Purpose**: Mathematical simulation of motorcycle suspension dynamics
- Spring-damper system modeling
- Force calculations based on IMU measurements
- Suspension parameter integration (damping, rebound, sag, spring rate)
- Non-linear damping curves
- Bottoming/topping detection

### 4. Simulation Engine
**Purpose**: Apply tuning parameters to recorded data and predict suspension response
- Replay recorded ride data
- Apply modified suspension parameters
- Calculate predicted suspension positions and forces
- Compare original vs. simulated behavior
- Performance metrics calculation

### 5. Visualization & UI Layer
**Purpose**: Interactive interface for tuning and analysis
- Telemetry data visualization (time series, 3D plots)
- Suspension parameter adjustment controls
- Real-time simulation feedback
- Comparative analysis (before/after tuning)
- Report generation

---

## Data Flow

```
IMU Dataloggers (Hardware)
    ↓
[Data Collection] → Raw telemetry files
    ↓
[Data Import] → Parsed & validated data structures
    ↓
[Suspension Model] → Physics-based simulation
    ↓
[Simulation Engine] → Predicted suspension behavior
    ↓
[Visualization/UI] → Interactive tuning & analysis
```

---

## Technology Stack

### Framework
- **Framework**: Flutter 3.x
- **Language**: Dart 3.x
- **Target Platforms**: Windows, Android, Web

### Core Libraries
- **State Management**: Provider / Riverpod / Bloc
- **Data Processing**: Dart math libraries, custom data processing utilities
- **Physics/Math**: Custom Dart implementations for suspension dynamics
- **File I/O**: dart:io, path_provider, file_picker
- **Data Serialization**: json_serializable, csv parser packages

### Visualization
- **Charts**: fl_chart, syncfusion_flutter_charts
- **3D visualization**: flutter_cube, custom Canvas rendering
- **UI Components**: Material Design 3, Cupertino widgets

### Platform-Specific Features
- **File System**: path_provider (cross-platform storage)
- **File Selection**: file_picker (multi-platform file dialogs)
- **Platform Channels**: For native integrations if needed

### Testing & Quality
- **Unit Testing**: flutter_test (built-in)
- **Widget Testing**: flutter_test
- **Integration Testing**: integration_test
- **Code Quality**: flutter analyze, dart format

---

## Project Structure

```
RideMetricX/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── requirements/
│   │   ├── 01-data-collection.md
│   │   ├── 02-data-import.md
│   │   ├── 03-suspension-model.md
│   │   ├── 04-visualization.md
│   │   └── 05-ui-tuning.md
│   └── api/
├── lib/
│   ├── main.dart
│   ├── models/           # Data models
│   │   ├── imu_data.dart
│   │   ├── suspension_params.dart
│   │   └── simulation_result.dart
│   ├── services/         # Business logic
│   │   ├── data_import/
│   │   ├── suspension_model/
│   │   ├── simulation/
│   │   └── file_service.dart
│   ├── ui/               # User interface
│   │   ├── screens/
│   │   ├── widgets/
│   │   └── theme/
│   ├── providers/        # State management
│   └── utils/            # Helper utilities
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
├── assets/
│   ├── data/             # Sample datasets
│   ├── images/
│   └── config/
├── android/              # Android-specific config
├── web/                  # Web-specific config
├── windows/              # Windows-specific config
├── pubspec.yaml
└── README.md
```

---

## Development Phases

### Phase 1: Foundation (Weeks 1-2)
- [ ] Project structure setup
- [ ] Data import module for common IMU formats
- [ ] Basic data validation
- [ ] Sample data generation/collection

### Phase 2: Physics Model (Weeks 3-4)
- [ ] Suspension dynamics equations
- [ ] Spring-damper model implementation
- [ ] Parameter configuration system
- [ ] Model validation with known scenarios

### Phase 3: Simulation Engine (Weeks 5-6)
- [ ] Replay mechanism
- [ ] Parameter application logic
- [ ] Comparison algorithms
- [ ] Performance metrics

### Phase 4: Visualization (Weeks 7-8)
- [ ] Time series plots
- [ ] Suspension travel visualization
- [ ] Comparative charts
- [ ] 3D trajectory visualization

### Phase 5: User Interface (Weeks 9-10)
- [ ] Parameter tuning controls
- [ ] File upload/management
- [ ] Interactive simulation
- [ ] Export/reporting

### Phase 6: Polish & Testing (Weeks 11-12)
- [ ] Comprehensive testing
- [ ] Documentation
- [ ] Performance optimization
- [ ] Real-world validation

---

## Key Technical Challenges

1. **IMU Data Format Compatibility**: Support various datalogger formats across platforms
2. **Time Synchronization**: Align front/rear sensor data accurately
3. **Physics Model Accuracy**: Balance complexity vs. computational efficiency
4. **Real-time Simulation**: Fast enough for interactive tuning on mobile devices
5. **Data Volume**: Handle large ride sessions efficiently on all platforms
6. **Cross-Platform UI/UX**: Consistent experience across Windows desktop, Android, and Web browsers
7. **File System Access**: Platform-specific storage and file access patterns
8. **Performance Optimization**: Efficient rendering and computation on mobile devices

---

## Success Criteria

- Import and parse IMU data from front/rear dataloggers
- Accurately model suspension physics for Tenere 700
- Simulate suspension response with <5% error vs. actual
- Interactive UI responds to parameter changes in <1 second
- Support ride sessions up to 2 hours duration
- Generate actionable tuning recommendations
