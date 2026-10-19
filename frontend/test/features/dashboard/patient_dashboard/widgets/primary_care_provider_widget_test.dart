// Tests for PrimaryCareProviderWidget
// (lib/features/dashboard/patient_dashboard/widgets/primary_care_provider_widget.dart).
//
// Pure StatelessWidget with no Provider or HTTP.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/primary_care_provider_widget.dart';

Widget _wrap() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PrimaryCareProviderWidget(
            providerName: 'Dr. Jane Smith',
            specialty: 'Family Medicine',
            organization: 'HealthFirst Clinic',
            phone: '555-1234',
            email: 'jsmith@health.com',
          ),
        ),
      ),
    );

void main() {
  group('PrimaryCareProviderWidget', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PrimaryCareProviderWidget), findsOneWidget);
    });

    testWidgets('shows provider name', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Dr. Jane Smith'), findsOneWidget);
    });

    testWidgets('shows specialty', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Family Medicine'), findsOneWidget);
    });

    testWidgets('shows organization', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('HealthFirst Clinic'), findsOneWidget);
    });

    testWidgets('shows "Your Primary Care Provider" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Your Primary Care Provider'), findsOneWidget);
    });

    testWidgets('shows CircleAvatar with initials', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('shows phone number', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('555-1234'), findsOneWidget);
    });

    testWidgets('shows email address', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('jsmith@health.com'), findsOneWidget);
    });

    testWidgets('shows Contact Information heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Contact Information'), findsOneWidget);
    });

    testWidgets('shows Contact Provider button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Contact Provider'), findsOneWidget);
    });
  });
}
