import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maps icon name strings to their constant IconData values.
/// Used to serialize and deserialize icons without non-constant IconData construction.
const Map<String, IconData> _kIconMap = {
  'medication': Icons.medication,
  'event': Icons.event,
  'fitness_center': Icons.fitness_center,
  'task': Icons.task,
  'science': Icons.science,
  'local_pharmacy': Icons.local_pharmacy,
  'file_upload': Icons.file_upload,
};

IconData _iconFromName(String name) => _kIconMap[name] ?? Icons.task;
String _iconToName(IconData icon) => _kIconMap.entries
    .firstWhere(
      (e) => e.value.codePoint == icon.codePoint,
      orElse: () => const MapEntry('task', Icons.task),
    )
    .key;

/// =============================
/// TaskTypeManager (Colors + Icons)
/// =============================
///
/// Manages task type settings including color and icon.
/// Handles creation, update, deletion, and persistence using SharedPreferences.
/// Notifies listeners so the UI reflects updates in real time.
class TaskTypeManager extends ChangeNotifier {
  static const String _prefsKey = 'task_type_settings';

  final Map<String, _TaskTypeData> _taskTypes = {};

  TaskTypeManager() {
    _loadFromPrefs();
  }

  /// =============================
  /// Accessors
  /// =============================
  Map<String, Color> get taskTypeColors => {
        for (final e in _taskTypes.entries) e.key: e.value.color,
      };

  IconData getIcon(String? type) {
    if (type == null) return Icons.task;
    return _taskTypes[type.toLowerCase()]?.icon ?? Icons.task;
  }

  Color getColor(String? type) {
    if (type == null) return Colors.deepOrange;
    return _taskTypes[type.toLowerCase()]?.color ?? Colors.deepOrange;
  }

  List<String> getSortedTypes() {
    final keys = _taskTypes.keys.toList()..sort();
    return keys;
  }

  /// =============================
  /// CRUD Operations
  /// =============================

  Future<void> addTaskType(String name, Color color, {IconData? icon}) async {
    _taskTypes[name.toLowerCase()] = _TaskTypeData(
      color: color,
      icon: icon ?? Icons.task,
    );
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> removeTaskType(String name) async {
    _taskTypes.remove(name.toLowerCase());
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> updateTaskColor(String name, Color newColor) async {
    final key = name.toLowerCase();
    if (_taskTypes.containsKey(key)) {
      _taskTypes[key] = _taskTypes[key]!.copyWith(color: newColor);
      await _saveToPrefs();
      notifyListeners();
    }
  }

  Future<void> updateTaskIcon(String name, IconData newIcon) async {
    final key = name.toLowerCase();
    if (_taskTypes.containsKey(key)) {
      _taskTypes[key] = _taskTypes[key]!.copyWith(icon: newIcon);
      await _saveToPrefs();
      notifyListeners();
    }
  }

  /// =============================
  /// Persistence
  /// =============================
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        decoded.forEach((k, v) {
          final data = Map<String, dynamic>.from(v);
          _taskTypes[k] = _TaskTypeData(
            color: Color(data['color'] as int),
            icon: _iconFromName(data['icon'] as String? ?? 'task'),
          );
        });
      } catch (_) {
        _setDefaults();
      }
    } else {
      _setDefaults();
    }
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _taskTypes.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_prefsKey, json.encode(encoded));
  }

  /// =============================
  /// Defaults
  /// =============================
  void _setDefaults() {
    _taskTypes.clear();
    _taskTypes.addAll({
      'medication': _TaskTypeData(color: Colors.red, icon: Icons.medication),
      'appointment': _TaskTypeData(color: Colors.blue, icon: Icons.event),
      'exercise': _TaskTypeData(
        color: Colors.green,
        icon: Icons.fitness_center,
      ),
      'general': _TaskTypeData(color: Colors.deepOrange, icon: Icons.task),
      'lab': _TaskTypeData(color: Colors.pink, icon: Icons.science),
      'pharmacy': _TaskTypeData(color: Colors.teal, icon: Icons.local_pharmacy),
      'imported': _TaskTypeData(color: Colors.purple, icon: Icons.file_upload),
    });
  }

  Future<void> resetDefaults() async {
    _setDefaults();
    await _saveToPrefs();
    notifyListeners();
  }
}

/// =============================
/// _TaskTypeData (Private Model)
/// =============================
///
/// Represents a single task type with color and icon.
/// Used internally for serialization and UI reference.

class _TaskTypeData {
  final Color color;
  final IconData icon;

  const _TaskTypeData({required this.color, required this.icon});

  _TaskTypeData copyWith({Color? color, IconData? icon}) {
    return _TaskTypeData(color: color ?? this.color, icon: icon ?? this.icon);
  }

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(),
        'icon': _iconToName(icon),
      };
}
