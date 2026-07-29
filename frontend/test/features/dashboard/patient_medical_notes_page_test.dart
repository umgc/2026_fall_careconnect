// Tests for PatientMedicalNotesPage
// (lib/features/dashboard/presentation/pages/patient_medical_notes_page.dart).
//
// StatelessWidget that reads UserProvider in build.
// PatientNotesWidget inside calls an API in initState, but the overall
// page Scaffold renders synchronously.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/patient_medical_notes_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

Widget _wrap({int patientId = 1, String patientName = 'Jane Doe'}) {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1),
  );
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales, 
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: PatientMedicalNotesPage(
        patientId: patientId,
        patientName: patientName,
      ),
    ),
  );
}

void main() {
  group('PatientMedicalNotesPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(PatientMedicalNotesPage), findsOneWidget);
    });

    testWidgets('shows patient name in AppBar', (tester) async {
      await tester.pumpWidget(_wrap(patientName: 'Jane Doe'));
      await tester.pump();
      expect(find.textContaining('Jane Doe'), findsWidgets);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows "Caregiver View" chip for caregiver role', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Caregiver View'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows with different patient name', (tester) async {
      await tester.pumpWidget(_wrap(patientName: 'John Smith'));
      await tester.pump();
      expect(find.textContaining('John Smith'), findsWidgets);
    });

    testWidgets('shows with different patientId', (tester) async {
      await tester.pumpWidget(_wrap(patientId: 42));
      await tester.pump();
      expect(find.byType(PatientMedicalNotesPage), findsOneWidget);
    });
  });
}
