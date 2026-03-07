# Component 5: UI & Parameter Tuning Requirements (Flutter)

## Overview
The User Interface and Parameter Tuning module provides a modern, responsive GUI using Flutter with Material Design 3. It enables users to import ride data, adjust suspension parameters, visualize results in real-time, and analyze ride sessions through an integrated 3D viewport and 2D telemetry charts. The UI is cross-platform compatible with Windows, Android, and iOS.

---

## 1. Technology Stack

### GUI Framework: Flutter
- **Version**: Flutter 3.x
- **Design System**: Material Design 3
- **State Management**: Provider, Riverpod, or Bloc
- **File Selection**: file_picker package
- **Navigation**: Navigator 2.0 with named routes
- **Responsive Design**: LayoutBuilder, MediaQuery for adaptive layouts

### Key Features
- **Declarative UI**: Widget tree-based composition
- **Hot Reload**: Fast iteration during development
- **Adaptive Layout**: Responsive design for desktop, tablet, mobile
- **State Persistence**: SharedPreferences for settings
- **Theming**: Light/Dark theme toggle with Material 3 ColorScheme
- **Platform Integration**: Native look and feel on each platform

---

## 2. Functional Requirements

### FR-UI-001: Application Structure and Main Layout
**Priority**: CRITICAL  
**Description**: Initialize Flutter app with Material 3 design and responsive layout

**Main Application Structure**:
```dart
class RideMetricXApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideMetricX',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: MainScreen(),
      routes: {
        '/import': (context) => ImportScreen(),
        '/session': (context) => SessionDetailScreen(),
        '/settings': (context) => SettingsScreen(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _screens = [
    SessionBrowserScreen(),
    VisualizationScreen(),
    ParameterTuningScreen(),
    AnalysisScreen(),
  ];
  
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('RideMetricX'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_upload),
            onPressed: () => Navigator.pushNamed(context, '/import'),
            tooltip: 'Import Session',
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Sessions'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.show_chart_outlined),
                      selectedIcon: Icon(Icons.show_chart),
                      label: Text('Visualize'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('Tuning'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: Text('Analysis'),
                    ),
                  ],
                ),
                VerticalDivider(width: 1),
                Expanded(child: _screens[_selectedIndex]),
              ],
            )
          : _screens[_selectedIndex],
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Sessions',
                ),
                NavigationDestination(
                  icon: Icon(Icons.show_chart_outlined),
                  selectedIcon: Icon(Icons.show_chart),
                  label: 'Visualize',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Tuning',
                ),
                NavigationDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics),
                  label: 'Analysis',
                ),
              ],
            ),
    );
  }
}
```

**App Bar with Menu**:
```dart
AppBar(
  title: Text('RideMetricX'),
  actions: [
    PopupMenuButton<String>(
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'new',
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('New Session'),
          ),
        ),
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Open Session'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.save),
            title: Text('Export...'),
          ),
        ),
      ],
      onSelected: (value) {
        // Handle menu selection
      },
    ),
  ],
)
```

---

### FR-UI-002: File Import Screen and Workflow
**Priority**: CRITICAL  
**Description**: Provide file picker and import configuration UI using Flutter widgets

**Import Screen**:
```dart
import 'package:file_picker/file_picker.dart';

class ImportScreen extends StatefulWidget {
  @override
  _ImportScreenState createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  File? frontFile;
  File? rearFile;
  DataFormat detectedFormat = DataFormat.csv;
  bool isImporting = false;
  double importProgress = 0.0;
  
  Future<void> _pickFrontFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'bin', 'json'],
    );
    
    if (result != null) {
      setState(() {
        frontFile = File(result.files.single.path!);
        detectedFormat = _detectFormat(frontFile!);
      });
    }
  }
  
  Future<void> _startImport() async {
    if (frontFile == null || rearFile == null) return;
    
    setState(() => isImporting = true);
    
    final importService = context.read<DataImportService>();
    
    await for (final progress in importService.importSession(
      frontFile: frontFile!,
      rearFile: rearFile!,
      format: detectedFormat,
    )) {
      setState(() => importProgress = progress.percent);
    }
    
    setState(() => isImporting = false);
    Navigator.pop(context);  // Return to main screen
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Import Session')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // File selection UI
            ListTile(
              title: Text('Front Fork Data'),
              subtitle: frontFile != null ? Text(frontFile!.path) : null,
              trailing: ElevatedButton(
                onPressed: _pickFrontFile,
                child: Text('Browse...'),
              ),
            ),
            // Import button
            if (isImporting)
              LinearProgressIndicator(value: importProgress / 100),
          ],
        ),
      ),
    );
  }
}
```

