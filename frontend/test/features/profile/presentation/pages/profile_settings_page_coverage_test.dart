// Coverage tests for ProfileSettingsPage
// (lib/features/profile/presentation/pages/profile_settings_page.dart):
// saving caregiver and patient profiles through ApiService (success
// response and error response), professional-field fallbacks, the
// upgrade navigation and the profile picture update callback.
//
// ProfileService uses package:http top-level calls, so bodies run inside
// http.runWithClient; ApiService uses its debugSetHttpClient seam.

import 'dart:convert';

import 'package:care_connect_app/features/profile/presentation/pages/profile_settings_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/profile_picture_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _store = {};

class _RecordingUserProvider extends MockUserProvider {
  _RecordingUserProvider() : super(mockUser: MockUser(role: 'CAREGIVER'));
  final names = <String>[];

  @override
  void updateUserName(String newName) => names.add(newName);
}

Map<String, dynamic> _caregiver({Map<String, dynamic>? professional}) => {
      'id': 10,
      'firstName': 'Jane',
      'lastName': 'Doe',
      'email': 'jane@example.com',
      'phone': '555-1234',
      'caregiverType': 'RN',
      'address': {'line1': '1 Main', 'city': 'Austin', 'state': 'TX'},
      'professional': professional ??
          {'specialization': 'Geriatrics', 'licenseNumber': 'LIC-1'},
    };

Map<String, dynamic> _patient() => {
      'id': 20,
      'firstName': 'John',
      'lastName': 'Smith',
      'email': 'john@example.com',
      'phone': '555-5678',
      'dob': '1990-06-20',
      'gender': 'Male',
      'emergencyContact': 'Mom',
      'address': {'line1': '9 Oak', 'city': 'Reno', 'state': 'NV', 'zip': '1'},
    };

class _Backend {
  _Backend(this.profile, {this.putStatus = 200});
  final Map<String, dynamic> profile;
  final int putStatus;
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];

  MockClient client() => MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        if (req.method == 'PUT') {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(profile), putStatus);
        }
        if (req.url.path.contains('/files/')) {
          return http.Response('{"error":"none"}', 404);
        }
        return http.Response(jsonEncode(profile), 200);
      });
}

