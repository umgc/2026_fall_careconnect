import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global test configuration — runs before every test file.
///
/// Suppresses the ink_sparkle.frag shader exception that occurs on
/// Flutter 3.44.x when tester.tap() triggers an InkSplash animation.
/// The shader binary format version mismatch is a test-environment-only
/// issue and does not affect production builds.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Install a global error handler that drops shader compilation errors.
  // This covers both FlutterError and plain Exception paths.
  final origFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    if (msg.contains('ink_sparkle') ||
        msg.contains('runtime stages format version') ||
        msg.contains('FragmentProgram')) {
      return;
    }
    if (origFlutterError != null) {
      origFlutterError(details);
    }
  };

  final origPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    final msg = error.toString();
    if (msg.contains('ink_sparkle') ||
        msg.contains('runtime stages format version') ||
        msg.contains('FragmentProgram')) {
      return true;
    }
    if (origPlatformError != null) {
      return origPlatformError(error, stack);
    }
    return false;
  };

  await testMain();
}
