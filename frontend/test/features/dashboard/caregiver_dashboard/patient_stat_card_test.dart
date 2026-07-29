// Tests for PatientStatisticsCards
// (lib/features/dashboard/caregiver-dashboard/widgets/patient-stat-card.dart).

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/patient-stat-card.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Missed Check-Ins stat value 24', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    // Large-screen layout: '# of Missed\nCheck-Ins'; search common substring.
    expect(find.textContaining('Missed'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('renders Active Patients stat value 32', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.text('32'), findsOneWidget);
  });

  testWidgets('renders on small screen (column layout, <600px)', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.text('24'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
  });

  testWidgets('shows people_outline and monitor_heart icons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
  });

  testWidgets('shows "Active Patients" text on large screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.textContaining('Active'), findsOneWidget);
    expect(find.textContaining('Patients'), findsOneWidget);
  });

  testWidgets('shows "Check-Ins" text on large screen', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.textContaining('Check-Ins'), findsOneWidget);
  });

  testWidgets('uses Row layout on large screen (>= 600px)', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.byType(Row), findsWidgets);
  });

  testWidgets('uses Column layout on small screen (< 600px)', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.byType(Column), findsWidgets);
  });

  testWidgets('shows FittedBox for value text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.byType(FittedBox), findsWidgets);
  });

  testWidgets('shows LayoutBuilder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales, 
        home: Scaffold(body: PatientStatisticsCards()),
      ),
    );
    expect(find.byType(LayoutBuilder), findsOneWidget);
  });
}
