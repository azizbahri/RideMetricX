# Component 4: Visualization Requirements (Flutter)

## Overview
The Visualization module provides real-time 3D rendering of motorcycle suspension dynamics and comprehensive 2D telemetry charting using Flutter widgets and custom painters. It renders suspension geometry, simulates deformation, and displays multi-sensor telemetry data at 60fps on all platforms (Windows, Android, iOS) with support for 1M+ data points.

---

## 1. Functional Requirements

### FR-VZ-001: Flutter Rendering Architecture
**Priority**: CRITICAL  
**Description**: Establish Flutter-based rendering infrastructure for cross-platform visualization

**Technology Stack**:
- **Framework**: Flutter 3.x with Material Design 3
- **3D Rendering**: flutter_cube package or Custom Canvas with transforms
- **2D Charting**: fl_chart or syncfusion_flutter_charts
- **Math Library**: vector_math package for 3D transformations
- **Animation**: Flutter's Animation framework with CustomPainter

**Rendering Components**:
```dart
class VisualizationWidget extends StatefulWidget {
  @override
  _VisualizationWidgetState createState() => _VisualizationWidgetState();
}

class _VisualizationWidgetState extends State<VisualizationWidget> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 16), // 60fps
    )..repeat();
  }
}
```

**Rendering Targets**:
- **Main 3D View**: Motorcycle suspension geometry (60fps target on desktop, 30fps acceptable on mobile)
- **Text Overlay**: Frame rate, session info, parameter values using Flutter Text widgets
- **Debug Visualization**: Force vectors, bounding boxes using CustomPaint

**Performance Considerations**:
- Use RepaintBoundary for expensive widgets
- Implement shouldRepaint optimization in CustomPainter
- Isolate computation for physics simulation
- Platform-specific performance tuning (desktop vs mobile)

---

### FR-VZ-002: 3D Motorcycle Suspension Model
**Priority**: CRITICAL  
**Description**: Render dynamic motorcycle suspension geometry using Flutter 3D rendering

**Model Components**:
1. **Front Suspension** (telescopic fork):
   - Fork tubes (2x cylinders)
   - Fork lowers (rigid bodies)
   - Wheel/hub assembly
   - Brake rotor/caliper
   - Animated compression/extension based on suspension travel

2. **Rear Suspension**:
   - Shock body (cylinder with piston)
   - Upper/lower links (rigid linkages)
   - Rear wheel assembly
   - Chain and sprocket
   - Animated shock compression

3. **Frame and Body**:
   - Main frame (simplified geometry)
   - Seat assembly
   - Tank/panels
   - Static reference geometry

**3D Rendering Options**:

**Option 1: flutter_cube Package**
```dart
import 'package:flutter_cube/flutter_cube.dart';

class SuspensionViewer extends StatelessWidget {
  final Object motorcycleModel;
  final double forkCompression;
  final double shockCompression;
  
  @override
  Widget build(BuildContext context) {
    return Cube(
      onSceneCreated: (Scene scene) {
        scene.world.add(motorcycleModel);
        // Update suspension positions
        updateSuspensionGeometry(scene, forkCompression, shockCompression);
      },
    );
  }
}
```

**Option 2: Custom Canvas Pseudo-3D**
```dart
class Suspension3DPainter extends CustomPainter {
  final SuspensionState state;
  final Matrix4 viewMatrix;
  
  @override
  void paint(Canvas canvas, Size size) {
    // Project 3D coordinates to 2D screen space
    // Draw fork tubes, shock, wheels using Canvas primitives
    _drawForkTubes(canvas, state.frontTravel);
    _drawShock(canvas, state.rearTravel);
    _drawWheels(canvas);
  }
  
  @override
  bool shouldRepaint(Suspension3DPainter oldDelegate) {
    return oldDelegate.state != state;
  }
}
```

**Mesh Specifications**:
- **Format**: OBJ or GLTF 2.0 (loaded via flutter_cube)
- **Vertex Budget**: Max 100k vertices for mobile, 500k for desktop
- **Texture Support**: Diffuse maps (Material Design colors preferred)
- **LOD System**: Lower detail models for mobile platforms

**Animated Elements**:
- Fork tubes: Vertical translation based on suspension state
- Shock: Length/angle changes via Transform widget
- Wheel rotation: RotationTransition based on distance
- Suspension indicators: Color lerp for strain visualization

---

### FR-VZ-003: Material and Rendering System
**Priority**: HIGH  
**Description**: Implement Flutter-based material system for visualization

**Material System with Flutter**:
```dart
class SuspensionMaterial {
  final Color baseColor;
  final double metallic;
  final double roughness;
  final Color? strainColor;  // For compression visualization
  
  SuspensionMaterial({
    required this.baseColor,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.strainColor,
  });
  
  /// Get color based on compression percentage
  Color getStrainColor(double compressionPercent) {
    if (strainColor == null) return baseColor;
    return Color.lerp(
      Colors.green,     // Relaxed
      Colors.red,       // Fully compressed
      compressionPercent,
    )!;
  }
}
```

