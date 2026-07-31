import 'package:flutter/foundation.dart';
import '../services/confirmation_api_service.dart';
import '../services/confirmation_cache_service.dart';

/// State manager for confirmation items (WBS 3.15.2).
///
/// Syncs between the backend API and local SharedPreferences cache so that
/// confirm/dismiss states persist across app restarts. The UI can read
/// [items] immediately on startup (from cache) and get fresh data once
/// the backend fetch completes.
class ConfirmationProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;

  /// Only PENDING items.
  List<Map<String, dynamic>> get pendingItems =>
      _items.where((e) => e['status'] == 'PENDING').toList();

  /// Whether any PENDING items exist.
  bool get hasPendingItems => _items.any((e) => e['status'] == 'PENDING');

  /// Look up a single item by id. Returns null if not found.
  Map<String, dynamic>? getItemById(int id) {
    try {
      return _items.firstWhere((e) => e['id'] == id);
    } catch (_) {
      return null;
    }
  }

  /// Load cached items from SharedPreferences (call on app startup).
  Future<void> loadFromCache() async {
    _items = await ConfirmationCacheService.getCachedItems();
    notifyListeners();
  }

  /// Fetch fresh data from the backend, update cache, notify listeners.
  Future<void> fetchFromBackend({String? sourceType}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ConfirmationApiService.fetchPendingItems(
        sourceType: sourceType,
      );
      if (result['success'] == true) {
        _items = List<Map<String, dynamic>>.from(result['items']);
        await ConfirmationCacheService.cacheItems(_items);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Confirm an item: call backend, update local state + cache.
  Future<bool> confirmItem(int id, {String? note}) async {
    final result = await ConfirmationApiService.confirmItem(id, note: note);
    if (result['success'] == true) {
      _updateLocalStatus(id, 'CONFIRMED');
      await ConfirmationCacheService.updateCachedItemStatus(id, 'CONFIRMED');
      return true;
    }
    return false;
  }

  /// Dismiss an item: call backend, update local state + cache.
  Future<bool> dismissItem(int id, {String? note}) async {
    final result = await ConfirmationApiService.dismissItem(id, note: note);
    if (result['success'] == true) {
      _updateLocalStatus(id, 'DISMISSED');
      await ConfirmationCacheService.updateCachedItemStatus(id, 'DISMISSED');
      return true;
    }
    return false;
  }

  /// Clear all state and cache (e.g. on logout).
  Future<void> clear() async {
    _items = [];
    await ConfirmationCacheService.clearCache();
    notifyListeners();
  }

  // ── internal ───────────────────────────────────────────────────────────

  void _updateLocalStatus(int id, String status) {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i]['id'] == id) {
        _items[i] = Map<String, dynamic>.from(_items[i])..['status'] = status;
        break;
      }
    }
    notifyListeners();
  }

  // ── test helpers ───────────────────────────────────────────────────────

  /// Replace items in-memory (for unit tests only).
  @visibleForTesting
  void setItemsForTest(List<Map<String, dynamic>> testItems) {
    _items = List<Map<String, dynamic>>.from(testItems);
    notifyListeners();
  }

  /// Update a single item's status in-memory (for unit tests only).
  @visibleForTesting
  void updateItemStatusForTest(int id, String status) {
    _updateLocalStatus(id, status);
  }
}