---

### FR-UI-003: Session Management Screen
**Priority**: CRITICAL  
**Description**: Browse and manage ride sessions using Flutter ListView

**Session Browser with ListView**:
```dart
class SessionBrowserScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SessionRepository>(
      builder: (context, repo, child) {
        final sessions = repo.getSessions();
        
        return ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('${session.qualityScore.toInt()}'),
                ),
                title: Text(session.metadata.date.toString()),
                subtitle: Text('Duration: ${session.metadata.durationSeconds}s'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () => repo.deleteSession(session.id),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pushNamed(context, '/session', arguments: session);
                },
              ),
            );
          },
        );
      },
    );
  }
}
```
        
        for (const auto& session : sessionList) {
            ImGui::TableNextRow();
            ImGui::TableSetColumnIndex(0);
            ImGui::TextUnformatted(session.date.c_str());
            
            ImGui::TableSetColumnIndex(1);
            ImGui::Text("%.1f min", session.duration_sec / 60.0f);
            
            ImGui::TableSetColumnIndex(2);
            ImGui::ProgressBar(session.quality / 100.0f);
            
            ImGui::TableSetColumnIndex(3);
            if (ImGui::Button(TextFormat("Open##%zu", session.id))) {
                LoadSession(session.id);
            }
            ImGui::SameLine();
            if (ImGui::Button(TextFormat("Delete##%zu", session.id))) {
                DeleteSession(session.id);
            }
        }
        ImGui::EndTable();
    }
    
    ImGui::End();
}
```

**Operations**:
- New Session: Opens import dialog
- Open Session: Loads session data and updates viewports
- Delete Session: Confirmation dialog then removes files
- Export Session: File picker for CSV/JSON/HDF5 export

---

### FR-UI-004: Real-Time 3D Viewport
**Priority**: CRITICAL  
**Description**: Embedded OpenGL viewport showing motorcycle suspension

**Viewport Window**:
```cpp
if (showViewport) {
    ImGui::SetNextWindowSize(ImVec2(800, 600), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("3D Suspension Viewer", &showViewport, 
                     ImGuiWindowFlags_NoScrollbar)) {
        
        // Get window dimensions
        ImVec2 viewportSize = ImGui::GetContentRegionAvail();
        ImVec2 viewportPos = ImGui::GetCursorScreenPos();
        
        // Render OpenGL scene to framebuffer
        renderer.RenderToFramebuffer((int)viewportSize.x, 
                                     (int)viewportSize.y);
        
        // Draw as image in ImGui
        ImGui::Image((void*)(intptr_t)renderer.GetFramebufferTexture(),
                     viewportSize,
                     ImVec2(0, 1), ImVec2(1, 0));  // Flip Y for GL texture
        
        // Input handling
        if (ImGui::IsItemHovered()) {
            ImGuiIO& io = ImGui::GetIO();
            renderer.HandleMouseInput(
                io.MousePos.x - viewportPos.x,
                io.MousePos.y - viewportPos.y,
                ImGui::IsMouseDown(ImGuiMouseButton_Right)
            );
            if (io.MouseWheel != 0) {
                renderer.HandleScrollInput(io.MouseWheel);
            }
        }
        
        // Camera controls info
        ImGui::TextDisabled("Right-click drag to rotate | Scroll to zoom");
        
        // Overlay info
        ImGui::GetForegroundDrawList()->AddText(
            ImVec2(viewportPos.x + 10, viewportPos.y + 10),
            IM_COL32(255, 255, 255, 255),
            TextFormat("FPS: %.1f | Tris: %d", 
                      io.Framerate, renderer.GetTriangleCount())
        );
        
        ImGui::End();
    }
}
```

**Viewport Controls**:
- Right-click drag: Arcball camera rotation
- Scroll wheel: Zoom in/out
- Camera mode toggle: Front/Side/Top/Rider POV buttons
- Info overlay: FPS, triangle count, camera position

---

### FR-UI-005: Parameter Tuning Panel
**Priority**: CRITICAL  
**Description**: Interactive suspension parameter adjustment

**Tuning Window**:
```cpp
if (showTuning) {
    ImGui::SetNextWindowSize(ImVec2(350, 700), ImGuiCond_FirstUseEver);
    ImGui::Begin("Suspension Tuning", &showTuning);
    
    // Presets dropdown
    const char* presets[] = { "Default", "Soft", "Medium", "Stiff", 
                              "Track", "Offroad", "Custom" };
    static int presetIdx = 0;
    if (ImGui::Combo("Preset", &presetIdx, presets, 
                     IM_ARRAYSIZE(presets))) {
        ApplySuspensionPreset(presets[presetIdx]);
    }
    
    ImGui::Separator();
    ImGui::Spacing();
    
    // FRONT SUSPENSION
    if (ImGui::CollapsingHeader("Front Suspension", 
                               ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Indent();
        
        static float frontSpringRate = 9.0f;
        ImGui::SliderFloat("Spring Rate (N/mm)##front", 
                          &frontSpringRate, 6.0f, 15.0f);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.springRate = frontSpringRate;
            TriggerSimulation();
        }
        
        static int frontPreload = 10;
        ImGui::SliderInt("Preload (mm)##front", 
                        &frontPreload, 0, 30);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.preload = (float)frontPreload;
            TriggerSimulation();
        }
        
        // Damping controls (clicks 0-20)
        static int frontLSC = 10;
        ImGui::SliderInt("Comp. LSC (clicks)##front", 
                        &frontLSC, 0, 20);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.compressionLSC = (float)frontLSC;
            TriggerSimulation();
        }
        
        static int frontHSC = 10;
        ImGui::SliderInt("Comp. HSC (clicks)##front", 
                        &frontHSC, 0, 20);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.compressionHSC = (float)frontHSC;
            TriggerSimulation();
        }
        
        static int frontRebL = 12;
        ImGui::SliderInt("Rebound L (clicks)##front", 
                        &frontRebL, 0, 20);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.reboundLow = (float)frontRebL;
            TriggerSimulation();
        }
        
        static int frontRebH = 12;
        ImGui::SliderInt("Rebound H (clicks)##front", 
                        &frontRebH, 0, 20);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.front.reboundHigh = (float)frontRebH;
            TriggerSimulation();
        }
        
        ImGui::Spacing();
        if (ImGui::Button("Reset Front to Default")) {
            suspensionParams.front = GetDefaultSuspension().front;
            TriggerSimulation();
        }
        
        ImGui::Unindent();
    }
    
    ImGui::Spacing();
    
    // REAR SUSPENSION
    if (ImGui::CollapsingHeader("Rear Suspension", 
                               ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Indent();
        
        static float rearSpringRate = 95.0f;
        ImGui::SliderFloat("Spring Rate (N/mm)##rear", 
                          &rearSpringRate, 70.0f, 150.0f);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.rear.springRate = rearSpringRate;
            TriggerSimulation();
        }
        
        static int rearPreload = 5;
        ImGui::SliderInt("Preload (mm)##rear", 
                        &rearPreload, 0, 20);
        if (ImGui::IsItemDeactivatedAfterEdit()) {
            suspensionParams.rear.preload = (float)rearPreload;
            TriggerSimulation();
        }
        
        // Rear damping (similar structure)
        // ... (damping controls for rear)
        
        ImGui::Unindent();
    }
    
    ImGui::Spacing();
    ImGui::Separator();
    
    // Auto-run mode toggle
    static bool autoRun = false;
    ImGui::Checkbox("Auto-Run Simulation", &autoRun);
    
    // Simulation button
    if (ImGui::Button("Run Simulation##main", ImVec2(-1, 0))) {
        RunSimulation();
    }
    
    // Status
    if (isSimulating) {
        ImGui::TextColored(ImVec4(1, 1, 0, 1), 
                          "Simulating... %.0f%%", simulationProgress);
        ImGui::ProgressBar(simulationProgress / 100.0f);
    } else {
        ImGui::TextColored(ImVec4(0, 1, 0, 1), "Ready");
    }
    
    ImGui::End();
}
```

**Input Debouncing**:
```cpp
static ImGuiInputTextFlags flags = ImGuiInputTextFlags_CallbackCharFilter;
const float DEBOUNCE_TIME = 0.5f;
static float lastUpdateTime = 0.0f;

