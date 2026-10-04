import 'package:care_connect_app/services/local_db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/local_db_test_bindings.dart';

void main() {
  group('app_database.dart', () {
    setUpAll(LocalDbTestBindings.install);
    tearDownAll(LocalDbTestBindings.uninstall);
    setUp(LocalDbTestBindings.reset);

    test('isEncrypted reflects key lifecycle after first DB open', () async {
      final db = AppDatabase();

      expect(await db.isEncrypted(), isFalse);
      await db.ensureOfflineSyncTable();
      expect(await db.isEncrypted(), isTrue);

      await db.closeDb();
    });

    test('upsertOfflineSyncOperation deduplicates by fingerprint', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      final firstId = await db.upsertOfflineSyncOperation(
        id: 'id-1',
        method: 'POST',
        url: 'https://example.org/v1/api/mood',
        headersJson: '{}',
        bodyJson: '{"score":9}',
        createdAtIso: '2026-03-12T11:00:00.000Z',
        fingerprint: 'fp-same',
      );
      final secondId = await db.upsertOfflineSyncOperation(
        id: 'id-2',
        method: 'POST',
        url: 'https://example.org/v1/api/mood',
        headersJson: '{}',
        bodyJson: '{"score":9}',
        createdAtIso: '2026-03-12T11:01:00.000Z',
        fingerprint: 'fp-same',
      );

      expect(firstId, equals('id-1'));
      expect(secondId, equals('id-1'));
      expect(await db.getPendingOfflineSyncCount(), equals(1));

      await db.closeDb();
    });

    test('getPendingOfflineSyncQueue returns FIFO by created_at', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      await db.upsertOfflineSyncOperation(
        id: 'third',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"third"}',
        createdAtIso: '2026-03-12T12:02:00.000Z',
        fingerprint: 'fp-3',
      );
      await db.upsertOfflineSyncOperation(
        id: 'first',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"first"}',
        createdAtIso: '2026-03-12T12:00:00.000Z',
        fingerprint: 'fp-1',
      );
      await db.upsertOfflineSyncOperation(
        id: 'second',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"second"}',
        createdAtIso: '2026-03-12T12:01:00.000Z',
        fingerprint: 'fp-2',
      );

      final rows = await db.getPendingOfflineSyncQueue(limit: 10);
      expect(rows.map((e) => e.id).toList(), equals(<String>['first', 'second', 'third']));

      await db.closeDb();
    });

    test('markOfflineSyncAsSyncing and markOfflineSyncAsFailed update status', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      await db.upsertOfflineSyncOperation(
        id: 'sync-item',
        method: 'DELETE',
        url: 'https://example.org/v1/api/tasks/101',
        headersJson: '{}',
        bodyJson: null,
        createdAtIso: '2026-03-12T12:00:00.000Z',
        fingerprint: 'fp-delete-101',
      );

      await db.markOfflineSyncAsSyncing('sync-item');
      var row = await db.getOfflineSyncById('sync-item');
      expect(row, isNotNull);
      expect(row!.status, equals('syncing'));

      await db.markOfflineSyncAsFailed(
        id: 'sync-item',
        errorMessage: 'network timeout',
      );
      row = await db.getOfflineSyncById('sync-item');
      expect(row, isNotNull);
      expect(row!.status, equals('failed'));
      expect(row.retryCount, equals(1));
      expect(row.lastError, contains('timeout'));

      await db.deleteOfflineSyncById('sync-item');
      expect(await db.getOfflineSyncById('sync-item'), isNull);

      await db.closeDb();
    });

    test('repeated failures mark the row terminal (dead) at the retry cap and '
        'exclude it from the pending queue', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      await db.upsertOfflineSyncOperation(
        id: 'doomed-item',
        method: 'POST',
        url: 'https://unreachable.example.org/v1/api/mood',
        headersJson: '{}',
        bodyJson: '{"moodValue":5}',
        createdAtIso: '2026-03-12T12:00:00.000Z',
        fingerprint: 'fp-doomed-mood',
      );

      // Fail one short of the cap: still retryable and still surfaced.
      for (var attempt = 1; attempt < AppDatabase.maxReplayAttempts; attempt++) {
        await db.markOfflineSyncAsFailed(
          id: 'doomed-item',
          errorMessage: 'connection refused',
        );
      }
      var row = await db.getOfflineSyncById('doomed-item');
      expect(row!.status, equals('failed'));
      expect(row.retryCount, equals(AppDatabase.maxReplayAttempts - 1));
      expect(await db.getPendingOfflineSyncCount(), equals(1));

      // The final failure reaches the cap and retires the row.
      await db.markOfflineSyncAsFailed(
        id: 'doomed-item',
        errorMessage: 'connection refused',
      );
      row = await db.getOfflineSyncById('doomed-item');
      expect(row!.status, equals('dead'));
      expect(row.retryCount, equals(AppDatabase.maxReplayAttempts));

      // Terminal rows no longer count as pending, so the sync banner can clear.
      expect(await db.getPendingOfflineSyncCount(), equals(0));
      expect(await db.getPendingOfflineSyncQueue(), isEmpty);

      await db.deleteOfflineSyncById('doomed-item');
      await db.closeDb();
    });

    test('getOfflineSyncById returns null for unknown id', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      expect(await db.getOfflineSyncById('missing-id'), isNull);

      await db.closeDb();
    });

    test('mark methods are no-op for unknown id', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      await db.markOfflineSyncAsSyncing('does-not-exist');
      await db.markOfflineSyncAsFailed(
        id: 'does-not-exist',
        errorMessage: 'should not throw',
      );

      expect(await db.getPendingOfflineSyncCount(), equals(0));
      await db.closeDb();
    });

    test('getPendingOfflineSyncQueue respects limit', () async {
      final db = AppDatabase();
      await db.ensureOfflineSyncTable();

      await db.upsertOfflineSyncOperation(
        id: 'one',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"one"}',
        createdAtIso: '2026-03-12T12:00:00.000Z',
        fingerprint: 'fp-one',
      );
      await db.upsertOfflineSyncOperation(
        id: 'two',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"two"}',
        createdAtIso: '2026-03-12T12:01:00.000Z',
        fingerprint: 'fp-two',
      );
      await db.upsertOfflineSyncOperation(
        id: 'three',
        method: 'POST',
        url: 'https://example.org/v1/api/tasks',
        headersJson: '{}',
        bodyJson: '{"title":"three"}',
        createdAtIso: '2026-03-12T12:02:00.000Z',
        fingerprint: 'fp-three',
      );

      final rows = await db.getPendingOfflineSyncQueue(limit: 2);
      expect(rows.length, equals(2));
      expect(rows.first.id, equals('one'));
      expect(rows.last.id, equals('two'));

      await db.closeDb();
    });
  });
}
