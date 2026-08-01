import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/shared/widgets/disclaimer_banner.dart';

/// Widget tests for the WBS 3.15.4 disclaimer banner
/// these assert the` [AppLocalizations] values and
/// verify the banner switches languages
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(DisclaimerBanner)))!;

  group('DisclaimerBanner', () {
    testWidgets('ai() renders the localized AI disclaimer', (tester) async {
      await pump(tester, const DisclaimerBanner.ai());
      expect(find.text(l10n(tester).aiDisclaimer), findsOneWidget);
    });

    testWidgets('medication() renders the localized medication disclaimer',
        (tester) async {
      await pump(tester, const DisclaimerBanner.medication());
      expect(find.text(l10n(tester).medicationDisclaimer), findsOneWidget);
    });

    testWidgets('renders Spanish copy under the es locale', (tester) async {
      await pump(tester, const DisclaimerBanner.ai(),
          locale: const Locale('es'));
      final es = l10n(tester);
      expect(es.localeName, 'es');
      expect(find.text(es.aiDisclaimer), findsOneWidget);
    });

    testWidgets('renders at the 18pt accessibility font size', (tester) async {
      await pump(tester, const DisclaimerBanner.ai());
      final Text text = tester.widget(find.text(l10n(tester).aiDisclaimer));
      expect(text.style?.fontSize, DisclaimerBanner.kFontSize);
      expect(DisclaimerBanner.kFontSize, 18.0);
    });

    testWidgets('exposes a localized Semantics label for screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const DisclaimerBanner.ai());
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n(tester).disclaimerLabel))),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('renders in dark theme without error', (tester) async {
      await pump(tester, const DisclaimerBanner.medication(),
          brightness: Brightness.dark);
      expect(find.text(l10n(tester).medicationDisclaimer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
