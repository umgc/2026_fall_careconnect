// Additional M4 localization regression cases. Registered by mapped test files.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/add_devices_screen.dart'
    as add;
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart'
    as wear;
import 'package:care_connect_app/features/integrations/presentation/pages/smart_devices.dart';

const _urlChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_ios',
  'plugins.flutter.io/url_launcher_linux',
  'plugins.flutter.io/url_launcher_macos',
  'plugins.flutter.io/url_launcher_windows',
];
bool _launchWorks = false;
final _urlCalls = <MethodCall>[];

Widget _app(Widget page, {String language = 'en'}) {
  final provider = UserProvider();
  provider.setUser(UserSession(
      id: 1, email: 'qa@example.com', role: 'PATIENT', token: 'test-token'));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page),
  );
}

Future<void> _open(WidgetTester tester, Widget page,
    {String language = 'en', double width = 1000}) async {
  await tester.binding.setSurfaceSize(Size(width, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(page, language: language));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

AppLocalizations _text(WidgetTester tester, Type page) =>
    AppLocalizations.of(tester.element(find.byType(page)))!;
Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void registerM4Coverage(String screen) {
  group('M4 additional localization coverage: $screen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      _launchWorks = false;
      _urlCalls.clear();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in _urlChannels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          _urlCalls.add(call);
          if (['canLaunch', 'launch', 'launchUrl'].contains(call.method)) {
            return _launchWorks;
          }
          return null;
        });
      }
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
        final session = jsonEncode({
          'role': 'PATIENT',
          'patientId': 1,
          'id': 1,
          'email': 'qa@example.com'
        });
        final data = <String, String>{
          'jwt_token': 'test-token',
          'user_session': session,
          'token_expiry':
              '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}'
        };
        if (call.method == 'readAll') return data;
        if (call.method == 'read') return data[call.arguments['key']];
        if (call.method == 'containsKey')
          return data.containsKey(call.arguments['key']);
        return null;
      });
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => call.method == 'check' ? ['wifi'] : null);
    });
    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in _urlChannels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });

    if (screen == 'alert') {
      FallAlert alert(
              {String id = 'patient-1',
              Duration age = const Duration(minutes: 5)}) =>
          FallAlert(
              id: 'coverage-alert',
              patientId: id,
              patientName: 'QA Patient',
              detectedAtUtc: DateTime.now().toUtc().subtract(age),
              source: 'watch',
              hasLiveVideo: false,
              patientPhone: '5550100',
              emergencyContactName: 'QA Contact',
              emergencyContactPhone: '5550200');
      for (final language in ['en', 'es']) {
        for (final action in [
          'call',
          'sms',
          'emergency',
          'contact',
          'missing-id'
        ]) {
          testWidgets('$language: $action failure shows localized feedback',
              (tester) async {
            await _open(
                tester,
                AlertDetailsPage(
                    alert:
                        alert(id: action == 'missing-id' ? '' : 'patient-1')),
                language: language);
            final t = _text(tester, AlertDetailsPage);
            late String expected;
            if (action == 'call') {
              await _tap(tester, t.fallAlertCallPatient);
              expected = t.fallAlertCallFailedToStart;
            } else if (action == 'sms') {
              await _tap(tester, t.fallAlertSendMessage);
              expected = t.fallAlertMessageFailedToStart;
            } else if (action == 'missing-id') {
              await _tap(tester, t.fallAlertViewDetails);
              expected = t.fallAlertPatientIdNotAvailable;
            } else {
              await _tap(tester, t.fallAlertContactEmergencyServices);
              await _tap(
                  tester,
                  action == 'emergency'
                      ? t.fallAlertCall911
                      : t.fallAlertCallContact('QA Contact'));
              expected = action == 'emergency'
                  ? t.fallAlertCouldNotStartCall911
                  : t.fallAlertCouldNotStartCallContact('QA Contact');
            }
            expect(find.text(expected), findsOneWidget);
            if (action != 'missing-id') expect(_urlCalls, isNotEmpty);
            await _dispose(tester);
          });
        }
        for (final age in [
          const Duration(minutes: 5),
          const Duration(hours: 3)
        ]) {
          testWidgets('$language: relative time $age is localized',
              (tester) async {
            await _open(tester, AlertDetailsPage(alert: alert(age: age)),
                language: language);
            final t = _text(tester, AlertDetailsPage);
            expect(
                find.text(age.inHours > 0
                    ? t.fallAlertHoursAgo(3)
                    : t.fallAlertMinutesAgo(5)),
                findsOneWidget);
            await _dispose(tester);
          });
        }
      }
    }

    if (screen == 'patient') {
      for (final language in ['en', 'es']) {
        for (final action in ['direct', 'automatic', 'contact']) {
          testWidgets('$language: $action call failure is localized',
              (tester) async {
            var escalations = 0;
            await _open(
                tester,
                PatientFallPromptPage(
                    autoCallSeconds: action == 'automatic' ? 2 : 999,
                    emergencyContactName: 'QA Contact',
                    emergencyContactPhone: '5550200',
                    onEscalate: () async {
                      escalations++;
                    }),
                language: language);
            final t = _text(tester, PatientFallPromptPage);
            if (action == 'automatic') {
              await tester.pump(const Duration(seconds: 3));
              await tester.pump();
              expect(find.text(t.fallAlertAutoCallFailed), findsOneWidget);
            } else {
              await _tap(tester, t.fallAlertCallForHelp);
              await _tap(
                  tester,
                  action == 'direct'
                      ? t.fallAlertCallEmergencyNumber('911')
                      : t.fallAlertCallContact('QA Contact'));
              expect(find.text(t.fallAlertCouldNotStartCall), findsOneWidget);
            }
            expect(_urlCalls, isNotEmpty);
            if (action != 'contact') expect(escalations, 1);
            await _dispose(tester);
          });
        }
      }
    }

    if (screen == 'add') {
      for (final language in ['en', 'es']) {
        testWidgets(
            '$language: wizard renders connecting, success, completion and reset',
            (tester) async {
          await _open(tester, const add.AddDeviceScreen(), language: language);
          final t = _text(tester, add.AddDeviceScreen);
          // Seed public presentation state to isolate the localized wizard UI
          // from native OAuth and Health Connect. No private methods invoked.
          final dynamic state = tester.state(find.byType(add.AddDeviceScreen));
          state.setState(() {
            state.selectedPlatform = 'fitbit';
            state.currentStep = 1;
            state.isConnecting = true;
          });
          await tester.pump();
          expect(find.text(t.addDevicesConnectToPlatform), findsOneWidget);
          expect(find.text(t.addDevicesConnectingTo('Fitbit')), findsOneWidget);
          expect(find.text(t.addDevicesAuthorizationPrompt), findsOneWidget);
          state.setState(() {
            state.isConnecting = false;
            state.isConnected = true;
          });
          await tester.pump();
          expect(find.text(t.addDevicesConnectedTo('Fitbit')), findsOneWidget);
          expect(
              find.text(t.addDevicesAddedToConnectedDevices), findsOneWidget);
          await _tap(tester, t.addDevicesContinue);
          expect(state.currentStep, 2);
          // ListView builds lazily; scrolling exercises the completion details.
          await tester.scrollUntilVisible(
              find.text(t.addDevicesAddAnotherPlatform), 400,
              scrollable: find.byType(Scrollable).first);
          expect(find.text(t.addDevicesBackToDashboard), findsOneWidget);
          await _tap(tester, t.addDevicesAddAnotherPlatform);
          expect(state.currentStep, 0);
          expect(state.selectedPlatform, isNull);
          expect(state.isConnected, isFalse);
          await _dispose(tester);
        });
        testWidgets('$language: connection error can be dismissed for retry',
            (tester) async {
          await _open(tester, const add.AddDeviceScreen(), language: language);
          final t = _text(tester, add.AddDeviceScreen);
          final dynamic state = tester.state(find.byType(add.AddDeviceScreen));
          state.setState(() {
            state.selectedPlatform = 'fitbit';
            state.currentStep = 1;
            state.isConnecting = false;
            state.errorMessage = 'QA connection denied';
          });
          await tester.pump();
          expect(find.text(t.addDevicesConnectionFailed), findsOneWidget);
          expect(find.text('QA connection denied'), findsOneWidget);
          // The first retry is the inline button; the bottom button starts OAuth.
          await _tap(tester, t.addDevicesTryAgain);
          expect(state.errorMessage, isNull);
          expect(find.text(t.addDevicesConnectionFailed), findsNothing);
          await _dispose(tester);
        });
      }
    }

    if (screen == 'wear') {
      for (final language in ['en', 'es']) {
        for (final mode in ['compact', 'error', 'empty', 'metrics']) {
          testWidgets('$language: wearable $mode state is localized',
              (tester) async {
            await _open(tester, const wear.WearablesScreen(),
                language: language, width: mode == 'compact' ? 400 : 1000);
            final t = _text(tester, wear.WearablesScreen);
            final dynamic state =
                tester.state(find.byType(wear.WearablesScreen));
            state.setState(() {
              state.connectedDevices = <wear.ConnectedDevice>[
                wear.ConnectedDevice(
                    id: 'qa-device',
                    platform: 'fitbit',
                    name: 'QA Band',
                    connectedAt: DateTime.now(),
                    permissions: ['steps'])
              ];
              state.isLoadingData = false;
              state.hasSyncError = mode == 'error';
              state.syncStatusMessage = mode == 'empty' ? '' : null;
              if (mode == 'error') {
                // Force the fallback description rather than a custom message.
                state.latestHealthData['steps'] = wear.HealthData(
                    type: 'Steps',
                    value: 100,
                    unit: 'steps',
                    date: DateTime.now(),
                    source: 'Fitbit');
              }
              if (mode == 'metrics') {
                state.latestHealthData['steps'] = wear.HealthData(
                    type: 'Steps',
                    value: 1234,
                    unit: 'steps',
                    date: DateTime.now(),
                    source: 'Fitbit');
                state.latestHealthData['heart_rate'] = wear.HealthData(
                    type: 'Heart Rate',
                    value: 0,
                    unit: 'bpm',
                    date: DateTime.now(),
                    source: 'Apple Health',
                    isPlaceholder: true,
                    supportStatus: 'QA unavailable',
                    placeholderReason: 'QA source unavailable');
              }
            });
            await tester.pump();
            expect(find.text(t.wearablesConnectedDevices), findsOneWidget);
            if (mode == 'compact')
              expect(find.text(t.wearablesAddDevice), findsOneWidget);
            if (mode == 'error') {
              expect(
                  find.text(t.wearablesSynchronizationFailed), findsOneWidget);
              expect(find.text(t.wearablesSynchronizationFailedDescription),
                  findsOneWidget);
            }
            if (mode == 'empty')
              expect(find.text(t.wearablesNoSyncedDataYet), findsOneWidget);
            if (mode == 'metrics') {
              expect(find.text(t.wearablesHealthMetrics), findsOneWidget);
              expect(find.text('1234'), findsOneWidget);
              expect(find.text('QA source unavailable'), findsOneWidget);
              expect(find.text(t.wearablesUpdated(t.wearablesJustNow)),
                  findsWidgets);
            }
            await _dispose(tester);
          });
        }
      }
    }

    if (screen == 'smart') {
      for (final language in ['en', 'es']) {
        testWidgets('$language: privacy URL failure shows translated feedback',
            (tester) async {
          await http.runWithClient(() async {
            await _open(tester, const SmartDevicesPage(), language: language);
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            final t = _text(tester, SmartDevicesPage);
            await tester.scrollUntilVisible(
                find.text(t.smartDevicesPrivacyPolicy), 400,
                scrollable: find.byType(Scrollable).first);
            await _tap(tester, t.smartDevicesPrivacyPolicy);
            expect(find.text(t.smartDevicesPrivacyOpenFailed), findsOneWidget);
            expect(_urlCalls, isNotEmpty);
            await _dispose(tester);
          },
              () => MockClient((request) async {
                    if (request.url.toString().contains('/v1/api/patients/')) {
                      return http.Response(
                          jsonEncode({
                            'id': 1,
                            'alexaLinked': false,
                            'user': {
                              'id': 1,
                              'role': 'PATIENT',
                              'email': 'qa@example.com'
                            }
                          }),
                          200);
                    }
                    if (request.url.toString().contains('picture'))
                      return http.Response('', 404);
                    return http.Response('{}', 200);
                  }));
        });
      }
    }
  });
}
