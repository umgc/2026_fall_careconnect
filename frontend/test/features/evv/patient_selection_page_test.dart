import 'package:care_connect_app/l10n/app_localizations.dart';
// Tests for PatientSelectionPage
// (lib/features/evv/presentation/pages/patient_selection_page.dart).
//
// _isLoading starts true; _loadPatients() uses Provider.of<UserProvider> (try/catch).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/evv/presentation/pages/patient_selection_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

Widget _wrap() {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER'));
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const PatientSelectionPage(),
    ),
  );
}

void main() {
  group('PatientSelectionPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PatientSelectionPage), findsOneWidget);
    });

    testWidgets('shows "Select Patient" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select Patient'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });
  });
}
