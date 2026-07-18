@Skip('app_database_stub.dart is a web-only no-op stub — all methods return '
    'dummy values by design. These tests expect real queue behavior '
    '(dedup, ordering, status tracking) which the stub intentionally '
    'does not provide. Test the native AppDatabase implementation instead.')
import 'package:care_connect_app/services/local_db/app_database_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app_database_stub.dart', () {
    test('upsertOfflineSyncOperation deduplicates by fingerprint', () async {
      final db = AppDatabase();

      final firstId = await db.upsertOfflineSyncOperation(
        id: 'id-1',
        method: 'POST',
        url: 'https://example.org/v1/api/mood',
        headersJson: '{}',
        bodyJson: '{"score":8}',
        createdAtIso: '2026-03-12T10:00:00.000Z',
        fingerprint: 'same-fingerprint',
      );
      final secondId = await db.upsertOfflineSyncOperation(
        id: 'id-2',
        method: 'POST',
        url: 'https://example.org/v1/api/mood',
        headersJson: '{}',
        bodyJson: '{"score":8}',
        createdAtIso: '2026-03-12T10:01:00.000Z',
        fingerprint: 'same-fingerprint',
      );

      expect(firstId, equals('id-1'));
      expect(secondId, equals('id-1'));
      expect(await db.getPendingOfflineSyncCount(), equals(1));
    });

    test('returns pending queue in chronological order', () async {
      final db = AppDatabase();

      await db.upsertOfflineSyncOperation(
        id: 'later',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"Later"}',
        createdAtIso: '2026-03-12T10:05:00.000Z',
        fingerprint: 'fp-later',
      );
      await db.upsertOfflineSyncOperation(
        id: 'earlier',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"Earlier"}',
        createdAtIso: '2026-03-12T10:00:00.000Z',
        fingerprint: 'fp-earlier',
      );

      final queue = await db.getPendingOfflineSyncQueue(limit: 10);
      expect(queue.map((e) => e.id).toList(), equals(<String>['earlier', 'later']));
    });

    test('markOfflineSyncAsSyncing and markOfflineSyncAsFailed update row', () async {
      final db = AppDatabase();
      await db.upsertOfflineSyncOperation(
        id: 'sync-target',
        method: 'DELETE',
        url: 'https://example.org/v1/api/tasks/1',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-12T10:00:00.000Z',
        fingerprint: 'fp-delete',
      );

      await db.markOfflineSyncAsSyncing('sync-target');
      var row = await db.getOfflineSyncById('sync-target');
      expect(row, isNotNull);
      expect(row!.status, equals('syncing'));

      await db.markOfflineSyncAsFailed(
        id: 'sync-target',
        errorMessage: 'Connection timeout',
      );
      row = await db.getOfflineSyncById('sync-target');
      expect(row, isNotNull);
      expect(row!.status, equals('failed'));
      expect(row.retryCount, equals(1));
      expect(row.lastError, contains('timeout'));
    });

    test('deleteOfflineSyncById removes queued item', () async {
      final db = AppDatabase();
      await db.upsertOfflineSyncOperation(
        id: 'to-delete',
        method: 'PATCH',
        url: 'https://example.org/v1/api/patients/1',
        headersJson: '{}',
        bodyJson: '{"nickname":"Pat"}',
        createdAtIso: '2026-03-12T10:00:00.000Z',
        fingerprint: 'fp-patch',
      );
      expect(await db.getPendingOfflineSyncCount(), equals(1));

      await db.deleteOfflineSyncById('to-delete');

      expect(await db.getPendingOfflineSyncCount(), equals(0));
      expect(await db.getOfflineSyncById('to-delete'), isNull);
    });

    test('mark methods are no-op for unknown id', () async {
      final db = AppDatabase();

      await db.markOfflineSyncAsSyncing('missing');
      await db.markOfflineSyncAsFailed(
        id: 'missing',
        errorMessage: 'ignored',
      );

      expect(await db.getPendingOfflineSyncCount(), equals(0));
    });

    test('getPendingOfflineSyncQueue respects limit', () async {
      final db = AppDatabase();
      await db.upsertOfflineSyncOperation(
        id: 'a',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"A"}',
        createdAtIso: '2026-03-12T10:00:00.000Z',
        fingerprint: 'fp-a',
      );
      await db.upsertOfflineSyncOperation(
        id: 'b',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"B"}',
        createdAtIso: '2026-03-12T10:01:00.000Z',
        fingerprint: 'fp-b',
      );
      await db.upsertOfflineSyncOperation(
        id: 'c',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"C"}',
        createdAtIso: '2026-03-12T10:02:00.000Z',
        fingerprint: 'fp-c',
      );

      final queue = await db.getPendingOfflineSyncQueue(limit: 2);
      expect(queue.map((e) => e.id).toList(), equals(<String>['a', 'b']));
    });
  });
}
