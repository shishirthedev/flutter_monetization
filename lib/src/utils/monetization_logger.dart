// ignore_for_file: avoid_print

/// Log verbosity levels for the package's internal logger.
enum MonetizationLogLevel { none, error, warning, info, debug }

/// Lightweight internal logger. Does NOT depend on any third-party library.
/// In production builds, set logLevel to [MonetizationLogLevel.none].
class MonetizationLogger {
  MonetizationLogger(this._level);

  MonetizationLogLevel _level;

  void setLevel(MonetizationLogLevel level) => _level = level;

  void debug(String message) {
    if (_level.index >= MonetizationLogLevel.debug.index) {
      print('[MonetizationSDK][DEBUG] $message');
    }
  }

  void info(String message) {
    if (_level.index >= MonetizationLogLevel.info.index) {
      print('[MonetizationSDK][INFO] $message');
    }
  }

  void warning(String message) {
    if (_level.index >= MonetizationLogLevel.warning.index) {
      print('[MonetizationSDK][WARN] $message');
    }
  }

  void error(String message, [Object? err, StackTrace? st]) {
    if (_level.index >= MonetizationLogLevel.error.index) {
      print('[MonetizationSDK][ERROR] $message${err != null ? ' | $err' : ''}');
      if (st != null) print(st);
    }
  }
}

/// Package-level singleton logger. Replaced during init with the configured level.
final MonetizationLogger logger = MonetizationLogger(MonetizationLogLevel.info);