if (ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
    float currentTime = ImGui::GetTime();
    if (currentTime - lastUpdateTime > DEBOUNCE_TIME) {
        TriggerSimulation();
        lastUpdateTime = currentTime;
    }
}
```

---

### FR-UI-006: Telemetry Charts Panel
**Priority**: CRITICAL  
**Description**: Display multi-plot telemetry data using ImPlot

**Charts Window**:
```cpp
if (showCharts) {
    ImGui::SetNextWindowSize(ImVec2(1000, 600), ImGuiCond_FirstUseEver);
    ImGui::Begin("Telemetry Analysis", &showCharts);
    
    // Chart selection tabs
    static const char* const chartTabs[] = { 
        "Suspension", "Acceleration", "Damping", "Comparison" 
    };
    static int selectedChart = 0;
    ImGui::RadioButton(chartTabs[0], &selectedChart, 0); ImGui::SameLine();
    ImGui::RadioButton(chartTabs[1], &selectedChart, 1); ImGui::SameLine();
    ImGui::RadioButton(chartTabs[2], &selectedChart, 2); ImGui::SameLine();
    ImGui::RadioButton(chartTabs[3], &selectedChart, 3);
    
    ImGui::Separator();
    
    // Suspension Travel Plot
    if (selectedChart == 0) {
        if (ImPlot::BeginPlot("Suspension Travel", "Time (s)", "Travel (mm)", 
                             ImVec2(-1, -1))) {
            ImPlot::SetNextLineStyle(ImVec4(0, 1, 0, 1), 2.0f);
            ImPlot::PlotLine("Front", &timeData[0], &frontTravel[0], 
                            dataCount);
            
            ImPlot::SetNextLineStyle(ImVec4(1, 0, 0, 1), 2.0f);
            ImPlot::PlotLine("Rear", &timeData[0], &rearTravel[0], 
                            dataCount);
            
            // Add reference lines for sag
            ImPlot::PlotHLines("Sag Reference", &sagValues[0], 2);
            
            ImPlot::EndPlot();
        }
    }
    
    // Acceleration Plot
    if (selectedChart == 1) {
        if (ImPlot::BeginPlot("Acceleration", "Time (s)", "Accel (g's)", 
                             ImVec2(-1, -1))) {
            ImPlot::PlotLine("Front X", &timeData[0], &frontAccelX[0], 
                            dataCount);
            ImPlot::PlotLine("Front Y", &timeData[0], &frontAccelY[0], 
                            dataCount);
            ImPlot::PlotLine("Front Z", &timeData[0], &frontAccelZ[0], 
                            dataCount);
            ImPlot::EndPlot();
        }
    }
    
    // Damping Comparison (Original vs Simulated)
    if (selectedChart == 3) {
        if (ImPlot::BeginPlot("Damping: Measured vs Simulated", 
                             "Velocity (m/s)", "Force (N)", 
                             ImVec2(-1, -1))) {
            ImPlot::PlotScatter("Measured", &measuredVel[0], 
                               &measuredDampingForce[0], measuredCount);
            ImPlot::PlotLine("Simulated", &simVel[0], 
                            &simDampingForce[0], simCount);
            ImPlot::EndPlot();
        }
    }
    
    ImGui::End();
}
```

**Export Plot Function**:
```cpp
if (ImGui::IsPlotHovered() && ImGui::IsMouseDoubleClicked(0)) {
    ExportPlotAsImage("plot_export.png");
}
```

---

### FR-UI-007: Comparison and Analysis
**Priority**: HIGH  
**Description**: Compare multiple simulations and analyze differences

**Comparison Panel**:
```cpp
if (showComparison) {
    ImGui::Begin("Comparison Tool", &showComparison);
    
    ImGui::Text("Baseline Configuration:");
    ImGui::TextUnformatted(baselineConfig.c_str());
    
    ImGui::Text("Test Configuration:");
    ImGui::TextUnformatted(testConfig.c_str());
    
    ImGui::Separator();
    ImGui::Text("Differences:");
    
    // Display differences in table
    if (ImGui::BeginTable("comparison", 3, ImGuiTableFlags_Borders)) {
        ImGui::TableSetupColumn("Metric");
        ImGui::TableSetupColumn("Baseline");
        ImGui::TableSetupColumn("Test");
        ImGui::TableHeadersRow();
        
        for (const auto& metric : comparisonMetrics) {
            ImGui::TableNextRow();
            ImGui::TableSetColumnIndex(0);
            ImGui::TextUnformatted(metric.name.c_str());
            ImGui::TableSetColumnIndex(1);
            ImGui::Text("%.2f", metric.baselineValue);
            ImGui::TableSetColumnIndex(2);
            ImGui::Text("%.2f", metric.testValue);
        }
        ImGui::EndTable();
    }
    
    ImGui::End();
}
```

---

## 3. Non-Functional Requirements

### NFR-UI-001: Performance
**Priority**: CRITICAL
- ImGui frame rate: 60+ FPS
- Slider response latency: <50ms
- Chart rendering with 1M points: <2ms
- Memory usage: <100MB for UI state
- Startup time: <2 seconds

### NFR-UI-002: Responsiveness
**Priority**: CRITICAL
- Simulation triggers non-blocking (background thread)
- Parameter updates immediate visual feedback
- No UI freezing during long operations
- Cancel button always responsive

### NFR-UI-003: Accessibility
**Priority**: HIGH
- Font size adjustable (12-20pt)
- High contrast theme available
- Keyboard navigation support
- Tooltips for all controls
- Clear error messages

### NFR-UI-004: Persistence
**Priority**: HIGH
- Save window layout (imgui.ini)
- Remember last session
- Preserve parameter presets
- Remember file browser paths

---

## 4. Implementation Architecture

### ImGui Integration Pattern
```cpp
class UIManager {
private:
    ImGuiContext* context;
    ImGuiIO* io;
    ImGuiStyle* style;
    GLFWwindow* window;
    
public:
    void Initialize(GLFWwindow* win) {
        IMGUI_CHECKVERSION();
        context = ImGui::CreateContext();
        ImGui::SetCurrentContext(context);
        
        io = &ImGui::GetIO();
        io->ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
        io->ConfigFlags |= ImGuiConfigFlags_DockingEnable;
        io->ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;
        
        ImGui_ImplGlfw_InitForOpenGL(win, true);
        ImGui_ImplOpenGL3_Init("#version 460");
        
        LoadTheme();
    }
    