**Shader-like Effects via CustomPainter**:
```dart
class PhongPainter extends CustomPainter {
  final Vector3 lightPos;
  final Color lightColor;
  
  @override
  void paint(Canvas canvas, Size size) {
    // Implement Phong lighting using gradients and blend modes
    final gradient = RadialGradient(
      colors: [lightColor, Colors.black],
      stops: [0.0, 1.0],
    );
    // Apply to primitives
  }
}
```

**Material Types**:
- **Standard Material**: Solid colors with shadow/highlight gradients
- **Strain Visualization**: Color gradient based on compression state
- **Debug Material**: Wireframe overlay using CustomPaint

**Rendering Performance**:
- Use cached Paint objects to avoid allocation
- Implement shouldRepaint to minimize redraws
- Use saveLayer sparingly (expensive on mobile)

---

### FR-VZ-004: Scene Management and Transforms
**Priority**: HIGH  
**Description**: Manage hierarchical transformation of 3D objects using Flutter's Transform widget

**Scene Graph with Flutter Widgets**:
```dart
class SuspensionSceneGraph extends StatelessWidget {
  final SuspensionState state;
  final CameraController camera;
  
  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: camera.viewMatrix,
      child: Stack(
        children: [
          // Ground plane
          Transform.translate(
            offset: Offset(0, 500),
            child: GroundPlane(),
          ),
          // Motorcycle chassis (root)
          Transform(
            transform: Matrix4.identity(),
            child: Column(
              children: [
                // Front fork (animated)
                Transform.translate(
                  offset: Offset(0, state.frontTravelMm),
                  child: FrontForkWidget(),
                ),
                // Rear shock (animated)
                Transform.translate(
                  offset: Offset(0, state.rearTravelMm),
                  child: RearShockWidget(),
                ),
                // Wheels
                Transform.rotate(
                  angle: state.wheelRotation,
                  child: WheelWidget(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Rendering Optimization**:
- Use `RepaintBoundary` for static elements
- `const` constructors where possible
- Implement custom layout for complex scenes

---

### FR-VZ-005: Camera System
**Priority**: HIGH  
**Description**: Provide interactive camera controls for 3D viewing using Flutter gestures

**Camera Types**:
1. **Arcball Camera**:
   - Pan gesture: Rotate around target
   - Pinch gesture: Zoom in/out
   - Two-finger drag: Pan
   - Smooth animation with AnimationController
   - Configurable sensitivity
  
2. **Orbit Camera**:
   - Fixed distance from target
   - Latitude/longitude rotation
   - Up-vector preservation
   
3. **Fixed Views**:
   - Front view (0°, 90° elevation)
   - Side view (90° rotation, 0° elevation)
   - Top view (90° elevation)
   - Rider POV (positioned at virtual rider seat)

**Camera Implementation**:
```dart
class CameraController {
  Vector3 center = Vector3.zero();
  Vector3 eye = Vector3(0, 0, 5);
  Vector3 up = Vector3(0, 1, 0);
  double radius = 5.0;
  double latitude = 0.0;
  double longitude = 0.0;
  double sensitivity = 0.01;
  
  Matrix4 get viewMatrix {
    return makeViewMatrix(eye, center, up);
  }
  
  void rotate(double dx, double dy) {
    longitude += dx * sensitivity;
    latitude += dy * sensitivity;
    latitude = latitude.clamp(-89.0, 89.0);
    _updateEyePosition();
  }
  
  void zoom(double delta) {
    radius *= (1.0 + delta * 0.1);
    radius = radius.clamp(1.0, 20.0);
    _updateEyePosition();
  }
  
  void pan(Offset delta) {
    // Pan implementation
  }
  
  void _updateEyePosition() {
    // Convert spherical to Cartesian coordinates
    double radLat = latitude * pi / 180.0;
    double radLon = longitude * pi / 180.0;
    
    eye = Vector3(
      radius * cos(radLat) * cos(radLon),
      radius * sin(radLat),
      radius * cos(radLat) * sin(radLon),
    ) + center;
  }
}

// Gesture handling
class InteractiveCamera extends StatefulWidget {
  final Widget child;
  final CameraController controller;
  
  @override
  _InteractiveCameraState createState() => _InteractiveCameraState();
}

