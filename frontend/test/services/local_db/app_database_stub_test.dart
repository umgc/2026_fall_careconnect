@Skip('app_database_stub.dart is a web-only no-op stub — all methods return '
    'dummy values by design. These tests expect real queue behavior '
    'which the stub intentionally does not provide.')
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/local_db/app_database_stub.dart';

void main() {
  group('AppDatabase stub', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    test('isEncrypted returns false', () async {
      final result = await db.isEncrypted();
      expect(result, isFalse);
    });

    test('upsertOfflineSyncOperation adds a new row', () async {
      final id = await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{"Content-Type":"application/json"}',
        bodyJson: '{"mood":"good"}',
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-1',
      );

      expect(id, '1');

      final row = await db.getOfflineSyncById('1');
      expect(row, isNotNull);
      expect(row!.id, '1');
      expect(row.status, 'pending');
      expect(row.retryCount, 0);
      expect(row.lastError, isNull);
      expect(row.method, 'POST');
      expect(row.url, '/sync/mood');
    });

    test('upsertOfflineSyncOperation deduplicates by fingerprint', () async {
      final firstId = await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{}',
        bodyJson: '{"mood":"good"}',
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'same-fingerprint',
      );

      final secondId = await db.upsertOfflineSyncOperation(
        id: '2',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{}',
        bodyJson: '{"mood":"better"}',
        createdAtIso: '2026-03-15T10:05:00Z',
        fingerprint: 'same-fingerprint',
      );

      final queue = await db.getPendingOfflineSyncQueue();

      expect(firstId, '1');
      expect(secondId, '1');
      expect(queue.length, 1);
      expect(queue.first.id, '1');
    });

    test('queue is sorted by createdAt ascending', () async {
      await db.upsertOfflineSyncOperation(
        id: 'late',
        method: 'POST',
        url: '/sync/calendar',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T11:00:00Z',
        fingerprint: 'fp-late',
      );

      await db.upsertOfflineSyncOperation(
        id: 'early',
        method: 'POST',
        url: '/sync/calendar',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T09:00:00Z',
        fingerprint: 'fp-early',
      );

      final queue = await db.getPendingOfflineSyncQueue();

      expect(queue.length, 2);
      expect(queue[0].id, 'early');
      expect(queue[1].id, 'late');
    });

    test('getPendingOfflineSyncQueue respects limit', () async {
      await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/a',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T09:00:00Z',
        fingerprint: 'fp-1',
      );

      await db.upsertOfflineSyncOperation(
        id: '2',
        method: 'POST',
        url: '/b',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-2',
      );

      final queue = await db.getPendingOfflineSyncQueue(limit: 1);

      expect(queue.length, 1);
      expect(queue.first.id, '1');
    });

    test('getPendingOfflineSyncCount returns count of actionable rows',
        () async {
      await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/a',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T09:00:00Z',
        fingerprint: 'fp-1',
      );

      await db.upsertOfflineSyncOperation(
        id: '2',
        method: 'POST',
        url: '/b',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-2',
      );

      final count = await db.getPendingOfflineSyncCount();
      expect(count, 2);
    });

    test('getOfflineSyncById returns null when row does not exist', () async {
      final row = await db.getOfflineSyncById('missing');
      expect(row, isNull);
    });

    test('markOfflineSyncAsSyncing updates status to syncing', () async {
      await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-1',
      );

      await db.markOfflineSyncAsSyncing('1');
      final row = await db.getOfflineSyncById('1');

      expect(row, isNotNull);
      expect(row!.status, 'syncing');
      expect(row.retryCount, 0);
    });

    test('markOfflineSyncAsFailed updates status, retryCount, and lastError',
        () async {
      await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-1',
      );

      await db.markOfflineSyncAsFailed(
        id: '1',
        errorMessage: 'network timeout',
      );

      final row = await db.getOfflineSyncById('1');

      expect(row, isNotNull);
      expect(row!.status, 'failed');
      expect(row.retryCount, 1);
      expect(row.lastError, 'network timeout');
    });

    test('deleteOfflineSyncById removes row from queue', () async {
      await db.upsertOfflineSyncOperation(
        id: '1',
        method: 'POST',
        url: '/sync/mood',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-15T10:00:00Z',
        fingerprint: 'fp-1',
      );

      await db.deleteOfflineSyncById('1');
      final row = await db.getOfflineSyncById('1');
      final count = await db.getPendingOfflineSyncCount();

      expect(row, isNull);
      expect(count, 0);
    });

    test('markOfflineSyncAsSyncing does nothing for missing id', () async {
      await db.markOfflineSyncAsSyncing('missing');
      final count = await db.getPendingOfflineSyncCount();
      expect(count, 0);
    });

    test('markOfflineSyncAsFailed does nothing for missing id', () async {
      await db.markOfflineSyncAsFailed(
        id: 'missing',
        errorMessage: 'error',
      );
      final count = await db.getPendingOfflineSyncCount();
      expect(count, 0);
    });
  });
}