    void BeginFrame() {
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        ImGui::DockSpaceOverViewport(ImGui::GetMainViewport());
    }
    
    void EndFrame() {
        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        
        if (io->ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
            ImGui::UpdatePlatformWindows();
            ImGui::RenderPlatformWindowsDefault();
        }
    }
};
```

### Data Flow
```
User Input (slider/button)
    ↓
ImGui detects change
    ↓
Callback updates suspensionParams
    ↓
TriggerSimulation() called (with debounce)
    ↓
Background thread runs physics simulation
    ↓
Results written to shared buffer
    ↓
Next frame: Update plots with new data
    ↓
Viewport updates suspension geometry representation
```

---

## 5. Acceptance Criteria

1. **UI Initialization**:
   - [ ] ImGui context initializes without errors
   - [ ] Main window opens with 1600x900 resolution minimum
   - [ ] Menu bar displays all menu items
   - [ ] Docking works; windows can be rearranged
   - [ ] Layout persists between sessions

2. **File Import**:
   - [ ] File picker opens and accepts CSV/BIN files
   - [ ] Progress indicator shows during import
   - [ ] Validation report displays clearly
   - [ ] Success notification appears on completion
   - [ ] Data preview renders correctly

3. **Parameter Tuning**:
   - [ ] All sliders respond to user input immediately
   - [ ] Invalid values prevented (validation)
   - [ ] Presets load correctly
   - [ ] Reset button restores defaults
   - [ ] Simulation triggers on parameter change

4. **Visualization**:
   - [ ] 3D viewport renders motorcycle model
   - [ ] Suspension deformation updates as simulation runs
   - [ ] ImPlot charts render with 1M+ points
   - [ ] Charts responsive to zoom/pan
   - [ ] Comparison view shows differences correctly

5. **Performance**:
   - [ ] UI maintains 60 FPS during interaction
   - [ ] Simulation runs in background without UI blocking
   - [ ] Memory usage stays below 100MB
   - [ ] Startup completes in <2 seconds

6. **User Experience**:
   - [ ] All controls have descriptive tooltips
   - [ ] Error messages are clear and actionable
   - [ ] Keyboard shortcuts work for common operations
   - [ ] Responsive feedback for all interactions

**Comparison Features**:

1. **Snapshot Management**:
   - Save current simulation as "Snapshot A"
   - Adjust parameters
   - Save as "Snapshot B"
   - Compare A vs B side-by-side

2. **Multi-Comparison**:
   - Compare up to 5 snapshots
   - Label each (e.g., "Stock", "Soft", "Stiff", "Optimal")
   - Color-coded traces on same plot

3. **Difference View**:
   - Show delta metrics in table
   - Highlight improvements (green) vs regressions (red)

**Comparison Table**:
```
┌────────────┬────────┬────────┬────────┬──────────┐
│ Metric     │ Stock  │ Soft   │ Stiff  │ Optimal  │
├────────────┼────────┼────────┼────────┼──────────┤
│ Bottoming  │   12   │   3 ↓  │  15 ↑  │   2 ↓↓   │
│ Max Travel │ 195mm  │ 210mm  │ 175mm  │  190mm   │
│ Avg Travel │  65mm  │  75mm  │  55mm  │   68mm   │
│ Comfort    │   72   │  85 ↑  │  60 ↓  │   80 ↑   │
└────────────┴────────┴────────┴────────┴──────────┘
```

---

### FR-UI-007: Recommendations Engine
**Priority**: MEDIUM  
**Description**: Suggest parameter adjustments based on data analysis

**Recommendation Logic**:

1. **Bottoming Too Much**:
   - Suggest: Increase compression damping or stiffer spring
   - Severity: HIGH if >10 events, MEDIUM if 5-10, LOW if <5

2. **Not Using Full Travel**:
   - Suggest: Decrease compression damping or softer spring
   - Severity: MEDIUM if using <70% of travel

3. **Harsh Ride**:
   - Detected: High-frequency chassis acceleration
   - Suggest: Decrease compression damping, check tire pressure

4. **Too Much Rebound**:
   - Detected: Oscillations, slow settlement
   - Suggest: Increase rebound damping

5. **Imbalanced Front/Rear**:
   - Detected: Front using 90% travel, rear using 60%
   - Suggest: Adjust to balance usage

**Recommendation Display**:
```
┌───────────────────────────────────────────────────┐
│  💡 RECOMMENDATIONS                               │
├───────────────────────────────────────────────────┤
│  ⚠️  HIGH: Bottoming detected 12 times            │
│     → Increase rear compression damping by 3-5    │
│        clicks                                     │
│     [Apply Suggestion]                            │
│                                                   │
│  ℹ️  MEDIUM: Front travel underutilized (65%)     │
│     → Consider decreasing preload by 5mm          │
│     [Apply Suggestion]                            │
│                                                   │
│  ✓  GOOD: Sag settings within optimal range      │
└───────────────────────────────────────────────────┘
```

**Features**:
- Auto-generate on simulation complete
- Prioritize by severity
- One-click apply suggestion
- Explain reasoning (expandable details)
- Learn from user feedback (optional)

---

### FR-UI-008: Preset Management
**Priority**: MEDIUM  
**Description**: Save and load suspension setup presets

**Preset Types**:

1. **Factory Presets** (read-only):
   - Stock (manufacturer default)
   - Soft (comfort, touring)
   - Medium (balanced, road)
   - Stiff (sport, track)
   - Off-road (loose terrain)

2. **User Presets**:
   - Save current settings with name
   - Edit existing preset
   - Delete preset
   - Export/import presets (JSON)

**Preset Browser**:
- List view with preview
- Metadata: Name, Date Created, Terrain Type
- Apply preset with one click
- Tag presets (e.g., "gravel", "fast riding", "passenger")

---

### FR-UI-009: Help and Documentation
**Priority**: MEDIUM  
**Description**: Integrated help system and tutorials

**Help Features**:

1. **Tooltips**:
   - Hover over any parameter for explanation
   - Include recommended range
   - Link to detailed docs

2. **Context Help**:
   - Press F1 to show help for current screen
   - Searchable help index

3. **Interactive Tutorials**:
   - First-time user walkthrough
   - "How to tune compression damping"
   - "Interpreting travel histograms"

4. **Documentation**:
   - Built-in user manual (HTML/PDF)
   - Glossary of terms
   - FAQ section

5. **Video Tutorials** (optional):
   - Embedded or linked videos
   - Screen recordings of common tasks

---

### FR-UI-010: Settings and Preferences
**Priority**: MEDIUM  
**Description**: Application configuration and user preferences

**Settings Categories**:

1. **General**:
   - Default data directory
   - Auto-save interval
   - Check for updates
   - Language (if multi-language)

2. **Appearance**:
   - Theme: Light, Dark, Auto (system)
   - Color palette
   - Font size
   - Plot style preferences

3. **Units**:
   - Distance: mm, inches
   - Weight: kg, lbs
   - Force: N, lbf
   - Temperature: °C, °F

4. **Advanced**:
   - Simulation parameters (time step, solver)
   - Filter defaults
   - Performance tuning (threads, memory)
   - Debug logging

5. **Motorcycle Profile**:
   - Model selection
   - Custom specifications (if not in database)
   - Suspension geometry details

**Settings UI**:
- Tabbed or sidebar navigation
- Search settings
- Reset to defaults option
- Apply and save

---

## 2. Non-Functional Requirements

### NFR-UI-001: Usability
**Priority**: CRITICAL
- Intuitive interface, learnable in <30 minutes
- Consistent design language
- Minimal clicks to common tasks (≤3 clicks)
- Keyboard shortcuts for power users
- Undo/redo for all actions

---

### NFR-UI-002: Responsiveness
**Priority**: HIGH
- UI responds to user input <100ms
- No freezing during long operations
- Progress feedback for operations >1 second
- Async/background processing for heavy tasks

---

### NFR-UI-003: Accessibility
**Priority**: MEDIUM
- Keyboard navigation for all functions
- Screen reader compatibility (if web-based)
- Colorblind-friendly visualizations
- Adjustable font sizes
- High contrast mode

---

### NFR-UI-004: Cross-Platform
**Priority**: HIGH (depends on deployment choice)
- **Desktop**: Windows, macOS, Linux
- **Web**: Chrome, Firefox, Safari, Edge
- Consistent behavior across platforms
- Native look and feel (or web modern design)

---

### NFR-UI-005: Performance
**Priority**: HIGH
- Application launch <3 seconds
- Session load <2 seconds
- UI render 60fps (smooth animations)
- Memory usage <1GB for typical session

---

### NFR-UI-006: Reliability
**Priority**: HIGH
- No crashes during normal use
- Graceful error handling with user-friendly messages
- Auto-recovery from crashes (restore session)
- Data integrity (no data loss on crash)

---

## 3. Technology Stack Options

### Option 1: Web Application (Streamlit)
**Pros**:
- Rapid development
- Python-native (integrate easily with backend)
- Built-in widgets and layouts
- Automatic reactivity
- Easy deployment

**Cons**:
- Limited customization
- Performance constraints for very large datasets
- Less control over UI/UX

**Best For**: Quick MVP, prototyping, internal use

---

### Option 2: Web Dashboard (Dash by Plotly)
**Pros**:
- More customization than Streamlit
- Excellent for data-heavy apps
- Plotly integration (same library for plots)
- Reactive callbacks

**Cons**:
- Steeper learning curve
- More boilerplate code
- Python + React knowledge helpful

**Best For**: Professional web dashboards, deployment to multiple users

---

### Option 3: Desktop Application (PyQt6/PySide6)
**Pros**:
- Full native desktop experience
- Maximum performance
- Complete UI control
- Offline-first
- Advanced features (system tray, file associations)

**Cons**:
- Longest development time
- Steeper learning curve
- Platform-specific packaging

**Best For**: Professional desktop software, advanced users, computational performance critical

---

### Option 4: Electron-based (Python backend + JavaScript frontend)
**Pros**:
- Modern web UI with desktop packaging
- Large ecosystem of UI components
- Cross-platform with single codebase

**Cons**:
- Larger application size
- More complex architecture (2 languages)
- Higher memory usage

**Best For**: Modern UI expectations, web experience in desktop form

---

### Recommended: Streamlit (MVP) → Dash (Production)
Start with Streamlit for rapid development and validation, migrate to Dash if more customization is needed.

---

## 4. UI Wireframes

### Main Dashboard (Streamlit Example)
```python
import streamlit as st

