// Tests for sync telemetry emitted by ApiServiceOffline.
//
// Uses LocalDbTestBindings for real SQLite queue state and http.runWithClient
// to capture telemetry POST bodies, matching telemetry_test.dart patterns.

import 'dart:convert';

import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/services/local_db/app_database.dart';
import 'package:care_connect_app/services/local_db/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../test_support/local_db_test_bindings.dart';

Future<void> _clearQueue() async {
  final pending = await ApiServiceOffline.getPendingQueue(limit: 2000);
  for (final item in pending) {
    await ApiServiceOffline.deleteQueuedRequestById(item.id);
  }
}

Future<List<Map<String, dynamic>>> _captureTelemetryEvents(
  Future<void> Function() action,
) async {
  final bodies = <String>[];
  final mock = MockClient((req) async {
    if (req.method == 'POST' &&
        req.url.path.contains('telemetry') &&
        !req.url.path.contains('enabled')) {
      bodies.add(req.body);
    }
    return http.Response(jsonEncode({'enabled': true}), 200);
  });

  ApiService.debugSetHttpClient(mock);
  try {
    await http.runWithClient(
      () async {
        await Telemetry.setBackendEnabled(true);
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      () => mock,
    );
  } finally {
    ApiService.debugResetHttpClient();
  }

  return bodies
      .map((body) => jsonDecode(body) as Map<String, dynamic>)
      .toList();
}

List<String> _eventNames(List<Map<String, dynamic>> events) {
  return events.map((event) => event['eventName'] as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await LocalDbTestBindings.install();
    await ApiServiceOffline.initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': false});
    await _clearQueue();
  });

  tearDownAll(LocalDbTestBindings.uninstall);

  group('ApiServiceOffline sync telemetry', () {
    test('syncPendingQueue emits no sync events when queue is empty', () async {
      final events = await _captureTelemetryEvents(() async {
        final summary = await ApiServiceOffline.syncPendingQueue(limit: 50);
        expect(summary.attempted, 0);
      });

      expect(_eventNames(events), isEmpty);
    });

    test('syncQueuedRequestById emits sync_started and sync_completed for unknown id',
        () async {
      final events = await _captureTelemetryEvents(() async {
        final ok = await ApiServiceOffline.syncQueuedRequestById('missing-id');
        expect(ok, isTrue);
      });

      expect(_eventNames(events), ['sync_started', 'sync_completed']);
      expect(events.first['details']['scope'], 'single');
      expect(events.last['details']['succeeded'], 1);
    });

    test('syncQueuedRequestById emits sync_failed for malformed queued URL',
        () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-item',
        method: 'POST',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"invalid"}',
        createdAtIso: '2026-03-12T15:00:00.000Z',
        fingerprint: 'fp-bad-url-item',
      );
      await db.closeDb();

      final events = await _captureTelemetryEvents(() async {
        final ok = await ApiServiceOffline.syncQueuedRequestById('bad-url-item');
        expect(ok, isFalse);
      });

      expect(_eventNames(events), ['sync_started', 'sync_failed']);
      expect(events.last['details']['scope'], 'single');

      final verifyDb = AppDatabase();
      await verifyDb.deleteOfflineSyncById('bad-url-item');
      await verifyDb.closeDb();
    });

    test('syncPendingQueue emits sync_completed and sync_failed for batch failures',
        () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-1',
        method: 'PUT',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"one"}',
        createdAtIso: '2026-03-12T15:01:00.000Z',
        fingerprint: 'fp-bad-url-1',
      );
      await db.upsertOfflineSyncOperation(
        id: 'bad-url-2',
        method: 'PATCH',
        url: 'http://[',
        headersJson: '{}',
        bodyJson: '{"title":"two"}',
        createdAtIso: '2026-03-12T15:02:00.000Z',
        fingerprint: 'fp-bad-url-2',
      );
      await db.closeDb();

      final events = await _captureTelemetryEvents(() async {
        final summary = await ApiServiceOffline.syncPendingQueue(limit: 10);
        expect(summary.attempted, 2);
        expect(summary.failed, 2);
      });

      expect(
        _eventNames(events),
        ['sync_started', 'sync_completed', 'sync_failed'],
      );
      expect(events[0]['details']['scope'], 'batch');
      expect(events[1]['details']['failed'], 2);
      expect(events[2]['details']['failed'], 2);

      final verifyDb = AppDatabase();
      await verifyDb.deleteOfflineSyncById('bad-url-1');
      await verifyDb.deleteOfflineSyncById('bad-url-2');
      await verifyDb.closeDb();
    });
  });
}
