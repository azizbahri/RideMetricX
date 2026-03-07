# Component 3: Suspension Physics Model Requirements (Flutter/Dart)

## Overview
The Suspension Physics Model simulates the dynamic behavior of motorcycle suspension systems (front forks and rear shock) based on physical principles. It models spring-damper systems with configurable parameters to predict suspension response to measured forces and accelerations. Implemented in Dart for cross-platform operation on Windows, Android, and iOS.

---

## 1. Functional Requirements

### FR-SM-001: Spring Model
**Priority**: CRITICAL  
**Description**: Model the elastic spring element of the suspension

**Spring Characteristics**:
1. **Linear Spring**:
   - Force = k × displacement
   - k = spring rate (N/mm)
   - Range: 0-200mm travel

2. **Progressive Spring**:
   - Force = k₁ × x + k₂ × x²
   - Models progressive spring rate
   - Common in motorcycle suspensions

3. **Dual-Rate Spring**:
   - Different spring rates before/after preload point
   - Models dual-spring setups

**Parameters**:
- `spring_rate`: N/mm (front: 8-12 N/mm, rear: 80-120 N/mm typical for Tenere 700)
- `preload`: mm (static sag setting)
- `free_length`: mm
- `progressive_rate`: N/mm² (for progressive springs)

**Outputs**:
- Spring force at given displacement
- Stored elastic energy
- Sag (static compression under rider weight)

---

### FR-SM-002: Damping Model
**Priority**: CRITICAL  
**Description**: Model velocity-dependent damping forces

**Damping Types**:

1. **Compression Damping** (suspension compressing):
   - Low-speed compression (LSC): 0-0.5 m/s
   - High-speed compression (HSC): >0.5 m/s
   - Typical use: controls dive under braking, bottom resistance

2. **Rebound Damping** (suspension extending):
   - Low-speed rebound (LSR): 0-0.5 m/s
   - High-speed rebound (HSR): >0.5 m/s
   - Typical use: controls oscillation, prevents pogo

**Damping Force Models**:

1. **Linear Damping**:
   ```
   F_damp = c × velocity
   c = damping coefficient (N·s/mm)
   ```

2. **Bi-Linear Damping** (Low/High speed):
   ```
   F_damp = c_low × v                    if |v| < v_threshold
   F_damp = c_high × v + offset          if |v| ≥ v_threshold
   ```

3. **Non-Linear Damping** (Realistic):
   ```
   F_damp = c × v + d × v² × sign(v)
   Models actual damper characteristics
   ```

**Parameters**:
- `compression_low_speed`: Clicks or coefficient
- `compression_high_speed`: Clicks or coefficient
- `rebound_low_speed`: Clicks or coefficient
- `rebound_high_speed`: Clicks or coefficient
- `velocity_threshold`: m/s (transition point, typically 0.5 m/s)

**Outputs**:
- Damping force at given velocity
- Energy dissipated
- Heat generation (for fade modeling)

---

### FR-SM-003: Suspension Geometry
**Priority**: HIGH  
**Description**: Model motorcycle-specific suspension geometry

**Front Suspension (Telescopic Forks)**:
- Fork angle (rake): typically 27° for Tenere 700
- Trail: affects steering stability
- Wheel travel: 210mm (Tenere 700 spec)
- Unsprung mass: ~15-20kg
- Spring/damper inline with fork axis

**Rear Suspension (Monoshock with Linkage)**:
- Linkage ratio: motion ratio varies with travel (progressive)
- Typical range: 2.0:1 to 3.5:1 (wheel travel : shock travel)
- Wheel travel: 200mm (Tenere 700 spec)
- Unsprung mass: ~25-30kg
- Rising rate linkage common

**Linkage Modeling**:
```dart
double calculateShockDisplacement(double wheelDisplacement) {
  return wheelDisplacement / linkageRatio(wheelDisplacement);
}

double calculateShockVelocity(double wheelVelocity, double wheelDisplacement) {
  return wheelVelocity / linkageRatio(wheelDisplacement);
}

double calculateWheelForce(double shockForce, double wheelDisplacement) {
  return shockForce * linkageRatio(wheelDisplacement);
}
```

**Parameters**:
- `wheel_travel_max`: mm
- `linkage_ratio_function`: Callable or lookup table
- `unsprung_mass`: kg
- `sprung_mass_front`: kg (portion of bike+rider on front)
- `sprung_mass_rear`: kg (portion of bike+rider on rear)

