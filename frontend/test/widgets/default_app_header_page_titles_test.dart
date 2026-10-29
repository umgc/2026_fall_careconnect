// Page-title tests for DefaultAppHeader (lib/widgets/default_app_header.dart):
// the settings icon opens Settings in a titled page (WCAG 2.4.2).
import 'package:care_connect_app/widgets/default_app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/titled_route_probe.dart';

void main() {
  testWidgets('the settings icon opens a page titled "Settings"',
      (tester) async {
    final probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const Scaffold(appBar: DefaultAppHeader()),
    ));
    expect(
        await probe.tapAndReadTitle(
            tester, find.byIcon(Icons.settings_outlined)),
        'Settings');
  });
}
