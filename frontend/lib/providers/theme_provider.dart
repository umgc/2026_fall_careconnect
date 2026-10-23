import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A provider that manages the theme mode (light, dark, system)
class ThemeProvider extends ChangeNotifier {
  // Theme mode constants for shared preferences
  static const String _themePreferenceKey = 'theme_mode';
  static const String _themeModeLight = 'light';
  static const String _themeModeDark = 'dark';
  static const String _themeModeSystem = 'system';

  // Default theme mode is system
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  // Constructor that initializes the theme from shared preferences
  ThemeProvider() {
    _loadThemePreference();
  }

  // Check if the theme is currently dark
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // Get the system brightness
      final brightness =
          SchedulerBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  // Load the theme preference from shared preferences
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themePreferenceKey);

    if (savedTheme != null) {
      switch (savedTheme) {
        case _themeModeLight:
          _themeMode = ThemeMode.light;
          break;
        case _themeModeDark:
          _themeMode = ThemeMode.dark;
          break;
        case _themeModeSystem:
        default:
          _themeMode = ThemeMode.system;
          break;
      }
    }

    notifyListeners();
  }

  // Save the theme preference to shared preferences
  Future<void> _saveThemePreference(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String themeValue;

    switch (mode) {
      case ThemeMode.light:
        themeValue = _themeModeLight;
        break;
      case ThemeMode.dark:
        themeValue = _themeModeDark;
        break;
      case ThemeMode.system:
        themeValue = _themeModeSystem;
        break;
    }

    await prefs.setString(_themePreferenceKey, themeValue);
  }

  // Set the theme mode and save to preferences
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _saveThemePreference(mode);
    notifyListeners();
  }

  // Toggle between light and dark mode (ignoring system)
  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.light ||
        (_themeMode == ThemeMode.system && !isDarkMode)) {
      await setThemeMode(ThemeMode.dark);
    } else {
      await setThemeMode(ThemeMode.light);
    }
  }
}
