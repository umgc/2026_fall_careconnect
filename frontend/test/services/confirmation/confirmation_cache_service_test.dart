// Tests for ConfirmationCacheService.
//
// ConfirmationCacheService uses SharedPreferences to persist confirmation
// item states locally so the UI can render immediately on app restart
// before the backend fetch completes.
//
// Strategy:
//   • Use SharedPreferences.setMockInitialValues() to seed or clear state
//     before each test.  No disk I/O occurs.
//   • Verify read/write/clear round-trips and JSON serialization.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/confirmation_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Start every test with a clean SharedPreferences slate.
    SharedPreferences.setMockInitialValues({});
  });

  // ── cacheItems / getCachedItems round-trip ──────────────────────────────

  group('cacheItems / getCachedItems', () {
    test('returns empty list when nothing cached', () async {
      final items = await ConfirmationCacheService.getCachedItems();
      expect(items, isEmpty);
    });

    test('round-trips a single item through cache', () async {
      final item = _sampleItem(id: 1, status: 'PENDING');
      await ConfirmationCacheService.cacheItems([item]);

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, hasLength(1));
      expect(cached.first['id'], 1);
      expect(cached.first['status'], 'PENDING');
      expect(cached.first['sourceType'], 'SUMMARY');
    });

    test('round-trips multiple items', () async {
      final items = [
        _sampleItem(id: 1, status: 'PENDING'),
        _sampleItem(id: 2, status: 'CONFIRMED'),
        _sampleItem(id: 3, status: 'DISMISSED'),
      ];
      await ConfirmationCacheService.cacheItems(items);

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, hasLength(3));
      expect(cached.map((e) => e['id']).toList(), [1, 2, 3]);
    });

    test('overwrites previous cache on re-cache', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
        _sampleItem(id: 2, status: 'PENDING'),
      ]);
      // Replace with a single item
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 3, status: 'CONFIRMED'),
      ]);

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, hasLength(1));
      expect(cached.first['id'], 3);
    });
  });

  // ── updateCachedItemStatus ──────────────────────────────────────────────

  group('updateCachedItemStatus', () {
    test('updates status of a specific item', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
        _sampleItem(id: 2, status: 'PENDING'),
      ]);

      await ConfirmationCacheService.updateCachedItemStatus(1, 'CONFIRMED');

      final cached = await ConfirmationCacheService.getCachedItems();
      final item1 = cached.firstWhere((e) => e['id'] == 1);
      final item2 = cached.firstWhere((e) => e['id'] == 2);
      expect(item1['status'], 'CONFIRMED');
      expect(item2['status'], 'PENDING'); // unchanged
    });

    test('no-op when item id not found in cache', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
      ]);

      // Should not throw or corrupt cache
      await ConfirmationCacheService.updateCachedItemStatus(99, 'CONFIRMED');

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, hasLength(1));
      expect(cached.first['status'], 'PENDING');
    });

    test('no-op when cache is empty', () async {
      await ConfirmationCacheService.updateCachedItemStatus(1, 'CONFIRMED');

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, isEmpty);
    });
  });

  // ── clearCache ──────────────────────────────────────────────────────────

  group('clearCache', () {
    test('removes all cached items', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
        _sampleItem(id: 2, status: 'CONFIRMED'),
      ]);

      await ConfirmationCacheService.clearCache();

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, isEmpty);
    });

    test('no-op when cache already empty', () async {
      // Should not throw
      await ConfirmationCacheService.clearCache();

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, isEmpty);
    });
  });

  // ── persistence across reads (WBS 3.15.2 contract) ─────────────────────

  group('persistence contract (WBS 3.15.2)', () {
    test('cached state survives multiple getCachedItems calls', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'CONFIRMED'),
      ]);

      // Multiple reads should return the same data
      final read1 = await ConfirmationCacheService.getCachedItems();
      final read2 = await ConfirmationCacheService.getCachedItems();
      expect(read1.first['status'], 'CONFIRMED');
      expect(read2.first['status'], 'CONFIRMED');
    });

    test('confirm status update persists across reads', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
      ]);

      await ConfirmationCacheService.updateCachedItemStatus(1, 'CONFIRMED');

      // Subsequent read reflects the update
      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached.first['status'], 'CONFIRMED');
    });

    test('dismiss status update persists across reads', () async {
      await ConfirmationCacheService.cacheItems([
        _sampleItem(id: 1, status: 'PENDING'),
      ]);

      await ConfirmationCacheService.updateCachedItemStatus(1, 'DISMISSED');

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached.first['status'], 'DISMISSED');
    });

    test('preserves all item fields through serialization', () async {
      final item = {
        'id': 42,
        'sourceType': 'ASK_AI',
        'status': 'PENDING',
        'payload': '{"response":"Take your medication"}',
        'referenceId': 'conv-abc',
        'requestedBy': 10,
        'resolvedBy': null,
        'resolvedAt': null,
        'resolutionNote': null,
        'createdAt': '2026-06-30T10:00:00',
        'updatedAt': '2026-06-30T10:00:00',
      };

      await ConfirmationCacheService.cacheItems([item]);
      final cached = await ConfirmationCacheService.getCachedItems();

      expect(cached.first['id'], 42);
      expect(cached.first['sourceType'], 'ASK_AI');
      expect(cached.first['payload'], '{"response":"Take your medication"}');
      expect(cached.first['referenceId'], 'conv-abc');
      expect(cached.first['requestedBy'], 10);
      expect(cached.first['resolvedBy'], isNull);
    });
  });

  // ── corrupt data resilience ─────────────────────────────────────────────

  group('corrupt data resilience', () {
    test('returns empty list on malformed JSON in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'confirmation_items_cache': 'not valid json [[[',
      });

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, isEmpty);
    });

    test('returns empty list on non-list JSON in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'confirmation_items_cache': jsonEncode({'not': 'a list'}),
      });

      final cached = await ConfirmationCacheService.getCachedItems();
      expect(cached, isEmpty);
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

Map<String, dynamic> _sampleItem({required int id, required String status}) => {
      'id': id,
      'sourceType': 'SUMMARY',
      'status': status,
      'payload': '{"headline":"Took medication"}',
      'referenceId': 'call-$id',
      'requestedBy': 10,
      'resolvedBy': null,
      'resolvedAt': null,
      'resolutionNote': null,
      'createdAt': '2026-06-30T10:00:00',
      'updatedAt': '2026-06-30T10:00:00',
    };