---

### FR-SM-004: Mass-Spring-Damper System
**Priority**: CRITICAL  
**Description**: Solve equations of motion for suspension system

**Single Wheel Model (Quarter Car)**:
```
m_unsprung × ẍ_unsprung = F_tire - F_spring - F_damper
m_sprung × ẍ_sprung = F_spring + F_damper - m_sprung × g
```

Where:
- `m_unsprung`: wheel, brake, lower fork/swingarm mass
- `m_sprung`: chassis, rider, engine mass on this wheel
- `F_tire`: force from ground (from IMU measurements)
- `F_spring`: spring force
- `F_damper`: damping force
- `g`: gravity (9.81 m/s²)

**Half Motorcycle Model (Pitch Plane)**:
- Couple front and rear suspensions
- Model pitch dynamics
- Account for weight transfer (braking/acceleration)
- Account for aerodynamic forces

**Inputs**:
- Ground acceleration (from tire contact, estimated from IMU)
- Chassis acceleration (measured by IMU)
- Rider weight distribution

**Outputs**:
- Suspension displacement (travel used)
- Suspension velocity
- Spring force
- Damper force
- Chassis acceleration (simulated)

---

### FR-SM-005: Force Reconstruction
**Priority**: HIGH  
**Description**: Estimate forces from IMU acceleration measurements

