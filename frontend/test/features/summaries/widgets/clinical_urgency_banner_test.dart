import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/summaries/widgets/clinical_urgency_banner.dart';

/// Widget tests for [ClinicalUrgencyBanner].
///
/// Verifies the risk-level → visual mapping documented in the widget:
/// HIGH renders a red strip with default copy; MODERATE renders an amber
/// strip; LOW, null, and unrecognized values collapse to nothing so
/// callers can drop the widget in without guards; and callers can
/// override the visible copy via [message].
///
/// Part of WBS 3.4.6 test coverage.
void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required String? riskLevel,
    String? message,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClinicalUrgencyBanner(
            riskLevel: riskLevel,
            message: message,
          ),
        ),
      ),
    );
  }

  group('ClinicalUrgencyBanner', () {
    testWidgets('HIGH risk renders warning icon and default copy',
        (tester) async {
      await pumpBanner(tester, riskLevel: 'HIGH');

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        find.text('High clinical risk — review recommended'),
        findsOneWidget,
      );
    });

    testWidgets('MODERATE risk renders info icon and default copy',
        (tester) async {
      await pumpBanner(tester, riskLevel: 'MODERATE');

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(
        find.text('Moderate clinical concern — monitor closely'),
        findsOneWidget,
      );
    });

    testWidgets('LOW risk collapses to SizedBox.shrink (no visible banner)',
        (tester) async {
      await pumpBanner(tester, riskLevel: 'LOW');

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('null risk collapses to SizedBox.shrink', (tester) async {
      await pumpBanner(tester, riskLevel: null);

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('Unrecognized risk value collapses to SizedBox.shrink',
        (tester) async {
      await pumpBanner(tester, riskLevel: 'urgent');

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('Custom message overrides default copy on HIGH',
        (tester) async {
      await pumpBanner(
        tester,
        riskLevel: 'HIGH',
        message: 'Escalate to on-call clinician immediately',
      );

      expect(
        find.text('Escalate to on-call clinician immediately'),
        findsOneWidget,
      );
      expect(
        find.text('High clinical risk — review recommended'),
        findsNothing,
      );
      // Icon still renders even with custom copy.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('Lowercase risk value ("high") still triggers HIGH banner',
        (tester) async {
      await pumpBanner(tester, riskLevel: 'high');

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        find.text('High clinical risk — review recommended'),
        findsOneWidget,
      );
    });
  });
}