# Sidebar
with st.sidebar:
    st.title("RideMetric")
    st.button("📁 New Session")
    st.button("📂 Open Session")
    st.selectbox("Current Session", ["Ride_2026-03-07"])
    st.divider()
    st.button("⚙️ Settings")
    st.button("❓ Help")

# Main area
st.title("Suspension Tuning Dashboard")

# Metrics row
col1, col2, col3, col4 = st.columns(4)
col1.metric("Quality Score", "92", "+5")
col2.metric("Bottoming Events", "3", "-9")
col3.metric("Front Travel", "75%", "+5%")
col4.metric("Rear Travel", "80%", "+10%")

# Tabs
tab1, tab2, tab3 = st.tabs(["Overview", "Tuning", "Analysis"])

with tab1:
    st.plotly_chart(travel_plot)
    st.plotly_chart(velocity_plot)

with tab2:
    col_left, col_right = st.columns(2)
    with col_left:
        st.subheader("Front Suspension")
        st.slider("Compression LSC", 0, 20, 10)
        st.slider("Rebound LSR", 0, 20, 12)
    with col_right:
        st.subheader("Rear Suspension")
        st.slider("Compression LSC", 0, 20, 8)
        st.slider("Rebound LSR", 0, 20, 10)
    
    if st.button("Run Simulation"):
        # Trigger simulation
        pass

