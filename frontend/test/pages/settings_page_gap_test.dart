// Gap tests for SettingsPage: the notification toggles (each one posts the
// flipped flag), the save-failure snackbar, and the "unable to load" retry
// card. HTTP goes through http.runWithClient and ApiService.debugSetHttpClient
// with a MockClient, so nothing touches the network.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

class _Backend {
  int getStatus = 200;
  int postStatus = 200;
  Map<String, dynamic> stored = {
    'id': 3,
    'userId': 1,
    'gamification': true,
    'emergency': true,
    'videoCall': true,
    'audioCall': true,
    'sms': true,
    'significantVitals': true,
  };
  final posts = <Map<String, dynamic>>[];
  int notificationGets = 0;

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/notification-settings')) {
          if (req.method == 'POST') {
            posts.add(jsonDecode(req.body) as Map<String, dynamic>);
            if (postStatus != 200) {
              return http.Response('{}', postStatus);
            }
            stored = {...stored, ...posts.last};
            return http.Response(jsonEncode(stored), 200);
          }
          notificationGets++;
          return getStatus == 200
              ? http.Response(jsonEncode(stored), 200)
              : http.Response('{}', getStatus);
        }
        // Everything else (connected-service tiles, telemetry) gets an
        // unauthenticated-style empty answer; the page tolerates it.
        return http.Response('{}', 404);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Backend backend;
  late AppLocalizations t;

  setUp(() async {
    backend = _Backend();
    t = await AppLocalizations.delegate.load(const Locale('en'));
    SharedPreferences.setMockInitialValues({
      'telemetry_opted_out': false,
      'telemetry_seen_optout_dialog': true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugSetHttpClient(backend.client());
    // UserProvider checks connectivity on construction.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    // Its change stream is an EventChannel; accept listen/cancel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            null);
  });

  Future<void> open(WidgetTester tester, Future<void> Function() body) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: MockUserProvider()),
          ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider()),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await body();
    }, () => backend.client());
  }

  Finder switchIn(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
        matching: find.byType(Switch),
      );

  Future<void> flip(WidgetTester tester, String title) async {
    final sw = switchIn(title);
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('each notification switch posts only its own flipped flag',
      (tester) async {
    await open(tester, () async {
      final cases = <String, String>{
        t.settingsNotifEmergency: 'emergency',
        t.settingsNotifVideoCall: 'videoCall',
        t.settingsNotifAudioCall: 'audioCall',
        t.settingsNotifSignificantVitals: 'significantVitals',
        t.settingsNotifSMS: 'sms',
        t.settingsNotifGamification: 'gamification',
      };
      for (final entry in cases.entries) {
        expect(tester.widget<Switch>(switchIn(entry.key)).value, isTrue,
            reason: '${entry.key} starts on');
      }

      for (final entry in cases.entries) {
        backend.posts.clear();
        await flip(tester, entry.key);

        expect(backend.posts, hasLength(1), reason: entry.key);
        final body = backend.posts.single;
        expect(body[entry.value], isFalse, reason: entry.key);
        // Every other flag is unchanged from the stored (earlier) state.
        for (final other in cases.values.where((v) => v != entry.value)) {
          expect(body.containsKey(other), isTrue);
        }
        expect(tester.widget<Switch>(switchIn(entry.key)).value, isFalse,
            reason: '${entry.key} reflects the saved value');
      }
      expect(find.textContaining(t.settingsSnackUpdated), findsOneWidget);
    });
  });

  testWidgets('a rejected save shows the failure snackbar and keeps the value',
      (tester) async {
    backend.postStatus = 500;
    await open(tester, () async {
      await flip(tester, t.settingsNotifEmergency);

      expect(backend.posts, hasLength(1));
      expect(find.text('❌ ${t.settingsSnackUpdateFailed}'), findsOneWidget);
      expect(find.textContaining(t.settingsSnackUpdated), findsNothing);
      expect(tester.widget<Switch>(switchIn(t.settingsNotifEmergency)).value,
          isTrue);
    });
  });

  testWidgets('unable-to-load card offers a refresh that reloads the settings',
      (tester) async {
    backend.getStatus = 500;
    await open(tester, () async {
      expect(find.text(t.settingsUnableToLoadNotificationSettings),
          findsOneWidget);
      expect(switchIn(t.settingsNotifEmergency), findsNothing);
      final before = backend.notificationGets;

      backend.getStatus = 200;
      final refresh = find.descendant(
        of: find.ancestor(
            of: find.text(t.settingsUnableToLoadNotificationSettings),
            matching: find.byType(Card)),
        matching: find.byIcon(Icons.refresh),
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(backend.notificationGets, before + 1);
      expect(
          find.text(t.settingsUnableToLoadNotificationSettings), findsNothing);
      expect(switchIn(t.settingsNotifEmergency), findsOneWidget);
    });
  });
}
