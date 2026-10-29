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
        supportedLocales: const <Locale>[Locale('en'), Locale('es')],
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

  testWidgets('uses a centered dialog with only supported choices', (
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
    expect(find.text('Español (Spanish)'), findsOneWidget);

    expect(find.text('EN'), findsOneWidget);
    expect(find.text('ES'), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsNothing);
    expect(find.textContaining('Arabic'), findsNothing);
  });

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
