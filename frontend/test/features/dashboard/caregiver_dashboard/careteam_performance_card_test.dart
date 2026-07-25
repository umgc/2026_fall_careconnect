// Tests for CareTeamPerformance widget
// (lib/features/dashboard/caregiver-dashboard/widgets/careteam-performace-card.dart).

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/careteam-performace-card.dart';

void main() {
  Widget buildTestWidget() {
    return const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CareTeamPerformance(),
        ),
      ),
    );
  }

  group('CareTeamPerformance', () {
    testWidgets('renders the title "Care Team Performance"', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Care Team Performance'), findsOneWidget);
    });

    testWidgets('renders the trending_up icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    });

    testWidgets('renders "Overall Patient Satisfaction" label', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Overall Patient Satisfaction'), findsOneWidget);
    });

    testWidgets('renders "Based on last 30 days" subtitle', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Based on last 30 days'), findsOneWidget);
    });

    testWidgets('renders satisfaction score "4.8/5"', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('4.8/5'), findsOneWidget);
    });

    testWidgets('renders "Excellent" rating text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Excellent'), findsOneWidget);
    });

    testWidgets('renders "Check-in Completion Rate" label', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Check-in Completion Rate'), findsOneWidget);
    });

    testWidgets('renders "89%" completion value', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('89%'), findsOneWidget);
    });

    testWidgets('renders a LinearProgressIndicator', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('LinearProgressIndicator has value 0.89', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 0.89);
    });

    testWidgets('widget is wrapped in a decorated container', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // The widget's root is a Container with BoxDecoration including
      // borderRadius and boxShadow. Verify Container exists.
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders correctly with dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: CareTeamPerformance(),
            ),
          ),
        ),
      );
      expect(find.text('Care Team Performance'), findsOneWidget);
      expect(find.text('4.8/5'), findsOneWidget);
      expect(find.text('89%'), findsOneWidget);
    });

    testWidgets('all text widgets are present in the tree', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      // Verify all key text elements render.
      final expectedTexts = [
        'Care Team Performance',
        'Overall Patient Satisfaction',
        'Based on last 30 days',
        '4.8/5',
        'Excellent',
        'Check-in Completion Rate',
        '89%',
      ];
      for (final text in expectedTexts) {
        expect(find.text(text), findsOneWidget, reason: 'Missing text: $text');
      }
    });
  });
}
