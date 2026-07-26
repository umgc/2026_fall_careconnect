import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import '../../config/environment_config.dart';
import 'pending_transcript_segment.dart';

sealed class TranscriptUploadOutcome {
  const TranscriptUploadOutcome();
}

final class TranscriptUploadSucceeded extends TranscriptUploadOutcome {
  const TranscriptUploadSucceeded({this.duplicate = false});

  final bool duplicate;
}

final class TranscriptUploadAuthPaused extends TranscriptUploadOutcome {
  const TranscriptUploadAuthPaused();
}

final class TranscriptUploadTerminal extends TranscriptUploadOutcome {
  const TranscriptUploadTerminal(this.statusCode);

  final int statusCode;
}

final class TranscriptUploadRetryable extends TranscriptUploadOutcome {
  const TranscriptUploadRetryable({this.retryAfter});

  final Duration? retryAfter;
}

abstract interface class TranscriptSegmentUploader {
  Future<TranscriptUploadOutcome> upload(
    PendingTranscriptSegment segment,
    String jwtToken,
  );
}

class HttpTranscriptSegmentUploader implements TranscriptSegmentUploader {
  HttpTranscriptSegmentUploader({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 8),
    String? baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl ?? EnvironmentConfig.baseUrl;

  final http.Client? _client;
  final Duration requestTimeout;
  final String _baseUrl;

  @override
  Future<TranscriptUploadOutcome> upload(
    PendingTranscriptSegment segment,
    String jwtToken,
  ) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/v3/calls/${segment.callId}/transcript/segments',
      );
      final response = await (_client == null
              ? http.post(
                  uri,
                  headers: _headers(jwtToken),
                  body: jsonEncode(segment.toUploadJson()),
                )
              : _client.post(
                  uri,
                  headers: _headers(jwtToken),
                  body: jsonEncode(segment.toUploadJson()),
                ))
          .timeout(requestTimeout);
      return classifyTranscriptUploadResponse(response);
    } on TimeoutException {
      return const TranscriptUploadRetryable();
    } on http.ClientException {
      return const TranscriptUploadRetryable();
    } catch (_) {
      return const TranscriptUploadRetryable();
    }
  }

  Map<String, String> _headers(String jwtToken) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      };
}

TranscriptUploadOutcome classifyTranscriptUploadResponse(
  http.Response response, {
  DateTime? now,
}) {
  final status = response.statusCode;
  if (status >= 200 && status < 300) {
    var duplicate = false;
    try {
      final body = jsonDecode(response.body);
      duplicate = body is Map<String, dynamic> && body['savedSegments'] == 0;
    } catch (_) {
      // A valid 2xx with a non-JSON body is still successful.
    }
    return TranscriptUploadSucceeded(duplicate: duplicate);
  }
  if (status == 409) {
    return const TranscriptUploadSucceeded(duplicate: true);
  }
  if (status == 401) {
    return const TranscriptUploadAuthPaused();
  }
  if (const <int>{400, 403, 404, 410, 422}.contains(status)) {
    return TranscriptUploadTerminal(status);
  }
  if (status == 429) {
    return TranscriptUploadRetryable(
      retryAfter: parseRetryAfter(response.headers['retry-after'], now: now),
    );
  }
  if (status == 408 || status == 425 || (status >= 500 && status < 600)) {
    return const TranscriptUploadRetryable();
  }
  return TranscriptUploadTerminal(status);
}

Duration? parseRetryAfter(String? value, {DateTime? now}) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final seconds = int.tryParse(normalized);
  if (seconds != null) {
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }
  DateTime? date = DateTime.tryParse(normalized)?.toUtc();
  if (date == null) {
    try {
      date = parseHttpDate(normalized).toUtc();
    } on FormatException {
      return null;
    }
  }
  final delay = date.difference((now ?? DateTime.now()).toUtc());
  return delay.isNegative ? Duration.zero : delay;
}
