// Tests for AlertNotification and AlertType
// (lib/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart).

import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Searches the widget tree for a RichText whose plain text contains [text].
Finder richTextContaining(String text) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(text),
    );

void main() {
  group('AlertType enum', () {
    test('has important, reminder, success, info', () {
      expect(AlertType.values, containsAll([
        AlertType.important,
        AlertType.reminder,
        AlertType.success,
        AlertType.info,
      ]));
    });
  });

  group('AlertNotification widget', () {
    testWidgets('renders Important: label and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, 
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.important,
              message: 'Take your medication',
            ),
          ),
        ),
      );
      expect(richTextContaining('Important:'), findsOneWidget);
      expect(richTextContaining('Take your medication'), findsOneWidget);
    });

    testWidgets('renders Reminder: label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, 
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.reminder,
              message: 'Check-in at 3pm',
            ),
          ),
        ),
      );
      expect(richTextContaining('Reminder:'), findsOneWidget);
    });

    testWidgets('renders Success: label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, 
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.success,
              message: 'Dose recorded',
            ),
          ),
        ),
      );
      expect(richTextContaining('Success:'), findsOneWidget);
    });

    testWidgets('renders Info: label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.info,
              message: 'New caregiver assigned',
            ),
          ),
        ),
      );
      expect(richTextContaining('Info:'), findsOneWidget);
    });

    testWidgets('shows close button when onDismiss provided', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, 
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.info,
              message: 'Tap X to dismiss',
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('hides close button when onDismiss is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, 
          home: Scaffold(
            body: AlertNotification(
              type: AlertType.important,
              message: 'No dismiss',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
