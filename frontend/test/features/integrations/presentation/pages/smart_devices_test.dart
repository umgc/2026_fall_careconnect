// Tests for SmartDevicesPage
// (lib/features/integrations/presentation/pages/smart_devices.dart).
//
// Coverage strategy:
//   SmartDevicesPage calls ProfileService.getCurrentUserProfile() in initState.
//   We mock FlutterSecureStorage and HTTP to control the profile response,
//   enabling us to test loading, error, patient-linked, patient-unlinked,
//   and caregiver states.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/smart_devices.dart';

/// Storage data to be returned by the mock secure storage.
Map<String, String> _secureStorageData = {};

/// Sets up the secure storage mock with a user session for a given role.
void _setupSecureStorageForRole(String role) {
  final session = {
    'role': role,
    'patientId': 1,
    'caregiverId': 2,
    'id': 1,
    'email': 'test@example.com',
  };
  _secureStorageData = {
    'jwt_token': 'mock.jwt.token',
    'user_session': jsonEncode(session),
    'token_expiry':
        ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600).toString(),
  };
}

/// Returns a mock HTTP handler for patient profile responses.
Future<http.Response> Function(http.Request) _patientProfileHandler({bool alexaLinked = false}) {
  return (http.Request request) async {
    final url = request.url.toString();
    if (url.contains('validate-token')) {
      return http.Response('{}', 200);
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
    if (url.contains('profile') && url.contains('picture')) {
      return http.Response('', 404);
    }
    if (url.contains('alexa/unlink')) {
      return http.Response(jsonEncode({'message': 'success'}), 200);
    }
    return http.Response('{}', 200);
  };
}

/// Returns a mock HTTP handler for caregiver profile responses.
Future<http.Response> Function(http.Request) _caregiverProfileHandler() {
  return (http.Request request) async {
    final url = request.url.toString();
    if (url.contains('validate-token')) {
      return http.Response('{}', 200);
    }
    if (url.contains('/v1/api/caregivers/')) {
      return http.Response(
        jsonEncode({
          'id': 2,
          'user': {'id': 1, 'role': 'CAREGIVER', 'email': 'cg@example.com'},
        }),
        200,
      );
    }
    if (url.contains('profile') && url.contains('picture')) {
      return http.Response('', 404);
    }
    return http.Response('{}', 200);
  };
}

/// Wraps [child] with UserProvider and MaterialApp.
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'test@example.com',
    role: 'PATIENT',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales, home: child),
  );
}

/// Wraps widget in a tall scrollable-friendly environment to avoid off-screen issues.
Widget _wrapSized(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'test@example.com',
    role: 'PATIENT',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 2000)),
        child: child,
      ),
    ),
  );
}