class _InteractiveCameraState extends State<InteractiveCamera> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        widget.controller.rotate(
          details.delta.dx,
          details.delta.dy,
        );
        setState(() {});
      },
      onScaleUpdate: (details) {
        widget.controller.zoom(details.scale - 1.0);
        setState(() {});
      },
      child: widget.child,
    );
  }
}
```

---

### FR-VZ-006: Flutter Chart Visualization
**Priority**: CRITICAL  
**Description**: Display telemetry data as interactive 2D charts using Flutter charting libraries

**Charting Library Options**:
1. **fl_chart** (MIT license, lightweight)
2. **syncfusion_flutter_charts** (community license, feature-rich)
3. **charts_flutter** (Google, deprecated but stable)

**Chart Types**:

1. **Line Charts**:
   - Time series plots (suspension travel, velocity, acceleration)
   - Dual-axis plots (left: displacement, right: force)
   - Multiple traces with per-trace styling
   - Auto-scaling or manual limits

2. **Scatter Charts**:
   - Phase plane plots (velocity vs displacement)
   - 2D scatter for sensor comparison
   - Color-coded by event type

3. **Bar Charts**:
   - Suspension bottoming frequency
   - G-force distribution
   - Error/residual distribution

4. **Custom Styling**:
   - Dark theme for racing aesthetic
   - Material Design 3 color schemes
   - Custom axis labels and scaling

**fl_chart Integration Example**:
```dart
import 'package:fl_chart/fl_chart.dart';

class SuspensionTravelChart extends StatelessWidget {
  final List<FlSpot> frontTravelData;
  final List<FlSpot> rearTravelData;
  
  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: -100,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: frontTravelData,
            color: Colors.blue,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
          LineChartBarData(
            spots: rearTravelData,
            color: Colors.red,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()} mm');
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text('${value.toStringAsFixed(1)} s');
              },
            ),
          ),
        ),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(show: true),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} mm',
                  TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
```

**Syncfusion Charts Example**:
```dart
import 'package:syncfusion_flutter_charts/charts.dart';

class AdvancedTelemetryChart extends StatelessWidget {
  final List<SensorData> data;
  
  @override
  Widget build(BuildContext context) {
    return SfCartesianChart(
      title: ChartTitle(text: 'Suspension Travel'),
      legend: Legend(isVisible: true),
      tooltipBehavior: TooltipBehavior(enable: true),
      zoomPanBehavior: ZoomPanBehavior(
        enablePinching: true,
        enablePanning: true,
        zoomMode: ZoomMode.x,
      ),
      series: <ChartSeries>[
        LineSeries<SensorData, double>(
          name: 'Front',
          dataSource: data,
          xValueMapper: (SensorData d, _) => d.time,
          yValueMapper: (SensorData d, _) => d.frontTravel,
          color: Colors.blue,
        ),
        LineSeries<SensorData, double>(
          name: 'Rear',
          dataSource: data,
          xValueMapper: (SensorData d, _) => d.time,
          yValueMapper: (SensorData d, _) => d.rearTravel,
          color: Colors.red,
        ),
      ],
      primaryXAxis: NumericAxis(
        title: AxisTitle(text: 'Time (s)'),
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: 'Travel (mm)'),
      ),
    );
  }
}
```

**Performance Optimizations**:
- **Data Downsampling**: Use Largest-Triangle-Three-Buckets (LTTB) algorithm for >10k points
- **Lazy Loading**: Load data in chunks for very large datasets
- **Caching**: Cache rendered chart images using RepaintBoundary
- **Platform-Specific**: Reduce point count on mobile devices

```dart
/// Downsample data using LTTB algorithm
List<FlSpot> downsampleData(List<FlSpot> data, int targetPoints) {
  if (data.length <= targetPoints) return data;
  
  // LTTB implementation
  final threshold = targetPoints - 2;
  final bucketSize = (data.length - 2) / threshold;
  
  List<FlSpot> sampled = [data.first];
  
  for (int i = 0; i < threshold; i++) {
    // Find largest triangle
    int maxIndex = (i * bucketSize + 1).floor();
    sampled.add(data[maxIndex]);
  }
  
  sampled.add(data.last);
  return sampled;
}
```

---

### FR-VZ-007: Suspension Strain Visualization
**Priority**: HIGH  
**Description**: Real-time visualization of suspension compression state using Flutter widgets

**Visualization Modes**:
1. **Compression Indicator**:
   - Color gradient (green=relaxed → red=compressed)
   - Applied to fork/shock geometry using Color.lerp
   - Percentage text overlay using Text widget

```dart
Color getCompressionColor(double compressionPercent) {
  return Color.lerp(
    Colors.green,      // 0% compression (relaxed)
    Colors.red,        // 100% compression
    compressionPercent,
  )!;
}
```

2. **Vector Field Visualization**:
   - Display force vectors using CustomPaint
   - Arrow length represents magnitude
   - Color represents compression/rebound

```dart
class ForceVectorPainter extends CustomPainter {
  final List<Vector3> forceVectors;
  final List<Vector3> positions;
  
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < forceVectors.length; i++) {
      _drawArrow(canvas, positions[i], forceVectors[i]);
    }
  }
}
```

3. **Graph Overlay**:
   - Suspension travel percentage bar (LinearProgressIndicator)
   - Damping mode indicator (LSC/HSC/Rebound) using badges
   - Spring force numeric display (Text widgets)

```dart
Widget buildStrainOverlay(SuspensionState state) {
  return Column(
    children: [
      LinearProgressIndicator(
        value: state.travelPercent,
        backgroundColor: Colors.grey[800],
        valueColor: AlwaysStoppedAnimation(
          getCompressionColor(state.travelPercent),
        ),
      ),
      Text('Travel: ${state.travelMm.toStringAsFixed(1)} mm'),
      Text('Force: ${state.springForceN.toStringAsFixed(0)} N'),
    ],
  );
}
```

---

## 2. Non-Functional Requirements

### NFR-VZ-001: Performance
**Priority**: CRITICAL
- **Desktop (Windows)**: 60 FPS minimum for 3D rendering and charts
- **Mobile (Android/iOS)**: 30 FPS minimum, 60 FPS target
- **Chart Rendering**: <16ms per frame for 100k points (after downsampling)
- **Memory Usage**: 
  - Desktop: <500MB for full scene + data buffers
  - Mobile: <200MB for optimized scene
- **Startup Time**: <3 seconds on desktop, <5 seconds on mobile

### NFR-VZ-002: Cross-Platform Compatibility
**Priority**: CRITICAL
- **Windows**: Windows 10+ (x64)
- **Android**: API Level 21+ (Android 5.0+)
- **iOS**: iOS 12+
- **Screen Resolutions**: 
  - Desktop: 1280x720 minimum, 4K supported
  - Mobile: 360x640 minimum (phone), tablets supported
- **Responsive Layout**: Adaptive UI for different screen sizes
- **Input Methods**: Touch, mouse, trackpad, keyboard

### NFR-VZ-003: Quality
**Priority**: HIGH
- **Precision**: Double precision for physics calculations
- **Smooth Animations**: 60fps on desktop with AnimationController
- **Anti-aliasing**: Platform default anti-aliasing for Canvas rendering
- **Color Accuracy**: Material Design color system
- **Accessibility**: 
  - Font scaling support
  - High contrast mode
  - Screen reader compatibility (Semantics widgets)

---

## 3. Implementation Details

### API Specification

```dart
/// Main visualization service
class VisualizationService {
  final CameraController camera;
  final ChartDataManager chartData;
  