with tab3:
    st.plotly_chart(histogram)
    st.plotly_chart(phase_plot)
```

---

## 5. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | New session |
| `Ctrl+O` | Open session |
| `Ctrl+S` | Save session |
| `Ctrl+E` | Export report |
| `Ctrl+R` | Run simulation |
| `Ctrl+Z` | Undo parameter change |
| `Ctrl+Y` | Redo parameter change |
| `F1` | Help |
| `F5` | Refresh/reload |
| `Esc` | Cancel operation |
| `Ctrl+,` | Settings |

---

## 6. Error Handling and Validation

### Input Validation
```python
# Example validation
def validate_spring_rate(value):
    if value <= 0:
        return "Spring rate must be positive"
    if value > 500:
        return "Spring rate seems unusually high (>500 N/mm)"
    return None  # Valid

def validate_clicks(value):
    if not 0 <= value <= 30:
        return "Clicks must be between 0 and 30"
    return None
```

### Error Messages
- **User-Friendly**: "Could not load file. Please check that it's a valid CSV."
- **Not Technical**: ~~"FileNotFoundError: errno 2"~~
- **Actionable**: "File not found. Please select a different file or check the path."
- **Severity Levels**: Info (blue), Warning (yellow), Error (red)

---

## 7. Testing & Validation

### Usability Tests
- **UT-UI-001**: New user can import session in <5 minutes
- **UT-UI-002**: Parameter adjustment updates plot
- **UT-UI-003**: Can undo/redo parameter changes
- **UT-UI-004**: Save and load session preserves data
- **UT-UI-005**: Recommendations display correctly
- **UT-UI-006**: Export report generates valid PDF
- **UT-UI-007**: Preset application works
- **UT-UI-008**: Settings persist across sessions

### Integration Tests
- **IT-UI-001**: End-to-end: Import → Tune → Simulate → Export
- **IT-UI-002**: Multi-session management
- **IT-UI-003**: Comparison mode with 3 snapshots

### User Acceptance Tests
- Real users complete common tasks
- Measure time to completion
- Collect feedback on intuitiveness
- Identify pain points

---

## 8. Acceptance Criteria

- [ ] User can import ride session via drag-and-drop or file browser
- [ ] Dashboard displays key metrics and plots
- [ ] Parameter sliders adjust suspension settings smoothly
- [ ] Run simulation button triggers computation and updates plots
- [ ] Comparison mode shows before/after side-by-side
- [ ] Recommendations display based on simulation results
- [ ] Can save/load presets
- [ ] Export report as PDF
- [ ] Settings persist between sessions
- [ ] Help system accessible and useful
- [ ] Application responsive (<100ms UI updates)
- [ ] No crashes during normal operation

---

## 9. Future Enhancements

- **Mobile App**: iOS/Android companion app for quick review
- **Cloud Sync**: Sync sessions across devices
- **Collaboration**: Share sessions with friends/tuners
- **Community Presets**: Download setups from other riders
- **AI Tuning Assistant**: Machine learning suggests optimal settings
- **Live Data**: Connect to dataloggers for real-time monitoring
- **Integration**: Export to other platforms (Garmin, Strava)
- **Advanced Analytics**: Lap timing, sector analysis (if GPS)
- **Voice Commands**: "Set front compression to 12 clicks"
- **Multi-Language**: Localization for international users
- **Telemetry Streaming**: Real-time visualization during ride (advanced)
- **VR/AR**: Immersive suspension visualization