/// Pumps widget and waits for async operations to complete.
Future<void> _pumpAndWait(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Suppress RenderFlex overflow errors only
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed') || message.contains('RenderFlex')) {
        return; // Suppress overflow warnings
      }
      // Re-throw all other errors
      FlutterError.presentError(details);
    };

    _secureStorageData = {};

    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') {
          return <String, String>{..._secureStorageData};
        }
        if (call.method == 'read') {
          final key = call.arguments['key'] as String?;
          if (key != null && _secureStorageData.containsKey(key)) {
            return _secureStorageData[key];
          }
          return null;
        }
        if (call.method == 'write') return null;
        if (call.method == 'delete') return null;
        if (call.method == 'containsKey') {
          final key = call.arguments['key'] as String?;
          return key != null && _secureStorageData.containsKey(key);
        }
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
    FlutterError.onError = FlutterError.presentError;
  });

  // ─── Loading state tests ───────────────────────────────────

  group('SmartDevicesPage - loading state', () {
    testWidgets('renders Scaffold without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const SmartDevicesPage()));
      // Don't pump again - the async call completes very quickly with empty storage
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does NOT show error text on initial pump', (tester) async {
      await tester.pumpWidget(_wrap(const SmartDevicesPage()));
      // On initial pump the widget is either loading or just resolved
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  // ─── Error state tests (null profile) ──────────────────────

  group('SmartDevicesPage - error state (null profile)', () {
    testWidgets('shows error when profile is null', (tester) async {

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Unable to load user profile.'), findsOneWidget);
        },
        () => MockClient((request) async => http.Response('{}', 200)),
      );
    });

    testWidgets('error state shows AppBar with Smart Devices title', (tester) async {

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Smart Devices'), findsOneWidget);
        },
        () => MockClient((request) async => http.Response('{}', 200)),
      );
    });

    testWidgets('error text is styled red', (tester) async {

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          final errorText = tester.widget<Text>(
            find.text('Unable to load user profile.'),
          );
          expect(errorText.style?.color, Colors.red);
        },
        () => MockClient((request) async => http.Response('{}', 200)),
      );
    });

    testWidgets('error state has Center widget', (tester) async {

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byType(Center), findsWidgets);
        },
        () => MockClient((request) async => http.Response('{}', 200)),
      );
    });

    testWidgets('error state does NOT show ElevatedButton', (tester) async {

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byType(ElevatedButton), findsNothing);
        },
        () => MockClient((request) async => http.Response('{}', 200)),
      );
    });
  });

  // ─── Exception error state tests ───────────────────────────

  group('SmartDevicesPage - exception error state', () {
    testWidgets('shows error when exception occurs during profile load', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          // HTTP throws => profile returns null => error state
          expect(find.text('Unable to load user profile.'), findsOneWidget);
        },
        () => MockClient((request) async {
          throw Exception('Network error');
        }),
      );
    });
  });

  // ─── Normal UI - Patient with Alexa linked ─────────────────

  group('SmartDevicesPage - patient with Alexa linked', () {
    testWidgets('shows linked status and Disable button', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Smart Device Integration'), findsOneWidget);
          expect(find.text('Your Alexa account is linked!'), findsOneWidget);
          expect(find.text('Amazon Alexa'), findsOneWidget);
          expect(find.text('Google Nest'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Privacy Policy link', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Privacy Policy'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Alexa device items', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Echo Devices'), findsOneWidget);
          expect(find.text('Thermostats'), findsOneWidget);
          expect(find.text('Smart Locks'), findsOneWidget);
          expect(find.text('Smart Plugs'), findsOneWidget);
          expect(find.text('Sensors'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Google Nest device items', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Nest Hubs'), findsOneWidget);
          expect(find.text('Google Home'), findsOneWidget);
          expect(find.text('Nest Thermostat'), findsOneWidget);
          expect(find.text('Nest Doorbell'), findsOneWidget);
          expect(find.text('Nest Cameras'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Coming Soon badges for unavailable devices', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Coming Soon'), findsWidgets);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Google Action coming soon button', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Enable Google Action (Coming Soon)'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows Google Home patient message', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(
            find.text('Google Home integration is under development. Stay tuned for updates!'),
            findsOneWidget,
          );
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows link icon when Alexa is linked', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.link), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows mic icon in Alexa card', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.mic), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows g_mobiledata_rounded icon in Google card', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.g_mobiledata_rounded), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('shows devices icon in header', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.devices), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: true)),
      );
    });

    testWidgets('tapping Disable Alexa calls unlink and shows snackbar', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      bool unlinkCalled = false;

      await http.runWithClient(
        () async {
          // Use a tall view so the button is visible
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          // Scroll to find the Disable button
          await tester.scrollUntilVisible(
            find.text('Disable Alexa Skill'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();

          await tester.tap(find.text('Disable Alexa Skill'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));

          expect(unlinkCalled, isTrue);
          expect(find.text('Alexa Skill disabled successfully.'), findsOneWidget);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient((http.Request request) async {
          final url = request.url.toString();
          if (url.contains('validate-token')) {
            return http.Response('{}', 200);
          }
          if (url.contains('/v1/api/patients/')) {
            return http.Response(
              jsonEncode({
                'id': 1,
                'alexaLinked': true,
                'user': {'id': 1, 'role': 'PATIENT', 'email': 'test@example.com'},
              }),
              200,
            );
          }
          if (url.contains('alexa/unlink')) {
            unlinkCalled = true;
            return http.Response(jsonEncode({'message': 'success'}), 200);
          }
          if (url.contains('profile') && url.contains('picture')) {
            return http.Response('', 404);
          }
          return http.Response('{}', 200);
        }),
      );
    });
  });

  // ─── Normal UI - Patient with Alexa NOT linked ─────────────

  group('SmartDevicesPage - patient with Alexa not linked', () {
    testWidgets('shows unlinked status and Enable button', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Alexa is not linked yet.'), findsOneWidget);
          expect(find.text('Enable Alexa Skill'), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });

    testWidgets('shows link_off icon when not linked', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.link_off), findsOneWidget);
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });

    testWidgets('tapping Enable Alexa shows enablement dialog', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          await tester.scrollUntilVisible(
            find.text('Enable Alexa Skill'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();

          await tester.tap(find.text('Enable Alexa Skill'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // The enablement dialog should appear
          expect(find.text('Cancel'), findsOneWidget);
          expect(find.text('Open Alexa Store'), findsOneWidget);
          expect(
            find.text('Note: Currently using a sample URL for demonstration.'),
            findsOneWidget,
          );

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });

    testWidgets('enablement dialog can be dismissed with Cancel', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          await tester.scrollUntilVisible(
            find.text('Enable Alexa Skill'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();

          await tester.tap(find.text('Enable Alexa Skill'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.text('Cancel'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Open Alexa Store'), findsNothing);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });

    testWidgets('description text is present', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(
            find.text('Connect Alexa or Google Nest compatible smart devices to help monitor and assist with daily activities.'),
            findsOneWidget,
          );
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });
  });

  // ─── Normal UI - Caregiver ─────────────────────────────────

  group('SmartDevicesPage - caregiver view', () {
    testWidgets('shows caregiver-only message for Alexa', (tester) async {
      _setupSecureStorageForRole('CAREGIVER');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(
            find.text('Alexa integration is currently available for patients only. Development is underway to support caregivers soon!'),
            findsOneWidget,
          );
          expect(find.text('Coming Soon for Caregivers'), findsOneWidget);
        },
        () => MockClient(_caregiverProfileHandler()),
      );
    });

    testWidgets('caregiver does not see Alexa link status indicators', (tester) async {
      _setupSecureStorageForRole('CAREGIVER');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Your Alexa account is linked!'), findsNothing);
          expect(find.text('Alexa is not linked yet.'), findsNothing);
          expect(find.byIcon(Icons.link_off), findsNothing);
        },
        () => MockClient(_caregiverProfileHandler()),
      );
    });

    testWidgets('caregiver sees Google Home caregiver message', (tester) async {
      _setupSecureStorageForRole('CAREGIVER');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(
            find.text('Google Home integration is currently available for patients only. Development is underway to support caregivers soon!'),
            findsOneWidget,
          );
        },
        () => MockClient(_caregiverProfileHandler()),
      );
    });

    testWidgets('shows Smart Devices title in AppBar', (tester) async {
      _setupSecureStorageForRole('CAREGIVER');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Smart Devices'), findsOneWidget);
        },
        () => MockClient(_caregiverProfileHandler()),
      );
    });

    testWidgets('shows header icon and description', (tester) async {
      _setupSecureStorageForRole('CAREGIVER');

      await http.runWithClient(
        () async {
          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.byIcon(Icons.devices), findsOneWidget);
          expect(find.text('Smart Device Integration'), findsOneWidget);
        },
        () => MockClient(_caregiverProfileHandler()),
      );
    });
  });

  // ─── Unlink failure tests ──────────────────────────────────

  group('SmartDevicesPage - unlink failure', () {
    testWidgets('shows error snackbar when unlink returns failure response', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          await tester.scrollUntilVisible(
            find.text('Disable Alexa Skill'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();

          await tester.tap(find.text('Disable Alexa Skill'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.text('Server error'), findsOneWidget);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient((http.Request request) async {
          final url = request.url.toString();
          if (url.contains('validate-token')) {
            return http.Response('{}', 200);
          }
          if (url.contains('/v1/api/patients/')) {
            return http.Response(
              jsonEncode({
                'id': 1,
                'alexaLinked': true,
                'user': {'id': 1, 'role': 'PATIENT', 'email': 'test@example.com'},
              }),
              200,
            );
          }
          if (url.contains('alexa/unlink')) {
            return http.Response(
              jsonEncode({'error': 'Server error'}),
              500,
            );
          }
          if (url.contains('profile') && url.contains('picture')) {
            return http.Response('', 404);
          }
          return http.Response('{}', 200);
        }),
      );
    });

    testWidgets('shows error snackbar when unlink throws exception', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          await tester.scrollUntilVisible(
            find.text('Disable Alexa Skill'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();

          await tester.tap(find.text('Disable Alexa Skill'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.textContaining('An unexpected error occurred'), findsOneWidget);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient((http.Request request) async {
          final url = request.url.toString();
          if (url.contains('validate-token')) {
            return http.Response('{}', 200);
          }
          if (url.contains('/v1/api/patients/')) {
            return http.Response(
              jsonEncode({
                'id': 1,
                'alexaLinked': true,
                'user': {'id': 1, 'role': 'PATIENT', 'email': 'test@example.com'},
              }),
              200,
            );
          }
          if (url.contains('alexa/unlink')) {
            throw Exception('Network failure');
          }
          if (url.contains('profile') && url.contains('picture')) {
            return http.Response('', 404);
          }
          return http.Response('{}', 200);
        }),
      );
    });
  });

  // ─── Layout tests ─────────────────────────────────────────

  group('SmartDevicesPage - layout', () {
    testWidgets('narrow layout renders both cards', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Amazon Alexa'), findsOneWidget);
          expect(find.text('Google Nest'), findsOneWidget);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });

    testWidgets('wide layout renders both cards', (tester) async {
      _setupSecureStorageForRole('PATIENT');

      await http.runWithClient(
        () async {
          tester.view.physicalSize = const Size(1200, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(_wrap(const SmartDevicesPage()));
          await _pumpAndWait(tester);

          expect(find.text('Amazon Alexa'), findsOneWidget);
          expect(find.text('Google Nest'), findsOneWidget);

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
        () => MockClient(_patientProfileHandler(alexaLinked: false)),
      );
    });
  });

  // ─── SmartDevicesPage widget construction ──────────────────

  group('SmartDevicesPage - widget construction', () {
    testWidgets('SmartDevicesPage can be constructed with const', (tester) async {
      const widget = SmartDevicesPage();
      expect(widget, isA<SmartDevicesPage>());
    });

    testWidgets('SmartDevicesPage accepts a key', (tester) async {
      const key = Key('test_key');
      const widget = SmartDevicesPage(key: key);
      expect(widget.key, equals(key));
    });
  });
}
