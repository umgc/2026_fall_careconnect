import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _key = 'selected_locale';
  static const Locale _fallbackLocale = Locale('en');

  static const Set<String> _supportedLanguageCodes = <String>{'en', 'es'};

  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_key);
    final normalizedCode = savedCode?.trim().toLowerCase();

    if (normalizedCode == null || normalizedCode.isEmpty) {
      _locale = null;
      await prefs.remove(_key);
      return;
    } else if (_supportedLanguageCodes.contains(normalizedCode)) {
      _locale = Locale(normalizedCode);
      await prefs.setString(_key, normalizedCode);
    } else {
      _locale = _fallbackLocale;
      await prefs.setString(_key, _fallbackLocale.languageCode);
    }

    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();

    if (locale == null) {
      _locale = null;
      notifyListeners();
      await prefs.remove(_key);
      return;
    }

    final normalizedCode = locale.languageCode.trim().toLowerCase();

    if (_supportedLanguageCodes.contains(normalizedCode)) {
      _locale = Locale(normalizedCode);
    } else {
      _locale = _fallbackLocale;
    }

    notifyListeners();
    await prefs.setString(_key, _locale!.languageCode);
  }

  Future<void> clearLocale() async {
    await setLocale(null);
  }
}
