import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';

class Logger {
  static final app = Loggy("app");
  static final bootstrap = Loggy("bootstrap");

  static void logFlutterError(FlutterErrorDetails details) {
    if (details.silent) {
      return;
    }

    final description = details.exceptionAsString();

    app.error('Flutter Error: $description', details.exception, details.stack);
    // The line above drops Flutter's context (which widget, which source line,
    // e.g. the Row that overflowed); print the full report in debug builds.
    if (kDebugMode) FlutterError.dumpErrorToConsole(details, forceReport: true);
  }

  static bool logPlatformDispatcherError(Object error, StackTrace stackTrace) {
    app.error('PlatformDispatcherError: $error', error, stackTrace);
    return true;
  }
}
