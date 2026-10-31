// Page-title tests for MainFeedScreen
// (lib/features/social/presentation/pages/main_feed_screen.dart): the header
// actions and a post's comments each open a titled page (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/features/social/presentation/pages/main_feed_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';

Widget _wrap(TitledRouteProbe probe, {int userId = 0}) => MaterialApp(
      navigatorObservers: [probe],
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MainFeedScreen(userId: userId),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
  });

  // userId 0 shows an empty feed without loading it.
  for (final (tooltip, title) in [
    ('Add Friend', 'Search User'),
    ('Friend Requests', 'Friend Requests'),
    ('Messages', 'Chat Inbox'),
    ('Create Post', 'New Post'),
  ]) {
    testWidgets('$tooltip opens a page titled "$title"', (tester) async {
      final probe = TitledRouteProbe();
      await tester.pumpWidget(_wrap(probe));
      await tester.pump();
      expect(await probe.tapAndReadTitle(tester, find.byTooltip(tooltip)),
          title);
    });
  }

  group('a post', () {
    Future<String?> titleAfterTapping(WidgetTester tester, Finder target) {
      final probe = TitledRouteProbe();
      return http.runWithClient(() async {
        await tester.pumpWidget(_wrap(probe, userId: 7));
        for (var i = 0; i < 5; i++) {
          await tester.idle();
          await tester.pump();
        }
        final title = await probe.tapAndReadTitle(tester, target);
        // Dispose the screen so its feed polling timer stops.
        await tester.pumpWidget(const SizedBox());
        return title;
      },
          () => MockClient((_) async => http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'userId': 8,
                  'content': 'Walked to the park today',
                  'createdAt': '2026-10-26T09:00:00',
                  'commentCount': 2,
                  'username': 'mary',
                },
              ]),
              200)));
    }

    testWidgets('opens a page titled "Post Comments" when tapped',
        (tester) async {
      expect(
          await titleAfterTapping(
              tester, find.text('Walked to the park today')),
          'Post Comments');
    });

    testWidgets('comments button opens a page titled "Post Comments"',
        (tester) async {
      expect(await titleAfterTapping(tester, find.byIcon(Icons.comment)),
          'Post Comments');
    });
  });
}
