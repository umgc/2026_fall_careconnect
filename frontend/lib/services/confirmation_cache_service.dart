import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache for confirmation item states (WBS 3.15.2).
///
/// Uses SharedPreferences so cached states survive app restarts and are
/// available instantly before the backend fetch completes. Cross-platform
/// (works on mobile and web).
class ConfirmationCacheService {
  static const _key = 'confirmation_items_cache';

  /// Replace the entire cache with [items].
  static Future<void> cacheItems(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  /// Read all cached items. Returns empty list on missing or corrupt data.
  static Future<List<Map<String, dynamic>>> getCachedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Update the status of a single cached item in-place.
  /// No-op if item not found or cache is empty.
  static Future<void> updateCachedItemStatus(int id, String status) async {
    final items = await getCachedItems();
    if (items.isEmpty) return;

    bool found = false;
    for (final item in items) {
      if (item['id'] == id) {
        item['status'] = status;
        found = true;
        break;
      }
    }
    if (found) {
      await cacheItems(items);
    }
  }

  /// Remove all cached items.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
