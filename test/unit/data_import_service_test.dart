// Integration tests for DataImportService orchestration.
//
// Covers:
//   - SessionImportState sealed hierarchy
//   - importSession: front-only, rear-only, front+rear
//   - Stage-wise progress events in correct order
//   - Metadata, processed samples, quality score in RideSession
//   - getImportedSession persistence retrieval
//   - listImportedSessions / clearImportedSession
//   - Corrupted file → SessionImportError
//   - Permission failure → SessionImportError (via onBeforeImport hook)
//   - No files provided → SessionImportError
//   - Export/re-import parity (toMap fields)
//   - QualityScore compute and band classification
//   - Domain exception toString helpers

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/quality_score.dart';
import 'package:ride_metric_x/models/ride_session.dart';
import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/models/validation_error.dart';
import 'package:ride_metric_x/models/validation_metrics.dart';
import 'package:ride_metric_x/models/validation_report.dart';
import 'package:ride_metric_x/services/data_import/corrupted_data_exception.dart';
import 'package:ride_metric_x/services/data_import/data_import_service.dart';
import 'package:ride_metric_x/services/data_import/import_service.dart';
import 'package:ride_metric_x/services/data_import/platform_permission_exception.dart';
import 'package:ride_metric_x/services/data_import/synchronization_exception.dart';
import 'package:ride_metric_x/services/data_import/validation_exception.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal valid CSV with three data rows (enough for preprocessing).
const _validCsv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
10,0.02,-0.01,1.00,0.5,-0.3,0.1,25.4,2
''';

/// CSV with correct header but malformed data (missing required fields).
const _corruptedCsv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,GARBAGE,GARBAGE,GARBAGE,GARBAGE,GARBAGE,GARBAGE,GARBAGE,0
''';

/// Collects all [SessionImportState] events into a list.
Future<List<SessionImportState>> _collect(
  DataImportService svc, {
  FileSelection? front,
  FileSelection? rear,
  String? sessionId,
}) async {
  final events = <SessionImportState>[];
  await for (final s in svc.importSession(
    frontFile: front,
    rearFile: rear,
    sessionId: sessionId,
  )) {
    events.add(s);
  }
  return events;
}

