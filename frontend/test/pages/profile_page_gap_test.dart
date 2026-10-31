// Gap tests for ProfilePage (lib/pages/profile_page.dart): the API-backed
// profile loads for caregivers and patients, load-failure Retry, the edit and
// save flow with form validation, and the avatar image picker.
//
// ApiService is pointed at a MockClient through its debugSetHttpClient seam so
// no network is used; the image picker plugin is faked at its method channel.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/pages/profile_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

final _caregiver = UserSession(
  id: 1,
  email: 'cg@test.com',
  role: 'caregiver',
  token: 'token',
  caregiverId: 5,
  name: 'Casey Giver',
);

final _patient = UserSession(
  id: 2,
  email: 'pat@test.com',
  role: 'patient',
  token: 'token',
  patientId: 8,
  name: 'Pat Ient',
);

Widget _app(UserSession user) {
  final provider = UserProvider()..setUser(user);
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: ProfilePage()),
  );
}

Future<void> _pump(WidgetTester tester, UserSession user) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(user));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

String _textOf(WidgetTester tester, String label) {
  final field = tester.widget<TextFormField>(
    find.widgetWithText(TextFormField, label),
  );
  return field.controller!.text;
}

void main() {
  late List<String> requests;
  late http.Response Function(http.Request) responder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = <String>[];
    responder = (_) => http.Response('{}', 200);
    ApiService.debugSetHttpClient(
      MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return responder(request);
      }),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read' &&
          (call.arguments as Map)['key'] == 'jwt_token') {
        return 'jwt';
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_imagePicker, null);
  });

  testWidgets('caregiver profile is filled in from the API', (tester) async {
    responder = (_) => http.Response(
          jsonEncode({
            'phone': '555-0100',
            'caregiverType': 'Nurse',
            'address': {
              'line1': '1 Main St',
              'city': 'Baltimore',
              'state': 'MD',
              'zip': '21201',
            },
          }),
          200,
        );
    await _pump(tester, _caregiver);

    expect(requests.single, endsWith('/5'));
    expect(requests.single, startsWith('GET'));
    expect(_textOf(tester, 'Phone Number'), '555-0100');
    expect(_textOf(tester, 'Specialization'), 'Nurse');
    expect(find.text('1 Main St'), findsOneWidget);
    expect(find.text('Baltimore'), findsOneWidget);
    expect(find.text('21201'), findsOneWidget);
    // Header shows the signed-in name, initial and role.
    expect(find.text('Casey Giver'), findsWidgets);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('caregiver'), findsOneWidget);
  });

  testWidgets('patient profile shows emergency contact and medical notes',
      (tester) async {
    responder = (_) => http.Response(
          jsonEncode({
            'phone': '555-0111',
            'emergencyContact': 'Sam 555-0199',
            'medicalConditions': 'Asthma',
            'address': {'line1': '2 Oak Ave'},
          }),
          200,
        );
    await _pump(tester, _patient);

    expect(requests.single, endsWith('/8'));
    expect(_textOf(tester, 'Phone Number'), '555-0111');
    expect(find.text('Sam 555-0199'), findsOneWidget);
    expect(find.text('Asthma'), findsOneWidget);
    expect(find.text('2 Oak Ave'), findsOneWidget);
    expect(find.text('Professional Information'), findsNothing);
  });

  testWidgets('patient notes fall back to the notes field', (tester) async {
    responder = (_) => http.Response(
          jsonEncode({'notes': 'Prefers morning visits'}),
          200,
        );
    await _pump(tester, _patient);
    expect(find.text('Prefers morning visits'), findsOneWidget);
  });

  testWidgets('a network failure shows the error and Retry reloads',
      (tester) async {
    responder = (_) => throw const SocketException('offline');
    await _pump(tester, _caregiver);
    expect(find.textContaining('Failed to load profile'), findsOneWidget);
    expect(find.text('Basic Information'), findsNothing);

    responder = (_) => http.Response(jsonEncode({'phone': '555-0123'}), 200);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, hasLength(2));
    expect(find.textContaining('Failed to load profile'), findsNothing);
    expect(_textOf(tester, 'Phone Number'), '555-0123');
  });

  testWidgets('save validates the name and email before succeeding',
      (tester) async {
    responder = (_) => http.Response(jsonEncode({'phone': '555-0100'}), 200);
    await _pump(tester, _caregiver);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), '');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), '');
    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'Casey Giver',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'not-an-email',
    );
    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();
    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(find.text('Name is required'), findsNothing);
    // Nothing was reloaded while the form was invalid.
    expect(requests, hasLength(1));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'casey@example.com',
    );
    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // View mode again, and the profile was reloaded after saving.
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.save), findsNothing);
    expect(requests, hasLength(2));
  });

  testWidgets('cancel leaves edit mode without saving', (tester) async {
    responder = (_) => http.Response('{}', 200);
    await _pump(tester, _caregiver);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('the camera badge only appears while editing', (tester) async {
    await _pump(tester, _caregiver);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  testWidgets('picking a photo replaces the initial with the image',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('profile_gap');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final photo = File('${tmp.path}/me.png')..writeAsBytesSync([0, 1, 2]);
    MethodCall? pickCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async {
      pickCall = call;
      return photo.path;
    });

    await _pump(tester, _caregiver);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    expect(find.text('C'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(pickCall, isNotNull);
    expect(find.text('C'), findsNothing);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<FileImage>());
  });

  testWidgets('a picker failure is reported in a snackbar', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async {
      throw PlatformException(code: 'denied', message: 'no access');
    });

    await _pump(tester, _caregiver);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to pick image'), findsOneWidget);
    // The initial is still shown because no image was chosen.
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('cancelling the picker keeps the current avatar', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async => null);

    await _pump(tester, _caregiver);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('C'), findsOneWidget);
    expect(find.textContaining('Failed to pick image'), findsNothing);
  });
}
