// Page-title tests for EmergencyScreen (lib/features/dashboard/presentation/mainscreen.dart).
// Setup copied from mainscreen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/mainscreen.dart';
import '../../../helpers/titled_route_probe.dart';

Widget _wrap() => MaterialApp(navigatorObservers: [probe], locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: EmergencyScreen());

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  for (final (button, title) in [
    ('Cancel', 'Cancel Alert'),
    ('Yes, Send SOS', 'Emergency Assistance'),
  ]) {
    testWidgets('"$button" in the SOS dialog opens a page titled "$title"',
        (tester) async {
      probe = TitledRouteProbe();
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(await probe.tapAndReadTitle(tester, find.text(button)), title);
    });
  }
}
