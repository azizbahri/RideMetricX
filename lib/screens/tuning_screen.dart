import 'package:flutter/material.dart';

import '../models/simulation_result.dart';
import '../models/suspension_parameters.dart';
import '../services/simulation/simulation_engine.dart';
import '../services/simulation/simulation_trigger.dart';

/// Screen that exposes front/rear suspension parameter controls, preset
/// selection, and a debounced simulation run trigger (FR-UI-005, NFR-UI-002).
class TuningScreen extends StatefulWidget {
  const TuningScreen({
    super.key,
    this.simulationRunner,
    this.debounceDuration,
    this.onSimulationResult,
  });

  /// Optional override for the simulation runner.  Receives the current
  /// [TuningParameters] and returns a [Future] that resolves when the run
  /// completes.  Useful for injecting a fast-completing stub in tests.
  final Future<void> Function(TuningParameters params)? simulationRunner;

  /// Override for the debounce delay.  Defaults to 500 ms in production;
  /// inject a shorter value in tests to avoid waiting.
  final Duration? debounceDuration;

  /// Optional callback invoked with the [SimulationResult] produced by the
  /// built-in engine runner.  Not called when [simulationRunner] is overridden.
  final void Function(SimulationResult result)? onSimulationResult;

  // ── Semantic keys for tests ────────────────────────────────────────────────
  static const Key presetDropdownKey = Key('tuning_preset_dropdown');
  static const Key resetButtonKey = Key('tuning_reset_button');
  static const Key runButtonKey = Key('tuning_run_button');
  static const Key frontSpringRateKey = Key('tuning_front_spring_rate');
  static const Key frontCompressionKey = Key('tuning_front_compression');
  static const Key frontReboundKey = Key('tuning_front_rebound');
  static const Key frontPreloadKey = Key('tuning_front_preload');
  static const Key rearSpringRateKey = Key('tuning_rear_spring_rate');
  static const Key rearCompressionKey = Key('tuning_rear_compression');
  static const Key rearReboundKey = Key('tuning_rear_rebound');
  static const Key rearPreloadKey = Key('tuning_rear_preload');

  @override
  State<TuningScreen> createState() => _TuningScreenState();
}

// ── Preset names ──────────────────────────────────────────────────────────────

const String _kPresetSoft = 'Soft';
const String _kPresetDefault = 'Default';
const String _kPresetFirm = 'Firm';

const List<String> _kPresets = [_kPresetSoft, _kPresetDefault, _kPresetFirm];

TuningParameters _parametersForPreset(String preset) => switch (preset) {
      _kPresetSoft => TuningParameters.softPreset,
      _kPresetFirm => TuningParameters.firmPreset,
      _ => TuningParameters.defaultPreset,
    };

// ── State ─────────────────────────────────────────────────────────────────────

class _TuningScreenState extends State<TuningScreen> {
  TuningParameters _params = TuningParameters.defaultPreset;
  String _selectedPreset = _kPresetDefault;
  late SimulationTrigger _trigger;

  @override
  void initState() {
    super.initState();
    _trigger = SimulationTrigger(
      debounceDuration:
          widget.debounceDuration ?? const Duration(milliseconds: 500),
      onRun: _executeSimulation,
    );
    _trigger.addListener(_onTriggerStateChanged);
  }

  @override
  void dispose() {
    _trigger.removeListener(_onTriggerStateChanged);
    _trigger.dispose();
    super.dispose();
  }

  void _onTriggerStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _executeSimulation() async {
    final runner = widget.simulationRunner ?? _defaultRunner;
    await runner(_params);
  }

  /// Default runner: delegates to [SimulationEngine] and forwards the result
  /// to [TuningScreen.onSimulationResult] if provided.
  Future<void> _defaultRunner(TuningParameters params) async {
    const engine = SimulationEngine();
    final result = await engine.simulate(tuning: params);
    widget.onSimulationResult?.call(result);
  }

