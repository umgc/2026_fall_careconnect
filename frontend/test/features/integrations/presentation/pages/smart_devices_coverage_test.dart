// Additional coverage for SmartDevicesPage
// (lib/features/integrations/presentation/pages/smart_devices.dart):
// profile-parse exception path, unlink exception path, Privacy Policy link
// and the "Open Alexa Store" dialog action (url_launcher mocked).

import 'dart:convert';

import 'package:care_connect_app/features/integrations/presentation/pages/smart_devices.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, String> _secure = {};

const _urlChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_ios',
  'plugins.flutter.io/url_launcher_windows',
  'plugins.flutter.io/url_launcher_linux',
  'plugins.flutter.io/url_launcher_macos',
];

void _setupPatientSession() {
  _secure = {
    'jwt_token': 'mock.jwt.token',
    'user_session': jsonEncode({
      'role': 'PATIENT',
      'patientId': 1,
      'id': 1,
      'email': 'test@example.com',
    }),
    'token_expiry':
        ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600).toString(),
  };
}

/// Installs url_launcher mocks; returns list of launched URLs.
List<String> _mockUrlLauncher({required bool canLaunch}) {
  final launched = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _urlChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') return canLaunch;
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'].toString());
        return true;
      }
      return null;
    });
  }
  return launched;
}

MockClient _client({
  Object alexaLinked = false,
  http.Response Function()? unlink,
}) {
  return MockClient((request) async {
    final url = request.url.toString();
    if (url.contains('validate-token')) return http.Response('{}', 200);
    if (url.contains('alexa/unlink')) {
      return unlink != null ? unlink() : http.Response('{}', 200);
    }
    if (url.contains('/v1/api/patients/')) {
      return http.Response(
        jsonEncode({
          'id': 1,
          'alexaLinked': alexaLinked,
          'user': {'id': 1, 'role': 'PATIENT', 'email': 'test@example.com'},
        }),
        200,
      );
    }
    if (url.contains('picture')) return http.Response('', 404);
    return http.Response('{}', 200);
  });
}

Widget _wrap() {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'test@example.com',
    role: 'PATIENT',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SmartDevicesPage(),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupPatientSession();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'readAll':
            return <String, String>{..._secure};
          case 'read':
            return _secure[args['key']];
          case 'containsKey':
            return _secure.containsKey(args['key']);
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _urlChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  testWidgets('non-boolean alexaLinked triggers the generic error state',
      (tester) async {
    _tall(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);
      expect(find.textContaining('An error occurred'), findsOneWidget);
    }, () => _client(alexaLinked: 'yes'));
  });

  testWidgets('unlink with non-string error message falls into catch',
      (tester) async {
    _tall(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('Disable Alexa Skill'));
      await _settle(tester);

      expect(find.textContaining('Error unlinking Alexa'), findsOneWidget);
      // Still linked because the unlink did not succeed.
      expect(find.text('Disable Alexa Skill'), findsOneWidget);
    },
        () => _client(
              alexaLinked: true,
              unlink: () => http.Response(jsonEncode({'error': 123}), 500),
            ));
  });

  testWidgets('Privacy Policy opens the external URL when launchable',
      (tester) async {
    _tall(tester);
    final launched = _mockUrlLauncher(canLaunch: true);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('Privacy Policy'));
      await _settle(tester);
    }, () => _client());
    expect(launched.single, contains('freeprivacypolicy.com'));
    expect(find.text('Could not open Privacy Policy'), findsNothing);
  });

  testWidgets('Privacy Policy shows snackbar when URL cannot be opened',
      (tester) async {
    _tall(tester);
    final launched = _mockUrlLauncher(canLaunch: false);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('Privacy Policy'));
      await _settle(tester);
      expect(find.text('Could not open Privacy Policy'), findsOneWidget);
    }, () => _client());
    expect(launched, isEmpty);
  });

  testWidgets('Open Alexa Store launches URL, closes dialog, shows snackbar',
      (tester) async {
    _tall(tester);
    final launched = _mockUrlLauncher(canLaunch: true);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('Enable Alexa Skill'));
      await _settle(tester);
      expect(find.text('Enable Alexa Skill'), findsWidgets);

      await tester.tap(find.text('Open Alexa Store'));
      await _settle(tester);

      expect(find.text('Open Alexa Store'), findsNothing);
      expect(find.text('Opening Alexa Skill store...'), findsOneWidget);
    }, () => _client());
    expect(launched.single, contains('amazon.com'));
  });

  testWidgets('Open Alexa Store shows error when store URL cannot open',
      (tester) async {
    _tall(tester);
    _mockUrlLauncher(canLaunch: false);
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      await _settle(tester);

      await tester.tap(find.text('Enable Alexa Skill'));
      await _settle(tester);
      await tester.tap(find.text('Open Alexa Store'));
      await _settle(tester);

      expect(find.text('Could not open the store URL'), findsOneWidget);
      // Dialog stays open on failure.
      expect(find.text('Open Alexa Store'), findsOneWidget);
    }, () => _client());
  });
}
