import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'app_database_stub.dart' if (dart.library.io) 'app_database.dart';
import 'offline_sync_row.dart';
import '../auth_token_manager.dart';

class OfflineSyncQueueItem {
  const OfflineSyncQueueItem({
    required this.id,
    required this.method,
    required this.url,
    required this.displayTitle,
    required this.displayDetails,
    required this.createdAt,
    required this.retryCount,
    required this.status,
    this.lastError,
  });

  final String id;
  final String method;
  final String url;
  final String displayTitle;
  final List<String> displayDetails;
  final DateTime createdAt;
  final int retryCount;
  final String status;
  final String? lastError;
}

class OfflineSyncRunSummary {
  const OfflineSyncRunSummary({
    required this.attempted,
    required this.succeeded,
    required this.failed,
  });

  final int attempted;
  final int succeeded;
  final int failed;
}

class OfflineSyncService {
  OfflineSyncService._internal({
    AppDatabase? appDatabase,
    http.Client? replayClient,
  })  : _appDatabase = appDatabase ?? AppDatabase(),
        _replayClient = replayClient ?? http.Client();

  static final OfflineSyncService _instance = OfflineSyncService._internal();

  static const String replayHeader = 'x-careconnect-offline-replay';
  static const Set<String> _queueableMethods = <String>{
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };

  final AppDatabase _appDatabase;
  final http.Client _replayClient;
  final Uuid _uuid = const Uuid();

  factory OfflineSyncService.instance() => _instance;

  bool isQueueableMethod(String method) {
    return _queueableMethods.contains(method.toUpperCase());
  }

  Future<void> initialize() async {
    await _appDatabase.ensureOfflineSyncTable();
  }

