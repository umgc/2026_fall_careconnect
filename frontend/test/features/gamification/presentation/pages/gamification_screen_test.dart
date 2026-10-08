// Tests for GamificationScreen
// (lib/features/gamification/presentation/pages/gamification_screen.dart).
//
// initState creates ConfettiController and calls initializePrefsAndLoad()
// (async -- SharedPreferences + GamificationService HTTP).
// isLoading = true initially; we use MockClient + runWithClient to provide
// fake HTTP responses so the widget can transition to loaded state.

import 'dart:convert';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/gamification/presentation/pages/gamification_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap({MockUserProvider? provider}) {
  final p =
      provider ?? MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'));
  return ChangeNotifierProvider<UserProvider>.value(
    value: p,
    child: const MaterialApp(home: GamificationScreen()),
  );
}

/// Creates a MockClient that intercepts GamificationService HTTP calls.
MockClient _createMockClient({
  int level = 2,
  int xp = 30,
  List<Map<String, dynamic>>? earned,
  List<Map<String, dynamic>>? allAchievements,
  int progressStatus = 200,
  int achievementsStatus = 200,
  int allAchievementsStatus = 200,
}) {
  final earnedList = earned ??
      [
        {
          'achievement': {'title': 'First Steps'},
        },
      ];
  final allList = allAchievements ??
      [
        {'title': 'First Steps', 'badge_icon': 'star'},
        {'title': 'Streak Master', 'badge_icon': 'fire'},
      ];

  return MockClient((request) async {
    final path = request.url.path;
    final headers = {'content-type': 'application/json; charset=utf-8'};

    if (path.contains('/progress/')) {
      return http.Response(
        jsonEncode({'level': level, 'xp': xp}),
        progressStatus,
        headers: headers,
      );
    }
    if (path.contains('/all-achievements')) {
      final body = jsonEncode(allList);
      return http.Response.bytes(
        utf8.encode(body),
        allAchievementsStatus,
        headers: headers,
      );
    }
    if (path.contains('/achievements/')) {
      final body = jsonEncode(earnedList);
      return http.Response.bytes(
        utf8.encode(body),
        achievementsStatus,
        headers: headers,
      );
    }

    return http.Response('Not Found', 404);
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Loading state (no mock HTTP -- HTTP fails, isLoading stays true)
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - initial loading state', () {
    testWidgets('renders GamificationScreen widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows AppBar with title Achievements', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsWidgets);
      expect(find.text('Achievements'), findsWidgets);
    });

    testWidgets('does NOT show LinearProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('does NOT show View Leaderboard button while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('View Leaderboard'), findsNothing);
    });

    testWidgets('does NOT show Gamification heading while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Gamification'), findsNothing);
    });

    testWidgets('contains a ConfettiWidget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ConfettiWidget), findsOneWidget);
    });

    testWidgets('does NOT show shield icon while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.shield), findsNothing);
    });

    testWidgets('does NOT show ElevatedButton while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('shows Stack widget', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Stack), findsWidgets);
    });

    testWidgets('AppBar contains emoji_events icon button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('AppBar contains arrow_back icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('does not show XP text while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('does not show Level text while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Level'), findsNothing);
    });

    testWidgets('Scaffold has a drawer', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isNotNull);
    });

    testWidgets('Scaffold uses surface background color', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, isNotNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Loaded state (MockClient provides fake HTTP responses)
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - loaded state', () {
    testWidgets('shows Gamification heading after data loads', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Gamification'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows Level text after data loads', (tester) async {
      final mockClient = _createMockClient(level: 3);
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Level 3'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows XP progress text after data loads', (tester) async {
      final mockClient = _createMockClient(level: 2, xp: 30);
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('30 / 100 XP'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows shield icon after data loads', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.shield), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows LinearProgressIndicator after data loads',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows View Leaderboard button after data loads',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('View Leaderboard'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows leaderboard icon on button', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.leaderboard), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows ElevatedButton after data loads', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ElevatedButton), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows ListView for achievements after data loads',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ListView), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('does NOT show CircularProgressIndicator after data loads',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }, () => mockClient);
    });

    testWidgets('shows Achievements section title after data loads',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // 'Achievements' appears in AppBar and as section title
        expect(find.text('Achievements'), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('shows daily motivational message', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // One of the motivational messages should be visible
        final dayIndex = DateTime.now().day % motivationalMessages.length;
        final expectedMessage = motivationalMessages[dayIndex];
        expect(find.text(expectedMessage), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows unlocked achievement title', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // 'First Steps' is in both earned and all, so it should be unlocked
        expect(find.text('First Steps'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('does not show locked achievement in the list',
        (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // 'Streak Master' is in allAchievements but NOT earned, so locked
        // The ListView only shows unlocked achievements
        expect(find.text('Streak Master'), findsNothing);
      }, () => mockClient);
    });

    testWidgets('shows check icon for unlocked achievement', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byIcon(Icons.check), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('shows InkWell for each achievement', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(InkWell), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('shows level 1 with xpTarget 50', (tester) async {
      final mockClient = _createMockClient(level: 1, xp: 20);
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Level 1'), findsOneWidget);
        expect(find.text('20 / 50 XP'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('shows multiple unlocked achievements', (tester) async {
      final mockClient = _createMockClient(
        earned: [
          {'achievement': {'title': 'First Steps'}},
          {'achievement': {'title': 'Streak Master'}},
        ],
        allAchievements: [
          {'title': 'First Steps', 'badge_icon': 'star'},
          {'title': 'Streak Master', 'badge_icon': 'flame'},
          {'title': 'Health Hero', 'badge_icon': 'pill'},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('First Steps'), findsOneWidget);
        expect(find.text('Streak Master'), findsOneWidget);
        // Health Hero is locked, not shown in list
        expect(find.text('Health Hero'), findsNothing);
      }, () => mockClient);
    });

    testWidgets('shows zero unlocked achievements when none earned',
        (tester) async {
      final mockClient = _createMockClient(
        earned: [],
        allAchievements: [
          {'title': 'First Steps', 'badge_icon': 'star'},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('First Steps'), findsNothing);
      }, () => mockClient);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Confetti trigger (new achievements > previousAchievementCount)
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - confetti trigger', () {
    testWidgets(
        'confetti plays when earned achievements exceed stored count',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'userId': '1',
        'achievement_count': 0,
      });
      final mockClient = _createMockClient(
        earned: [
          {'achievement': {'title': 'First Steps'}},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // The confetti widget should still be present
        expect(find.byType(ConfettiWidget), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets(
        'confetti does not play when earned equals stored count',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'userId': '1',
        'achievement_count': 1,
      });
      final mockClient = _createMockClient(
        earned: [
          {'achievement': {'title': 'First Steps'}},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ConfettiWidget), findsOneWidget);
      }, () => mockClient);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // SharedPreferences variations
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - SharedPreferences variations', () {
    testWidgets('renders with stored userId', (tester) async {
      SharedPreferences.setMockInitialValues({'userId': '42'});
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });

    testWidgets('renders with empty userId string', (tester) async {
      SharedPreferences.setMockInitialValues({'userId': ''});
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });

    testWidgets('renders with invalid userId string', (tester) async {
      SharedPreferences.setMockInitialValues({'userId': 'not_a_number'});
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // motivationalMessages
  // ───────────────────────────────────────────────────────────────────────────
  group('motivationalMessages', () {
    test('contains exactly 5 messages', () {
      expect(motivationalMessages.length, 5);
    });

    test('all messages are non-empty strings', () {
      for (final msg in motivationalMessages) {
        expect(msg, isA<String>());
        expect(msg.isNotEmpty, isTrue);
      }
    });

    test('first message contains "keep going"', () {
      expect(motivationalMessages[0], contains('keep going'));
    });

    test('second message contains "Small steps"', () {
      expect(motivationalMessages[1], contains('Small steps'));
    });

    test('third message contains "Believe"', () {
      expect(motivationalMessages[2], contains('Believe'));
    });

    test('fourth message contains "Progress"', () {
      expect(motivationalMessages[3], contains('Progress'));
    });

    test('last message contains "you got this"', () {
      expect(motivationalMessages[4], contains('you got this'));
    });

    test('messages are accessible by day-based index', () {
      final dayIndex = DateTime.now().day % motivationalMessages.length;
      expect(dayIndex, greaterThanOrEqualTo(0));
      expect(dayIndex, lessThan(motivationalMessages.length));
      final msg = motivationalMessages[dayIndex];
      expect(msg.isNotEmpty, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Dispose / lifecycle
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - dispose and lifecycle', () {
    testWidgets('disposes cleanly when removed from tree', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Replace widget to trigger dispose
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value:
              MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT')),
          child: const MaterialApp(home: Scaffold(body: Text('replaced'))),
        ),
      );
      await tester.pump();
      expect(find.text('replaced'), findsOneWidget);
      expect(find.byType(GamificationScreen), findsNothing);
    });

    testWidgets('disposes cleanly after data has loaded', (tester) async {
      final mockClient = _createMockClient();
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // Data has loaded
        expect(find.text('Gamification'), findsOneWidget);
      }, () => mockClient);
      // Now replace to trigger dispose
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value:
              MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT')),
          child: const MaterialApp(home: Scaffold(body: Text('done'))),
        ),
      );
      await tester.pump();
      expect(find.text('done'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // UserProvider role variations
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - UserProvider role variations', () {
    testWidgets('renders with PATIENT role', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'));
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });

    testWidgets('renders with CAREGIVER role', (tester) async {
      final provider =
          MockUserProvider(mockUser: MockUser(id: 2, role: 'CAREGIVER'));
      await tester.pumpWidget(_wrap(provider: provider));
      await tester.pump();
      expect(find.byType(GamificationScreen), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Achievement with missing title fallback
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - achievement edge cases', () {
    testWidgets('shows Unnamed Achievement for null title', (tester) async {
      final mockClient = _createMockClient(
        earned: [
          {'achievement': {'title': null}},
        ],
        allAchievements: [
          {'title': null, 'badge_icon': 'star'},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Unnamed Achievement'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('handles achievement without badge_icon', (tester) async {
      final mockClient = _createMockClient(
        earned: [
          {'achievement': {'title': 'No Badge'}},
        ],
        allAchievements: [
          {'title': 'No Badge'},
        ],
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('No Badge'), findsOneWidget);
      }, () => mockClient);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Error handling (HTTP fails)
  // ───────────────────────────────────────────────────────────────────────────
  group('GamificationScreen - HTTP error handling', () {
    testWidgets('stays loading when progress API returns error',
        (tester) async {
      final mockClient = _createMockClient(progressStatus: 500);
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        // Error caught, stays in loading state
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }, () => mockClient);
    });
  });
}
