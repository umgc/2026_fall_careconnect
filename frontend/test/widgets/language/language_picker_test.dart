import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/widgets/language/language_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget buildApp(LocaleProvider provider) {
    return ChangeNotifierProvider<LocaleProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => LanguagePicker.show(context),
                  child: const Text('Open language picker'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets('uses a centered dialog with all supported language choices', (
    tester,
  ) async {
    final provider = LocaleProvider();

    await tester.pumpWidget(buildApp(provider));
    await tester.tap(find.text('Open language picker'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    expect(find.text('EN'), findsOneWidget);
    expect(find.text('ES'), findsOneWidget);

    expect(find.byIcon(Icons.translate), findsNothing);

    final languageList = find.byType(ListView);
    expect(languageList, findsOneWidget);

    for (var i = 0;
        i < 5 && find.text('Français (French)').evaluate().isEmpty;
        i++) {
      await tester.drag(languageList, const Offset(0, -200));
      await tester.pumpAndSettle();
    }

    expect(find.text('Français (French)'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
  });

  testWidgets(
    'selects and persists a supported language outside English and Spanish',
    (tester) async {
      final provider = LocaleProvider();

      await tester.pumpWidget(buildApp(provider));
      await tester.tap(find.text('Open language picker'));
      await tester.pumpAndSettle();

      final languageList = find.byType(ListView);
      expect(languageList, findsOneWidget);

      for (var i = 0;
          i < 5 && find.text('Français (French)').evaluate().isEmpty;
          i++) {
        await tester.drag(languageList, const Offset(0, -200));
        await tester.pumpAndSettle();
      }

      expect(find.text('Français (French)'), findsOneWidget);
      expect(find.text('FR'), findsOneWidget);

      await tester.tap(find.text('Français (French)'));
      await tester.pumpAndSettle();

      expect(provider.locale, const Locale('fr'));
      expect(find.byType(Dialog), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_locale'), 'fr');
    },
  );

  testWidgets('System Default clears an explicit selection', (tester) async {
    final provider = LocaleProvider();
    await provider.setLocale(const Locale('es'));

    await tester.pumpWidget(buildApp(provider));
    await tester.tap(find.text('Open language picker'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();

    expect(provider.locale, isNull);
    expect(find.byType(Dialog), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('selected_locale'), isFalse);
  });
}
