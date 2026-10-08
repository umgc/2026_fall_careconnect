// Tests for ChatRoomScreen
// (lib/features/social/presentation/pages/chat_room_screen.dart).
//
// didChangeDependencies reads UserProvider.
// With non-null user: sets _currentUserId, starts polling timer (cancelled on dispose),
// calls fetchConversation() async (HTTP fails gracefully, isLoading=true initially).
// Build: peerName shown in AppBar, loading spinner visible.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap() {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT'),
  );
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const ChatRoomScreen(peerUserId: 2, peerName: 'Alice'),
    ),
  );
}

void main() {
  group('ChatRoomScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ChatRoomScreen), findsOneWidget);
    });

    testWidgets('shows peer name in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      // isLoading=true on first frame before fetchConversation() resolves.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
