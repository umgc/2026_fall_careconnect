import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _key = 'selected_locale';

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
    } else {
      final locale = Locale(normalizedCode);

      if (AppLocalizations.delegate.isSupported(locale)) {
        _locale = locale;
        await prefs.setString(_key, normalizedCode);
      } else {
        _locale = null;
        await prefs.remove(_key);
      }
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

    final normalizedLocale = Locale(
      locale.languageCode.trim().toLowerCase(),
    );

    if (!AppLocalizations.delegate.isSupported(normalizedLocale)) {
      return;
    }

    _locale = normalizedLocale;

    notifyListeners();
    await prefs.setString(_key, normalizedLocale.languageCode);
  }

  Future<void> clearLocale() async {
    await setLocale(null);
  }
}
