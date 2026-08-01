// Tests for VisitCompletedSuccessPage
// (lib/features/evv/presentation/pages/visit_completed_success_page.dart)
//
// The page loads the visit's patient via ApiService.getCaregiverPatients
// (backed by an injectable http.Client), then renders the EVV completion
// summary: a success banner, an EVV location-verification card, a
// patient/service card, and a time/duration card, plus Export EDI / Preview /
// Dashboard actions. These tests exercise the load/render states
// (loading, success, patient-not-found, API error, unauthenticated), both
// branches of the location formatter (GPS vs patient address), the duration
// and time formatting, and the EDI export/preview actions.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/evv/presentation/pages/visit_completed_success_page.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');
const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');
const MethodChannel _shareChannel =
    MethodChannel('dev.fluttercommunity.plus/share');
const MethodChannel _openFileChannel = MethodChannel('com.crazecoder.openfile');

void _setupStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  messenger.setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
  // path_provider / share / open_filex are only touched by the export path;
  // return harmless values so a tapped export never throws an uncaught error.
  messenger.setMockMethodCallHandler(_pathProviderChannel,
      (call) async => Directory.systemTemp.path);
  messenger.setMockMethodCallHandler(_shareChannel, (call) async => null);
  messenger.setMockMethodCallHandler(_openFileChannel,
      (call) async => <String, dynamic>{'type': 'done', 'message': 'ok'});
  // Swallow Clipboard writes from the Preview sheet's Copy button.
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    return null;
  });
}

void _teardownStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final ch in [
    _secureStorageChannel,
    _connectivityChannel,
    _pathProviderChannel,
    _shareChannel,
    _openFileChannel,
  ]) {
    messenger.setMockMethodCallHandler(ch, null);
  }
  messenger.setMockMethodCallHandler(SystemChannels.platform, null);
}

UserSession _caregiver() => UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    );

String _patientsJson(int id) => jsonEncode([
      {
        'id': id,
        'firstName': 'Mary',
        'lastName': 'Johnson',
        'email': 'mary@careconnect.com',
        'phone': '555-0100',
        'dob': '1950-01-01',
        'relationship': 'parent',
        'gender': 'FEMALE',
        'maNumber': 'MA123456789',
        'address': {
          'line1': '123 Main St',
          'city': 'Richmond',
          'state': 'VA',
          'zip': '23220',
        },
      }
    ]);

VisitCompletedSuccessPage _page({
  int patientId = 42,
  String checkinType = 'gps',
  String checkoutType = 'gps',
  double? checkinLat = 38.900000,
  double? checkinLng = -77.000000,
  double? checkoutLat = 38.900000,
  double? checkoutLng = -77.000000,
  int duration = 3600,
  String notes = 'Administered morning medications',
}) =>
    VisitCompletedSuccessPage(
      patientId: patientId,
      serviceType: 'Personal Care',
      checkinLocationType: checkinType,
      checkoutLocationType: checkoutType,
      checkinLatitude: checkinLat,
      checkinLongitude: checkinLng,
      checkoutLatitude: checkoutLat,
      checkoutLongitude: checkoutLng,
      notes: notes,
      duration: duration,
      checkinTime: DateTime(2026, 8, 1, 9, 0, 0),
      checkoutTime: DateTime(2026, 8, 1, 10, 0, 0),
    );

Widget _host({UserSession? user, required VisitCompletedSuccessPage page}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    initialLocation: '/visit-success',
    routes: [
      GoRoute(path: '/visit-success', builder: (_, __) => page),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
      GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const Scaffold(body: Text('SELECT PATIENT'))),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
  });

  tearDown(() {
    _teardownStubs();
    ApiService.debugResetHttpClient();
  });

  group('VisitCompletedSuccessPage - load states', () {
    testWidgets('shows a loading indicator while the patient loads',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('renders the "Visit Completed" app bar', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.text('Visit Completed'), findsOneWidget);
    });

    testWidgets('renders the success summary when the patient is found',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      expect(find.text('Visit completed and ready for submission'),
          findsOneWidget);
      expect(find.text('Mary Johnson'), findsOneWidget);
      expect(find.text('Personal Care'), findsOneWidget);
      expect(find.text('EVV Location Verification'), findsOneWidget);
      expect(find.text('EVV compliance confirmed for this visit.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the error state when the API returns 500',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response('server error', 500)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows the patient-not-found state when the id is absent',
        (tester) async {
      // The list holds patient id 7, but the page requested id 42.
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(7), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      expect(find.text('Error Loading Patient'), findsOneWidget);
    });

    testWidgets('shows an error when there is no authenticated user',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(page: _page())); // no user
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Try Again re-requests the patient after an error',
        (tester) async {
      var calls = 0;
      ApiService.debugSetHttpClient(MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('server error', 500)
            : http.Response(_patientsJson(42), 200);
      }));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Mary Johnson'), findsOneWidget);
      expect(calls, 2);
    });
  });

  group('VisitCompletedSuccessPage - location formatting', () {
    testWidgets('formats GPS check-in/out with coordinates and GPS badges',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      expect(find.textContaining('GPS 38.900000, -77.000000'), findsWidgets);
      expect(find.text('GPS'), findsWidgets); // location badges
    });

    testWidgets('formats a patient-address check-in with the address label',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(
        user: _caregiver(),
        page: _page(checkinType: 'address', checkoutType: 'address'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PATIENT ADDRESS'), findsWidgets);
      expect(find.textContaining('123 Main St, Richmond, VA, 23220'),
          findsWidgets);
    });
  });

  group('VisitCompletedSuccessPage - time & duration', () {
    testWidgets('renders check-in/out times and total duration',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(
          _host(user: _caregiver(), page: _page(duration: 3600)));
      await tester.pumpAndSettle();

      expect(find.text('9:00:00 AM'), findsOneWidget); // check-in
      expect(find.text('10:00:00 AM'), findsOneWidget); // check-out
      expect(find.text('60m'), findsOneWidget); // 3600s total
      expect(find.textContaining('01:00:00'), findsOneWidget); // detailed
    });
  });

  group('VisitCompletedSuccessPage - EDI actions', () {
    testWidgets('Export EDI generates and exports without crashing',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      final exportBtn = find.widgetWithText(OutlinedButton, 'Export EDI');
      expect(exportBtn, findsOneWidget);
      await tester.ensureVisible(exportBtn);

      // The export writes a real temp file and calls plugin channels, so it
      // needs the real event loop; runAsync lets those awaits complete. The
      // EDI content is generated at the top of the handler and the page's own
      // try/catch keeps any plugin gap from throwing uncaught.
      await tester.runAsync(() async {
        await tester.tap(exportBtn);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Visit Completed'), findsOneWidget); // still on the page
    });

    testWidgets('Preview opens an EDI bottom sheet with a Copy action',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      final previewBtn = find.widgetWithText(OutlinedButton, 'Preview');
      expect(previewBtn, findsOneWidget);
      await tester.ensureVisible(previewBtn);
      await tester.tap(previewBtn);
      await tester.pumpAndSettle();

      expect(find.text('Preview EDI'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Copy'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Copy'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
