/// Date/time helper utilities for the monetization package.
abstract final class MonetizationDateUtils {
  /// Returns true if [date] is in the future (not yet expired).
  static bool isActive(DateTime? date) {
    if (date == null) return false;
    return date.isAfter(DateTime.now());
  }

  /// Returns true if [date] is in the past (expired).
  static bool isExpired(DateTime? date) {
    if (date == null) return false;
    return date.isBefore(DateTime.now());
  }

  /// Returns true if [date] is within [window] from now (approaching expiry).
  static bool isWithinWindow(DateTime? date, Duration window) {
    if (date == null) return false;
    final cutoff = DateTime.now().add(window);
    return date.isBefore(cutoff) && date.isAfter(DateTime.now());
  }

  /// Parses an ISO-8601 string safely, returning null on failure.
  static DateTime? tryParseIso(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Converts a Unix epoch milliseconds timestamp to [DateTime].
  static DateTime? fromEpochMs(int? ms) {
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
}
