import '../../models/imu_sample.dart';
import '../../models/quality_score.dart';
import '../../models/ride_session.dart';
import '../../models/session_metadata.dart';
import '../../models/sync_result.dart';
import 'corrupted_data_exception.dart';
import 'file_format_exception.dart';
import 'import_service.dart';
import 'platform_permission_exception.dart';
import 'preprocessing_pipeline.dart';
import 'synchronization_exception.dart';
import 'synchronization_service.dart';

/// Stage identifier emitted with each [SessionImportProgress] event.
enum ImportStage {
  /// Files are being decoded and parsed into [ImuSample] streams.
  parsing,

  /// Parsed samples are being validated (range checks, continuity, etc.).
  validating,

  /// Validated samples are being run through the preprocessing pipeline.
  processing,

  /// Front and rear streams are being time-aligned.
  syncing,

  /// Quality metrics are being aggregated and scored.
  scoring,
}

// ── Session import state hierarchy ─────────────────────────────────────────────

/// Represents a step in the [DataImportService] orchestration pipeline.
sealed class SessionImportState {
  const SessionImportState();
}

/// Import has not yet started.
class SessionImportIdle extends SessionImportState {
  const SessionImportIdle();
}

/// Import is running at the given [stage]; [progress] ∈ [0.0, 1.0].
class SessionImportProgress extends SessionImportState {
  const SessionImportProgress(this.stage, this.progress);

  /// Which pipeline stage is currently executing.
  final ImportStage stage;

  /// Overall import completion fraction in [0.0, 1.0].
  final double progress;
}

/// Import completed successfully; the [session] is ready.
class SessionImportSuccess extends SessionImportState {
  const SessionImportSuccess(this.session);

  /// The fully-imported and processed ride session.
  final RideSession session;
}

/// Import failed; [message] describes the problem.
class SessionImportError extends SessionImportState {
  const SessionImportError(this.message);

  /// Human-readable description of what went wrong.
  final String message;
}

// ── DataImportService ─────────────────────────────────────────────────────────

/// Orchestrates the full two-sensor import pipeline.
///
/// Accepts optional front and rear [FileSelection]s and emits stage-wise
/// [SessionImportState] progress events.  On success the terminal event is
/// [SessionImportSuccess] carrying a [RideSession] that is also persisted
/// internally for retrieval via [getImportedSession].
///
/// ## Pipeline stages and global progress milestones
/// 1. **Parsing**   (0.0 → 0.4): decode each file via [ImportService].
/// 2. **Validating** (0.4 → 0.45): validation milestone (done inside parsing).
/// 3. **Processing** (0.45 → 0.7): run [PreprocessingPipeline] on each stream.
/// 4. **Syncing**   (0.7 → 0.85): align streams via [SynchronizationService]
///    (skipped when only one sensor is present).
/// 5. **Scoring**   (0.85 → 1.0): aggregate metrics into [QualityScore].
///
/// ## Error surfacing
/// All failures are surfaced as [SessionImportError] with a human-readable
/// message.  The underlying exception type determines the message format:
/// - [PlatformPermissionException] — permission denied by the OS.
/// - [CorruptedDataException] — file payload is undecodable.
/// - [SynchronizationException] — front/rear streams cannot be aligned.
/// - [FileFormatException] — unsupported or structurally invalid file.
/// - Any other exception — generic fallback message.
///
/// ## Testability
/// Inject custom [importService], [pipeline], and [syncService] instances to
/// override pipeline behaviour without platform I/O.  Pass [onBeforeImport]
/// to simulate permission-denied scenarios in tests.
class DataImportService {
  DataImportService({
    this.importService = const ImportService(),
    this.pipeline = const PreprocessingPipeline(),
    this.syncService = const SynchronizationService(),
    this.onBeforeImport,
  });

  /// Per-file parse/validate service.
  final ImportService importService;

  /// Preprocessing pipeline applied to each sensor stream.
  final PreprocessingPipeline pipeline;

  /// Synchronisation service used when both front and rear files are present.
  final SynchronizationService syncService;

