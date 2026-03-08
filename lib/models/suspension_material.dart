import 'package:flutter/material.dart';

/// Material definition for a suspension component (FR-VZ-003).
///
/// Encapsulates the base colour, simulated PBR hints ([metallic], [roughness]),
/// and a strain-colour integration hook via [getStrainColor].
///
/// The [getStrainColor] method lerps from [Colors.green] (relaxed) to
/// [Colors.red] (fully compressed) when [strainColor] is set, providing
/// per-component compression visualisation without requiring a shader pipeline.
@immutable
class SuspensionMaterial {
  const SuspensionMaterial({
    required this.baseColor,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.strainColor,
  })  : assert(metallic >= 0.0 && metallic <= 1.0,
            'metallic must be in [0, 1]'),
        assert(roughness >= 0.0 && roughness <= 1.0,
            'roughness must be in [0, 1]');

  /// The default (unstrained) colour of the component.
  final Color baseColor;

  /// Simulated metallic value in [0, 1]; drives highlight brightness.
  final double metallic;

  /// Simulated roughness in [0, 1]; drives gradient spread in shading.
  final double roughness;

  /// Optional override that activates strain-colour mode.  When non-null,
  /// [getStrainColor] lerps from [Colors.green] → [Colors.red] instead of
  /// returning [baseColor].
  final Color? strainColor;

  // ── Predefined materials ───────────────────────────────────────────────────

  /// Brushed-aluminium finish (fork tubes, wheel hubs).
  static const SuspensionMaterial aluminum = SuspensionMaterial(
    baseColor: Color(0xFFBDBDBD),
    metallic: 0.9,
    roughness: 0.3,
  );

  /// Carbon-fibre finish (frame members).
  static const SuspensionMaterial carbon = SuspensionMaterial(
    baseColor: Color(0xFF212121),
    metallic: 0.3,
    roughness: 0.7,
  );

  /// Strain-sensor material: green at rest, red at full compression.
  static const SuspensionMaterial strainSensor = SuspensionMaterial(
    baseColor: Colors.green,
    metallic: 0.0,
    roughness: 0.8,
    strainColor: Colors.red,
  );

  // ── Colour integration ─────────────────────────────────────────────────────

  /// Returns the rendered colour for the given [compressionPercent] ∈ [0, 1].
  ///
  /// When [strainColor] is null the [baseColor] is returned unchanged.
  /// Otherwise the colour lerps from [Colors.green] (0 % compression) to
  /// [Colors.red] (100 % compression).
  Color getStrainColor(double compressionPercent) {
    if (strainColor == null) return baseColor;
    return Color.lerp(
      Colors.green,
      Colors.red,
      compressionPercent.clamp(0.0, 1.0),
    )!;
  }

  /// Highlight colour derived from [baseColor] and [metallic].
  Color get highlightColor {
    final factor = 0.3 + metallic * 0.5;
    return Color.lerp(baseColor, Colors.white, factor)!;
  }

  /// Shadow colour derived from [baseColor] and [roughness].
  Color get shadowColor {
    final factor = 0.3 + (1.0 - roughness) * 0.3;
    return Color.lerp(baseColor, Colors.black, factor)!;
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuspensionMaterial &&
          baseColor == other.baseColor &&
          metallic == other.metallic &&
          roughness == other.roughness &&
          strainColor == other.strainColor;

  @override
  int get hashCode =>
      Object.hash(baseColor, metallic, roughness, strainColor);
}
