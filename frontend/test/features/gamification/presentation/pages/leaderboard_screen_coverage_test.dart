// Coverage tests for LeaderboardScreen
// (lib/features/gamification/presentation/pages/leaderboard_screen.dart):
// a loaded leaderboard (medals, names, XP/level), an empty leaderboard and a
// non-200 response that keeps the spinner.

import 'dart:convert';

import 'package:care_connect_app/features/gamification/presentation/pages/leaderboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<void> _pump(WidgetTester tester, int status, Object body) async {
  final client =
      MockClient((_) async => http.Response(jsonEncode(body), status));
  await http.runWithClient(() async {
    await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }, () => client);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('renders ranked users with medals', (tester) async {
    await _pump(tester, 200, [
      {'name': 'Alice', 'xp': 500, 'level': 5, 'profileImageUrl': ''},
      {'name': 'Bob', 'xp': 400, 'level': 4},
      {'name': 'Cara', 'xp': 300, 'level': 3},
      {'xp': 10, 'level': 1},
    ]);

    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.text('XP: 500  |  Level: 5'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
    expect(find.text('🥈'), findsOneWidget);
    expect(find.text('🥉'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNWidgets(4));
  });

  testWidgets('empty leaderboard shows the placeholder', (tester) async {
    await _pump(tester, 200, []);
    expect(find.text('No leaderboard data available.'), findsOneWidget);
  });

  testWidgets('a failed request keeps loading', (tester) async {
    await _pump(tester, 500, {'error': 'x'});
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
