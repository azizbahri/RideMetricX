import 'dart:convert';

import 'package:archive/archive.dart';

import 'file_format_exception.dart';

/// Supported compression wrappers for import files.
enum CompressionFormat {
  /// gzip (`.gz`) single-stream compression.
  gzip,

  /// ZIP archive (`.zip`), expected to contain a single importable file.
  zip,
}

/// Decompresses `.gz` and `.zip` byte streams into a UTF-8 string.
///
/// For `.gz` files the entire stream is decompressed as a single payload.
///
/// For `.zip` files the archive is expected to contain at least one
/// non-directory entry; the first such entry is decoded and returned.
/// When the archive contains multiple entries, only the first is used.
///
/// Throws [FileFormatException] when decompression fails or the archive
/// contains no suitable entries.
class Decompressor {
  const Decompressor._();

  /// Decompresses [bytes] using [format] and returns the decoded string.
  ///
  /// Throws [FileFormatException] on decompression errors or empty result.
  static String decompress(List<int> bytes, CompressionFormat format) {
    switch (format) {
      case CompressionFormat.gzip:
        return _decompressGzip(bytes);
      case CompressionFormat.zip:
        return _decompressZip(bytes);
    }
  }

  /// Detects the [CompressionFormat] from a file name extension.
  ///
  /// Throws [FileFormatException] for unsupported extensions.
  static CompressionFormat formatFromFileName(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'gz':
        return CompressionFormat.gzip;
      case 'zip':
        return CompressionFormat.zip;
      default:
        throw FileFormatException(
          'Unsupported compression format ".$ext". '
          'Only .gz and .zip are supported.',
        );
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  static String _decompressGzip(List<int> bytes) {
    try {
      final decoded = GZipDecoder().decodeBytes(bytes);
      return utf8.decode(decoded);
    } catch (e) {
      throw FileFormatException(
        'Failed to decompress gzip stream: $e',
      );
    }
  }

  static String _decompressZip(List<int> bytes) {
    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FileFormatException('Failed to decode ZIP archive: $e');
    }

    final entries =
        archive.files.where((f) => !f.isDirectory && f.size > 0).toList();

    if (entries.isEmpty) {
      throw const FileFormatException(
        'ZIP archive contains no importable files.',
      );
    }

    try {
      return utf8.decode(entries.first.content);
    } on FormatException catch (e) {
      final location = e.offset != null ? ' at byte offset ${e.offset}' : '';
      throw FileFormatException(
        'ZIP entry "${entries.first.name}" contains invalid UTF-8$location: '
        '${e.message}',
      );
    } catch (e) {
      throw FileFormatException(
        'Failed to decode ZIP entry "${entries.first.name}" as UTF-8: $e',
      );
    }
  }
}