  VisualizationService({
    required this.camera,
    required this.chartData,
  });
  
  /// Initialize visualization system
  Future<void> initialize() async {
    await _loadModels();
    await _initializeCharts();
  }
  
  /// Load 3D models for suspension components
  Future<void> _loadModels() async {
    // Load OBJ/GLTF models
  }
  
  /// Update suspension geometry based on simulation state
  void updateSuspensionState(SuspensionState state) {
    _frontTravelMm = state.frontTravelMm;
    _rearTravelMm = state.rearTravelMm;
    _wheelRotation = state.wheelRotationRad;
    notifyListeners();
  }
  
  /// Render frame (called by AnimationController)
  void render(Canvas canvas, Size size) {
    _render3DScene(canvas, size);
    _renderOverlays(canvas, size);
  }
}

/// Chart data manager for telemetry visualization
class ChartDataManager {
  final int maxPoints;
  List<FlSpot> _frontTravelData = [];
  List<FlSpot> _rearTravelData = [];
  
  ChartDataManager({this.maxPoints = 100000});
  
  /// Add new data point
  void addDataPoint(double time, double frontMm, double rearMm) {
    _frontTravelData.add(FlSpot(time, frontMm));
    _rearTravelData.add(FlSpot(time, rearMm));
    
    // Downsample if needed
    if (_frontTravelData.length > maxPoints) {
      _frontTravelData = downsampleData(_frontTravelData, maxPoints ~/ 2);
      _rearTravelData = downsampleData(_rearTravelData, maxPoints ~/ 2);
    }
  }
  
  /// Get chart data for specific time range
  ChartData getChartData({
    required double startTime,
    required double endTime,
  }) {
    // Filter and return data
    return ChartData(
      frontTravel: _filterByTime(_frontTravelData, startTime, endTime),
      rearTravel: _filterByTime(_rearTravelData, startTime, endTime),
    );
  }
  
  /// Clear all data
  void clear() {
    _frontTravelData.clear();
    _rearTravelData.clear();
  }
}

/// 3D model loader
class ModelLoader {
  /// Load OBJ model from assets
  static Future<Object3D> loadOBJ(String assetPath) async {
    // Implementation
    throw UnimplementedError();
  }
  
  /// Load GLTF model from assets
  static Future<Object3D> loadGLTF(String assetPath) async {
    // Implementation
    throw UnimplementedError();
  }
}
```

### Data Structures
```dart
class SuspensionState {
  final double frontTravelMm;
  final double rearTravelMm;
  final double frontVelocityMps;
  final double rearVelocityMps;
  final double wheelRotationRad;
  final double timestamp;
  
  SuspensionState({
    required this.frontTravelMm,
    required this.rearTravelMm,
    required this.frontVelocityMps,
    required this.rearVelocityMps,
    required this.wheelRotationRad,
    required this.timestamp,
  });
  
  double get frontTravelPercent => frontTravelMm / 210.0;  // 210mm max
  double get rearTravelPercent => rearTravelMm / 200.0;    // 200mm max
}

