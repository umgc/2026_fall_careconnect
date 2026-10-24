// Validates who sees AI condition screening on the post-call screen: caregivers, family members
// and admins get the card; patients never do, and their device never even requests the flags.
// HTTP is replaced with a MockClient that records requested paths, and secure storage is stubbed
// because ApiService reads auth headers from it.
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../../mock_user_provider.dart';

const _secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Every request path the screen made, so tests can assert the flags were never fetched.
final List<String> _requestedPaths = [];

void _stubBackend() {
  _requestedPaths.clear();
  ApiService.debugSetHttpClient(MockClient((request) async {
    final path = request.url.path;
    _requestedPaths.add(path);
    if (path.endsWith('/telemetry') || path.endsWith('/transcript/segments')) {
      return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
    }
    if (path.endsWith('/condition-flags')) {
      return http.Response(
        jsonEncode({
          'disclaimer': 'd',
          'runs': [
            {
              'modelId': 'kintsugi-dam-3.1',
              'displayName': 'Voice',
              'inputKind': 'PATIENT_AUDIO',
              'status': 'PROCESSING',
              'flags': <Map<String, dynamic>>[],
            },
          ],
        }),
        200,
      );
    }
    return http.Response('', 404);
  }));
}

Future<void> _pumpScreen(WidgetTester tester, {UserProvider? provider}) async {
  const screen = PostCallTelemetrySummaryScreen(callId: 'call-1');
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  );
  await tester.pumpWidget(
    provider == null ? app : ChangeNotifierProvider<UserProvider>.value(value: provider, child: app),
  );
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

MockUserProvider _as(String role) => MockUserProvider(mockUser: MockUser(role: role));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'containsKey':
          return false;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  setUp(_stubBackend);
  tearDown(ApiService.debugResetHttpClient);

  /// Every non-patient role sees the card, fetched from the condition-flags endpoint.
  for (final role in ['CAREGIVER', 'FAMILY_MEMBER', 'ADMIN']) {
    testWidgets('$role sees the condition screening card', (tester) async {
      await _pumpScreen(tester, provider: _as(role));

      expect(find.byKey(const Key('conditionFlagsCard')), findsOneWidget);
      expect(_requestedPaths.where((p) => p.endsWith('/call-1/condition-flags')), hasLength(1));
    });
  }

  /// A patient viewing their own call summary never sees, or requests, screening flags.
  testWidgets('PATIENT never sees or requests the card', (tester) async {
    await _pumpScreen(tester, provider: _as('PATIENT'));

    expect(find.byKey(const Key('conditionFlagsCard')), findsNothing);
    expect(_requestedPaths.where((p) => p.endsWith('/condition-flags')), isEmpty);
  });

  /// Role comparison is case-insensitive, so a lower-case role cannot slip past the gate.
  testWidgets('lower-case patient role is still hidden', (tester) async {
    await _pumpScreen(tester, provider: _as('patient'));

    expect(find.byKey(const Key('conditionFlagsCard')), findsNothing);
  });

  /// With no signed-in user available the screen fails closed.
  testWidgets('no user provider hides the card', (tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const Key('conditionFlagsCard')), findsNothing);
    expect(_requestedPaths.where((p) => p.endsWith('/condition-flags')), isEmpty);
  });
}
