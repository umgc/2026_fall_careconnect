import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telemetry.dart';

/// Maps an API path to a coarse, anonymous endpoint bucket.
///
/// Never returns full paths or segments that may contain patient IDs.
String bucketEndpoint(String path) {
  final lower = path.toLowerCase();

  if (lower.contains('/dev/telemetry') || lower.endsWith('/telemetry')) {
    return 'telemetry';
  }
  if (lower.contains('/evv')) return 'evv';
  if (lower.contains('/calls')) return 'calls';
  if (lower.contains('/patients')) return 'patients';
  if (lower.contains('/caregivers')) return 'caregivers';
  if (lower.contains('/auth')) return 'auth';
  if (lower.contains('/messages') || lower.contains('/chat')) return 'chat';
  if (lower.contains('/tasks')) return 'tasks';
  if (lower.contains('/analytics')) return 'analytics';

  return 'api';
}

bool isTelemetryEndpoint(String endpoint) => endpoint == 'telemetry';

bool isTimeoutError(Object error) => error is TimeoutException;

bool isNetworkError(Object error) {
  if (error is TimeoutException) {
    return false;
  }
  if (error is SocketException || error is http.ClientException) {
    return true;
  }

  final lower = error.runtimeType.toString().toLowerCase();
  if (lower.contains('socketexception') || lower.contains('clientexception')) {
    return true;
  }

  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset');
}

String networkErrorType(Object error) {
  if (error is SocketException) return 'socket';
  if (error is http.ClientException) return 'client';
  return 'connection';
}

void recordHttpTimeout({
  required String source,
  required String method,
  required String endpoint,
  int? timeoutMs,
}) {
  if (isTelemetryEndpoint(endpoint)) return;

  final details = <String, Object?>{
    'source': source,
    'method': method,
    'endpoint': endpoint,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
  };

  unawaited(Telemetry.event('error_timeout', details));
}

void recordHttpNetworkError({
  required String source,
  required String method,
  required String endpoint,
  int statusCode = 0,
  required String errorType,
}) {
  if (isTelemetryEndpoint(endpoint)) return;

  unawaited(Telemetry.event('error_network', {
    'source': source,
    'method': method,
    'endpoint': endpoint,
    'statusCode': statusCode,
    'errorType': errorType,
  }));
}

/// Emits [error_timeout] or [error_network] for uncaught errors that look
/// network-related. Does not log exception text or stack traces.
void tryRecordUncaughtError(Object error) {
  if (isTimeoutError(error)) {
    recordHttpTimeout(
      source: 'dart',
      method: 'UNKNOWN',
      endpoint: 'api',
    );
    return;
  }

  if (isNetworkError(error)) {
    recordHttpNetworkError(
      source: 'dart',
      method: 'UNKNOWN',
      endpoint: 'api',
      errorType: networkErrorType(error),
    );
  }
}

/// Installs global handlers that preserve existing Flutter error presentation
/// while emitting anonymous HTTP-related telemetry for network failures.
void installTelemetryErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint(
        'FlutterError: \n${details.exceptionAsString()}\n${details.stack}',
      );
    }
    tryRecordUncaughtError(details.exception);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    tryRecordUncaughtError(error);
    return false;
  };
}

void recordZoneUncaughtError(Object error) {
  tryRecordUncaughtError(error);
}