class ChartData {
  final List<FlSpot> frontTravel;
  final List<FlSpot> rearTravel;
  final List<FlSpot>? frontVelocity;
  final List<FlSpot>? rearVelocity;
  
  ChartData({
    required this.frontTravel,
    required this.rearTravel,
    this.frontVelocity,
    this.rearVelocity,
  });
}

class Object3D {
  final List<Vector3> vertices;
  final List<Vector3> normals;
  final List<int> indices;
  final Matrix4 transform;
  
  Object3D({
    required this.vertices,
    required this.normals,
    required this.indices,
    Matrix4? transform,
  }) : transform = transform ?? Matrix4.identity();
}
```
    void BeginFrame();
    void RenderScene(const SuspensionState& state);
    void EndFrame();
    
    // Camera control
    void SetCameraMode(CameraMode mode);
    void HandleMouseInput(double x, double y, int button);
    void HandleScrollInput(double delta);
    
    // Suspension updates
    void UpdateSuspensionGeometry(const SuspensionState& front,
                                  const SuspensionState& rear);
    
private:
    GLFWwindow* window;
    ShaderProgram phongShader;
    ShaderProgram lineShader;
    SceneNode rootNode;
    ArcballCamera camera;
    int frameWidth, frameHeight;
};

class ImPlotChart {
public:
    ImPlotChart(const std::string& title, size_t maxPoints = 100000);
    
    void AddSeries(const std::string& name, 
                   const std::vector<float>& xData,
                   const std::vector<float>& yData);
    void Render();
    void SetAxisLimits(float xMin, float xMax, float yMin, float yMax);
    
private:
    std::string title;
    struct Series {
        std::string name;
        std::vector<float> x, y;
    };
    std::vector<Series> dataSeries;
    size_t maxPoints;
};

}
```

---

## 4. Acceptance Criteria

1. **3D Rendering**:
   - [ ] Motorcycle 3D model renders using flutter_cube or CustomPainter
   - [ ] Suspension components animate smoothly with travel changes
   - [ ] Framerate maintains 60 FPS on desktop, 30 FPS on mobile
   - [ ] Camera controls respond to touch/mouse gestures smoothly
   - [ ] Renders correctly on Windows, Android, and iOS

2. **Data Visualization**:
   - [ ] Charts render time series plots with 100k points (downsampled)
   - [ ] Downsampling (LTTB) activates automatically for >10k points
   - [ ] Multi-trace plots display correctly with legend
   - [ ] Zoom/pan interactions responsive (<50ms latency)
   - [ ] Touch gestures work on mobile platforms

3. **Strain Visualization**:
   - [ ] Compression indicator updates in real-time
   - [ ] Color gradient correctly maps compression percentage using Color.lerp
   - [ ] Force vectors display using CustomPaint with correct magnitude/direction
   - [ ] Text overlays readable on all screen sizes

4. **Cross-Platform Compatibility**:
   - [ ] Runs on Windows 10+
   - [ ] Runs on Android 5.0+ (API 21+)
   - [ ] Runs on iOS 12+
   - [ ] Responsive layout adapts to different screen sizes
   - [ ] Performance acceptable on mid-range mobile devices

5. **Performance**:
   - [ ] App startup completes in <5 seconds
   - [ ] Chart updates render in <16ms per frame
   - [ ] Memory usage stays under limits (500MB desktop, 200MB mobile)
   - [ ] No frame drops during animation on target hardware

---

### FR-VZ-008: Comparative Analysis
**Priority**: CRITICAL  
**Description**: Compare original data vs simulated response with different parameters using Flutter charts

**Comparison Views**:

1. **Overlay Mode**:
   - Plot original and simulated on same chart using fl_chart
   - Different line styles (solid vs dashed via isCurved, dashArray)
   - Different colors for each series
   - Interactive legend to show/hide traces

```dart
class ComparisonChart extends StatelessWidget {
  final List<FlSpot> originalData;
  final List<FlSpot> simulatedData;
  
  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: originalData,
            color: Colors.blue,
            barWidth: 2,
            dotData: FlDotData(show: false),
          ),
          LineChartBarData(
            spots: simulatedData,
            color: Colors.orange,
            barWidth: 2,
            dotData: FlDotData(show: false),
            dashArray: [5, 5],  // Dashed line
          ),
        ],
      ),
    );
  }
}
```

2. **Difference Plot**:
   - Show delta between original and simulated
   - Highlight regions with color fill
   - RMS error display in Text widget

3. **Before/After Split View**:
   - Side-by-side Row layout with two charts
   - Synchronized zoom/pan using shared state
   - Same Y-axis scale for fair comparison

4. **Multi-Parameter Comparison**:
   - Compare 3-5 different parameter sets simultaneously
   - Color-coded traces (Material Design color palette)
   - Interactive legend with checkboxes to toggle visibility

### Required Flutter Packages

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 3D Rendering
  flutter_cube: ^0.1.1
  vector_math: ^2.1.4
  
  # Charting
  fl_chart: ^0.65.0
  syncfusion_flutter_charts: ^23.2.4  # Optional, if using Syncfusion
  
  # Math and utilities
  collection: ^1.17.0
  
