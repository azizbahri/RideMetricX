import 'package:flutter/rendering.dart';

/// A node in the suspension scene graph (FR-VZ-004).
///
/// Each node owns a local [Matrix4] [transform] relative to its parent and an
/// ordered list of [children].  Together they form the transform hierarchy
/// that mirrors the physical parent/child relationships of the motorcycle:
///
/// ```
/// chassis
/// ├── front_fork   (translated with front suspension travel)
/// │   └── front_wheel  (rotated by wheel angle)
/// └── rear_shock   (translated with rear suspension travel)
///     └── rear_wheel   (rotated by wheel angle)
/// ```
///
/// Call [worldTransform] with the accumulated parent transform to obtain the
/// full model-to-world matrix for this node.
class SceneNode {
  SceneNode({
    String? name,
    Matrix4? transform,
    List<SceneNode>? children,
  })  : name = name ?? '',
        transform = transform ?? Matrix4.identity(),
        children = children ?? [];

  /// Optional debug label for this node.
  final String name;

  /// Local transform relative to the parent node's coordinate frame.
  Matrix4 transform;

  /// Ordered child nodes attached to this node's local frame.
  final List<SceneNode> children;

  // ── Hierarchy ──────────────────────────────────────────────────────────────

  /// Returns the accumulated world transform for this node.
  ///
  /// Pass [parentTransform] as [Matrix4.identity()] when calling on the root
  /// node.  For non-root nodes, pass the world transform of the parent.
  Matrix4 worldTransform([Matrix4? parentTransform]) {
    final parent = parentTransform ?? Matrix4.identity();
    return parent.multiplied(transform);
  }

  /// Appends [child] to [children] and returns `this` for chaining.
  SceneNode add(SceneNode child) {
    children.add(child);
    return this;
  }

  /// Returns all descendants in depth-first order, including this node.
  Iterable<SceneNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }
}

// ── Scene graph ───────────────────────────────────────────────────────────────

/// Root scene graph for the motorcycle suspension model (FR-VZ-004).
///
/// Builds and maintains the transform hierarchy for all animated suspension
/// components.  Call [updateState] to advance the graph to a new suspension
/// state; node transforms are updated in-place so the painter can traverse
/// the graph each frame without allocating new nodes.
///
/// Hierarchy:
/// ```
/// chassis (identity)
/// ├── frontFork  — Matrix4.translationValues(0, frontTravelMm, 0)
/// │   └── frontWheel — Matrix4.rotationZ(wheelRotationRad)
/// └── rearShock  — Matrix4.translationValues(0, rearTravelMm, 0)
///     └── rearWheel  — Matrix4.rotationZ(wheelRotationRad)
/// ```
class SuspensionSceneGraph {
  SuspensionSceneGraph() {
    _buildGraph();
  }

  // ── Named nodes ────────────────────────────────────────────────────────────

  /// Root chassis node; all other nodes are its descendants.
  late final SceneNode chassis;

  /// Front-fork node; translated on Y by front suspension travel.
  late final SceneNode frontFork;

  /// Front-wheel node; child of [frontFork]; rotated by wheel angle.
  late final SceneNode frontWheel;

  /// Rear-shock node; translated on Y by rear suspension travel.
  late final SceneNode rearShock;

  /// Rear-wheel node; child of [rearShock]; rotated by wheel angle.
  late final SceneNode rearWheel;

  // ── Graph construction ─────────────────────────────────────────────────────

  void _buildGraph() {
    frontWheel = SceneNode(name: 'front_wheel');
    frontFork = SceneNode(name: 'front_fork', children: [frontWheel]);

    rearWheel = SceneNode(name: 'rear_wheel');
    rearShock = SceneNode(name: 'rear_shock', children: [rearWheel]);

    chassis = SceneNode(
      name: 'chassis',
      children: [frontFork, rearShock],
    );
  }

  // ── State update ───────────────────────────────────────────────────────────

  /// Updates in-place the transforms of all animated nodes.
  ///
  /// [frontTravelMm]    – front-fork compression in mm (positive = compressed).
  /// [rearTravelMm]     – rear-shock compression in mm (positive = compressed).
  /// [wheelRotationRad] – cumulative wheel rotation in radians.
  void updateState({
    double frontTravelMm = 0.0,
    double rearTravelMm = 0.0,
    double wheelRotationRad = 0.0,
  }) {
    // Front fork translates downward (positive Y) as suspension compresses.
    frontFork.transform = Matrix4.translationValues(0, frontTravelMm, 0);

    // Rear shock translates downward on compression.
    rearShock.transform = Matrix4.translationValues(0, rearTravelMm, 0);

    // Wheels rotate about the Z-axis as the bike moves forward.
    frontWheel.transform = Matrix4.rotationZ(wheelRotationRad);
    rearWheel.transform = Matrix4.rotationZ(wheelRotationRad);
  }

  // ── World-transform resolution ─────────────────────────────────────────────

  /// Returns the world transform of [node] by traversing the hierarchy from
  /// the root ([chassis]).
  ///
  /// Returns `null` if [node] is not found in the graph.
  Matrix4? worldTransformOf(SceneNode node) {
    return _resolveWorldTransform(chassis, node, Matrix4.identity());
  }

  Matrix4? _resolveWorldTransform(
    SceneNode current,
    SceneNode target,
    Matrix4 accumulated,
  ) {
    final world = accumulated.multiplied(current.transform);
    if (identical(current, target)) return world;
    for (final child in current.children) {
      final result = _resolveWorldTransform(child, target, world);
      if (result != null) return result;
    }
    return null;
  }
}
