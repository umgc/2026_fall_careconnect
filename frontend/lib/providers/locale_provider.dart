import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const _key = 'selected_locale';
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null && code.isNotEmpty) {
      if(AppLocalizations.delegate.isSupported(Locale(code))){
          _locale = Locale(code);
          notifyListeners();
      }
      else{
          clearLocale();
          notifyListeners();
      }
    }
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
  }

  Future<void> clearLocale() async {
    _locale = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
