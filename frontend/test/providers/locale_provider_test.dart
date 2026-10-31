import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset SharedPreferences before each test to prevent state leakage.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('LocaleProvider initial state', () {
    test('locale is null before any value is loaded or set', () {
      // Verifies that a newly constructed provider exposes no locale until
      // either loadSaved() or setLocale() is called.
      final provider = LocaleProvider();
      expect(provider.locale, isNull);
    });
  });

  group('LocaleProvider.loadSaved', () {
    test('sets locale from a previously persisted language code', () async {
      // Verifies that loadSaved() reads the stored code and wraps it in a
      // Locale object, restoring the user's language choice across sessions.
      SharedPreferences.setMockInitialValues(
          <String, Object>{'selected_locale': 'es'});
      final provider = LocaleProvider();
      await provider.loadSaved();

      expect(provider.locale, isNotNull);
      expect(provider.locale!.languageCode, 'es');
    });

    test('restores a supported locale outside English and Spanish', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'selected_locale': 'fr'},
      );
      final provider = LocaleProvider();
      await provider.loadSaved();

      expect(provider.locale, const Locale('fr'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), 'fr');
    });

    test('clears a saved language when it is unsupported', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'selected_locale': 'fy'},
      );
      final provider = LocaleProvider();
      await provider.loadSaved();

      expect(provider.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), isNull);
    });

    test('keeps locale null when no preference has been saved', () async {
      // Verifies the early-return path when the key is absent.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = LocaleProvider();
      await provider.loadSaved();

      expect(provider.locale, isNull);
    });

    test('keeps locale null when the saved code is an empty string', () async {
      // Verifies the guard that ignores empty strings from SharedPreferences.
      SharedPreferences.setMockInitialValues(
          <String, Object>{'selected_locale': ''});
      final provider = LocaleProvider();
      await provider.loadSaved();

      expect(provider.locale, isNull);
    });

    test('notifies listeners when a saved locale is found', () async {
      // Verifies that widgets are rebuilt after loadSaved() resolves a locale.
      SharedPreferences.setMockInitialValues(
          <String, Object>{'selected_locale': 'fr'});
      final provider = LocaleProvider();
      bool notified = false;
      provider.addListener(() => notified = true);
      await provider.loadSaved();

      expect(notified, isTrue);
    });

    test('does not notify listeners when no preference is stored', () async {
      // Verifies that a no-op loadSaved() does not trigger unnecessary rebuilds.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = LocaleProvider();
      bool notified = false;
      provider.addListener(() => notified = true);
      await provider.loadSaved();

      expect(notified, isFalse);
    });
  });

  group('LocaleProvider.setLocale', () {
    test(
        'sets locale in memory and persists language code to SharedPreferences',
        () async {
      // Verifies that setLocale stores the locale and writes its languageCode
      // so that it can be restored by loadSaved() on the next app launch.
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('es'));

      expect(provider.locale!.languageCode, 'es');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), 'es');
    });

    test('sets and persists a supported locale outside English and Spanish',
        () async {
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ja'));

      expect(provider.locale, const Locale('ja'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), 'ja');
    });

    test('ignores an unsupported locale', () async {
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ko'));

      expect(provider.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), isNull);
    });

    test('clears locale and removes preference when called with null',
        () async {
      // Verifies the null branch: passing null removes the stored preference
      // so the app falls back to the system locale on next launch.
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ja'));
      await provider.setLocale(null);

      expect(provider.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), isNull);
    });

    test('notifies listeners on every call including null', () async {
      // Verifies ChangeNotifier behaviour for both set and clear operations.
      final provider = LocaleProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.setLocale(const Locale('zh'));
      await provider.setLocale(null);

      expect(notifyCount, 2);
    });

    test('overwrites a previously set locale', () async {
      // Verifies that calling setLocale twice keeps only the latest value.
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('en'));
      await provider.setLocale(const Locale('es'));

      expect(provider.locale!.languageCode, 'es');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), 'es');
    });
  });

  group('LocaleProvider.clearLocale', () {
    test('sets locale to null and removes the SharedPreferences key', () async {
      // Verifies that clearLocale() is equivalent to setLocale(null) but as a
      // dedicated method for clarity at call sites.
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ko'));
      await provider.clearLocale();

      expect(provider.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('selected_locale'), isFalse);
    });

    test('notifies listeners', () async {
      // Verifies that clearing the locale triggers a widget rebuild.
      final provider = LocaleProvider();
      await provider.setLocale(const Locale('ar'));
      bool notified = false;
      provider.addListener(() => notified = true);
      await provider.clearLocale();

      expect(notified, isTrue);
    });

    test('is safe to call when locale is already null', () async {
      // Verifies that clearLocale() on a provider with no locale does not throw.
      final provider = LocaleProvider();
      await expectLater(provider.clearLocale(), completes);
      expect(provider.locale, isNull);
    });
  });
}