dev_dependencies:
  flutter_test:
    sdk: flutter
```

**Metrics Display**:
- RMS difference
- Maximum difference
- Correlation coefficient
- Improvement percentage

---

### FR-VZ-003: Histogram and Distribution Plots
**Priority**: HIGH  
**Description**: Statistical distribution of suspension behavior

**Histogram Types**:

1. **Travel Usage Histogram**:
   - X-axis: Suspension displacement (0-210mm)
   - Y-axis: Time spent at each displacement (% or seconds)
   - Shows if suspension is using full travel
   - Identify underused or overused regions

2. **Velocity Distribution**:
   - Compression vs rebound distribution
   - Low-speed vs high-speed percentage
   - Helps tune damping adjustments

3. **Acceleration Distribution**:
   - G-force distribution
   - Identify typical vs extreme events

4. **Force Distribution**:
   - Spring force histogram
   - Damping force histogram

**Features**:
- Bin size adjustment
- Cumulative distribution overlay
- Percentile markers (50th, 90th, 99th)
- Gaussian fit overlay (if applicable)

---

### FR-VZ-004: Phase Plots
**Priority**: MEDIUM  
**Description**: Velocity vs displacement plots (phase space)

**Phase Plot**:
- X-axis: Displacement
- Y-axis: Velocity
- Shows suspension cycles (loops)
- Color-coded by time or force
- Reveals damping characteristics

**Use Cases**:
- Identify hysteresis
- Visualize damping asymmetry
- Detect suspension stiction
- Compare compression/rebound balance

**Features**:
- Density heatmap option (for cluttered data)
- Individual cycle highlighting
- Reference curves (ideal damping)

---

### FR-VZ-005: 3D Trajectory Visualization
**Priority**: MEDIUM  
**Description**: 3D visualization of motorcycle motion

**3D Plot Elements**:
- X-axis: Longitudinal position
- Y-axis: Lateral position
- Z-axis: Altitude (from GPS or integration)
- Motorcycle model overlay
- Suspension travel indicators (color-coded)

**Advanced 3D**:
- Pitch, roll, yaw angles visualized
- Path through turns
- Suspension compression color-mapped on path
- Animation playback of ride

**Controls**:
- Rotate, pan, zoom
- Time scrubber to animate
- Camera presets (top, side, isometric)

---

### FR-VZ-006: Event Markers and Annotations
**Priority**: HIGH  
**Description**: Mark and label significant events in telemetry

**Event Types**:
1. **Bottoming Events**: Red markers at full compression
2. **Topping Events**: Yellow markers at full extension
3. **Hard Braking**: Detected from deceleration (>0.5g)
4. **Hard Acceleration**: Detected from acceleration (>0.3g)
5. **Jumps/Air Time**: Detected from near-zero acceleration
6. **Sharp Turns**: Detected from lateral G-force
7. **User Markers**: Manual annotations by user

**Event Display**:
- Vertical lines on time series
- Icon/symbol on plot
- Tooltip with event details
- Event list panel (click to jump to time)
- Color-coded by severity/type

**Event Filtering**:
- Show/hide by event type
- Filter by severity
- Search events by time range

---

### FR-VZ-007: Dashboard Overview
**Priority**: HIGH  
**Description**: Summary dashboard with key metrics

**Dashboard Widgets**:

1. **Session Summary Card**:
   - Date, duration, distance (if GPS)
   - Terrain type
   - Quality score

2. **Suspension Usage Gauges**:
   - Front travel: % of max used
   - Rear travel: % of max used
   - Radial gauge or progress bar
   - Color: green (good), yellow (marginal), red (issue)

3. **Event Counter**:
   - Number of bottoming events
   - Number of topping events
   - Warning if excessive

4. **Sag Indicator**:
   - Current sag vs target range
   - Visual bar with target zone highlighted

5. **Performance Score**:
   - Overall suspension tuning score (0-100)
   - Based on travel usage, events, balance

6. **Quick Stats**:
   - Max G-forces (vertical, lateral, longitudinal)
   - Max suspension speed
   - Average travel used

**Layout**:
- Grid layout (2-3 columns)
- Responsive for different screen sizes
- Click widget to drill down to detailed view

---

### FR-VZ-008: Heatmaps
**Priority**: MEDIUM  
**Description**: 2D heatmap visualizations

**Heatmap Types**:

1. **Time vs Frequency Heatmap** (Spectrogram):
   - X-axis: Time
   - Y-axis: Frequency (Hz)
   - Color: Power spectral density
   - Identify resonant frequencies, vibrations

2. **Travel vs Velocity Heatmap**:
   - X-axis: Displacement
   - Y-axis: Velocity
   - Color: Time spent in each region
   - Shows damping effectiveness

3. **GPS Track Heatmap** (if GPS available):
   - Map overlay with color-coded speed or G-forces
   - Identify challenging sections

**Features**:
- Color scale adjustment
- Logarithmic scale option
- Export as image

---

### FR-VZ-009: Parameter Sensitivity Plots
**Priority**: MEDIUM  
**Description**: Show how metrics change with parameter adjustments

**Sensitivity Analysis**:
- X-axis: Parameter value (e.g., compression damping clicks)
- Y-axis: Performance metric (e.g., # bottoming events)
- Multiple metrics on same plot (dual Y-axis)

**Use Cases**:
- Find optimal damping setting
- Understand parameter interactions
- Guide tuning decisions

**Example**:
- "How does changing rebound damping affect travel usage?"
- Plot: Rebound clicks (X) vs Average travel (Y1) and Bottoming events (Y2)

---

### FR-VZ-010: Export and Reporting
**Priority**: HIGH  
**Description**: Generate reports and export visualizations

**Export Formats**:
- **Images**: PNG, SVG, PDF
- **Data**: CSV, Excel, JSON
- **Report**: HTML, PDF multi-page report

**Report Contents**:
1. Session metadata
2. Dashboard summary
3. Key plots (travel, velocity, forces)
4. Event log
5. Recommendations (if applicable)

**Report Templates**:
- Quick summary (1-page)
- Detailed analysis (multi-page)
- Comparison report (before/after tuning)

**Sharing**:
- Save report to file
- Print
- Optional: Share link (if cloud storage)

---

## 2. Non-Functional Requirements

### NFR-VZ-001: Interactivity
**Priority**: HIGH
- Plot updates <100ms after parameter change
- Smooth pan/zoom (60fps minimum)
- Responsive hover tooltips (<50ms delay)
- Handle datasets with 500k+ points without lag

---

### NFR-VZ-002: Aesthetics
**Priority**: MEDIUM
- Professional, clean visual design
- Consistent color scheme (configurable theme)
- Clear labels, legends, and units
- Accessibility: colorblind-friendly palettes
- Dark mode support

---

### NFR-VZ-003: Usability
**Priority**: HIGH
- Intuitive controls (standard zoom/pan conventions)
- Clear visual hierarchy
- Tooltips and help text
- Undo/redo for view changes
- Reset zoom button

---

### NFR-VZ-004: Performance
**Priority**: HIGH
- Render 1-hour session (720k samples) in <2 seconds
- Downsampling for display (show peaks/valleys)
- WebGL acceleration for large datasets
- Lazy rendering (only visible time range)

---

### NFR-VZ-005: Responsive Design
**Priority**: MEDIUM
- Adapt to screen sizes: desktop, tablet, mobile
- Touch-friendly controls
- Minimum resolution: 1024x768
- Optimal: 1920x1080+

---

## 3. Technology Recommendations

### Visualization Libraries (Python)

**Option 1: Plotly** (Recommended)
- Interactive web-based plots
- Supports zooming, panning, hover
- Good performance with downsampling
- Export to PNG, SVG, HTML
- Works with Streamlit/Dash

**Option 2: Matplotlib + mpld3**
- Static plots with web interactivity
- Highly customizable
- Good for publication-quality figures

**Option 3: Bokeh**
- Interactive server-side Python plots
- Great for streaming data
- Responsive and modern

**Option 4: PyQtGraph** (for desktop app)
- High-performance Qt-based plotting
- Real-time updates
- Desktop-only (PyQt/PySide)

### 3D Visualization
- **Plotly 3D**: Web-based 3D
- **Mayavi/VTK**: Advanced 3D (desktop)
- **Three.js**: Web-based custom 3D (JavaScript)

---

## 4. Chart Specifications

### Standard Chart Template
```python
{
    "title": "Front Suspension Travel",
    "x_axis": {
        "label": "Time (s)",
        "range": [0, "auto"],
        "grid": True
    },
    "y_axis": {
        "label": "Displacement (mm)",
        "range": [0, 210],
        "grid": True
    },
    "traces": [
        {
            "name": "Actual",
            "data": {"x": [...], "y": [...]},
            "color": "#1f77b4",
            "line_width": 1.5,
            "mode": "lines"
        },
        {
            "name": "Simulated",
            "data": {"x": [...], "y": [...]},
            "color": "#ff7f0e",
            "line_width": 1.5,
            "line_dash": "dash",
            "mode": "lines"
        }
    ],
    "annotations": [
        {
            "type": "hline",
            "y": 35,
            "label": "Static Sag",
            "color": "green",
            "dash": "dot"
        }
    ],
    "interactive": True,
    "toolbar": ["pan", "zoom", "reset", "download"]
}
```

---

## 5. Color Scheme

### Default Palette
```python
COLORS = {
    "front_suspension": "#1f77b4",  # Blue
    "rear_suspension": "#ff7f0e",   # Orange
    "simulated": "#2ca02c",         # Green
    "actual": "#d62728",            # Red
    "spring_force": "#9467bd",      # Purple
    "damping_force": "#8c564b",     # Brown
    "bottoming": "#e377c2",         # Pink
    "topping": "#bcbd22",           # Olive
    "warning": "#ffbb00",           # Amber
    "error": "#ff0000",             # Red
    "success": "#00cc00",           # Green
}
```

### Accessibility
- Use line dash styles in addition to colors
- Provide labels, not just color coding
- Minimum contrast ratio: 4.5:1

---

## 6. API Specification

### Visualization API
```python
class Visualizer:
    """Create interactive visualizations."""
    
    def plot_time_series(
        self,
        data: Union[RideSession, SimulationResult],
        traces: List[str] = ["displacement", "velocity"],
        title: str = None,
        interactive: bool = True
    ) -> Figure:
        """Create time series plot."""
        pass
    
    def plot_comparison(
        self,
        original: SimulationResult,
        simulated: SimulationResult,
        metric: str = "displacement"
    ) -> Figure:
        """Create comparison plot (original vs simulated)."""
        pass
    
    def plot_histogram(
        self,
        data: np.ndarray,
        bins: int = 50,
        title: str = None
    ) -> Figure:
        """Create histogram/distribution plot."""
        pass
    
    def plot_phase_diagram(
        self,
        displacement: np.ndarray,
        velocity: np.ndarray,
        color_by: str = "time"
    ) -> Figure:
        """Create phase space plot (velocity vs displacement)."""
        pass
    
    def create_dashboard(
        self,
        session: RideSession,
        simulation: SimulationResult = None
    ) -> Dashboard:
        """Create summary dashboard."""
        pass
    
    def export_report(
        self,
        session: RideSession,
        simulation: SimulationResult,
        output_path: Path,
        format: str = "pdf"
    ):
        """Generate and export analysis report."""
        pass