  /// Optional hook invoked before the import starts.
  ///
  /// Throw [PlatformPermissionException] from this callback to simulate a
  /// permission-denied scenario in tests or to enforce platform-level checks
  /// before any file I/O is attempted.
  final void Function()? onBeforeImport;

  // ── In-memory session store ─────────────────────────────────────────────────

  final Map<String, RideSession> _store = {};

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Runs the full import pipeline for the supplied sensor files.
  ///
  /// At least one of [frontFile] or [rearFile] must be non-null.  When both
  /// are supplied the service synchronises the two streams after preprocessing.
  ///
  /// [sessionId] may be provided to use a custom identifier; if omitted a
  /// UTC ISO-8601 timestamp string is generated automatically.
  ///
  /// Emits [SessionImportProgress] events followed by either
  /// [SessionImportSuccess] or [SessionImportError].
  Stream<SessionImportState> importSession({
    FileSelection? frontFile,
    FileSelection? rearFile,
    String? sessionId,
  }) async* {
    if (frontFile == null && rearFile == null) {
      yield const SessionImportError(
        'At least one sensor file (front or rear) must be provided.',
      );
      return;
    }

    try {
      // Permission / pre-import check (injectable for tests).
      onBeforeImport?.call();

      final id = sessionId ?? DateTime.now().toUtc().toIso8601String();

      // ── 1. Parsing (0.0 → 0.4) ─────────────────────────────────────────────
      yield const SessionImportProgress(ImportStage.parsing, 0.0);

      ImportSuccess? frontSuccess;
      ImportSuccess? rearSuccess;

      if (frontFile != null) {
        frontSuccess = await _parseFile(frontFile, SensorPosition.front);
        yield const SessionImportProgress(ImportStage.parsing, 0.2);
      }

      if (rearFile != null) {
        rearSuccess = await _parseFile(rearFile, SensorPosition.rear);
        yield const SessionImportProgress(ImportStage.parsing, 0.4);
      }

      // ── 2. Validating milestone (0.4 → 0.45) ───────────────────────────────
      // Validation was already performed inside ImportService; this stage just
      // emits the milestone so the UI can show "Validating…".
      yield const SessionImportProgress(ImportStage.validating, 0.45);

      // ── 3. Processing (0.45 → 0.7) ─────────────────────────────────────────
      yield const SessionImportProgress(ImportStage.processing, 0.45);

      List<ProcessedSample> frontProcessed = const [];
      List<ProcessedSample> rearProcessed = const [];

      if (frontSuccess != null) {
        frontProcessed = pipeline.process(frontSuccess.samples);
        yield const SessionImportProgress(ImportStage.processing, 0.6);
      }

      if (rearSuccess != null) {
        rearProcessed = pipeline.process(rearSuccess.samples);
        yield const SessionImportProgress(ImportStage.processing, 0.7);
      }

      // ── 4. Syncing (0.7 → 0.85) ────────────────────────────────────────────
      yield const SessionImportProgress(ImportStage.syncing, 0.7);

      SyncResult? syncResult;
      if (frontSuccess != null && rearSuccess != null) {
        syncResult = _sync(frontSuccess.samples, rearSuccess.samples);
      }

      yield const SessionImportProgress(ImportStage.syncing, 0.85);

      // ── 5. Scoring (0.85 → 1.0) ────────────────────────────────────────────
      yield const SessionImportProgress(ImportStage.scoring, 0.85);

      final qualityScore = QualityScore.compute(
        frontReport: frontSuccess?.report,
        rearReport: rearSuccess?.report,
        syncResult: syncResult,
      );

      yield const SessionImportProgress(ImportStage.scoring, 1.0);

      // ── Build metadata ──────────────────────────────────────────────────────
      final frontMeta = frontSuccess != null
          ? SessionMetadata(
              sessionId: id,
              position: SensorPosition.front,
              samplingRateHz:
                  frontSuccess.report.metrics.effectiveSampleRateHz > 0
                      ? frontSuccess.report.metrics.effectiveSampleRateHz
                      : 200.0,
              syncOffsetMs: syncResult?.offsetMs ?? 0,
              pairedSessionId: rearSuccess != null ? id : null,
            )
          : null;

      final rearMeta = rearSuccess != null
          ? SessionMetadata(
              sessionId: id,
              position: SensorPosition.rear,
              samplingRateHz:
                  rearSuccess.report.metrics.effectiveSampleRateHz > 0
                      ? rearSuccess.report.metrics.effectiveSampleRateHz
                      : 200.0,
              // For rear metadata we negate this value so that the sign keeps
              // the convention: positive means "this sensor started AFTER the
              // paired sensor". Thus, if front starts after rear (offsetMs > 0),
              // rear.syncOffsetMs will be negative, indicating rear started first.
              syncOffsetMs: syncResult != null ? -(syncResult.offsetMs) : 0,
              pairedSessionId: frontSuccess != null ? id : null,
            )
          : null;

      // ── Persist and emit success ────────────────────────────────────────────
      final session = RideSession(
        sessionId: id,
        importedAt: DateTime.now().toUtc(),
        frontMetadata: frontMeta,
        rearMetadata: rearMeta,
        frontProcessed: frontProcessed,
        rearProcessed: rearProcessed,
        frontReport: frontSuccess?.report,
        rearReport: rearSuccess?.report,
        syncResult: syncResult,
        qualityScore: qualityScore,
      );

      _store[id] = session;
      yield SessionImportSuccess(session);
    } on PlatformPermissionException catch (e) {
      yield SessionImportError(e.toString());
    } on CorruptedDataException catch (e) {
      yield SessionImportError(e.toString());
    } on SynchronizationException catch (e) {
      yield SessionImportError(e.toString());
    } on FileFormatException catch (e) {
      yield SessionImportError(e.toString());
    } catch (e) {
      yield SessionImportError(e.toString());
    }
  }

