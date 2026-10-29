// Accessibility test for AlertNotification: the dismiss button has a name
// (WCAG 4.1.2), found unnamed on the patient dashboard in the VPAT final pass.
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the dismiss button is named "Close"', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AlertNotification(
          type: AlertType.important,
          message: 'Mood score below normal range.',
          onDismiss: () => dismissed = true,
        ),
      ),
    ));
    await tester.tap(find.byTooltip('Close'));
    expect(dismissed, isTrue);
  });
}
