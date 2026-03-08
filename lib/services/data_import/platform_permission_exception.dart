/// Exception thrown when the application lacks the platform permissions
/// required to access a requested file or resource.
///
/// On mobile platforms this typically means the user denied storage or media
/// access. On desktop it can arise from file-system ACLs or sandboxing
/// restrictions.
class PlatformPermissionException implements Exception {
  /// Human-readable description of the permission failure.
  final String message;

  /// File-system path that could not be accessed, if known.
  final String? path;

  const PlatformPermissionException(this.message, {this.path});

  @override
  String toString() {
    final pathPart = path != null ? ' (path: $path)' : '';
    return 'PlatformPermissionException: $message$pathPart';
  }
}
