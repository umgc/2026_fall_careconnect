import 'dart:async';

import 'package:http/http.dart' as http;

import '../features/telemetry/telemetry_error_handler.dart';

/// HTTP client wrapper that emits anonymous [error_network] and
/// [error_timeout] telemetry for transport-level failures.
class TelemetryHttpClient extends http.BaseClient {
  TelemetryHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final endpoint = bucketEndpoint(request.url.path);
    if (isTelemetryEndpoint(endpoint)) {
      return _inner.send(request);
    }

    final method = request.method.toUpperCase();

    try {
      return await _inner.send(request);
    } on TimeoutException {
      recordHttpTimeout(
        source: 'http',
        method: method,
        endpoint: endpoint,
      );
      rethrow;
    } catch (error) {
      if (isNetworkError(error)) {
        recordHttpNetworkError(
          source: 'http',
          method: method,
          endpoint: endpoint,
          errorType: networkErrorType(error),
        );
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
