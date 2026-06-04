import 'dart:async';

import 'package:flutter/foundation.dart';

/// Central sink for user-facing error messages. Uncaught Flutter framework and
/// platform errors are forwarded here (via [install]) and surfaced by a listener
/// in the widget tree, so failures show a snackbar instead of vanishing.
class AppErrorReporter {
  final _controller = StreamController<String>.broadcast();

  /// A stream of human-readable messages to present to the user.
  Stream<String> get messages => _controller.stream;

  /// Push an error to the UI. Safe to call after [dispose] (no-op).
  void report(Object error, [StackTrace? stack]) {
    if (_controller.isClosed) return;
    _controller.add(friendlyMessage(error));
  }

  /// Route uncaught framework/platform errors here while preserving the default
  /// console/red-screen behaviour. Call once at startup.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details); // keep console logging / red screen in debug
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true; // handled — don't crash the app
    };
  }

  void dispose() => _controller.close();

  /// Map an arbitrary error to a concise, human-friendly message. Business
  /// invariants throw [StateError] with an already-readable message.
  static String friendlyMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is FormatException) {
      return error.message.isEmpty
          ? 'Invalid input.'
          : 'Invalid input: ${error.message}';
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Invalid argument.';
    }
    final text = error.toString();
    const max = 200;
    return text.length > max ? '${text.substring(0, max)}…' : text;
  }
}
