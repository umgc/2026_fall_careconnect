// Coverage tests for ProfilePage (lib/pages/profile_page.dart): role-specific
// profile loading through ApiService (caregiver and patient), the load
// failure state, edit mode with validation, saving, and picking an image.

import 'dart:convert';

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

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

Future<void> _pump(WidgetTester tester, UserSession user) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(mockUser: user),
      child: const MaterialApp(home: ProfilePage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late List<String> requests;

  setUp(() {
    requests = <String>[];
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_imagePicker, null);
    ApiService.debugResetHttpClient();
  });

  void serve(int status, Map<String, dynamic> body) {
    ApiService.debugSetHttpClient(MockClient((req) async {
      requests.add(req.url.path);
      return http.Response(jsonEncode(body), status);
    }));
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, label))
      .controller!
      .text;

  testWidgets('caregiver profile is loaded from the caregiver endpoint',
      (tester) async {
    serve(200, {
      'phone': '555-0100',
      'caregiverType': 'Nurse',
      'address': {
        'line1': '1 Main St',
        'city': 'Austin',
        'state': 'TX',
        'zip': '73301',
      },
    });
    await _pump(
      tester,
      MockUser(role: 'CAREGIVER', caregiverId: 7, name: 'Casey Giver'),
    );
    expect(requests.single, endsWith('/7'));
    expect(fieldText(tester, 'Phone Number'), '555-0100');
    expect(fieldText(tester, 'City'), 'Austin');
    expect(fieldText(tester, 'Specialization'), 'Nurse');
    // Avatar falls back to the first letter of the name.
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('patient profile maps emergency contact and notes',
      (tester) async {
    serve(200, {
      'phone': '555-0199',
      'address': {'line1': '9 Elm', 'city': 'Reno', 'state': 'NV', 'zip': '1'},
      'emergencyContact': 'Mom',
      'notes': 'Allergic to nuts',
    });
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3));
    expect(requests.single, endsWith('/3'));
    expect(fieldText(tester, 'Emergency Contact'), 'Mom');
    expect(fieldText(tester, 'Medical Notes'), 'Allergic to nuts');
    expect(fieldText(tester, 'Street Address'), '9 Elm');
  });

  testWidgets('patient profile with no address keeps blank fields',
      (tester) async {
    serve(200, {'medicalConditions': 'Asthma'});
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3));
    expect(fieldText(tester, 'Medical Notes'), 'Asthma');
    expect(fieldText(tester, 'City'), '');
  });

  testWidgets('a non-200 caregiver response keeps the default profile',
      (tester) async {
    serve(500, {'error': 'boom'});
    await _pump(tester, MockUser(role: 'CAREGIVER', caregiverId: 7));
    expect(fieldText(tester, 'Phone Number'), '');
    expect(find.text('Basic Information'), findsOneWidget);
  });

  testWidgets('a failing request shows the load error', (tester) async {
    ApiService.debugSetHttpClient(
      MockClient((req) async => throw Exception('offline')),
    );
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3));
    expect(find.textContaining('Failed to load profile'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('edit mode validates, cancels and saves', (tester) async {
    serve(200, {'phone': '555-0100'});
    await _pump(
      tester,
      MockUser(role: 'CAREGIVER', caregiverId: 7, name: 'Casey Giver'),
    );
    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pump();
    expect(find.byTooltip('Save Profile'), findsOneWidget);

    // Cancel leaves edit mode.
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(find.byTooltip('Edit Profile'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pump();

    // Empty name and email fail validation.
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), '');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), '');
    await tester.tap(find.byTooltip('Save Profile'));
    await tester.pump();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.tap(find.byTooltip('Save Profile'));
    await tester.pump();
    expect(find.text('Please enter a valid email'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'), 'Casey New');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'casey@example.com');
    await tester.tap(find.byTooltip('Save Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('✅ Profile updated successfully!'), findsOneWidget);
    expect(find.byTooltip('Edit Profile'), findsOneWidget);
    // Saving reloads the profile from the API.
    expect(requests.length, 2);
  });

  testWidgets('saving a single-word name for a patient succeeds',
      (tester) async {
    serve(200, {});
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3, name: 'Pat'));
    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pump();
    await tester.tap(find.byTooltip('Save Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('✅ Profile updated successfully!'), findsOneWidget);
  });

  testWidgets('picking an image in edit mode updates the avatar',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async {
      calls.add(call);
      return '/photos/me.jpg';
    });
    serve(200, {});
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3, name: 'Pat'));
    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();
    await tester.pump();
    expect(calls.single.method, 'pickImage');
    // The picked file replaces the initial-letter avatar.
    expect(find.text('P'), findsNothing);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<FileImage>());
    tester.takeException();

    // Saving with a picked image still succeeds.
    await tester.tap(find.byTooltip('Save Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('✅ Profile updated successfully!'), findsOneWidget);
    tester.takeException();
  });

  testWidgets('an image picker failure is reported', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, (call) async {
      throw PlatformException(code: 'denied', message: 'no access');
    });
    serve(200, {});
    await _pump(tester, MockUser(role: 'PATIENT', patientId: 3, name: 'Pat'));
    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Failed to pick image'), findsOneWidget);
  });
}
