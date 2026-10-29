// Tests for HiringFormsTab (lib/widgets/forms/hiring_forms_tab.dart).
//
// The tab loads the bundled form definitions (assets/forms/*.form.json).
// Opening a form shows its details page, and "Fill out" opens the fill-in
// page; both are titled pages (WCAG 2.4.2).
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/forms/hiring_forms_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [probe],
      home: const Scaffold(body: HiringFormsTab(patientId: 12)),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the bundled hiring forms', (tester) async {
    await pumpTab(tester);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });

  testWidgets('opening a form pushes a page titled "Hiring Form Details"',
      (tester) async {
    await pumpTab(tester);
    expect(
        await probe.tapAndReadTitle(
            tester, find.byIcon(Icons.chevron_right).first),
        'Hiring Form Details');
  });

  testWidgets('"Fill out" pushes a page titled "Complete Hiring Form"',
      (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(
        await probe.tapAndReadTitle(tester, find.byType(FloatingActionButton)),
        'Complete Hiring Form');
  });
}
