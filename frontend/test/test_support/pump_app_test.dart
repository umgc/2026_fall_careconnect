// Tests for the shared pump helper (test/test_support/pump_app.dart).

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'pump_app.dart';

void main() {
  testWidgets('provides AppLocalizations to the child', (tester) async {
    AppLocalizations? l10n;
    await pumpCareConnectApp(
      tester,
      Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const SizedBox();
      }),
    );

    expect(l10n, isNotNull);
    expect(l10n!.localeName, 'en');
  });

  testWidgets('honors the locale argument', (tester) async {
    final other = AppLocalizations.supportedLocales
        .firstWhere((l) => l.languageCode != 'en');
    String? localeName;
    await pumpCareConnectApp(
      tester,
      Builder(builder: (context) {
        localeName = AppLocalizations.of(context)!.localeName;
        return const SizedBox();
      }),
      locale: other,
    );

    expect(localeName, isNot('en'));
  });

  testWidgets('exposes the given providers', (tester) async {
    await pumpCareConnectApp(
      tester,
      Builder(builder: (context) => Text(context.watch<String>())),
      providers: [Provider<String>.value(value: 'from provider')],
    );

    expect(find.text('from provider'), findsOneWidget);
  });
}
