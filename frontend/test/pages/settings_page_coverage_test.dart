// Coverage tests for SettingsPage (lib/pages/settings_page.dart): each
// notification toggle saving through NotificationSettingsService (success
// and failure), the language picker row with a saved locale, and the
// default-settings fallback when the backend has none yet.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/theme_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

class _Backend {
  _Backend({this.getStatus = 200, this.postStatus = 200});
  final int getStatus;
  final int postStatus;
  final saved = <Map<String, dynamic>>[];

  MockClient client() => MockClient((req) async {
        if (req.url.path.contains('notification-settings')) {
          if (req.method == 'GET') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'userId': 1,
                'gamification': true,
                'emergency': true,
                'videoCall': true,
                'audioCall': true,
                'sms': true,
                'significantVitals': true,
              }),
              getStatus,
            );
          }
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          saved.add(body);
          return http.Response(jsonEncode(body), postStatus);
        }
        return http.Response(jsonEncode({'enabled': true}), 200);
      });
}

Future<void> _pump(WidgetTester tester, {LocaleProvider? locale}) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: MockUserProvider()),
        ChangeNotifierProvider<LocaleProvider>.value(
            value: locale ?? LocaleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _switchFor(String title) => find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byType(Switch),
    );

void main() {
  final t = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'telemetry_opted_out': false,
      'telemetry_seen_optout_dialog': true,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(_connectivity, (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
  });

  testWidgets('every notification toggle is saved', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pump(tester);
      final toggles = <String, String>{
        t.settingsNotifEmergency: 'emergency',
        t.settingsNotifVideoCall: 'videoCall',
        t.settingsNotifAudioCall: 'audioCall',
        t.settingsNotifSignificantVitals: 'significantVitals',
        t.settingsNotifSMS: 'sms',
        t.settingsNotifGamification: 'gamification',
      };
      for (final entry in toggles.entries) {
        final toggle = _switchFor(entry.key);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(backend.saved.last[entry.value], isFalse, reason: entry.value);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        ScaffoldMessenger.of(tester.element(find.byType(SettingsPage)))
            .removeCurrentSnackBar();
        await tester.pump();
      }
      expect(backend.saved, hasLength(6));
      expect(find.textContaining(t.settingsSnackUpdated), findsNothing);
    }, backend.client);
  });

  testWidgets('a toggle reports success with a snackbar', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(_switchFor(t.settingsNotifSMS));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }, backend.client);
    expect(find.text('✅ ${t.settingsSnackUpdated}'), findsOneWidget);
  });

  testWidgets('a failed save keeps the toggle and shows an error',
      (tester) async {
    final backend = _Backend(postStatus: 500);
    await http.runWithClient(() async {
      await _pump(tester);
      final toggle = _switchFor(t.settingsNotifEmergency);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('❌ ${t.settingsSnackUpdateFailed}'), findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isTrue);
    }, backend.client);
  });

  testWidgets('missing settings fall back to the defaults', (tester) async {
    final backend = _Backend(getStatus: 404);
    await http.runWithClient(() async {
      await _pump(tester);
    }, backend.client);
    expect(
        tester.widget<Switch>(_switchFor(t.settingsNotifEmergency)).value,
        isTrue);
  });

  testWidgets('language row shows the saved locale and opens the picker',
      (tester) async {
    final locale = LocaleProvider();
    await locale.setLocale(const Locale('es'));
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pump(tester, locale: locale);
      final row = find.widgetWithText(ListTile, t.language);
      expect(row, findsOneWidget);
      // The subtitle is the saved locale's label, not "System default".
      expect(
        find.descendant(of: row, matching: find.text(t.systemDefault)),
        findsNothing,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    }, backend.client);
  });
}
