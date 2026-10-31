// Gap tests for LeaderboardScreen: the loaded list, empty state and medal
// labels. The screen calls package:http directly, so the HTTP layer is
// replaced through HttpOverrides (FakeHttpOverrides); no network is used.

import 'dart:io';

import 'package:care_connect_app/features/gamification/presentation/pages/leaderboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/fake_http_overrides.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => HttpOverrides.global = null);

  /// Pumps the screen and lets the real HTTP future complete.
  Future<void> openWith(WidgetTester tester, FakeResponder responder) async {
    HttpOverrides.global = FakeHttpOverrides(responder);
    await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }

  testWidgets('requests the leaderboard endpoint and lists users with medals',
      (tester) async {
    String? requested;
    await openWith(tester, (m, u) {
      requested = '$m ${u.path}';
      return FakeResponse(200, '''[
        {"name":"Ada Test","xp":900,"level":9},
        {"name":"Ben Test","xp":700,"level":7},
        {"name":"Cy Test","xp":500,"level":5},
        {"name":"Di Test","xp":300,"level":3}
      ]''');
    });

    expect(requested, 'GET /v1/api/users/leaderboard');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Ada Test'), findsOneWidget);
    expect(find.text('XP: 900  |  Level: 9'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
    expect(find.text('🥈'), findsOneWidget);
    expect(find.text('🥉'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
  });

  testWidgets(
      'shows Anonymous and a person icon when name and image are absent',
      (tester) async {
    await openWith(
        tester,
        (m, u) =>
            FakeResponse(200, '[{"xp":10,"level":1,"profileImageUrl":""}]'));

    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('uses the profile image instead of the person icon',
      (tester) async {
    await openWith(
        tester,
        (m, u) => FakeResponse(200,
            '[{"name":"Pic User","xp":1,"level":1,"profileImageUrl":"http://img.test/a.png"}]'));
    // The fake returns no valid image bytes, so the image load reports an error.
    tester.takeException();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<NetworkImage>());
    expect(find.byIcon(Icons.person), findsNothing);
  });

  testWidgets('shows the empty message when the list is empty', (tester) async {
    await openWith(tester, (m, u) => FakeResponse(200, '[]'));

    expect(find.text('No leaderboard data available.'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('does not render any user rows when the server answers 500',
      (tester) async {
    var requests = 0;
    await openWith(tester, (m, u) {
      requests++;
      return FakeResponse(500, '{"error":"boom"}');
    });

    expect(requests, 1);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not render user rows when the request itself fails',
      (tester) async {
    await openWith(tester, (m, u) => throw const SocketException('offline'));

    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
