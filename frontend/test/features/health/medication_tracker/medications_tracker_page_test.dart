// Tests for MedicationsTrackerPage
// (lib/features/health/medication-tracker/pages/medication-tracker.dart).
//
// initState calls _fetchMedications() using Provider.of<UserProvider>.
// With patientId=null, returns early setting error without HTTP call.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

import '../../../mock_user_provider.dart';

Widget _wrap() {
  // patientId: null -> _fetchMedications() sets error without HTTP call.
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT', patientId: null),
  );
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const MedicationsTrackerPage(),
    ),
  );
}

void main() {
  group('MedicationsTrackerPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(MedicationsTrackerPage), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error for null patientId', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Patient ID not found'), findsOneWidget);
    });

    testWidgets('shows error_outline icon on error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows Retry button on error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows refresh icon on Retry button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('does NOT show CircularProgressIndicator after error',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
