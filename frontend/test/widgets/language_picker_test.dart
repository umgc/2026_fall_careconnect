// Tests for LanguagePicker
// (lib/widgets/language/language_picker.dart).
//
// The show() method opens a bottom sheet and requires a live BuildContext
// with a LocaleProvider — tested separately below.
// The labelFor() method is a pure static function, fully testable here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/language/language_picker.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  // ──────────────────────────────────────────────────────────────
  // LanguagePicker.labelFor
  // ──────────────────────────────────────────────────────────────

  group('LanguagePicker.labelFor', () {
    test('returns English for en locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('en'), l10n), 'English');
    });

    test('returns Spanish label for es locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('es'), l10n),
          contains('Spanish'));
    });

    test('returns French label for fr locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('fr'), l10n),
          contains('French'));
    });

    test('returns Urdu label for ur locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
          LanguagePicker.labelFor(const Locale('ur'), l10n), contains('Urdu'));
    });

    test('returns Arabic label for ar locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('ar'), l10n),
          contains('Arabic'));
    });

    test('returns Amharic label for am locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('am'), l10n),
          contains('Amharic'));
    });

    test('returns Nepali label for ne locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('ne'), l10n),
          contains('Nepali'));
    });

    test('returns Hindi label for hi locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
          LanguagePicker.labelFor(const Locale('hi'), l10n), contains('Hindi'));
    });

    test('returns Farsi label for fa locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
          LanguagePicker.labelFor(const Locale('fa'), l10n), contains('Farsi'));
    });

    test('returns Chinese label for zh locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('zh'), l10n),
          contains('Chinese'));
    });

    test('returns Portuguese label for pt locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('pt'), l10n),
          contains('Portuguese'));
    });

    test('returns Bengali label for bn locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('bn'), l10n),
          contains('Bengali'));
    });

    test('returns Russian label for ru locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('ru'), l10n),
          contains('Russian'));
    });

    test('returns Japanese label for ja locale', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(LanguagePicker.labelFor(const Locale('ja'), l10n),
          contains('Japanese'));
    });

    test('falls back to language tag for unknown locale', () async {
      // Verifies that an unknown locale returns its language tag string.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final locale = const Locale('xx');
      expect(LanguagePicker.labelFor(locale, l10n), locale.toLanguageTag());
    });
  });

  // ──────────────────────────────────────────────────────────────
  // LanguagePicker.show — widget test (bottom sheet content)
  // ──────────────────────────────────────────────────────────────

  group('LanguagePicker.show', () {
    testWidgets(
        'TC-S4-REG-L10N-002 selecting Spanish updates and persists locale',
        (tester) async {
      final localeProvider = LocaleProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleProvider>.value(
          value: localeProvider,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => LanguagePicker.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Spanish'));
      await tester.pumpAndSettle();

      expect(localeProvider.locale, const Locale('es'));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('selected_locale'), 'es');
    });

    testWidgets('opens a bottom sheet with a ListView', (tester) async {
      // Verifies that show() renders a bottom sheet containing a ListView.
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () => LanguagePicker.show(ctx),
            child: const Text('Open'),
          );
        }),
      ));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('bottom sheet contains System Default option', (tester) async {
      // Verifies that the "System default" item is shown in the picker.
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () => LanguagePicker.show(ctx),
            child: const Text('Open'),
          );
        }),
      ));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The first item is the "System default" tile.
      expect(find.byIcon(Icons.phone_iphone), findsOneWidget);
    });

    testWidgets('bottom sheet contains translate icon for locales',
        (tester) async {
      // Verifies that locale items use the translate icon.
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () => LanguagePicker.show(ctx),
            child: const Text('Open'),
          );
        }),
      ));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // There should be at least one translate icon (one per supported locale).
      expect(find.byIcon(Icons.translate), findsWidgets);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // LanguagePicker.show — responsive layout (landscape / tablet)
  // ──────────────────────────────────────────────────────────────

  group('LanguagePicker.show - responsive layout', () {
    // Opens the picker at whatever surface size the test has configured.
    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () => LanguagePicker.show(ctx),
            child: const Text('Open'),
          );
        }),
      ));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('TC-S4-REG-RESP-003 mobile landscape sheet stays in viewport',
            (tester) async {
          tester.view.physicalSize = const Size(800, 360);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await openPicker(tester);

          final listRect = tester.getRect(find.byType(ListView));
          expect(listRect.left, greaterThanOrEqualTo(0));
          expect(listRect.right, lessThanOrEqualTo(800));
          expect(listRect.top, greaterThanOrEqualTo(0));
          expect(listRect.bottom, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
        });

    testWidgets('mobile-landscape: can scroll to the last locale',
            (tester) async {
          // The core requirement: every language stays reachable on a short
          // landscape screen where only a few rows fit at once.
          tester.view.physicalSize = const Size(800, 360);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await openPicker(tester);

          final lastLocale = AppLocalizations.supportedLocales.last;
          final context = tester.element(find.byType(ListView));
          final lastLabel = LanguagePicker.labelFor(
            lastLocale,
            AppLocalizations.of(context)!,
          );

          // Off-screen initially on a short sheet; scroll to reveal it.
          await tester.scrollUntilVisible(
            find.text(lastLabel),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text(lastLabel), findsOneWidget);
        });

    testWidgets('tablet width: sheet remains bounded and usable',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await openPicker(tester);

          final listRect = tester.getRect(find.byType(ListView));
          expect(listRect.left, greaterThanOrEqualTo(0));
          expect(listRect.right, lessThanOrEqualTo(1000));
          expect(tester.takeException(), isNull);
        });

    testWidgets('narrow width: sheet remains bounded and usable',
            (tester) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await openPicker(tester);

          final listRect = tester.getRect(find.byType(ListView));
          expect(listRect.left, greaterThanOrEqualTo(0));
          expect(listRect.right, lessThanOrEqualTo(400));
          expect(tester.takeException(), isNull);
        });
  });
}
