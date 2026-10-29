// Tests for MedicationAppHeader
// (lib/features/health/medication-tracker/widgets/medication-header.dart).
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('back button has the localized "Back" name and pops',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('Home')),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
          appBar: MedicationAppHeader(onAddPressed: () {}),
          body: const Text('Medications')),
    ));
    await tester.pumpAndSettle();

    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Medications'), findsNothing);
  });

  testWidgets('Add calls onAddPressed', (tester) async {
    var added = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(appBar: MedicationAppHeader(onAddPressed: () => added++)),
    ));
    await tester.tap(find.text('Add'));
    expect(added, 1);
  });
}
