import 'suspension_parameters.dart';

/// A labeled, timestamped snapshot of [TuningParameters] captured for
/// later comparison (FR-UI-007).
///
/// Snapshots are stored in [SnapshotRepository] and rendered in
/// [ComparisonScreen] to allow side-by-side delta analysis of multiple
/// tuning setups.
class TuningSnapshot {
  const TuningSnapshot({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.parameters,
    this.notes = '',
  });

  /// Unique identifier, typically a UUID or ISO-8601 timestamp string.
  final String id;

  /// Human-readable name assigned at capture time (e.g. "Stock setup").
  final String label;

  /// UTC instant at which this snapshot was captured.
  final DateTime createdAt;

  /// Tuning parameter values recorded in this snapshot.
  final TuningParameters parameters;

  /// Optional free-text rider notes attached to this snapshot.
  final String notes;

  // ── Derived accessors ──────────────────────────────────────────────────────

  /// Front spring rate in N/mm.
  double get frontSpringRate => parameters.front.springRate;

  /// Rear spring rate in N/mm.
  double get rearSpringRate => parameters.rear.springRate;

  /// Front compression damping in clicks.
  double get frontCompression => parameters.front.compression;

  /// Rear compression damping in clicks.
  double get rearCompression => parameters.rear.compression;

  /// Front rebound damping in clicks.
  double get frontRebound => parameters.front.rebound;

  /// Rear rebound damping in clicks.
  double get rearRebound => parameters.rear.rebound;

  /// Front preload in mm.
  double get frontPreload => parameters.front.preload;

  /// Rear preload in mm.
  double get rearPreload => parameters.rear.preload;

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Serialises the snapshot to a [Map] suitable for persistence.
  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'created_at': createdAt.toIso8601String(),
        'notes': notes,
        'front_spring_rate': frontSpringRate,
        'front_compression': frontCompression,
        'front_rebound': frontRebound,
        'front_preload': frontPreload,
        'rear_spring_rate': rearSpringRate,
        'rear_compression': rearCompression,
        'rear_rebound': rearRebound,
        'rear_preload': rearPreload,
      };

  /// Restores a [TuningSnapshot] from the [Map] produced by [toMap].
  factory TuningSnapshot.fromMap(Map<String, dynamic> map) {
    return TuningSnapshot(
      id: map['id'] as String,
      label: map['label'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      notes: (map['notes'] as String?) ?? '',
      parameters: TuningParameters(
        front: SuspensionParameters(
          springRate: (map['front_spring_rate'] as num).toDouble(),
          compression: (map['front_compression'] as num).toDouble(),
          rebound: (map['front_rebound'] as num).toDouble(),
          preload: (map['front_preload'] as num).toDouble(),
        ),
        rear: SuspensionParameters(
          springRate: (map['rear_spring_rate'] as num).toDouble(),
          compression: (map['rear_compression'] as num).toDouble(),
          rebound: (map['rear_rebound'] as num).toDouble(),
          preload: (map['rear_preload'] as num).toDouble(),
        ),
      ),
    );
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  /// Returns a copy with any provided fields replaced.
  TuningSnapshot copyWith({
    String? id,
    String? label,
    DateTime? createdAt,
    TuningParameters? parameters,
    String? notes,
  }) {
    return TuningSnapshot(
      id: id ?? this.id,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
      parameters: parameters ?? this.parameters,
      notes: notes ?? this.notes,
    );
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuningSnapshot &&
          id == other.id &&
          label == other.label &&
          createdAt == other.createdAt &&
          parameters == other.parameters &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(id, label, createdAt, parameters, notes);

  @override
  String toString() =>
      'TuningSnapshot(id=$id, label="$label", createdAt=$createdAt)';
}
