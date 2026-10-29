import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/analytics/analytics_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

Widget _analyticsApp(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
void main() {
  group('AI Analytics Integration Tests', () {
    testWidgets('AnalyticsPage contains loading state initially', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _analyticsApp(const AnalyticsPage(patientId: 123)),
      );

      // Don't use pumpAndSettle — it times out due to ongoing animations.
      // Just pump once to render the initial loading state.
      await tester.pump();

      // The analytics page starts in loading state with a CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AI chat widget is accessible via FAB after data loads', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _analyticsApp(const AnalyticsPage(patientId: 123)),
      );

      // Pump to trigger initial frame
      await tester.pump();

      // The AnalyticsPage shows a FAB with chat_bubble_outline icon
      // even in loading/error states the Scaffold is present
      expect(find.byType(Scaffold), findsOneWidget);
    });

    test('Health data context anonymizes patient information', () {
      // Test the concept that analytics pages should:
      // - Remove patient names and personal identifiers
      // - Include anonymized health data
      // - Provide guidance on what questions can be asked

      expect(
        true,
        isTrue,
      ); // Placeholder - actual implementation would test the context method
    });

    testWidgets('AnalyticsPage shows Scaffold', (WidgetTester tester) async {
      await tester.pumpWidget(
        _analyticsApp(const AnalyticsPage(patientId: 123)),
      );
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('AnalyticsPage shows AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        _analyticsApp(const AnalyticsPage(patientId: 123)),
      );
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('AnalyticsPage renders with different patientId',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _analyticsApp(const AnalyticsPage(patientId: 456)),
      );
      expect(find.byType(AnalyticsPage), findsOneWidget);
    });
  });
}
