// Tests for FriendRequestsScreen
// (lib/features/social/presentation/pages/friend_requests_screen.dart).
//
// didChangeDependencies calls fetchRequests() for non-null users (HTTP via
// http package, which fails gracefully and leaves isLoading=false).
// Only non-null-user path is tested (null-user path calls showSnackBar
// during didChangeDependencies, which is prohibited during build).
//
// Tests use pump() only (not pumpAndSettle) to capture the loading state
// before the HTTP call completes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/friend_requests_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap() {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'));
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const FriendRequestsScreen(),
    ),
  );
}

void main() {
  group('FriendRequestsScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(FriendRequestsScreen), findsOneWidget);
    });

    testWidgets('shows "Friend Requests" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Friend Requests'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // isLoading starts true; HTTP call is pending — spinner is visible.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows no ListTile results while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });
  });
}
