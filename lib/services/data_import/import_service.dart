import '../../models/imu_sample.dart';
import '../../models/session_metadata.dart';
import '../../models/validation_report.dart';
import 'binary_parser.dart';
import 'csv_import_parser.dart';
import 'data_format.dart';
import 'data_parser.dart';
import 'file_format_exception.dart';
import 'json_import_parser.dart';
import 'jsonl_parser.dart';
import 'validation_service.dart';

/// A file selected by the user for import.
///
/// Bundles the original [fileName] (used for format detection) with the
/// already-decoded text [content].
class FileSelection {
  const FileSelection({required this.fileName, required this.content});

  /// Original file name, e.g. `front_session.csv`.
  ///
  /// Used by [DataFormatDetector] to identify the data format.
  final String fileName;

  /// Decoded text content of the file.
  final String content;
}

/// Represents a step in the import pipeline emitted by [ImportService].
sealed class ImportState {}

/// Import has not yet started.
class ImportIdle extends ImportState {
  ImportIdle();
}

/// Import is running; [progress] ∈ [0.0, 1.0] indicates completion.
class ImportInProgress extends ImportState {
  ImportInProgress(this.progress);

  /// Completion fraction in [0.0, 1.0].
  final double progress;
}

/// Import completed successfully.
class ImportSuccess extends ImportState {
  ImportSuccess({
    required this.report,
    required this.position,
    required this.fileName,
    required this.samples,
  });

  /// Validation result for the imported data.
  final ValidationReport report;

  /// Sensor position this file corresponds to.
  final SensorPosition position;

  /// Original file name.
  final String fileName;

  /// Parsed and validated IMU samples.
  final List<ImuSample> samples;
}

/// Import failed; [message] describes the problem.
class ImportError extends ImportState {
  ImportError(this.message);

  /// Human-readable description of what went wrong.
  final String message;
}

/// Orchestrates the full file import pipeline.
///
/// Steps (progress milestones):
/// 1. Format detection  – 0.0 → 0.2
/// 2. Parsing           – 0.2 → 0.5
/// 3. Record mapping    – 0.5 → 0.7
/// 4. Validation        – 0.7 → 1.0
/// 5. Terminal event: [ImportSuccess] or [ImportError]
class ImportService {
  const ImportService({this.validator = const ValidationService()});

  /// Validation rules applied after parsing.
  final ValidationService validator;

  /// Runs the import pipeline for [selection] and [position].
  ///
  /// Emits [ImportInProgress] events at each pipeline stage, followed by
  /// either [ImportSuccess] or [ImportError].
  Stream<ImportState> importFile(
    FileSelection selection,
    SensorPosition position,
  ) async* {
    yield ImportInProgress(0.0);

    try {
      // ── 1. Format detection (0 → 20 %) ──────────────────────────────────
      final format = DataFormatDetector.detect(selection.fileName);
      yield ImportInProgress(0.2);

      // ── 2. Parse (20 → 50 %) ────────────────────────────────────────────
      final DataParser parser;
      switch (format) {
        case DataFormat.csv:
          parser = const CsvImportParser();
        case DataFormat.json:
          parser = const JsonImportParser();
        case DataFormat.jsonl:
          parser = const JsonlParser();
        case DataFormat.binary:
          parser = const BinaryParser();
      }
      final records = parser.parse(selection.content);
      yield ImportInProgress(0.5);

      // ── 3. Record → ImuSample (50 → 70 %) ───────────────────────────────
      if (records.isEmpty) {
        yield ImportError(
          'No records found in "${selection.fileName}".',
        );
        return;
      }
      final samples = _mapRecords(records);
      yield ImportInProgress(0.7);

      // ── 4. Validate (70 → 100 %) ────────────────────────────────────────
      final report = validator.validate(samples);
      yield ImportInProgress(1.0);

      yield ImportSuccess(
        report: report,
        position: position,
        fileName: selection.fileName,
        samples: samples,
      );
    } on FileFormatException catch (e) {
      yield ImportError(e.message);
    } on FormatException catch (e) {
      yield ImportError(e.message);
    } catch (e) {
      yield ImportError(e.toString());
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Maps raw parser records to [ImuSample] objects.
  ///
  /// Throws [FormatException] when a required field is missing or has an
  /// incompatible type.
  List<ImuSample> _mapRecords(List<Map<String, dynamic>> records) {
    final samples = <ImuSample>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      try {
        samples.add(
          ImuSample(
            timestampMs: _toInt(r['timestamp_ms']),
            accelXG: _toDouble(r['accel_x_g']),
            accelYG: _toDouble(r['accel_y_g']),
            accelZG: _toDouble(r['accel_z_g']),
            gyroXDps: _toDouble(r['gyro_x_dps']),
            gyroYDps: _toDouble(r['gyro_y_dps']),
            gyroZDps: _toDouble(r['gyro_z_dps']),
            tempC: _toDouble(r['temp_c']),
            sampleCount: _toInt(r['sample_count']),
          ),
        );
      } catch (e) {
        throw FormatException('Row ${i + 1}: $e');
      }
    }
    return samples;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.parse(v.trim());
    throw FormatException(
      'Expected integer, got ${v.runtimeType}',
    );
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.parse(v.trim());
    throw FormatException(
      'Expected number, got ${v.runtimeType}',
    );
  }
}