  Future<String> enqueueRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    String? body,
  }) async {
    final normalizedHeaders = _normalizeHeaders(headers ?? <String, String>{});
    final normalizedBody =
        (body == null || body.isEmpty) ? null : body;
    final createdAt = DateTime.now().toUtc();
    final fingerprint = _buildFingerprint(
      method: method,
      uri: uri,
      headers: normalizedHeaders,
      body: normalizedBody,
    );

    final queuedId = await _appDatabase.upsertOfflineSyncOperation(
      id: _uuid.v4(),
      method: method.toUpperCase(),
      url: uri.toString(),
      headersJson: jsonEncode(normalizedHeaders),
      bodyJson: normalizedBody,
      createdAtIso: createdAt.toIso8601String(),
      fingerprint: fingerprint,
    );

    return queuedId;
  }

  Future<int> getPendingCount() async {
    return _appDatabase.getPendingOfflineSyncCount();
  }

  Future<List<OfflineSyncQueueItem>> getPendingQueue({
    int limit = 200,
  }) async {
    final rows = await _appDatabase.getPendingOfflineSyncQueue(limit: limit);
    return rows.map(_toQueueItem).toList();
  }

  Future<bool> deleteQueuedRequestById(String id) async {
    final existing = await _appDatabase.getOfflineSyncById(id);
    if (existing == null) {
      return false;
    }
    await _appDatabase.deleteOfflineSyncById(id);
    return true;
  }

  Future<bool> syncQueuedRequestById(String id) async {
    final row = await _appDatabase.getOfflineSyncById(id);
    if (row == null) {
      return true;
    }
    if (row.status != 'pending' &&
        row.status != 'failed' &&
        row.status != 'syncing') {
      return false;
    }
    return _syncRow(row);
  }

  Future<OfflineSyncRunSummary> syncPendingQueue({int limit = 200}) async {
    final rows = await _appDatabase.getPendingOfflineSyncQueue(limit: limit);
    if (rows.isEmpty) {
      return const OfflineSyncRunSummary(
        attempted: 0,
        succeeded: 0,
        failed: 0,
      );
    }

    var succeeded = 0;
    var failed = 0;

    for (final row in rows) {
      final ok = await _syncRow(row);
      if (ok) {
        succeeded++;
      } else {
        failed++;
      }
    }

    return OfflineSyncRunSummary(
      attempted: rows.length,
      succeeded: succeeded,
      failed: failed,
    );
  }

  http.StreamedResponse buildQueuedStreamedResponse(
    http.BaseRequest request, {
    required String queuedId,
  }) {
    final body = jsonEncode(<String, dynamic>{
      'queued': true,
      'offline': true,
      'requestId': queuedId,
      'message': 'Request queued for retry when network is restored.',
    });

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
      headers: <String, String>{
        'content-type': 'application/json',
        'x-offline-queued': 'true',
        'x-offline-request-id': queuedId,
      },
      reasonPhrase: 'OK (queued offline)',
    );
  }

  bool shouldQueueForError(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    if (error is http.ClientException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('timed out');
  }

  Future<void> close() async {
    _replayClient.close();
    await _appDatabase.closeDb();
  }

  Future<bool> _syncRow(OfflineSyncDbRow row) async {
    await _appDatabase.markOfflineSyncAsSyncing(row.id);

    Uri uri;
    try {
      uri = Uri.parse(row.url);
    } catch (_) {
      await _appDatabase.markOfflineSyncAsFailed(
        id: row.id,
        errorMessage: 'Invalid queued URL',
      );
      return false;
    }

    final headers = _decodeHeaders(row.headersJson);
    try {
      final authHeaders = await AuthTokenManager.getAuthHeaders();
      final authorization = authHeaders['Authorization'];
      if (authorization != null && authorization.isNotEmpty) {
        headers['Authorization'] = authorization;
      }
    } catch (_) {}
    headers[replayHeader] = 'true';

    final request = http.Request(row.method, uri);
    request.headers.addAll(headers);
    if (row.bodyJson != null && row.bodyJson!.isNotEmpty) {
      request.body = row.bodyJson!;
    }

    try {
      final streamed = await _replayClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (_isReplaySuccess(response.statusCode)) {
        await _appDatabase.deleteOfflineSyncById(row.id);
        return true;
      }
      await _appDatabase.markOfflineSyncAsFailed(
        id: row.id,
        errorMessage:
            'HTTP ${response.statusCode}: ${_truncate(response.body)}',
      );
      return false;
    } catch (error) {
      await _appDatabase.markOfflineSyncAsFailed(
        id: row.id,
        errorMessage: _truncate(error.toString()),
      );
      return false;
    }
  }

  OfflineSyncQueueItem _toQueueItem(OfflineSyncDbRow row) {
    final display = _buildSafeDisplay(
      url: row.url,
      bodyJson: row.bodyJson,
      createdAt: row.createdAt,
    );

    return OfflineSyncQueueItem(
      id: row.id,
      method: row.method,
      url: row.url,
      displayTitle: display.title,
      displayDetails: display.details,
      createdAt: row.createdAt,
      retryCount: row.retryCount,
      status: row.status,
      lastError: row.lastError,
    );
  }

  _SafeDisplay _buildSafeDisplay({
    required String url,
    required String? bodyJson,
    required DateTime createdAt,
  }) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    final body = _decodeBodyMap(bodyJson);

    if (path.contains('/mood-pain-log')) {
      final moodValue = body['moodValue'];
      final timestamp = _formatIsoDateTime(body['timestamp']?.toString()) ??
          _formatDateTime(createdAt);
      return _SafeDisplay(
        title: 'Mood Check-In',
        details: <String>[
          'Mood rating: ${moodValue ?? '-'}',
          'Date: $timestamp',
        ],
      );
    }

    if (path.contains('/mood')) {
      final score = body['score'] ?? body['moodValue'];
      final label = body['label'];
      return _SafeDisplay(
        title: 'Mood Entry',
        details: <String>[
          'Mood rating: ${score ?? '-'}${label != null ? ' ($label)' : ''}',
          'Date: ${_formatDateTime(createdAt)}',
        ],
      );
    }

    if (path.contains('/tasks')) {
      final taskBody = _expandNestedTaskPayload(body);
      final title = _firstNonEmpty(
        taskBody,
        <String>['title', 'taskTitle', 'name', 'taskName'],
      );
      final note = _firstNonEmpty(
        taskBody,
        <String>['note', 'notes', 'description', 'details'],
      );
      final date = _firstNonEmpty(
        taskBody,
        <String>['taskDate', 'date', 'dueDate', 'scheduledDate'],
      );
      final time = _firstNonEmpty(
        taskBody,
        <String>['time', 'dueTime', 'scheduledTime'],
      );

      final details = <String>[
        'Title: ${title ?? '-'}',
        'Note: ${note ?? '-'}',
        'Task date: ${date ?? '-'}',
        'Task time: ${time ?? '-'}',
      ];

      return _SafeDisplay(title: 'Task', details: details);
    }

    final genericDetails = _buildGenericPayloadDetails(body);
    if (genericDetails.isNotEmpty) {
      return _SafeDisplay(
        title: 'Queued Update',
        details: genericDetails,
      );
    }

    return _SafeDisplay(
      title: 'Queued Update',
      details: <String>['Waiting to sync'],
    );
  }

  Map<String, dynamic> _decodeBodyMap(String? bodyJson) {
    if (bodyJson == null || bodyJson.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(bodyJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  List<String> _buildGenericPayloadDetails(Map<String, dynamic> body) {
    if (body.isEmpty) {
      return const <String>[];
    }

    final details = <String>[];
    final entries = body.entries.where((entry) {
      return !_isSensitiveField(entry.key);
    });

    for (final entry in entries) {
      final value = _toDisplayValue(entry.value);
      if (value == null || value.isEmpty) {
        continue;
      }
      details.add('${_humanizeField(entry.key)}: $value');
      if (details.length >= 5) {
        break;
      }
    }

    return details;
  }

  bool _isSensitiveField(String key) {
    final lower = key.toLowerCase();
    return lower.contains('password') ||
        lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('authorization') ||
        lower.contains('cookie') ||
        lower.contains('refresh');
  }

  String _humanizeField(String raw) {
    final withSpaces = raw.replaceAll(RegExp(r'[_-]+'), ' ').replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final trimmed = withSpaces.trim();
    if (trimmed.isEmpty) {
      return 'Field';
    }
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String? _toDisplayValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) {
        return null;
      }
      return _truncate(text, max: 80);
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is List) {
      if (value.isEmpty) {
        return null;
      }
      return '${value.length} item${value.length == 1 ? '' : 's'}';
    }
    if (value is Map) {
      if (value.isEmpty) {
        return null;
      }
      return '${value.length} field${value.length == 1 ? '' : 's'}';
    }
    return _truncate(value.toString(), max: 80);
  }

  Map<String, dynamic> _expandNestedTaskPayload(Map<String, dynamic> body) {
    final merged = Map<String, dynamic>.from(body);
    final nested = body['task'];
    if (nested is Map<String, dynamic>) {
      merged.addAll(nested);
      return merged;
    }
    if (nested is String && nested.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(nested);
        if (decoded is Map<String, dynamic>) {
          merged.addAll(decoded);
        }
      } catch (_) {}
    }
    return merged;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day/${local.year} $hour:$minute';
  }

  String? _formatIsoDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return _formatDateTime(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  Map<String, String> _normalizeHeaders(Map<String, String> headers) {
    final sorted = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final normalized = <String, String>{};
    for (final entry in sorted) {
      if (entry.key.toLowerCase() == replayHeader) {
        continue;
      }
      normalized[entry.key] = entry.value;
    }
    return normalized;
  }

  Map<String, String> _decodeHeaders(String headersJson) {
    try {
      final decoded = jsonDecode(headersJson);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {}
    return <String, String>{};
  }

  String _buildFingerprint({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    final stableHeaders = Map<String, String>.from(headers)
      ..removeWhere((key, _) {
        final lower = key.toLowerCase();
        return lower == 'authorization' ||
            lower == 'cookie' ||
            lower == 'set-cookie';
      });
    final payload = jsonEncode(<String, dynamic>{
      'method': method.toUpperCase(),
      'url': uri.toString(),
      'headers': stableHeaders,
      'body': body ?? '',
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool _isReplaySuccess(int statusCode) {
    return (statusCode >= 200 && statusCode < 300) || statusCode == 409;
  }

  String _truncate(String value, {int max = 300}) {
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}...';
  }
}

class _SafeDisplay {
  const _SafeDisplay({required this.title, required this.details});

  final String title;
  final List<String> details;
}

class OfflineQueueHttpClient extends http.BaseClient {
  OfflineQueueHttpClient({
    required http.Client inner,
    required OfflineSyncService offlineSyncService,
    bool Function()? canQueueWrites,
  })  : _inner = inner,
        _defaultInner = inner,
        _offlineSyncService = offlineSyncService,
        _canQueueWrites = canQueueWrites;

  http.Client _inner;
  final http.Client _defaultInner;
  final OfflineSyncService _offlineSyncService;
  final bool Function()? _canQueueWrites;

  /// Replace the inner transport used for outbound HTTP (tests only).
  @visibleForTesting
  void debugSetInnerClient(http.Client client) {
    _inner = client;
  }

  /// Restore the inner client created at construction time (tests only).
  @visibleForTesting
  void debugResetInnerClient() {
    _inner = _defaultInner;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final method = request.method.toUpperCase();
    final isQueueable = _offlineSyncService.isQueueableMethod(method);
    final isAuthEndpoint =
        request.url.path.toLowerCase().contains('/v1/api/auth/');
    final replayFlag = request.headers[OfflineSyncService.replayHeader];
    final canQueueWrites = _canQueueWrites?.call() ?? true;

    if (!isQueueable ||
        isAuthEndpoint ||
        request is http.MultipartRequest ||
        request is http.StreamedRequest ||
        replayFlag == 'true') {
      return _inner.send(request);
    }

    String? body;
    if (request is http.Request && request.body.isNotEmpty) {
      body = request.body;
    }

    try {
      return await _inner.send(request);
    } catch (error) {
      if (!canQueueWrites || !_offlineSyncService.shouldQueueForError(error)) {
        rethrow;
      }

      final queuedId = await _offlineSyncService.enqueueRequest(
        method: method,
        uri: request.url,
        headers: request.headers,
        body: body,
      );

      return _offlineSyncService.buildQueuedStreamedResponse(
        request,
        queuedId: queuedId,
      );
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
