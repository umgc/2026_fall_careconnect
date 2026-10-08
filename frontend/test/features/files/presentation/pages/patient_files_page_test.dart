// Tests for PatientFilesPage
// (lib/features/files/presentation/pages/patient_files_page.dart).
//
// initState calls _loadFiles() (API via EnhancedFileService, try/catch).
// _isLoading is set to true at the start of _loadFiles().
// Tests use pump() only to check the initial loading state.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/files/presentation/pages/patient_files_page.dart';

Widget _wrap({int patientId = 1, String patientName = 'Jane Doe'}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: PatientFilesPage(patientId: patientId, patientName: patientName),
    );

void main() {
  group('PatientFilesPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PatientFilesPage), findsOneWidget);
    });

    testWidgets('shows patient name in AppBar title', (tester) async {
      await tester.pumpWidget(_wrap(patientName: 'Jane Doe'));
      expect(find.textContaining('Jane Doe'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows TabBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // _loadFiles() sets _isLoading=true before the async API call.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows no file ListTile items while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListTile), findsNothing);
    });
  });
}
