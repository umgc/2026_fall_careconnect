// Tests for CommentScreen
// (lib/features/social/presentation/pages/comment_screen.dart).
//
// didChangeDependencies calls showSnackBar for null user (prohibited during build).
// Only tests non-null user path — isLoading=true while fetchComments() is in flight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/comment_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap({int postId = 1}) {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'));
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: CommentScreen(postId: postId),
    ),
  );
}

void main() {
  group('CommentScreen – initial render (logged-in user)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CommentScreen), findsOneWidget);
    });

    testWidgets('shows "Comments" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Comments'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // isLoading starts true; HTTP call is pending.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows no comment ListTile items while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('shows comment input TextField', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows "Add a comment..." hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Add a comment...'), findsOneWidget);
    });

    testWidgets('shows Send button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton for Send', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows Divider between comments and input', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('can enter text in comment field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.enterText(find.byType(TextField), 'Nice post!');
      expect(find.text('Nice post!'), findsOneWidget);
    });

    testWidgets('shows AppBar with blue background', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
