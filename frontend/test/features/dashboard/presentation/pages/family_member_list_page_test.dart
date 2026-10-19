// Tests for FamilyPatientsPage
// (lib/features/dashboard/presentation/pages/family_member_list_page.dart).
//
// FamilyPatientsPage calls ApiService.getAccessiblePatients() in initState.
// The call is wrapped in try/catch, so failures silently set error+isLoading=false.
// Initial render (isLoading=true) is safe to test with pump() only.
// Does NOT require UserProvider or GoRouter (navigation only in onTap).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/family_member_list_page.dart';

Widget _wrap() => const MaterialApp(home: FamilyPatientsPage());

void main() {
  group('FamilyPatientsPage – initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      // Do NOT pumpAndSettle — the API call is in flight.
      expect(find.byType(FamilyPatientsPage), findsOneWidget);
    });

    testWidgets('shows "My Patients" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('My Patients'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // isLoading starts true → progress indicator displayed immediately.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows a RefreshIndicator', (tester) async {
      // The body is always wrapped in RefreshIndicator.
      await tester.pumpWidget(_wrap());
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('does NOT show a ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('does NOT show error icon while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.error), findsNothing);
    });
  });
}
