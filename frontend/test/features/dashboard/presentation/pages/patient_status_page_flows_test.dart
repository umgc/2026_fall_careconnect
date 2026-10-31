// Widget tests for PatientStatusPage
// (lib/features/dashboard/presentation/pages/patient_status_page.dart).
//
// The page fetches the patient profile and vitals with top-level http.get
// (intercepted with http.runWithClient) and the risk list / profile update
// through ApiService (intercepted with ApiService.debugSetHttpClient).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/dashboard/presentation/pages/patient_status_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show debugNetworkImageHttpClientProvider;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

/// HttpClient whose requests never complete, so avatar NetworkImages stay
/// pending instead of reporting the test binding's HTTP 400 as an error.
class _PendingImageHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// testWidgets wrapper that installs the pending image client for the body
/// and restores it before flutter_test verifies painting invariants.
void _testPage(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    debugNetworkImageHttpClientProvider = () => _PendingImageHttpClient();
    try {
      await body(tester);
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });
}

typedef _Handler = Future<http.Response> Function(http.Request request);

late _Handler _handler;
final MockClient _mockClient = MockClient((r) => _handler(r));

Map<String, dynamic> _patientJson({
  bool withAddress = true,
  bool withMedical = true,
  String? comm = 'verbal',
}) =>
    {
      'id': 7,
      'firstName': 'Ada',
      'lastName': 'Lovelace',
      'email': 'ada@example.test',
      'phone': '555-0100',
      'dob': '01/15/1950',
      'relationship': 'Self',
      'gender': 'Female',
      'profileImageUrl': 'https://example.test/a.png',
      if (withAddress)
        'address': {
          'line1': '1 Test Way',
          'line2': 'Apt 2',
          'city': 'Testville',
          'state': 'MD',
          'zip': '20000',
        },
      if (withMedical) 'allergies': ['Peanuts', 'Dust'],
      if (withMedical)
        'latestVitals': {
          'heartRate': 72,
          'bloodPressure': '120/80',
          'temperature': 98.6,
          'oxygenSaturation': 97,
          'medications': 'Aspirin',
          'respiratoryRate': 16,
          'blank': '',
        },
      'likes': 'Gardening',
      'dislikes': '',
      'habits': 'Morning walk',
      'phobias': null,
      'preferredCommunicationMethod': comm,
    };

Map<String, dynamic> _vitalsJson() => {
      'avgHeartRate': 71.25,
      'avgSpo2': 97.5,
      'avgSystolic': 120,
      'avgDiastolic': 80,
      'avgWeight': 150.4,
      'adherenceRate': 88.8,
    };

/// Builds a request handler with overridable responses per endpoint.
_Handler _routes({
  http.Response Function()? profile,
  http.Response Function()? risks,
  http.Response Function()? vitals,
  FutureOr<http.Response> Function(http.Request)? update,
}) {
  return (request) async {
    final path = request.url.path;
    if (request.method == 'PUT' && path.endsWith('/profile')) {
      return update != null
          ? await update(request)
          : http.Response(jsonEncode({'data': {}}), 200);
    }
    if (path.endsWith('/risks')) {
      return risks != null ? risks() : http.Response('[]', 200);
    }
    if (path.contains('/analytics/dashboard')) {
      return vitals != null
          ? vitals()
          : http.Response(jsonEncode(_vitalsJson()), 200);
    }
    if (path.contains('/tasks/') || path.contains('/files/')) {
      return http.Response('[]', 200);
    }
    if (RegExp(r'/users/\d+$').hasMatch(path) ||
        RegExp(r'caregivers/\d+/patients/\d+$').hasMatch(path)) {
      return profile != null
          ? profile()
          : http.Response(jsonEncode(_patientJson()), 200);
    }
    return http.Response('[]', 200);
  };
}

Widget _wrap(UserProvider provider, {int? patientId, double textScale = 1.0}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PatientStatusPage(patientId: patientId),
    ),
  );
}

MockUserProvider _patientUser({int? patientId = 7}) => MockUserProvider(
      mockUser: MockUser(id: 1, role: 'PATIENT', patientId: patientId),
    );

MockUserProvider _caregiverUser({String role = 'CAREGIVER'}) =>
    MockUserProvider(
      mockUser: MockUser(id: 2, role: role, patientId: null, caregiverId: 5),
    );

