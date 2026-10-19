import 'package:shared_preferences/shared_preferences.dart';

/// Temporary client-side persistence for enabled activities per client/category.
///
/// This exists because backend activity-config persistence may not be implemented yet.
/// Keyed by clientId + category and stores a list of enabled activity names.
class LocalActivityPrefsStore {
  static String _key(int clientId, String category) =>
      'activity_enabled_names:$clientId:${category.toUpperCase()}';

  static Future<Set<String>> getEnabledNames({
    required int clientId,
    required String category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList(_key(clientId, category)) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> setEnabled({
    required int clientId,
    required String category,
    required String activityName,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final k = _key(clientId, category);
    final current = (prefs.getStringList(k) ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final name = activityName.trim();
    if (name.isEmpty) return;

    if (enabled) {
      current.add(name);
    } else {
      current.removeWhere((e) => e.toLowerCase() == name.toLowerCase());
    }

    await prefs.setStringList(k, current.toList()..sort());
  }
}
