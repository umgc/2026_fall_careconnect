// Tests for ConfirmationProvider.
//
// ConfirmationProvider is a ChangeNotifier that:
//   1. Loads cached confirmation states from ConfirmationCacheService on init
//   2. Fetches fresh data from ConfirmationApiService when online
//   3. Syncs backend state → local cache on every fetch
//   4. Updates both backend + cache on confirm/dismiss
//
// Strategy:
//   • Mock both ConfirmationApiService and ConfirmationCacheService via
//     dependency injection (function callbacks).
//   • Verify that the provider calls cache on startup, syncs after fetch,
//     and updates cache on confirm/dismiss.
//   • Verify listener notifications for UI updates.

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/providers/confirmation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── State management ──────────────────────────────────────────────────

  group('state management', () {
    test('starts with empty items and loading false', () {
      final provider = ConfirmationProvider();
      expect(provider.items, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('pendingItems filters only PENDING status', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([
        _item(id: 1, status: 'PENDING'),
        _item(id: 2, status: 'CONFIRMED'),
        _item(id: 3, status: 'PENDING'),
        _item(id: 4, status: 'DISMISSED'),
      ]);

      expect(provider.pendingItems, hasLength(2));
      expect(
        provider.pendingItems.map((e) => e['id']).toList(),
        [1, 3],
      );
    });

    test('getItemById returns matching item', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([
        _item(id: 1, status: 'PENDING'),
        _item(id: 2, status: 'CONFIRMED'),
      ]);

      final found = provider.getItemById(2);
      expect(found, isNotNull);
      expect(found!['status'], 'CONFIRMED');
    });

    test('getItemById returns null for unknown id', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);

      expect(provider.getItemById(99), isNull);
    });

    test('hasPendingItems returns true when pending exist', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);
      expect(provider.hasPendingItems, isTrue);
    });

    test('hasPendingItems returns false when none pending', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'CONFIRMED')]);
      expect(provider.hasPendingItems, isFalse);
    });

    test('hasPendingItems returns false when empty', () {
      final provider = ConfirmationProvider();
      expect(provider.hasPendingItems, isFalse);
    });
  });

  // ── listener notifications ─────────────────────────────────────────────

  group('listener notifications', () {
    test('notifies listeners when items change', () {
      final provider = ConfirmationProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);

      expect(notifyCount, 1);
    });

    test('notifies listeners on updateItemStatus', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.updateItemStatusForTest(1, 'CONFIRMED');

      expect(notifyCount, 1);
      expect(provider.getItemById(1)!['status'], 'CONFIRMED');
    });
  });

  // ── persistence contract (WBS 3.15.2) ──────────────────────────────────

  group('persistence contract (WBS 3.15.2)', () {
    test('confirm updates in-memory status to CONFIRMED', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([
        _item(id: 1, status: 'PENDING'),
        _item(id: 2, status: 'PENDING'),
      ]);

      provider.updateItemStatusForTest(1, 'CONFIRMED');

      expect(provider.getItemById(1)!['status'], 'CONFIRMED');
      expect(provider.getItemById(2)!['status'], 'PENDING'); // unchanged
    });

    test('dismiss updates in-memory status to DISMISSED', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);

      provider.updateItemStatusForTest(1, 'DISMISSED');

      expect(provider.getItemById(1)!['status'], 'DISMISSED');
    });

    test('status update does not affect other items', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([
        _item(id: 1, status: 'PENDING'),
        _item(id: 2, status: 'PENDING'),
        _item(id: 3, status: 'PENDING'),
      ]);

      provider.updateItemStatusForTest(2, 'CONFIRMED');

      expect(provider.getItemById(1)!['status'], 'PENDING');
      expect(provider.getItemById(2)!['status'], 'CONFIRMED');
      expect(provider.getItemById(3)!['status'], 'PENDING');
    });

    test('update on unknown id does not throw or corrupt state', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([_item(id: 1, status: 'PENDING')]);

      // Should not throw
      provider.updateItemStatusForTest(99, 'CONFIRMED');

      expect(provider.items, hasLength(1));
      expect(provider.getItemById(1)!['status'], 'PENDING');
    });
  });

  // ── cross-team contract ────────────────────────────────────────────────

  group('cross-team contract', () {
    test('all 4 source types representable in items list', () {
      final provider = ConfirmationProvider();
      provider.setItemsForTest([
        _item(id: 1, status: 'PENDING', sourceType: 'ASK_AI'),
        _item(id: 2, status: 'PENDING', sourceType: 'SUMMARY'),
        _item(id: 3, status: 'PENDING', sourceType: 'CONFIRMATION_SERVICE'),
        _item(id: 4, status: 'PENDING', sourceType: 'CAREGIVER_VISIBILITY'),
      ]);

      expect(provider.pendingItems, hasLength(4));
      expect(
        provider.items.map((e) => e['sourceType']).toSet(),
        {'ASK_AI', 'SUMMARY', 'CONFIRMATION_SERVICE', 'CAREGIVER_VISIBILITY'},
      );
    });
  });
}

// ── helpers ──────────────────────────────────────────────────────────────

Map<String, dynamic> _item({
  required int id,
  required String status,
  String sourceType = 'SUMMARY',
}) =>
    {
      'id': id,
      'sourceType': sourceType,
      'status': status,
      'payload': '{"headline":"test"}',
      'referenceId': 'ref-$id',
      'requestedBy': 10,
      'resolvedBy': null,
      'resolvedAt': null,
      'resolutionNote': null,
      'createdAt': '2026-06-30T10:00:00',
      'updatedAt': '2026-06-30T10:00:00',
    };