```

---

## 7. Dashboard Layout

### Main Dashboard Structure
```
┌─────────────────────────────────────────────────────────────┐
│  Session: Tenere_2026-03-07_Morning  │  Quality: 92/100    │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Travel  │  │  Events  │  │   Sag    │  │  Score   │   │
│  │  Usage   │  │  Count   │  │  Check   │  │  85/100  │   │
│  │  Front   │  │ Bottom:3 │  │  Front   │  │          │   │
│  │  [████░]│  │  Top: 1  │  │  [████]  │  │  [████]  │   │
│  │  Rear    │  │          │  │  Rear    │  │          │   │
│  │  [█████]│  │          │  │  [████]  │  │          │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Suspension Travel vs Time                                  │
│  [═══════════════════════════════════════════════════════] │
│  Front ─── Rear ───                                         │
├─────────────────────────────────────────────────────────────┤
│  Suspension Velocity                                        │
│  [═══════════════════════════════════════════════════════] │
│  Compression | Rebound                                      │
├─────────────────────────────────────────────────────────────┤
│  [Travel Histogram]      [Velocity Distribution]            │
│  [════════════════]      [════════════════]                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Testing & Validation

### Test Cases

- **UT-VZ-001**: Render time series with 100k points
- **UT-VZ-002**: Zoom and pan interaction
- **UT-VZ-003**: Export plot to PNG
- **UT-VZ-004**: Toggle trace visibility
- **UT-VZ-005**: Hover tooltip displays correct values
- **UT-VZ-006**: Event markers render at correct times
- **UT-VZ-007**: Dashboard calculates metrics correctly
- **UT-VZ-008**: Histogram bins data correctly
- **UT-VZ-009**: Comparison plot aligns timelines
- **UT-VZ-010**: Report export generates valid PDF