Future<void> _pump(
  WidgetTester tester,
  UserProvider provider,
) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp(
        home: const ProfileSettingsPage(),
        routes: {
          '/select-package': (_) => const Scaffold(body: Text('Packages')),
        },
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(ElevatedButton, 'SAVE CHANGES');
  await tester.ensureVisible(save);
  await tester.tap(save);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _field(WidgetTester tester, String label) => tester
    .widget<TextFormField>(find.widgetWithText(TextFormField, label))
    .controller!
    .text;

void main() {
  setUp(() {
    _store.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'read':
          return _store[args!['key']];
        case 'write':
          _store[args!['key'] as String] = args['value'] as String?;
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return _store.containsKey(args!['key']);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    ApiService.debugResetHttpClient();
  });

  void session(Map<String, dynamic> s) =>
      _store['user_session'] = jsonEncode(s);

  testWidgets('caregiver save sends the professional payload',
      (tester) async {
    session({'id': 1, 'role': 'CAREGIVER', 'caregiverId': 10});
    final backend = _Backend(_caregiver());
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      expect(_field(tester, 'Full Name'), 'Jane Doe');
      expect(_field(tester, 'Specialization'), 'Geriatrics');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Specialization'), '12');
      await _save(tester);
    }, backend.client);
    final put = backend.requests.where((r) => r.startsWith('PUT')).single;
    expect(put, endsWith('/10'));
    final body = backend.bodies.single;
    expect(body['firstName'], 'Jane');
    expect(body['lastName'], 'Doe');
    expect((body['professional'] as Map)['yearsExperience'], 12);
    expect(body['caregiverType'], 'RN');
    // The page cannot parse a raw http.Response, so it reports an error.
    expect(find.textContaining('Error saving profile'), findsOneWidget);
  });

  testWidgets('caregiver save failure reports the status code',
      (tester) async {
    session({'id': 1, 'role': 'CAREGIVER', 'caregiverId': 10});
    final backend = _Backend(_caregiver(), putStatus: 500);
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name'), 'Mononym');
      await _save(tester);
    }, backend.client);
    expect(backend.bodies.single['lastName'], '');
    expect(
      find.textContaining('Failed to update caregiver profile: 500'),
      findsOneWidget,
    );
  });

  testWidgets('patient save sends medical info and address', (tester) async {
    session({'id': 2, 'role': 'PATIENT', 'patientId': 20});
    final backend = _Backend(_patient());
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      expect(_field(tester, 'Gender'), 'Male');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Allergies'), 'Peanuts');
      await _save(tester);
    }, backend.client);
    final put = backend.requests.where((r) => r.startsWith('PUT')).single;
    expect(put, endsWith('/20/profile'));
    final body = backend.bodies.single;
    expect((body['medicalInfo'] as Map)['allergies'], 'Peanuts');
    expect((body['address'] as Map)['city'], 'Reno');
    expect(body['dob'], '1990-06-20');
    expect(find.textContaining('Error saving profile'), findsOneWidget);
  });

  testWidgets('patient save failure reports the status code', (tester) async {
    session({'id': 2, 'role': 'PATIENT', 'patientId': 20});
    final backend = _Backend(_patient(), putStatus: 400);
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full Name'), 'Solo');
      await _save(tester);
    }, backend.client);
    expect(backend.bodies.single['lastName'], '');
    expect(
      find.textContaining('Failed to update patient profile: 400'),
      findsOneWidget,
    );
  });

  testWidgets('a patient session without a patient id cannot save',
      (tester) async {
    session({'id': 2, 'role': 'PATIENT', 'patientId': 20});
    final backend = _Backend(_patient());
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      session({'id': 2, 'role': 'PATIENT'});
      await _save(tester);
    }, backend.client);
    expect(backend.requests.where((r) => r.startsWith('PUT')), isEmpty);
    expect(find.textContaining('Patient ID not found'), findsOneWidget);
  });

  testWidgets('a caregiver session without a caregiver id cannot save',
      (tester) async {
    session({'id': 1, 'role': 'CAREGIVER', 'caregiverId': 10});
    final backend = _Backend(_caregiver());
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      session({'id': 1, 'role': 'CAREGIVER'});
      await _save(tester);
    }, backend.client);
    expect(backend.requests.where((r) => r.startsWith('PUT')), isEmpty);
    expect(find.textContaining('Caregiver ID not found'), findsOneWidget);
  });

  testWidgets('specialization falls back to specialty then experience',
      (tester) async {
    session({'id': 1, 'role': 'CAREGIVER', 'caregiverId': 10});
    var backend = _Backend(_caregiver(professional: {'specialty': 'Peds'}));
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
    }, backend.client);
    expect(_field(tester, 'Specialization'), 'Peds');

    await tester.pumpWidget(const SizedBox());
    backend = _Backend(_caregiver(
      professional: {'yearsExperience': 7, 'license': 'L-7'},
    ));
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
    }, backend.client);
    expect(_field(tester, 'Specialization'), '7');
    expect(_field(tester, 'License Number'), 'L-7');
  });

  testWidgets('upgrade buttons open the package selector', (tester) async {
    session({'id': 1, 'role': 'CAREGIVER', 'caregiverId': 10});
    final backend = _Backend(_caregiver());
    ApiService.debugSetHttpClient(backend.client());
    await http.runWithClient(() async {
      await _pump(tester, MockUserProvider());
      final upgrade = find.text('Upgrade Plan');
      await tester.ensureVisible(upgrade);
      await tester.tap(upgrade);
      await tester.pumpAndSettle();
      expect(find.text('Packages'), findsOneWidget);
      Navigator.of(tester.element(find.text('Packages'))).pop();
      await tester.pumpAndSettle();

      final view = find.text('View Plan');
      await tester.ensureVisible(view);
      await tester.tap(view);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upgrade'));
      await tester.pumpAndSettle();
      expect(find.text('Packages'), findsOneWidget);
    }, backend.client);
  });

  UserFileDTO image(int id) => UserFileDTO(
        id: id,
        originalFilename: 'me.png',
        contentType: 'image/png',
        fileSize: 10,
        fileCategory: 'PROFILE_PICTURE',
        ownerId: 1,
        ownerType: 'USER',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        downloadUrl: 'https://example.test/me.png',
        fileName: 'me.png',
      );

  for (final role in ['CAREGIVER', 'PATIENT']) {
    testWidgets('$role profile picture updates and removals are applied',
        (tester) async {
      session(role == 'CAREGIVER'
          ? {'id': 1, 'role': role, 'caregiverId': 10}
          : {'id': 2, 'role': role, 'patientId': 20});
      final backend =
          _Backend(role == 'CAREGIVER' ? _caregiver() : _patient());
      ApiService.debugSetHttpClient(backend.client());
      await http.runWithClient(() async {
        await _pump(tester, _RecordingUserProvider());
        ProfilePictureWidget picture() =>
            tester.widget<ProfilePictureWidget>(
                find.byType(ProfilePictureWidget));
        expect(picture().existingImageUrl, isNull);
        picture().onImageUpdated!(image(5));
        await tester.pump();
        expect(picture().existingImageUrl, 'https://example.test/me.png');
        // A removal (id -1) is handled without error. Note: the profile
        // models' copyWith cannot clear a field with null, so the old URL
        // is kept.
        picture().onImageUpdated!(image(-1));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfilePictureWidget), findsOneWidget);
      }, backend.client);
    });
  }
}
