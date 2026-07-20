import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../features/telemetry/telemetry.dart';
import 'local_db/offline_sync_service.dart';
import 'telemetry_http_client.dart';

export 'local_db/offline_sync_service.dart'
    show OfflineSyncQueueItem, OfflineSyncRunSummary;

/// Centralizes offline queue wiring used by ApiService.
///
/// Responsibilities:
/// - Provide a configured HTTP client that supports offline queueing
/// - Expose offline queue operations (read, delete, sync)
/// - Act as a bridge between API layer and offline sync service
///
/// NOTE:
/// This class does NOT modify business logic. It delegates all behavior
/// to OfflineSyncService and only exposes a simplified interface.
class ApiServiceOffline {
  ApiServiceOffline._();

  static final OfflineSyncService _offlineSyncService =
      OfflineSyncService.instance();

  static bool Function()? _canQueueOfflineWrites;

  /// HTTP client that automatically routes requests through the offline queue.
  /// Tests may replace this via [debugOverrideHttpClient] to bypass the
  /// offline-queue and telemetry wrappers, which otherwise swallow mock
  /// clients and return synthetic responses.
  static http.Client get httpClient => _testHttpClient ?? _defaultHttpClient;

  static http.Client? _testHttpClient;

  static final http.Client _defaultHttpClient = OfflineQueueHttpClient(
    inner: TelemetryHttpClient(http.Client()),
    offlineSyncService: _offlineSyncService,
    canQueueWrites: () => _canQueueOfflineWrites?.call() ?? true,
  );

  @visibleForTesting
  static void debugOverrideHttpClient(http.Client? client) {
    _testHttpClient = client;
  }

  /// Configures whether offline writes are allowed.
  static void configure({
    required bool Function() canQueueOfflineWrites,
  }) {
    _canQueueOfflineWrites = canQueueOfflineWrites;

    assert(() {
      print('[OfflineAPI] Configuration updated for offline write capability');
      return true;
    }());
  }

  /// Initializes the offline sync service.
  static Future<void> initialize() async {
    assert(() {
      print('[OfflineAPI] Initializing offline sync service');
      return true;
    }());

    await _offlineSyncService.initialize();
  }

  /// Returns a list of pending queued requests.
  static Future<List<OfflineSyncQueueItem>> getPendingQueue({
    int limit = 200,
  }) async {
    assert(() {
      print('[OfflineAPI] Fetching pending queue (limit: $limit)');
      return true;
    }());

    return _offlineSyncService.getPendingQueue(limit: limit);
  }

  /// Returns the total number of pending queued requests.
  static Future<int> getPendingCount() async {
    assert(() {
      print('[OfflineAPI] Fetching pending queue count');
      return true;
    }());

    return _offlineSyncService.getPendingCount();
  }

  /// Attempts to sync a single queued request by ID.
  static Future<bool> syncQueuedRequestById(String id) async {
    assert(() {
      print('[OfflineAPI] Syncing queued request: $id');
      return true;
    }());

    final pendingCount = await getPendingCount();

    unawaited(Telemetry.event('sync_started', {
      'scope': 'single',
      'pendingCount': pendingCount,
    }));

    try {
      final ok = await _offlineSyncService.syncQueuedRequestById(id);

      if (ok) {
        unawaited(Telemetry.event('sync_completed', {
          'scope': 'single',
          'attempted': 1,
          'succeeded': 1,
          'failed': 0,
        }));
      } else {
        unawaited(Telemetry.event('sync_failed', {
          'scope': 'single',
          'attempted': 1,
          'failed': 1,
        }));
      }

      return ok;
    } catch (_) {
      unawaited(Telemetry.event('sync_failed', {
        'scope': 'single',
        'attempted': 1,
        'failed': 1,
      }));
      rethrow;
    }
  }

  /// Deletes a queued request by ID.
  static Future<bool> deleteQueuedRequestById(String id) async {
    assert(() {
      print('[OfflineAPI] Deleting queued request: $id');
      return true;
    }());

    return _offlineSyncService.deleteQueuedRequestById(id);
  }

  /// Syncs all pending queued requests.
  static Future<OfflineSyncRunSummary> syncPendingQueue({
    int limit = 200,
  }) async {
    assert(() {
      print('[OfflineAPI] Syncing pending queue (limit: $limit)');
      return true;
    }());

    final pendingCount = await getPendingCount();

    if (pendingCount == 0) {
      return const OfflineSyncRunSummary(
        attempted: 0,
        succeeded: 0,
        failed: 0,
      );
    }

    unawaited(Telemetry.event('sync_started', {
      'scope': 'batch',
      'pendingCount': pendingCount,
    }));

    try {
      final summary = await _offlineSyncService.syncPendingQueue(limit: limit);

      unawaited(Telemetry.event('sync_completed', {
        'scope': 'batch',
        'attempted': summary.attempted,
        'succeeded': summary.succeeded,
        'failed': summary.failed,
      }));

      if (summary.failed > 0) {
        unawaited(Telemetry.event('sync_failed', {
          'scope': 'batch',
          'attempted': summary.attempted,
          'failed': summary.failed,
        }));
      }

      return summary;
    } catch (_) {
      unawaited(Telemetry.event('sync_failed', {
        'scope': 'batch',
        'attempted': pendingCount,
        'failed': pendingCount,
      }));
      rethrow;
    }
  }

  /// Checks whether a response was queued offline.
  static bool isQueuedOfflineResponse(http.Response response) {
    return response.headers['x-offline-queued'] == 'true';
  }
}
