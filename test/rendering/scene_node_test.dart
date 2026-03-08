// Unit tests for SceneNode and SuspensionSceneGraph (FR-VZ-004).
//
// Covers:
//  • SceneNode default construction
//  • worldTransform with identity parent
//  • worldTransform accumulates parent transform correctly
//  • SceneNode.add chaining
//  • SceneNode.descendants traversal order
//  • SuspensionSceneGraph initial graph structure
//  • SuspensionSceneGraph.updateState → node transforms
//  • SuspensionSceneGraph.worldTransformOf resolves hierarchy

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_metric_x/rendering/scene_node.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Extracts the translation vector [tx, ty, tz] from a [Matrix4].
List<double> _translation(Matrix4 m) =>
    [m.getTranslation().x, m.getTranslation().y, m.getTranslation().z];

/// Returns true when two Matrix4 instances are element-wise equal within
/// [epsilon].
bool _matricesClose(Matrix4 a, Matrix4 b, {double epsilon = 1e-6}) {
  final as_ = a.storage;
  final bs = b.storage;
  for (var i = 0; i < 16; i++) {
    if ((as_[i] - bs[i]).abs() > epsilon) return false;
  }
  return true;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── SceneNode construction ────────────────────────────────────────────────
  group('SceneNode construction', () {
    test('defaults: empty name, identity transform, empty children', () {
      final node = SceneNode();
      expect(node.name, '');
      expect(node.children, isEmpty);
      expect(_matricesClose(node.transform, Matrix4.identity()), isTrue);
    });

    test('custom name is stored', () {
      final node = SceneNode(name: 'fork');
      expect(node.name, 'fork');
    });

    test('custom transform is stored', () {
      final t = Matrix4.translationValues(10, 20, 0);
      final node = SceneNode(transform: t);
      expect(_matricesClose(node.transform, t), isTrue);
    });
  });

  // ── worldTransform ────────────────────────────────────────────────────────
  group('SceneNode.worldTransform', () {
    test('with identity parent equals node local transform', () {
      final node = SceneNode(
        transform: Matrix4.translationValues(5, 0, 0),
      );
      final world = node.worldTransform();
      expect(_translation(world), [5.0, 0.0, 0.0]);
    });

    test('accumulates parent translation correctly', () {
      final parent = Matrix4.translationValues(10, 0, 0);
      final node = SceneNode(
        transform: Matrix4.translationValues(5, 0, 0),
      );
      final world = node.worldTransform(parent);
      expect(_translation(world), [15.0, 0.0, 0.0]);
    });

    test('child world = parent_world * child_local', () {
      final parentLocal = Matrix4.translationValues(0, 3, 0);
      final parentWorld = Matrix4.identity().multiplied(parentLocal);
      final childLocal = Matrix4.translationValues(0, 2, 0);
      final childNode = SceneNode(transform: childLocal);

      final childWorld = childNode.worldTransform(parentWorld);
      final t = _translation(childWorld);
      expect(t[0], closeTo(0.0, 1e-6));
      expect(t[1], closeTo(5.0, 1e-6));
      expect(t[2], closeTo(0.0, 1e-6));
    });
  });

  // ── SceneNode.add ─────────────────────────────────────────────────────────
  group('SceneNode.add', () {
    test('appends child', () {
      final parent = SceneNode(name: 'root');
      final child = SceneNode(name: 'child');
      parent.add(child);
      expect(parent.children, contains(child));
    });

    test('returns this for chaining', () {
      final root = SceneNode();
      final result = root.add(SceneNode());
      expect(identical(result, root), isTrue);
    });
  });

  // ── SceneNode.descendants ─────────────────────────────────────────────────
  group('SceneNode.descendants', () {
    test('leaf node yields only itself', () {
      final leaf = SceneNode(name: 'leaf');
      expect(leaf.descendants.map((n) => n.name).toList(), ['leaf']);
    });

    test('depth-first order: root → child → grandchild', () {
      final grandchild = SceneNode(name: 'grand');
      final child = SceneNode(name: 'child', children: [grandchild]);
      final root = SceneNode(name: 'root', children: [child]);

      final names = root.descendants.map((n) => n.name).toList();
      expect(names, ['root', 'child', 'grand']);
    });
  });

  // ── SuspensionSceneGraph initial structure ────────────────────────────────
  group('SuspensionSceneGraph structure', () {
    late SuspensionSceneGraph graph;

    setUp(() => graph = SuspensionSceneGraph());

    test('chassis is the root node', () {
      expect(graph.chassis.name, 'chassis');
    });

    test('chassis has frontFork and rearShock as direct children', () {
      expect(graph.chassis.children, containsAll([graph.frontFork, graph.rearShock]));
    });

    test('frontFork has frontWheel as direct child', () {
      expect(graph.frontFork.children, contains(graph.frontWheel));
    });

    test('rearShock has rearWheel as direct child', () {
      expect(graph.rearShock.children, contains(graph.rearWheel));
    });

    test('all named nodes appear in descendants of chassis', () {
      final names = graph.chassis.descendants.map((n) => n.name).toSet();
      for (final expected in [
        'chassis',
        'front_fork',
        'front_wheel',
        'rear_shock',
        'rear_wheel',
      ]) {
        expect(names, contains(expected));
      }
    });
  });

  // ── SuspensionSceneGraph.updateState ─────────────────────────────────────
  group('SuspensionSceneGraph.updateState (state → geometry mapping)', () {
    late SuspensionSceneGraph graph;

    setUp(() => graph = SuspensionSceneGraph());

    test('frontFork Y-translation equals frontTravelMm', () {
      graph.updateState(frontTravelMm: 50.0);
      expect(
        graph.frontFork.transform.getTranslation().y,
        closeTo(50.0, 1e-6),
      );
    });

    test('rearShock Y-translation equals rearTravelMm', () {
      graph.updateState(rearTravelMm: 30.0);
      expect(
        graph.rearShock.transform.getTranslation().y,
        closeTo(30.0, 1e-6),
      );
    });

    test('frontWheel and rearWheel carry wheel rotation', () {
      const angle = 1.57;
      graph.updateState(wheelRotationRad: angle);
      // Both wheel nodes receive the same rotation matrix
      final fw = graph.frontWheel.transform;
      final rw = graph.rearWheel.transform;
      expect(_matricesClose(fw, rw), isTrue);
    });

    test('zero state resets all transforms to identity-like values', () {
      graph.updateState(
        frontTravelMm: 100,
        rearTravelMm: 80,
        wheelRotationRad: 3.14,
      );
      graph.updateState(); // all zeros
      expect(graph.frontFork.transform.getTranslation().y, closeTo(0.0, 1e-6));
      expect(graph.rearShock.transform.getTranslation().y, closeTo(0.0, 1e-6));
    });
  });

  // ── SuspensionSceneGraph.worldTransformOf ─────────────────────────────────
  group('SuspensionSceneGraph.worldTransformOf (transform consistency)', () {
    late SuspensionSceneGraph graph;

    setUp(() {
      graph = SuspensionSceneGraph();
      graph.updateState(frontTravelMm: 60.0, rearTravelMm: 40.0);
    });

    test('chassis world transform is its own local (parent = identity)', () {
      final world = graph.worldTransformOf(graph.chassis);
      expect(world, isNotNull);
      expect(_matricesClose(world!, graph.chassis.transform), isTrue);
    });

    test('frontFork world Y equals chassis.Y + fork translation', () {
      final world = graph.worldTransformOf(graph.frontFork);
      expect(world, isNotNull);
      // chassis has identity transform; fork adds 60 mm on Y
      expect(world!.getTranslation().y, closeTo(60.0, 1e-6));
    });

    test('frontWheel world Y includes fork translation', () {
      // frontWheel is a child of frontFork → inherits fork's Y offset
      final world = graph.worldTransformOf(graph.frontWheel);
      expect(world, isNotNull);
      expect(world!.getTranslation().y, closeTo(60.0, 1e-6));
    });

    test('rearShock world Y equals rearTravelMm', () {
      final world = graph.worldTransformOf(graph.rearShock);
      expect(world!.getTranslation().y, closeTo(40.0, 1e-6));
    });

    test('returns null for a node not in the graph', () {
      final orphan = SceneNode(name: 'orphan');
      expect(graph.worldTransformOf(orphan), isNull);
    });
  });
}
