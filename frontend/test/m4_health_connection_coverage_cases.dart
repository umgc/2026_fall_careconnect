// M4 health connection behavior tests. No real authorization or device calls.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart'
    as add;
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart'
    as wear;

// The screen only reads point.type while logging the fetched summary.
class _Point extends Fake implements HealthDataPoint {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #type) return HealthDataType.STEPS;
    return super.noSuchMethod(invocation);
  }
}

class _Health extends Fake implements Health {
  bool authorize = true;
  bool permissions = true;
  bool failFetch = false;
  int authorizationCalls = 0;
  int fetchCalls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #configure) return Future<void>.value();
    if (invocation.memberName == #requestAuthorization) {
      authorizationCalls++;
      return Future<bool>.value(authorize);
    }
    if (invocation.memberName == #hasPermissions)
      return Future<bool?>.value(permissions);
    if (invocation.memberName == #getHealthDataFromTypes) {
      fetchCalls++;
      if (failFetch)
        return Future<List<HealthDataPoint>>.error(
            StateError('QA fetch failed'));
      return Future<List<HealthDataPoint>>.value([_Point()]);
    }
    return super.noSuchMethod(invocation);
  }
}

bool _failWrite = false;
bool _failDelete = false;
final _storageWrites = <String>[];
Widget _app(Widget home, String language) {
  final provider = UserProvider();
  provider.setUser(UserSession(
      id: 1, email: 'qa@example.com', role: 'PATIENT', token: 'test-token'));
  return ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home));
}

