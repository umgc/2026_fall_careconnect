// Page-title tests for GamificationScreen (lib/features/gamification/presentation/pages/gamification_screen.dart).
// Setup copied from gamification_screen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

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
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';
import '../../../../helpers/titled_route_probe.dart';

Widget _wrap({
  MockUserProvider? provider,
  Locale locale = const Locale('en'),
}) {
  final p =
      provider ?? MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT'));
  return ChangeNotifierProvider<UserProvider>.value(
    value: p,
    child: MaterialApp(navigatorObservers: [probe], 
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GamificationScreen(),
    ),
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

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  Future<String?> titleAfterTapping(WidgetTester tester, Finder target) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    String? title;
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      for (var i = 0; i < 5; i++) {
        await tester.idle();
        await tester.pump(const Duration(milliseconds: 100));
      }
      title = await probe.tapAndReadTitle(tester, target);
    }, () => _createMockClient());
    return title;
  }

  testWidgets('the trophy action opens a page titled "Achievement Details"',
      (tester) async {
    expect(await titleAfterTapping(tester, find.byIcon(Icons.emoji_events)),
        'Achievement Details');
  });

  testWidgets('an unlocked achievement opens "Achievement Details"',
      (tester) async {
    expect(await titleAfterTapping(tester, find.text('First Steps').first),
        'Achievement Details');
  });

  testWidgets('the leaderboard button opens a page titled "Leaderboard"',
      (tester) async {
    expect(
        await titleAfterTapping(
            tester, find.byIcon(Icons.leaderboard, skipOffstage: false)),
        'Leaderboard');
  });
}