**Method**:
1. Measure chassis acceleration (from IMU on swingarm/fork)
2. Estimate force: F = m × a (Newton's second law)
3. Account for gravity component
4. Filter noise and integrate to get displacement

**Challenges**:
- IMU measures acceleration, not force directly
- Need to estimate unsprung/sprung mass distribution
- Gravity must be removed (only dynamic acceleration)
- Integration drift must be compensated

**Algorithm**:
```dart
// Remove gravity from accelerometer
Vector3 accelDynamic = accelMeasured - gravityVector;

// Estimate force on suspension
double fEstimated = (sprungMass + unsprungMass) * accelDynamic.z;

// Integrate to get velocity and displacement
List<double> velocity = integrate(accelDynamic);
List<double> displacement = integrate(velocity);
```

---

### FR-SM-006: Suspension Parameter Configuration
**Priority**: HIGH  
**Description**: Define and manage suspension tuning parameters

**Yamaha Tenere 700 (2025) Baseline**:

**Front Fork (KYB USD 43mm)**:
- Travel: 210mm
- Spring rate: ~9.0 N/mm (estimated)
- Compression damping: 10-20 clicks adjustable
- Rebound damping: 10-20 clicks adjustable
- Preload: Non-adjustable (spacers only)

**Rear Shock (KYB)**:
- Travel: 200mm (wheel travel)
- Spring rate: ~95 N/mm (estimated)
- Compression damping: Adjustable (clicks)
- Rebound damping: Adjustable (clicks)
- Preload: Adjustable (turns)

**Configuration Format**:
```yaml
motorcycle:
  model: "Yamaha Tenere 700 2025"
  weight_dry_kg: 204
  
rider:
  weight_kg: 80
  gear_weight_kg: 10
  
front_suspension:
  type: "telescopic_fork"
  travel_mm: 210
  spring:
    type: "linear"
    rate_N_per_mm: 9.0
    preload_mm: 10
  damping:
    compression_low_clicks: 10  # out from full hard
    compression_high_clicks: 10
    rebound_low_clicks: 10
    rebound_high_clicks: 10
  geometry:
    unsprung_mass_kg: 18
    rake_deg: 27
    trail_mm: 110

rear_suspension:
  type: "monoshock_linkage"
  travel_mm: 200
  spring:
    type: "linear"
    rate_N_per_mm: 95.0
    preload_mm: 5
  damping:
    compression_low_clicks: 8
    compression_high_clicks: 8
    rebound_low_clicks: 10
    rebound_high_clicks: 10
  linkage:
    type: "progressive"
    ratio_function: "lookup_table"
  geometry:
    unsprung_mass_kg: 28
    lever_ratio: 2.8
```

---

### FR-SM-007: Click-to-Coefficient Conversion
**Priority**: MEDIUM  
**Description**: Convert adjuster clicks to damping coefficients

**Typical Relationship**:
- Each click changes damping ~5-10%
- Exponential or linear progression
- Different ranges for LSC/HSC and LSR/HSR

**Example Mapping**:
```dart
/// Convert damper clicker position to damping coefficient.
/// 
/// [clicks]: 0 = full hard, 20 = full soft
/// [baseCoeff]: minimum damping coefficient (full hard)
/// [clicksRange]: total number of clicks available
double clicksToCoefficient(int clicks, double baseCoeff, {int clicksRange = 20}) {
  double factor = 1.0 + (clicks / clicksRange) * 2.0;  // 1x to 3x range
  return baseCoeff * factor;
}
```

---

### FR-SM-008: Sag Calculation
**Priority**: HIGH  
**Description**: Calculate static and race sag

**Sag Types**:
1. **Free Sag**: Suspension compression with bike weight only
2. **Static Sag (Race Sag)**: Compression with bike + rider weight
3. **Dynamic Sag**: Typical compression during riding

**Calculation**:
```dart
double freeSagMm = (weightBikeKg * 9.81) / springRateNPerMm;
double staticSagMm = ((weightBikeKg + weightRiderKg) * 9.81) / springRateNPerMm;
```

**Target Sag (Tenere 700 typical)**:
- Front: 35-40mm static sag (free sag 20-25mm)
- Rear: 35-45mm static sag (free sag 5-10mm)

---

### FR-SM-009: Bottoming and Topping Detection
**Priority**: MEDIUM  
**Description**: Detect suspension hitting travel limits

**Bottoming** (Full compression):
- Occurs when displacement ≥ available travel
- Can damage suspension
- Indicates too soft spring or insufficient compression damping

**Topping** (Full extension):
- Occurs when displacement ≤ 0 (fully extended)
- Indicates too stiff rebound or excessive preload
- Can cause wheel hop

**Detection**:
```python
if displacement >= wheel_travel_max - 5mm:
    bottoming_event = True
    severity = displacement - (wheel_travel_max - 5mm)
    
if displacement <= 5mm:
    topping_event = True
```

**Output**:
- Number of bottoming events
- Maximum bottoming severity (mm past travel limit)
- Number of topping events
- Percentage of time spent in bottom 10% of travel
- Percentage of time spent in top 10% of travel

---

### FR-SM-010: Simulation Step
**Priority**: CRITICAL  
**Description**: Execute single time-step of suspension simulation

**Algorithm** (Runge-Kutta 4th order or similar):
```python
def simulate_step(state, forces, params, dt):
    """
    Advance suspension simulation by one time step.
    
    Args:
        state: Current state (displacement, velocity)
        forces: Input forces (from IMU reconstruction)
        params: Suspension parameters (spring, damping)
        dt: Time step (seconds)
        
    Returns:
        new_state: Updated state after dt
        outputs: Forces, accelerations, etc.
    """
    # Calculate spring force
    F_spring = params.spring_rate × state.displacement
    
    # Calculate damping force
    F_damper = damping_force(state.velocity, params.damping)
    
    # Solve equation of motion
    F_net = forces.F_input - F_spring - F_damper
    acceleration = F_net / params.mass
    
    # Update state (RK4 integration)
    new_velocity = state.velocity + acceleration × dt
    new_displacement = state.displacement + new_velocity × dt
    
    return State(new_displacement, new_velocity), Forces(F_spring, F_damper)
```

---

## 2. Non-Functional Requirements

### NFR-SM-001: Accuracy
**Priority**: CRITICAL
- Simulation error <5% compared to actual suspension behavior
- Spring force calculation exact for linear springs
- Damping force within 10% of manufacturer dyno data
- Validated against known test cases

---

### NFR-SM-002: Performance
**Priority**: HIGH
- Simulate 1 hour of data (200Hz) in <30 seconds on desktop, <90 seconds on mobile
- Real-time simulation capability (1:1 time ratio) for UI on desktop
- Memory usage <500MB for 1-hour session on desktop, <200MB on mobile
- Efficient use of Dart's isolates for parallel computation

---

### NFR-SM-003: Stability
**Priority**: HIGH
- Numerical integration stable for typical time steps (5ms)
- No divergence or oscillation in simulation
- Handles edge cases (zero damping, infinite stiffness)

---

### NFR-SM-004: Extensibility
**Priority**: MEDIUM
- Easy to add new suspension types (inverted forks, air shocks)
- Support for advanced models (friction, hysteresis)
- Pluggable damping curve models

---

## 3. Physics Equations

### Complete Suspension Model

**State Variables**:
- $x_s$: Sprung mass displacement (chassis)
- $x_u$: Unsprung mass displacement (wheel assembly)
- $\dot{x}_s$: Sprung mass velocity
- $\dot{x}_u$: Unsprung mass velocity

**Equations of Motion**:

$$m_s \ddot{x}_s = -k(x_s - x_u) - c(\dot{x}_s - \dot{x}_u)$$

$$m_u \ddot{x}_u = k(x_s - x_u) + c(\dot{x}_s - \dot{x}_u) - k_t(x_u - x_r)$$

Where:
- $m_s$: Sprung mass
- $m_u$: Unsprung mass
- $k$: Suspension spring rate
- $c$: Damping coefficient (velocity-dependent)
- $k_t$: Tire stiffness
- $x_r$: Road/ground displacement (input)

**Damping Force (Bi-Linear)**:

$$F_d = \begin{cases}
c_{low} \cdot \dot{x} & \text{if } |\dot{x}| < v_{threshold} \\
c_{high} \cdot \dot{x} + c_{offset} \cdot \text{sign}(\dot{x}) & \text{if } |\dot{x}| \geq v_{threshold}
\end{cases}$$

**Progressive Linkage Ratio**:

$$r(x) = r_0 + r_1 \cdot x + r_2 \cdot x^2$$

Where $x$ is wheel displacement, $r(x)$ is instantaneous linkage ratio.

---

## 4. API Specification

### Suspension Model Service
```dart
class SuspensionModel {
  final SuspensionConfig config;
  
  SuspensionModel({required this.config});
  
  /// Update suspension parameters (spring rate, damping, etc.)
  void setParameters(SuspensionParams params) {
    // Implementation
  }
  
  /// Calculate static sag for given weight
  double calculateSag(double weightKg) {
    return (weightKg * 9.81) / config.springRateNPerMm;
  }
  
  /// Calculate spring force at given displacement
  double calculateSpringForce(double displacementMm) {
    if (config.springType == SpringType.linear) {
      return config.springRateNPerMm * displacementMm;
    } else if (config.springType == SpringType.progressive) {
      return config.springRateNPerMm * displacementMm + 
             config.progressiveRate * displacementMm * displacementMm;
    }
    return 0.0;
  }
  
  /// Calculate damping force at given velocity
  /// 
  /// [velocity]: Suspension velocity in m/s
  /// [direction]: DampingDirection.compression or .rebound
  double calculateDampingForce(double velocity, DampingDirection direction) {
    // Implementation based on bi-linear damping model
    return 0.0;
  }
  
  /// Execute one simulation time step
  /// 
  /// Returns new state and forces
  SimulationStep simulateStep({
    required SuspensionState currentState,
    required double inputForce,
    required double dt,
  }) {
    // Runge-Kutta 4th order integration
    return SimulationStep(state: currentState, forces: Forces.zero());
  }
  
  /// Simulate entire ride session with given parameters
  /// 
  /// Returns stream for progress updates
  Stream<SimulationProgress> simulateSession({
    required RideSession sessionData,
    required SuspensionParams parameters,
  }) async* {
    // Implementation
  }
  
  /// Get final simulation result
  Future<SimulationResult> getSimulationResult(String sessionId);
}
```

### Data Structures
```dart
class SuspensionState {
  final double displacementM;  // meters
  final double velocityMps;    // m/s
  final double accelerationMps2;  // m/s²
  
  SuspensionState({
    required this.displacementM,
    required this.velocityMps,
    required this.accelerationMps2,
  });
}

class Forces {
  final double springN;   // Newtons
  final double dampingN;  // Newtons
  final double totalN;    // Newtons
  
  Forces({required this.springN, required this.dampingN, required this.totalN});
  
  factory Forces.zero() => Forces(springN: 0, dampingN: 0, totalN: 0);
}

class SuspensionParams {
  final double springRateNPerMm;
  final double preloadMm;
  final int compressionLowClicks;
  final int compressionHighClicks;
  final int reboundLowClicks;
  final int reboundHighClicks;
  
  SuspensionParams({
    required this.springRateNPerMm,
    required this.preloadMm,
    required this.compressionLowClicks,
    required this.compressionHighClicks,
    required this.reboundLowClicks,
    required this.reboundHighClicks,
  });
}

class SimulationResult {
  final List<double> time;
  final List<double> displacementMm;
  final List<double> velocityMps;
  final List<double> springForceN;
  final List<double> dampingForceN;
  final List<double> bottomingEvents;  // timestamps
  final List<double> toppingEvents;
  final Map<String, double> metrics;
  
  SimulationResult({
    required this.time,
    required this.displacementMm,
    required this.velocityMps,
    required this.springForceN,
    required this.dampingForceN,
    required this.bottomingEvents,
    required this.toppingEvents,
    required this.metrics,
  });
}

class SimulationStep {
  final SuspensionState state;
  final Forces forces;
  
  SimulationStep({required this.state, required this.forces});
}

class SimulationProgress {
  final double percent;  // 0-100
  final String stage;    // 'initializing', 'computing', 'analyzing'
  
  SimulationProgress(this.percent, this.stage);
}

enum SpringType { linear, progressive, dualRate }
enum DampingDirection { compression, rebound }
```

---

## 5. Validation & Testing

### Unit Tests

- **UT-SM-001**: Linear spring force calculation
- **UT-SM-002**: Progressive spring force calculation
- **UT-SM-003**: Linear damping force (compression)
- **UT-SM-004**: Linear damping force (rebound)
- **UT-SM-005**: Bi-linear damping transition
- **UT-SM-006**: Sag calculation
- **UT-SM-007**: Linkage ratio application
- **UT-SM-008**: Bottoming detection
- **UT-SM-009**: Topping detection
- **UT-SM-010**: Integration stability (step response)

### Physical Validation Tests

- **PV-SM-001**: Free oscillation decay matches theory
- **PV-SM-002**: Step input response (bump test)
- **PV-SM-003**: Frequency response (sine sweep)
- **PV-SM-004**: Static sag matches calculated value
- **PV-SM-005**: Dyno data comparison (if available)

### Test Cases

**Test 1: Static Compression**
```dart
// Given: 90kg total weight on rear suspension
// Spring rate: 95 N/mm, No preload
// Expected: Sag = (90 × 9.81) / 95 = 9.3mm
test('Static compression calculation', () {
  final sagMm = (90 * 9.81) / 95;
  expect(sagMm, closeTo(9.3, 0.1));
});
```

**Test 2: Free Oscillation**
```dart
// Given: Initial displacement, no external force
// Expected: Decaying oscillation
// Natural frequency: f = (1/2π) × sqrt(k/m)
// Damping ratio determines decay rate
test('Free oscillation decay', () {
  // Test implementation
});
```

**Test 3: Bottoming**
```dart
// Given: Large step input (curb hit)
// Expected: Displacement reaches max travel limit
// Should detect bottoming event
test('Bottoming detection', () {
  // Test implementation
});
```

---

## 6. Performance Metrics

### Suspension Performance Indicators

1. **Travel Usage**:
   - Average travel used (mm)
   - Maximum travel used (mm)
   - Percentage of available travel used
   - Travel histogram

2. **Bottoming/Topping**:
   - Number of bottoming events
   - Number of topping events
   - Severity of events (mm beyond limit)

3. **Damping Efficiency**:
   - Energy dissipated by damper
   - Compression vs rebound energy ratio
   - Velocity histogram (LSC/HSC distribution)

4. **Dynamic Response**:
   - Sprung mass acceleration (RMS)
   - Suspension settling time after bumps
   - Oscillation frequency

5. **Setup Quality**:
   - Sag within target range (yes/no)
   - Balance front/rear usage
   - Estimated comfort index

---

## 7. Acceptance Criteria

- [ ] Accurately model linear and progressive springs
- [ ] Implement bi-linear compression/rebound damping
- [ ] Calculate static and race sag within 5% error
- [ ] Simulate rear linkage ratio correctly
- [ ] Detect bottoming and topping events
- [ ] Simulate 1-hour session in <30 seconds
- [ ] Numerical integration remains stable
- [ ] Parameter changes produce expected behavior changes
- [ ] Validated against at least 3 real-world test cases

---

## 8. Future Enhancements

- **Friction Modeling**: Static and kinetic friction in damper seals
- **Thermal Effects**: Damping fade due to oil heating
- **Cavitation**: Loss of damping at extreme velocities
- **Air Spring Model**: For air-sprung forks/shocks
- **Full Bike Model**: Multi-body dynamics (7+ DOF)
- **Tire Model**: Contact patch dynamics, grip estimation
- **Anti-dive/squat**: Model fork brace, link geometry effects
- **Machine Learning**: Learn damping curves from data
- **Wear Modeling**: Predict seal wear, oil degradation
- **Comparative Analysis**: Compare against professional setup data
