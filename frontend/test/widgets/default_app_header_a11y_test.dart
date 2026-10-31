// Accessibility tests for DefaultAppHeader: its icon-only back and Settings
// buttons have names (WCAG 4.1.2), found unnamed in the VPAT final-build pass.
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/default_app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({bool showBackButton = false}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(appBar: DefaultAppHeader(showBackButton: showBackButton)),
    );

void main() {
  testWidgets('the Settings button is named "Settings"', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('the back button is named "Back"', (tester) async {
    await tester.pumpWidget(_wrap(showBackButton: true));
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}
