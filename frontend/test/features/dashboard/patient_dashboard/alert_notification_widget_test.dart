// Tests for AlertNotification widget
// (lib/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart).
//
// Pure StatelessWidget with no Provider or HTTP.
// Uses RichText internally — text assertions use find.byType(RichText).

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';

Widget _wrap(AlertNotification widget) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: widget));

void main() {
  group('AlertNotification widget', () {
    testWidgets('renders without crashing (info type)', (tester) async {
      await tester.pumpWidget(_wrap(const AlertNotification(
        type: AlertType.info,
        message: 'Test message',
      )));
      expect(find.byType(AlertNotification), findsOneWidget);
    });

    testWidgets('renders RichText with message', (tester) async {
      await tester.pumpWidget(_wrap(const AlertNotification(
        type: AlertType.info,
        message: 'Test message',
      )));
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('shows warning icon', (tester) async {
      await tester.pumpWidget(_wrap(const AlertNotification(
        type: AlertType.important,
        message: 'Important alert',
      )));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows dismiss button when onDismiss provided', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.reminder,
        message: 'Reminder',
        onDismiss: () {},
      )));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('does NOT show dismiss button when onDismiss is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const AlertNotification(
        type: AlertType.success,
        message: 'Success',
      )));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('dismiss callback fires when close icon tapped', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.reminder,
        message: 'Tap dismiss',
        onDismiss: () => dismissed = true,
      )));
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('renders with success type', (tester) async {
      await tester.pumpWidget(_wrap(const AlertNotification(
        type: AlertType.success,
        message: 'All good',
      )));
      expect(find.byType(AlertNotification), findsOneWidget);
    });
  });
}