Future<void> _pumpPage(
  WidgetTester tester,
  UserProvider provider, {
  int? patientId,
  Size size = const Size(1200, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    await tester.pumpWidget(
      _wrap(provider, patientId: patientId, textScale: textScale),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }, () => _mockClient);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    _handler = _routes();
    ApiService.debugSetHttpClient(_mockClient);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('PatientStatusPage error states', () {
    _testPage('shows not-logged-in message when there is no user',
        (tester) async {
      await _pumpPage(tester, _NullUserProvider());
      expect(find.text('User not logged in.'), findsOneWidget);
      expect(find.text('Patient Status'), findsOneWidget);
    });

    _testPage('shows loading indicator before data arrives', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(_wrap(_patientUser()));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }, () => _mockClient);
    });

    _testPage('shows no-patient-id message when id is unavailable',
        (tester) async {
      await _pumpPage(tester, _patientUser(patientId: null));
      expect(find.text('No patient ID available'), findsOneWidget);
    });

    _testPage('shows profile load failure with status code', (tester) async {
      _handler = _routes(profile: () => http.Response('nope', 500));
      await _pumpPage(tester, _patientUser());
      expect(
        find.text('Failed to load patient profile. Status: 500'),
        findsOneWidget,
      );
    });

    _testPage('shows vitals load failure with status code', (tester) async {
      _handler = _routes(vitals: () => http.Response('nope', 503));
      await _pumpPage(tester, _patientUser());
      expect(
        find.text('Failed to load vitals summary. Status: 503'),
        findsOneWidget,
      );
    });

    _testPage('shows generic error when profile body is not JSON',
        (tester) async {
      _handler = _routes(profile: () => http.Response('<html>', 200));
      await _pumpPage(tester, _patientUser());
      expect(find.textContaining('Error: '), findsOneWidget);
    });
  });

  group('PatientStatusPage patient view (wide layout)', () {
    _testPage('renders header, info, address, medical and vitals sections',
        (tester) async {
      _handler = _routes(
        risks: () => http.Response(
          jsonEncode([
            {'riskTypeName': 'Fall risk'},
            {'riskTypeName': 'Wandering'},
            'not-a-map',
          ]),
          200,
        ),
      );
      await _pumpPage(tester, _patientUser());

      expect(find.text('Ada Lovelace'), findsWidgets);
      expect(find.textContaining('Age: '), findsOneWidget);
      expect(find.text('Phone: 555-0100'), findsOneWidget);
      expect(find.text('Email: ada@example.test'), findsOneWidget);

      // Risk banner
      expect(find.text('Known Risks: Fall risk, Wandering'), findsOneWidget);

      // Patient information rows (wide layout uses Row with fixed label)
      expect(find.text('Relationship:'), findsOneWidget);
      expect(find.text('Self'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('01/15/1950'), findsOneWidget);

      // Address
      expect(find.text('1 Test Way\nApt 2'), findsOneWidget);
      expect(find.text('Testville'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.text('20000'), findsOneWidget);

      // Medical information
      expect(find.text('Peanuts, Dust'), findsOneWidget);
      expect(find.text('Aspirin'), findsOneWidget);
      expect(find.text('72 bpm'), findsOneWidget);
      expect(find.text('120/80 mmHg'), findsOneWidget);
      expect(find.text('98.6°F'), findsOneWidget);
      expect(find.text('97%'), findsOneWidget);
      expect(find.text('Respiratory Rate:'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);

      // Vitals summary
      expect(find.text('Vitals Summary (Past 7 Days)'), findsOneWidget);
      expect(find.text('71.3 bpm'), findsOneWidget);
      expect(find.text('97.5%'), findsOneWidget);
      expect(find.text('120.0 mmHg'), findsOneWidget);
      expect(find.text('80.0 mmHg'), findsOneWidget);
      expect(find.text('150.4 lbs'), findsOneWidget);
      expect(find.text('88.8%'), findsOneWidget);

      // Personalization read-only values
      expect(find.text('Gardening'), findsOneWidget);
      expect(find.text('Morning walk'), findsOneWidget);
      expect(find.text('Not set'), findsNWidgets(2));
      expect(find.text('Verbal'), findsOneWidget);
    });

    _testPage('uses widget patientId over the user patientId',
        (tester) async {
      final requested = <String>[];
      final base = _routes();
      _handler = (r) {
        requested.add(r.url.path);
        return base(r);
      };
      await _pumpPage(tester, _patientUser(patientId: 3), patientId: 9);
      expect(requested.any((p) => p.endsWith('/users/9')), isTrue);
      expect(requested.any((p) => p.endsWith('/users/3')), isFalse);
    });

    _testPage('shows no-information placeholder when medical data empty',
        (tester) async {
      _handler = _routes(
        profile: () => http.Response(
          jsonEncode(_patientJson(withMedical: false, withAddress: false)),
          200,
        ),
        vitals: () => http.Response('{}', 200),
      );
      await _pumpPage(tester, _patientUser());
      expect(find.text('Medical Information'), findsOneWidget);
      expect(find.text('No information available'), findsOneWidget);
      expect(find.textContaining('Known Risks'), findsNothing);
      expect(find.text('Testville'), findsNothing);
    });

    _testPage('shows no-allergies text when only vitals are present',
        (tester) async {
      final json = _patientJson(withAddress: false, withMedical: false)
        ..['latestVitals'] = {'heartRate': 60};
      _handler = _routes(profile: () => http.Response(jsonEncode(json), 200));
      await _pumpPage(tester, _patientUser());
      expect(find.text('No allergies listed'), findsOneWidget);
      expect(find.text('60 bpm'), findsOneWidget);
    });

    _testPage('omits unknown communication method and handles bad dob',
        (tester) async {
      final json = _patientJson(comm: 'telepathy')
        ..['dob'] = 'not/a/date'
        ..['phone'] = ''
        ..['email'] = '';
      _handler = _routes(
        profile: () => http.Response(jsonEncode(json), 200),
        risks: () => http.Response('oops', 500),
      );
      await _pumpPage(tester, _patientUser());
      expect(find.text('Age: 0'), findsOneWidget);
      expect(find.textContaining('Phone: '), findsNothing);
      expect(find.text('Not set'), findsNWidgets(3));
      expect(find.textContaining('Known Risks'), findsNothing);
    });

    _testPage('treats a two-part dob as age zero and risk errors as empty',
        (tester) async {
      final json = _patientJson()..['dob'] = '01/1950';
      _handler = _routes(
        profile: () => http.Response(jsonEncode(json), 200),
        risks: () => throw Exception('risk service down'),
      );
      await _pumpPage(tester, _patientUser());
      expect(find.text('Age: 0'), findsOneWidget);
      expect(find.textContaining('Known Risks'), findsNothing);
    });

    _testPage('computes age for a birthday later this year', (tester) async {
      final now = DateTime.now();
      // A birthday in December (unless today is Dec 31) is still to come.
      final json = _patientJson()..['dob'] = '12/31/${now.year - 30}';
      _handler = _routes(profile: () => http.Response(jsonEncode(json), 200));
      await _pumpPage(tester, _patientUser());
      final expected = (now.month == 12 && now.day == 31) ? 30 : 29;
      expect(find.text('Age: $expected'), findsOneWidget);
    });
  });

  group('PatientStatusPage mobile layout', () {
    _testPage('renders stacked header and sections on narrow screens',
        (tester) async {
      _handler = _routes(
        risks: () => http.Response(
          jsonEncode([
            {'riskTypeName': 'Choking'},
          ]),
          200,
        ),
      );
      await _pumpPage(tester, _patientUser(), size: const Size(590, 3000), textScale: 0.5);
      expect(find.text('Ada Lovelace'), findsWidgets);
      expect(find.text('Phone: 555-0100'), findsOneWidget);
      expect(find.text('Email: ada@example.test'), findsOneWidget);
      expect(find.text('Date of Birth:'), findsOneWidget);
      expect(find.text('1 Test Way\nApt 2'), findsOneWidget);
      expect(find.text('Testville'), findsOneWidget);
      expect(find.text('Known Risks: Choking'), findsOneWidget);
      expect(find.text('Peanuts, Dust'), findsOneWidget);
    });

    _testPage('renders mobile layout without address', (tester) async {
      _handler = _routes(
        profile: () => http.Response(
          jsonEncode(_patientJson(withAddress: false)),
          200,
        ),
      );
      await _pumpPage(tester, _patientUser(), size: const Size(590, 3000), textScale: 0.5);
      expect(find.text('Testville'), findsNothing);
      expect(find.text('Personalization'), findsWidgets);
    });
  });

  group('PatientStatusPage caregiver view', () {
    _testPage('reads nested patient and flagged risks from response',
        (tester) async {
      final requested = <String>[];
      final base = _routes(
        profile: () => http.Response(
          jsonEncode({
            'patient': _patientJson(),
            'flaggedRisks': [
              {'riskTypeName': 'Elopement'},
              {'other': 'x'},
            ],
          }),
          200,
        ),
      );
      _handler = (r) {
        requested.add(r.url.path);
        return base(r);
      };
      await _pumpPage(tester, _caregiverUser(), patientId: 7);
      expect(
        requested.any((p) => p.endsWith('caregivers/5/patients/7')),
        isTrue,
      );
      expect(requested.any((p) => p.endsWith('/risks')), isFalse);
      expect(find.text('Known Risks: Elopement'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsWidgets);
    });

    _testPage('accepts snake_case flagged_risks for family link users',
        (tester) async {
      final body = Map<String, dynamic>.from(_patientJson())
        ..['flagged_risks'] = [
          {'riskTypeName': 'Burns'},
        ];
      _handler = _routes(profile: () => http.Response(jsonEncode(body), 200));
      await _pumpPage(tester, _caregiverUser(role: 'FAMILY_LINK'),
          patientId: 7);
      expect(find.text('Known Risks: Burns'), findsOneWidget);
    });

    _testPage('falls back to risks endpoint when response omits them',
        (tester) async {
      _handler = _routes(
        risks: () => http.Response(
          jsonEncode([
            {'riskTypeName': 'Sundowning'},
          ]),
          200,
        ),
      );
      await _pumpPage(tester, _caregiverUser(), patientId: 7);
      expect(find.text('Known Risks: Sundowning'), findsOneWidget);
    });

    _testPage('fallback risks null body leaves banner hidden',
        (tester) async {
      _handler = _routes(risks: () => http.Response('null', 200));
      await _pumpPage(tester, _caregiverUser(), patientId: 7);
      expect(find.textContaining('Known Risks'), findsNothing);
      expect(find.text('Ada Lovelace'), findsWidgets);
    });

    _testPage('patient view risks null body leaves banner hidden',
        (tester) async {
      _handler = _routes(risks: () => http.Response('null', 200));
      await _pumpPage(tester, _patientUser());
      expect(find.textContaining('Known Risks'), findsNothing);
      expect(find.text('Ada Lovelace'), findsWidgets);
    });

    _testPage('fallback risks non-200 leaves banner hidden', (tester) async {
      _handler = _routes(risks: () => http.Response('x', 404));
      await _pumpPage(tester, _caregiverUser(), patientId: 7);
      expect(find.textContaining('Known Risks'), findsNothing);
      expect(find.text('Ada Lovelace'), findsWidgets);
    });

    _testPage('fallback risks exception leaves banner hidden',
        (tester) async {
      _handler = _routes(risks: () => http.Response('not json', 200));
      await _pumpPage(tester, _caregiverUser(), patientId: 7);
      expect(find.textContaining('Known Risks'), findsNothing);
      expect(find.text('Ada Lovelace'), findsWidgets);
    });
  });

  group('PatientStatusPage personalization editing', () {
    Future<void> enterEditMode(WidgetTester tester) async {
      final edit = find.widgetWithText(ElevatedButton, 'Edit');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pump();
    }

    _testPage('edit mode shows text fields and dropdown', (tester) async {
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
    });

    _testPage('saving successfully updates values and shows snackbar',
        (tester) async {
      Map<String, dynamic>? sent;
      _handler = _routes(
        update: (r) {
          sent = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'likes': 'Chess',
                'dislikes': 'Noise',
                'habits': 'Tea',
                'phobias': 'Heights',
                'preferredCommunicationMethod': 'written',
              },
            }),
            200,
          );
        },
      );
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);

      await tester.enterText(find.byType(TextField).at(0), ' Chess ');
      await tester.enterText(find.byType(TextField).at(1), 'Noise');

      // Change preferred communication method via the dropdown.
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gesture').last);
      await tester.pumpAndSettle();

      final save = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent?['likes'], 'Chess');
      expect(sent?['dislikes'], 'Noise');
      expect(sent?['preferredCommunicationMethod'], 'gesture');
      expect(find.text('Personalization saved'), findsOneWidget);
      expect(find.text('Chess'), findsOneWidget);
      expect(find.text('Heights'), findsOneWidget);
      expect(find.text('Written'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Edit'), findsOneWidget);
    });

    _testPage('saving with a flat response body is accepted',
        (tester) async {
      _handler = _routes(
        update: (r) => http.Response(jsonEncode({'likes': 'Puzzles'}), 200),
      );
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);
      final save = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Personalization saved'), findsOneWidget);
      expect(find.text('Puzzles'), findsOneWidget);
    });

    _testPage('save failure status shows error snackbar', (tester) async {
      _handler = _routes(update: (r) => http.Response('bad', 500));
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);
      final save = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Save failed: 500'), findsOneWidget);
      // Still in edit mode.
      expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
    });

    _testPage('save exception shows error snackbar', (tester) async {
      _handler = _routes(update: (r) => throw Exception('offline'));
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);
      final save = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Save failed: '), findsOneWidget);
    });

    _testPage('shows progress indicator in button while saving',
        (tester) async {
      final pending = Completer<http.Response>();
      _handler = _routes(update: (r) => pending.future);
      await _pumpPage(tester, _patientUser());
      await enterEditMode(tester);
      final save = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ElevatedButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      pending.complete(http.Response(jsonEncode({'data': {}}), 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Personalization saved'), findsOneWidget);
    });
  });
}