FileSelection _csv(String name) =>
    FileSelection(fileName: name, content: _validCsv);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── SessionImportState hierarchy ─────────────────────────────────────────

  group('SessionImportState hierarchy', () {
    test('SessionImportIdle is a SessionImportState', () {
      expect(const SessionImportIdle(), isA<SessionImportState>());
    });

    test('SessionImportProgress carries stage and progress', () {
      const s = SessionImportProgress(ImportStage.parsing, 0.3);
      expect(s, isA<SessionImportState>());
      expect(s.stage, ImportStage.parsing);
      expect(s.progress, 0.3);
    });

    test('SessionImportError carries message', () {
      const s = SessionImportError('oops');
      expect(s, isA<SessionImportState>());
      expect(s.message, 'oops');
    });

    test('SessionImportSuccess carries session', () async {
      final svc = DataImportService();
      final events = await _collect(
        svc,
        front: _csv('front.csv'),
        sessionId: 'test-hierarchy',
      );
      expect(events.last, isA<SessionImportSuccess>());
      final success = events.last as SessionImportSuccess;
      expect(success.session, isA<RideSession>());
    });
  });

  // ── No-files guard ────────────────────────────────────────────────────────

  group('DataImportService – no files', () {
    test('emits SessionImportError when no files are provided', () async {
      final svc = DataImportService();
      final events = await _collect(svc);
      expect(events.last, isA<SessionImportError>());
    });

    test('error message is non-empty', () async {
      final svc = DataImportService();
      final events = await _collect(svc);
      expect((events.last as SessionImportError).message, isNotEmpty);
    });
  });

  // ── Front-only import ─────────────────────────────────────────────────────

  group('DataImportService – front-only import', () {
    late DataImportService svc;
    late List<SessionImportState> events;
    late RideSession session;

    setUpAll(() async {
      svc = DataImportService();
      events = await _collect(
        svc,
        front: _csv('front.csv'),
        sessionId: 'front-only',
      );
      session = (events.last as SessionImportSuccess).session;
    });

    test('terminal event is SessionImportSuccess', () {
      expect(events.last, isA<SessionImportSuccess>());
    });

    test('session has expected sessionId', () {
      expect(session.sessionId, 'front-only');
    });

    test('session has front metadata', () {
      expect(session.frontMetadata, isNotNull);
      expect(session.frontMetadata!.position, SensorPosition.front);
    });

    test('session has no rear metadata', () {
      expect(session.rearMetadata, isNull);
    });

    test('session has front processed samples', () {
      expect(session.frontProcessed, isNotEmpty);
    });

    test('session has no rear processed samples', () {
      expect(session.rearProcessed, isEmpty);
    });

    test('session has front validation report', () {
      expect(session.frontReport, isNotNull);
    });

    test('session has no sync result for single sensor', () {
      expect(session.syncResult, isNull);
    });

    test('session has a quality score', () {
      expect(session.qualityScore, isA<QualityScore>());
      expect(session.qualityScore.score, inInclusiveRange(0, 100));
    });

    test('importedAt is set', () {
      expect(session.importedAt, isA<DateTime>());
    });
  });

  // ── Rear-only import ──────────────────────────────────────────────────────

  group('DataImportService – rear-only import', () {
    test('succeeds with rear metadata and no front metadata', () async {
      final svc = DataImportService();
      final events = await _collect(
        svc,
        rear: _csv('rear.csv'),
        sessionId: 'rear-only',
      );
      expect(events.last, isA<SessionImportSuccess>());
      final session = (events.last as SessionImportSuccess).session;
      expect(session.rearMetadata, isNotNull);
      expect(session.rearMetadata!.position, SensorPosition.rear);
      expect(session.frontMetadata, isNull);
    });
  });

  // ── Front+rear import ─────────────────────────────────────────────────────

  group('DataImportService – front+rear import', () {
    late DataImportService svc;
    late List<SessionImportState> events;
    late RideSession session;

    setUpAll(() async {
      svc = DataImportService();
      events = await _collect(
        svc,
        front: _csv('front.csv'),
        rear: _csv('rear.csv'),
        sessionId: 'both',
      );
      session = (events.last as SessionImportSuccess).session;
    });

    test('terminal event is SessionImportSuccess', () {
      expect(events.last, isA<SessionImportSuccess>());
    });

    test('session has both front and rear metadata', () {
      expect(session.frontMetadata, isNotNull);
      expect(session.rearMetadata, isNotNull);
    });

    test('both front and rear processed samples are populated', () {
      expect(session.frontProcessed, isNotEmpty);
      expect(session.rearProcessed, isNotEmpty);
    });

    test('session has a sync result', () {
      expect(session.syncResult, isNotNull);
    });

    test('sync result correlationCoefficient is in [-1, 1]', () {
      final corr = session.syncResult!.correlationCoefficient;
      expect(corr, inInclusiveRange(-1.0, 1.0));
    });

    test('session has a quality score in [0, 100]', () {
      expect(session.qualityScore.score, inInclusiveRange(0, 100));
    });

    test('front metadata is paired with session id', () {
      expect(session.frontMetadata!.pairedSessionId, session.sessionId);
    });

    test('rear metadata is paired with session id', () {
      expect(session.rearMetadata!.pairedSessionId, session.sessionId);
    });
  });

  // ── Progress events ───────────────────────────────────────────────────────

  group('DataImportService – progress events', () {
    test('first event is SessionImportProgress(parsing, 0.0)', () async {
      final svc = DataImportService();
      final events =
          await _collect(svc, front: _csv('front.csv'), sessionId: 'prog1');
      expect(events.first, isA<SessionImportProgress>());
      final p = events.first as SessionImportProgress;
      expect(p.stage, ImportStage.parsing);
      expect(p.progress, 0.0);
    });

    test('progress values are non-decreasing', () async {
      final svc = DataImportService();
      final events =
          await _collect(svc, front: _csv('front.csv'), sessionId: 'prog2');
      final progresses = events
          .whereType<SessionImportProgress>()
          .map((e) => e.progress)
          .toList();
      for (int i = 1; i < progresses.length; i++) {
        expect(
          progresses[i],
          greaterThanOrEqualTo(progresses[i - 1]),
          reason: 'progress must not decrease',
        );
      }
    });

    test('last progress event has progress 1.0', () async {
      final svc = DataImportService();
      final events =
          await _collect(svc, front: _csv('front.csv'), sessionId: 'prog3');
      final progresses = events
          .whereType<SessionImportProgress>()
          .map((e) => e.progress)
          .toList();
      expect(progresses.last, 1.0);
    });

    test('all ImportStages appear in events for front+rear import', () async {
      final svc = DataImportService();
      final events = await _collect(
        svc,
        front: _csv('front.csv'),
        rear: _csv('rear.csv'),
        sessionId: 'prog4',
      );
      final stages =
          events.whereType<SessionImportProgress>().map((e) => e.stage).toSet();
      expect(stages, containsAll(ImportStage.values));
    });

    test('parsing stage appears before processing stage', () async {
      final svc = DataImportService();
      final events = await _collect(
        svc,
        front: _csv('front.csv'),
        sessionId: 'prog5',
      );
      final stageList = events
          .whereType<SessionImportProgress>()
          .map((e) => e.stage)
          .toList();
      final firstParsing = stageList.indexOf(ImportStage.parsing);
      final firstProcessing = stageList.indexOf(ImportStage.processing);
      expect(firstParsing, lessThan(firstProcessing));
    });
  });

  // ── Persistence (getImportedSession) ─────────────────────────────────────

  group('DataImportService – persistence', () {
    test('getImportedSession returns null before import', () {
      final svc = DataImportService();
      expect(svc.getImportedSession('nonexistent'), isNull);
    });

    test('getImportedSession returns session after successful import',
        () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('front.csv'), sessionId: 'persist-1');
      final retrieved = svc.getImportedSession('persist-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.sessionId, 'persist-1');
    });

    test('listImportedSessions returns all stored sessions', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'list-a');
      await _collect(svc, rear: _csv('r.csv'), sessionId: 'list-b');
      final sessions = svc.listImportedSessions();
      expect(sessions, hasLength(2));
      expect(
          sessions.map((s) => s.sessionId), containsAll(['list-a', 'list-b']));
    });

    test('clearImportedSession removes the session', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'clear-1');
      expect(svc.getImportedSession('clear-1'), isNotNull);
      svc.clearImportedSession('clear-1');
      expect(svc.getImportedSession('clear-1'), isNull);
    });

    test('clearImportedSession on nonexistent id is a no-op', () {
      final svc = DataImportService();
      expect(() => svc.clearImportedSession('nope'), returnsNormally);
    });
  });

  // ── Export / re-import parity ─────────────────────────────────────────────

  group('DataImportService – export/re-import parity', () {
    test('toMap contains expected top-level keys', () async {
      final svc = DataImportService();
      await _collect(
        svc,
        front: _csv('front.csv'),
        rear: _csv('rear.csv'),
        sessionId: 'parity-1',
      );
      final session = svc.getImportedSession('parity-1')!;
      final map = session.toMap();

      expect(map['session_id'], 'parity-1');
      expect(map['imported_at'], isA<String>());
      expect(map['front_metadata'], isNotNull);
      expect(map['rear_metadata'], isNotNull);
      expect(map['front_sample_count'], session.frontProcessed.length);
      expect(map['rear_sample_count'], session.rearProcessed.length);
      expect(map['quality_score'], isA<Map>());
    });

    test('quality_score map contains score and band', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'parity-2');
      final map = svc.getImportedSession('parity-2')!.toMap();
      final qs = map['quality_score'] as Map;
      expect(qs['score'], isA<int>());
      expect(qs['band'], isA<String>());
    });

    test('front_metadata map contains position and sampling_rate_hz', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'parity-3');
      final map = svc.getImportedSession('parity-3')!.toMap();
      final fm = map['front_metadata'] as Map;
      expect(fm['position'], 'front');
      expect(fm['sampling_rate_hz'], isA<double>());
    });

    test('imported_at is a valid ISO-8601 string', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'parity-4');
      final map = svc.getImportedSession('parity-4')!.toMap();
      expect(
          () => DateTime.parse(map['imported_at'] as String), returnsNormally);
    });

    test('toMap round-trip preserves session_id', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'roundtrip');
      final session = svc.getImportedSession('roundtrip')!;
      final map = session.toMap();
      expect(map['session_id'], session.sessionId);
    });
  });

  // ── Corrupted file path ───────────────────────────────────────────────────

  group('DataImportService – corrupted file', () {
    test('corrupted front file emits SessionImportError', () async {
      final svc = DataImportService();
      const corrupted = FileSelection(
        fileName: 'corrupted.csv',
        content: _corruptedCsv,
      );
      final events = await _collect(svc, front: corrupted);
      expect(events.last, isA<SessionImportError>());
    });

    test('error message is non-empty for corrupted file', () async {
      final svc = DataImportService();
      const corrupted = FileSelection(
        fileName: 'corrupted.csv',
        content: _corruptedCsv,
      );
      final events = await _collect(svc, front: corrupted);
      expect((events.last as SessionImportError).message, isNotEmpty);
    });

    test('unknown file extension emits SessionImportError', () async {
      final svc = DataImportService();
      const unknown = FileSelection(fileName: 'data.xyz', content: 'stuff');
      final events = await _collect(svc, front: unknown);
      expect(events.last, isA<SessionImportError>());
    });
  });

  // ── Permission failure path ───────────────────────────────────────────────

  group('DataImportService – permission failure', () {
    test('onBeforeImport throwing PlatformPermissionException → error',
        () async {
      final svc = DataImportService(
        onBeforeImport: () =>
            throw const PlatformPermissionException('Storage access denied'),
      );
      final events = await _collect(svc, front: _csv('front.csv'));
      expect(events.last, isA<SessionImportError>());
    });

    test('SessionImportError message reflects permission denial', () async {
      final svc = DataImportService(
        onBeforeImport: () =>
            throw const PlatformPermissionException('Storage access denied'),
      );
      final events = await _collect(svc, front: _csv('front.csv'));
      final error = events.last as SessionImportError;
      expect(error.message, contains('Storage access denied'));
    });
  });

  // ── QualityScore ──────────────────────────────────────────────────────────

  group('QualityScore', () {
    test('score 100 → excellent band', () {
      expect(const QualityScore(100).band, QualityBand.excellent);
    });

    test('score 90 → excellent band', () {
      expect(const QualityScore(90).band, QualityBand.excellent);
    });

    test('score 89 → good band', () {
      expect(const QualityScore(89).band, QualityBand.good);
    });

    test('score 70 → good band', () {
      expect(const QualityScore(70).band, QualityBand.good);
    });

    test('score 69 → fair band', () {
      expect(const QualityScore(69).band, QualityBand.fair);
    });

    test('score 50 → fair band', () {
      expect(const QualityScore(50).band, QualityBand.fair);
    });

    test('score 49 → poor band', () {
      expect(const QualityScore(49).band, QualityBand.poor);
    });

    test('score 0 → poor band', () {
      expect(const QualityScore(0).band, QualityBand.poor);
    });

    test('compute with no reports returns score 0', () {
      final score = QualityScore.compute();
      expect(score.score, 0);
    });

    test('compute with clean report returns high score', () {
      const report = ValidationReport(
        errors: [],
        warnings: [],
        metrics: ValidationMetrics(
          sampleCount: 1000,
          durationMs: 5000,
          effectiveSampleRateHz: 200.0,
          nanCount: 0,
          gapCount: 0,
          outlierCount: 0,
          stuckFieldCount: 0,
          correctedCount: 0,
        ),
        wasCorrected: false,
        corrections: [],
      );
      final score = QualityScore.compute(frontReport: report);
      expect(score.score, greaterThanOrEqualTo(90));
    });

    test('compute with many NaNs returns lower score', () {
      const cleanReport = ValidationReport(
        errors: [],
        warnings: [],
        metrics: ValidationMetrics(
          sampleCount: 100,
          durationMs: 500,
          effectiveSampleRateHz: 200.0,
          nanCount: 0,
          gapCount: 0,
          outlierCount: 0,
          stuckFieldCount: 0,
          correctedCount: 0,
        ),
        wasCorrected: false,
        corrections: [],
      );
      const dirtyReport = ValidationReport(
        errors: [],
        warnings: [],
        metrics: ValidationMetrics(
          sampleCount: 100,
          durationMs: 500,
          effectiveSampleRateHz: 200.0,
          nanCount: 200,
          gapCount: 10,
          outlierCount: 20,
          stuckFieldCount: 2,
          correctedCount: 0,
        ),
        wasCorrected: false,
        corrections: [],
      );
      final cleanScore = QualityScore.compute(frontReport: cleanReport);
      final dirtyScore = QualityScore.compute(frontReport: dirtyReport);
      expect(dirtyScore.score, lessThan(cleanScore.score));
    });

    test('toMap contains score and band', () {
      final map = const QualityScore(75).toMap();
      expect(map['score'], 75);
      expect(map['band'], 'good');
    });

    test('equality is based on score', () {
      expect(const QualityScore(80), const QualityScore(80));
      expect(const QualityScore(80), isNot(const QualityScore(79)));
    });

    test('toString includes score and band', () {
      final s = const QualityScore(65).toString();
      expect(s, contains('65'));
      expect(s, contains('fair'));
    });
  });

  // ── Domain exceptions ─────────────────────────────────────────────────────

  group('Domain exceptions', () {
    test('CorruptedDataException toString includes message', () {
      const e = CorruptedDataException('bad data', fileName: 'file.csv');
      expect(e.toString(), contains('bad data'));
      expect(e.toString(), contains('file.csv'));
    });

    test('CorruptedDataException without fileName omits file part', () {
      const e = CorruptedDataException('bad data');
      expect(e.toString(), isNot(contains('file')));
    });

    test('PlatformPermissionException toString includes message', () {
      const e = PlatformPermissionException('denied', path: '/data');
      expect(e.toString(), contains('denied'));
      expect(e.toString(), contains('/data'));
    });

    test('PlatformPermissionException without path omits path part', () {
      const e = PlatformPermissionException('denied');
      expect(e.toString(), isNot(contains('path')));
    });

    test('SynchronizationException toString includes message', () {
      const e = SynchronizationException('no overlap');
      expect(e.toString(), contains('no overlap'));
    });

    test('ValidationException toString includes message and count', () {
      const e = ValidationException('failed', errors: []);
      expect(e.toString(), contains('failed'));
    });

    test('ValidationException with errors includes error count', () {
      final e = ValidationException(
        'failed',
        errors: [const ValidationError(message: 'err1')],
      );
      expect(e.toString(), contains('1 error(s)'));
    });
  });

  // ── RideSession.toString ──────────────────────────────────────────────────

  group('RideSession', () {
    test('toString includes sessionId', () async {
      final svc = DataImportService();
      await _collect(svc, front: _csv('f.csv'), sessionId: 'str-test');
      final session = svc.getImportedSession('str-test')!;
      expect(session.toString(), contains('str-test'));
    });
  });
}
