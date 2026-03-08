import 'processed_sample.dart';
import 'quality_score.dart';
import 'session_metadata.dart';
import 'sync_result.dart';
import 'validation_report.dart';

/// A fully-imported and processed ride session.
///
/// Holds the original sensor metadata, preprocessed sample data (front and/or
/// rear), an optional synchronisation result, and an aggregate [QualityScore].
///
/// Call [toMap] to serialise the session for persistence; the returned map
/// contains all session-level fields and can be stored in a database or file.
/// Individual [frontProcessed] and [rearProcessed] samples are serialised
/// separately via [ProcessedSample.toMap] to keep the top-level map compact.
class RideSession {
  /// Unique session identifier (ISO-8601 timestamp string by default).
  final String sessionId;

  /// UTC instant at which the import was completed.
  final DateTime importedAt;

  /// Metadata for the front sensor recording, if imported.
  final SessionMetadata? frontMetadata;

  /// Metadata for the rear sensor recording, if imported.
  final SessionMetadata? rearMetadata;

  /// Preprocessed front sensor samples.
  ///
  /// Empty when no front file was imported.
  final List<ProcessedSample> frontProcessed;

  /// Preprocessed rear sensor samples.
  ///
  /// Empty when no rear file was imported.
  final List<ProcessedSample> rearProcessed;

  /// Validation report for the front sensor stream, if imported.
  final ValidationReport? frontReport;

  /// Validation report for the rear sensor stream, if imported.
  final ValidationReport? rearReport;

  /// Synchronisation result between front and rear streams.
  ///
  /// `null` when only a single sensor was imported, or when synchronisation
  /// was not attempted.
  final SyncResult? syncResult;

  /// Aggregate quality score for the session.
  final QualityScore qualityScore;

  const RideSession({
    required this.sessionId,
    required this.importedAt,
    this.frontMetadata,
    this.rearMetadata,
    this.frontProcessed = const [],
    this.rearProcessed = const [],
    this.frontReport,
    this.rearReport,
    this.syncResult,
    required this.qualityScore,
  });

  /// Serialises the session to a [Map] suitable for persistence.
  ///
  /// The map includes all session-level fields.  The heavy sample arrays
  /// ([frontProcessed], [rearProcessed]) are represented as counts; use
  /// [ProcessedSample.toMap] to serialise individual samples if needed.
  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'imported_at': importedAt.toIso8601String(),
        if (frontMetadata != null)
          'front_metadata': _metadataToMap(frontMetadata!),
        if (rearMetadata != null)
          'rear_metadata': _metadataToMap(rearMetadata!),
        'front_sample_count': frontProcessed.length,
        'rear_sample_count': rearProcessed.length,
        if (frontReport != null) 'front_passed': frontReport!.passed,
        if (rearReport != null) 'rear_passed': rearReport!.passed,
        if (syncResult != null) 'sync_result': syncResult!.toMap(),
        'quality_score': qualityScore.toMap(),
      };

  static Map<String, dynamic> _metadataToMap(SessionMetadata m) => {
        'session_id': m.sessionId,
        'position': m.position.name,
        if (m.recordedAt != null)
          'recorded_at': m.recordedAt!.toIso8601String(),
        'sampling_rate_hz': m.samplingRateHz,
        'sync_offset_ms': m.syncOffsetMs,
        if (m.pairedSessionId != null) 'paired_session_id': m.pairedSessionId,
      };

  @override
  String toString() => 'RideSession(id=$sessionId, '
      'front=${frontProcessed.length} samples, '
      'rear=${rearProcessed.length} samples, '
      'score=$qualityScore)';
}