### Performance Tests

- **PT-VZ-001**: Render 1M points in <5 seconds
- **PT-VZ-002**: Pan/zoom remains smooth (>30 fps)
- **PT-VZ-003**: Dashboard loads in <2 seconds

---

## 9. Acceptance Criteria

- [ ] Display time series plots for displacement, velocity, forces
- [ ] Compare actual vs simulated data on same chart
- [ ] Interactive zoom, pan, and tooltips work smoothly
- [ ] Dashboard shows key metrics at-a-glance
- [ ] Event markers displayed on plots
- [ ] Histogram and distribution plots render correctly
- [ ] Export plots as PNG/SVG
- [ ] Generate PDF report with plots and metrics
- [ ] Support dark/light themes
- [ ] Handle 1-hour sessions (720k points) without lag

---

## 10. Future Enhancements

- **Real-time Visualization**: Live plotting during data collection
- **Machine Learning Insights**: Anomaly highlighting, pattern detection
- **Comparative Database**: Compare session to historical data
- **Video Overlay**: Sync telemetry with onboard video
- **GPS Map Integration**: Plot telemetry on map (if GPS available)
- **Custom Dashboards**: User-configurable widgets
- **Multi-Session Comparison**: Compare multiple rides
- **Weather Overlay**: Show temperature, rain, wind conditions
- **Tire Pressure Correlation**: If TPMS data available
- **Social Sharing**: Share visualizations to social media
- **AR Visualization**: Augmented reality suspension view (mobile)