  void _applyPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      _params = _parametersForPreset(preset);
    });
    _trigger.trigger();
  }

  void _reset() => _applyPreset(_kPresetDefault);

  void _updateFront(SuspensionParameters updated) {
    setState(() => _params = _params.copyWith(front: updated));
    _trigger.trigger();
  }

  void _updateRear(SuspensionParameters updated) {
    setState(() => _params = _params.copyWith(rear: updated));
    _trigger.trigger();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isRunning = _trigger.isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PresetCard(
            selectedPreset: _selectedPreset,
            presets: _kPresets,
            isRunning: isRunning,
            onPresetChanged: _applyPreset,
            onReset: _reset,
            onRun: isRunning ? null : _trigger.trigger,
          ),
          const SizedBox(height: 16),
          _SuspensionPanel(
            title: 'Front Suspension',
            params: _params.front,
            springRateKey: TuningScreen.frontSpringRateKey,
            compressionKey: TuningScreen.frontCompressionKey,
            reboundKey: TuningScreen.frontReboundKey,
            preloadKey: TuningScreen.frontPreloadKey,
            onChanged: _updateFront,
          ),
          const SizedBox(height: 16),
          _SuspensionPanel(
            title: 'Rear Suspension',
            params: _params.rear,
            springRateKey: TuningScreen.rearSpringRateKey,
            compressionKey: TuningScreen.rearCompressionKey,
            reboundKey: TuningScreen.rearReboundKey,
            preloadKey: TuningScreen.rearPreloadKey,
            onChanged: _updateRear,
          ),
        ],
      ),
    );
  }
}

// ── Preset Card ───────────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.selectedPreset,
    required this.presets,
    required this.isRunning,
    required this.onPresetChanged,
    required this.onReset,
    required this.onRun,
  });

  final String selectedPreset;
  final List<String> presets;
  final bool isRunning;
  final void Function(String) onPresetChanged;
  final VoidCallback onReset;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Preset',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: TuningScreen.presetDropdownKey,
              value: selectedPreset,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: presets
                  .map(
                    (p) => DropdownMenuItem(value: p, child: Text(p)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onPresetChanged(v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: TuningScreen.resetButtonKey,
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: TuningScreen.runButtonKey,
                  onPressed: onRun,
                  icon: isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(isRunning ? 'Running…' : 'Run Simulation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suspension Panel ──────────────────────────────────────────────────────────

class _SuspensionPanel extends StatelessWidget {
  const _SuspensionPanel({
    required this.title,
    required this.params,
    required this.springRateKey,
    required this.compressionKey,
    required this.reboundKey,
    required this.preloadKey,
    required this.onChanged,
  });

  final String title;
  final SuspensionParameters params;
  final Key springRateKey;
  final Key compressionKey;
  final Key reboundKey;
  final Key preloadKey;
  final void Function(SuspensionParameters) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _ParameterSlider(
              sliderKey: springRateKey,
              label: 'Spring Rate',
              unit: 'N/mm',
              value: params.springRate,
              min: SuspensionParameters.kMinSpringRate,
              max: SuspensionParameters.kMaxSpringRate,
              fractionDigits: 1,
              onChanged: (v) => onChanged(params.copyWith(springRate: v)),
            ),
            _ParameterSlider(
              sliderKey: compressionKey,
              label: 'Compression',
              unit: 'clicks',
              value: params.compression,
              min: SuspensionParameters.kMinClicks,
              max: SuspensionParameters.kMaxClicks,
              divisions: 20,
              fractionDigits: 0,
              onChanged: (v) => onChanged(params.copyWith(compression: v)),
            ),
            _ParameterSlider(
              sliderKey: reboundKey,
              label: 'Rebound',
              unit: 'clicks',
              value: params.rebound,
              min: SuspensionParameters.kMinClicks,
              max: SuspensionParameters.kMaxClicks,
              divisions: 20,
              fractionDigits: 0,
              onChanged: (v) => onChanged(params.copyWith(rebound: v)),
            ),
            _ParameterSlider(
              sliderKey: preloadKey,
              label: 'Preload',
              unit: 'mm',
              value: params.preload,
              min: SuspensionParameters.kMinPreload,
              max: SuspensionParameters.kMaxPreload,
              fractionDigits: 1,
              onChanged: (v) => onChanged(params.copyWith(preload: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Parameter Slider ──────────────────────────────────────────────────────────

class _ParameterSlider extends StatelessWidget {
  const _ParameterSlider({
    required this.sliderKey,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.fractionDigits = 1,
  });

  final Key sliderKey;
  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${value.toStringAsFixed(fractionDigits)} $unit',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          key: sliderKey,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(fractionDigits),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