Future<void> _open(WidgetTester tester, Widget page, String language) async {
  await tester.binding.setSurfaceSize(const Size(1100, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(page, language));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label).first;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void registerM4HealthCoverage(String screen) {
  group('M4 native boundary and persistence: $screen', () {
    setUp(() {
      _failWrite = false;
      _failDelete = false;
      _storageWrites.clear();
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
        final data = <String, String>{
          'jwt_token': 'test-token',
          'token_expiry':
              '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}',
          'user_session': jsonEncode({
            'id': 1,
            'patientId': 1,
            'role': 'PATIENT',
            'email': 'qa@example.com'
          })
        };
        if (call.method == 'readAll') return data;
        if (call.method == 'read') return data[call.arguments['key']];
        if (call.method == 'containsKey')
          return data.containsKey(call.arguments['key']);
        if (call.method == 'write') {
          _storageWrites.add(call.arguments['key'] as String);
          if (_failWrite) throw PlatformException(code: 'qa-write-failed');
        }
        if (call.method == 'delete' && _failDelete) {
          throw PlatformException(code: 'qa-delete-failed');
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => call.method == 'check' ? ['wifi'] : null);
    });
    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });

    if (screen == 'add') {
      for (final language in ['en', 'es']) {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          for (final scenario in [
            'success',
            'denied',
            'partial',
            'fetch-fails',
            'write-fails'
          ]) {
            if (scenario == 'partial' && platform != TargetPlatform.iOS)
              continue;
            if (scenario == 'fetch-fails' && platform != TargetPlatform.android)
              continue;
            testWidgets(
                '$language $platform $scenario authorization and persistence',
                (tester) async {
              final health = _Health();
              health.authorize = scenario != 'denied';
              health.permissions = scenario != 'partial';
              health.failFetch = scenario == 'fetch-fails';
              await _open(
                  tester,
                  add.AddDeviceScreen(
                      healthClient: health, platformOverride: platform),
                  language);
              _failWrite = scenario == 'write-fails';
              final t = AppLocalizations.of(
                  tester.element(find.byType(add.AddDeviceScreen)))!;
              final label = platform == TargetPlatform.iOS
                  ? 'Apple Health'
                  : 'Health Connect';
              await _tap(tester, label);
              // Flush mocked plugin, secure storage and preference futures.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 200));
              final dynamic state =
                  tester.state(find.byType(add.AddDeviceScreen));
              expect(health.authorizationCalls, 1);
              expect(state.isConnecting, isFalse);
              if (scenario == 'denied') {
                expect(state.isConnected, isFalse);
                expect(state.errorMessage, isNotNull);
                expect(find.text(t.addDevicesConnectionFailed), findsOneWidget);
                expect(
                    _storageWrites
                        .where((key) => key.endsWith('_access_token')),
                    isEmpty);
              } else {
                expect(state.isConnected, isTrue);
                expect(
                    find.text(t.addDevicesConnectedTo(label)), findsOneWidget);
                final prefs = await SharedPreferences.getInstance();
                final devices =
                    jsonDecode(prefs.getString('connected_devices')!) as List;
                final key = platform == TargetPlatform.iOS
                    ? 'apple_health'
                    : 'google_fit';
                expect((devices.single as Map)['platform'], key);
                expect((devices.single as Map)['permissions'],
                    contains('heart_rate'));
                expect(_storageWrites, contains('${key}_access_token'));
                if (platform == TargetPlatform.android)
                  expect(health.fetchCalls, 1);
                // Return to selection, rebuild loaded device badges and check that
                // the connected platform is identified rather than reauthorized.
                state.setState(() {
                  state.currentStep = 0;
                  state.selectedPlatform = null;
                });
                await tester.pump();
                expect(find.text(t.addDevicesConnected), findsOneWidget);
                await _tap(tester, label);
                expect(health.authorizationCalls, 1);
              }
              await _close(tester);
            });
          }
        }
        testWidgets(
            '$language: corrupt stored device JSON leaves selection usable',
            (tester) async {
          SharedPreferences.setMockInitialValues(
              {'connected_devices': 'invalid JSON'});
          await _open(
              tester,
              add.AddDeviceScreen(
                  healthClient: _Health(),
                  platformOverride: TargetPlatform.android),
              language);
          expect(find.text('Health Connect'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _close(tester);
        });
      }
    }

    if (screen == 'wear') {
      for (final language in ['en', 'es']) {
        testWidgets('$language: backend sync failure is localized',
            (tester) async {
          await http.runWithClient(() async {
            await _open(tester, const wear.WearablesScreen(), language);
            final t = AppLocalizations.of(
                tester.element(find.byType(wear.WearablesScreen)))!;
            final dynamic state =
                tester.state(find.byType(wear.WearablesScreen));
            state.setState(() {
              state.connectedDevices = <wear.ConnectedDevice>[
                wear.ConnectedDevice(
                    id: 'qa',
                    platform: 'unknown',
                    name: 'QA Band',
                    connectedAt: DateTime.now(),
                    permissions: [])
              ];
            });
            await tester.pump();
            final refresh =
                tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
            await tester.runAsync(() => refresh.onRefresh());
            await tester.pump();
            expect(state.hasSyncError, isTrue);
            expect(find.text(t.wearablesSynchronizationFailed), findsOneWidget);
            expect(state.syncStatusMessage, contains('503'));
            expect(
                find.text(state.syncStatusMessage as String), findsOneWidget);
            await _close(tester);
          },
              () => MockClient((request) async => http.Response(
                  '{}',
                  request.url.toString().contains('validate-token')
                      ? 200
                      : 503)));
        });
        testWidgets(
            '$language: secure-token removal failure shows localized error',
            (tester) async {
          await _open(tester, const wear.WearablesScreen(), language);
          final t = AppLocalizations.of(
              tester.element(find.byType(wear.WearablesScreen)))!;
          final dynamic state = tester.state(find.byType(wear.WearablesScreen));
          state.setState(() {
            state.connectedDevices = <wear.ConnectedDevice>[
              wear.ConnectedDevice(
                  id: 'qa',
                  platform: 'unknown',
                  name: 'QA Band',
                  connectedAt: DateTime.now(),
                  permissions: [])
            ];
          });
          await tester.pump();
          _failDelete = true;
          final delete = find.byIcon(Icons.delete_outline);
          await tester.ensureVisible(delete);
          await tester.tap(delete);
          await tester.pumpAndSettle();
          await _tap(tester, t.wearablesRemove);
          expect(find.text(t.wearablesFailedToRemoveDevice), findsOneWidget);
          await _close(tester);
        });
      }
    }
  });
}
