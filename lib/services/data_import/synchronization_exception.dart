/// Exception thrown when the front/rear IMU stream synchronisation fails.
///
/// Common causes include mismatched sample lengths, time ranges with no
/// overlap, or a cross-correlation coefficient below an acceptable threshold.
class SynchronizationException implements Exception {
  /// Human-readable description of the synchronisation failure.
  final String message;

  const SynchronizationException(this.message);

  @override
  String toString() => 'SynchronizationException: $message';
}