  /// Returns the [RideSession] previously imported with [sessionId].
  ///
  /// Returns `null` when no session with that ID exists in the internal store.
  RideSession? getImportedSession(String sessionId) => _store[sessionId];

  /// Returns an unmodifiable list of all sessions currently in the store.
  List<RideSession> listImportedSessions() =>
      List.unmodifiable(_store.values.toList());

  /// Removes the session with [sessionId] from the internal store.
  ///
  /// Does nothing when no session with that ID exists.
  void clearImportedSession(String sessionId) => _store.remove(sessionId);

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Runs [ImportService.importFile] and returns the [ImportSuccess] result.
  ///
  /// Format/structural failures (unknown extension, unsupported file type) are
  /// mapped to [FileFormatException].  Payload-level errors (bad field values,
  /// missing required columns, empty record set) are mapped to
  /// [CorruptedDataException].  Both carry the original diagnostic message.
  Future<ImportSuccess> _parseFile(
    FileSelection file,
    SensorPosition position,
  ) async {
    ImportSuccess? result;
    await for (final state in importService.importFile(file, position)) {
      if (state is ImportSuccess) {
        result = state;
      } else if (state is ImportError) {
        // "No records found" and per-row/field failures indicate the file was
        // decodable but its payload is bad → CorruptedDataException.
        // All other failures (unsupported format, unknown extension, JSON parse
        // error) indicate a structural/format problem → FileFormatException.
        final msg = state.message;
        final isPayloadError = msg.contains('No records found') ||
            msg.contains('Row ') ||
            msg.startsWith('Row') ||
            msg.contains('Field "');
        if (isPayloadError) {
          throw CorruptedDataException(msg, fileName: file.fileName);
        }
        throw FileFormatException(msg);
      }
    }
    if (result == null) {
      throw CorruptedDataException(
        'No output produced by import pipeline for "${file.fileName}".',
        fileName: file.fileName,
      );
    }
    return result;
  }

  /// Aligns [front] and [rear] sample streams via auto cross-correlation.
  ///
  /// Throws [SynchronizationException] when the underlying service fails.
  SyncResult _sync(List<ImuSample> front, List<ImuSample> rear) {
    try {
      return syncService.alignAuto(front, rear);
    } catch (e) {
      throw SynchronizationException(
        'Failed to synchronise front and rear streams: $e',
      );
    }
  }
}
