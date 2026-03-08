// Unit tests for SuspensionMaterial (FR-VZ-003).
//
// Covers:
//  • Predefined material constants
//  • getStrainColor: returns baseColor when strainColor is null
//  • getStrainColor: lerps green→red when strainColor is set
//  • getStrainColor: clamps compressionPercent to [0, 1]
//  • highlightColor and shadowColor derivations
//  • Equality and hashCode

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_metric_x/models/suspension_material.dart';

void main() {
  // ── Predefined materials ──────────────────────────────────────────────────
  group('SuspensionMaterial predefined constants', () {
    test('aluminum has high metallic and low roughness', () {
      expect(SuspensionMaterial.aluminum.metallic, greaterThan(0.5));
      expect(SuspensionMaterial.aluminum.roughness, lessThan(0.5));
      expect(SuspensionMaterial.aluminum.strainColor, isNull);
    });

    test('carbon has low metallic and high roughness', () {
      expect(SuspensionMaterial.carbon.metallic, lessThan(0.5));
      expect(SuspensionMaterial.carbon.roughness, greaterThan(0.5));
    });

    test('strainSensor has strainColor set', () {
      expect(SuspensionMaterial.strainSensor.strainColor, isNotNull);
    });
  });

  // ── getStrainColor – no strainColor ───────────────────────────────────────
  group('SuspensionMaterial.getStrainColor without strainColor', () {
    const mat = SuspensionMaterial(
      baseColor: Colors.blue,
      metallic: 0.5,
      roughness: 0.5,
    );

    test('returns baseColor regardless of compressionPercent', () {
      expect(mat.getStrainColor(0.0), equals(Colors.blue));
      expect(mat.getStrainColor(0.5), equals(Colors.blue));
      expect(mat.getStrainColor(1.0), equals(Colors.blue));
    });
  });

  // ── getStrainColor – with strainColor ─────────────────────────────────────
  group('SuspensionMaterial.getStrainColor with strainColor', () {
    const mat = SuspensionMaterial.strainSensor;

    test('returns baseColor at 0 % compression', () {
      // Color.lerp returns a plain Color; compare via .value to avoid
      // MaterialColor vs Color type mismatch.
      expect(mat.getStrainColor(0.0).value, equals(mat.baseColor.value));
    });

    test('returns strainColor at 100 % compression', () {
      expect(mat.getStrainColor(1.0).value, equals(mat.strainColor!.value));
    });

    test('returns a colour between green and red at 50 %', () {
      final mid = mat.getStrainColor(0.5);
      // The interpolated colour should have non-trivial red and green channels
      expect(mid.red, greaterThan(0));
      expect(mid.green, greaterThan(0));
    });

    test('clamps value below 0 to baseColor', () {
      expect(mat.getStrainColor(-0.5).value, equals(mat.baseColor.value));
    });

    test('clamps value above 1 to strainColor', () {
      expect(mat.getStrainColor(2.0).value, equals(mat.strainColor!.value));
    });

    test('lerps between custom baseColor and strainColor', () {
      const custom = SuspensionMaterial(
        baseColor: Colors.blue,
        strainColor: Colors.orange,
      );
      expect(custom.getStrainColor(0.0).value, equals(Colors.blue.value));
      expect(custom.getStrainColor(1.0).value, equals(Colors.orange.value));
      // Mid-point should differ from both endpoints
      final mid = custom.getStrainColor(0.5);
      expect(mid.value, isNot(equals(Colors.blue.value)));
      expect(mid.value, isNot(equals(Colors.orange.value)));
    });
  });

  // ── highlightColor and shadowColor ────────────────────────────────────────
  group('SuspensionMaterial highlight and shadow colours', () {
    test('highlightColor is lighter than baseColor for metallic material', () {
      final highlight = SuspensionMaterial.aluminum.highlightColor;
      final base = SuspensionMaterial.aluminum.baseColor;
      // Highlight blended towards white → higher luminance
      expect(highlight.computeLuminance(), greaterThan(base.computeLuminance()));
    });

    test('shadowColor is darker than baseColor', () {
      final shadow = SuspensionMaterial.aluminum.shadowColor;
      final base = SuspensionMaterial.aluminum.baseColor;
      expect(shadow.computeLuminance(), lessThan(base.computeLuminance()));
    });
  });

  // ── Equality and hashCode ─────────────────────────────────────────────────
  group('SuspensionMaterial equality', () {
    test('same fields are equal', () {
      const a = SuspensionMaterial(baseColor: Colors.grey, metallic: 0.5);
      const b = SuspensionMaterial(baseColor: Colors.grey, metallic: 0.5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different baseColor are not equal', () {
      const a = SuspensionMaterial(baseColor: Colors.red);
      const b = SuspensionMaterial(baseColor: Colors.blue);
      expect(a, isNot(equals(b)));
    });

    test('different metallic are not equal', () {
      const a = SuspensionMaterial(baseColor: Colors.grey, metallic: 0.2);
      const b = SuspensionMaterial(baseColor: Colors.grey, metallic: 0.8);
      expect(a, isNot(equals(b)));
    });
  });
}
