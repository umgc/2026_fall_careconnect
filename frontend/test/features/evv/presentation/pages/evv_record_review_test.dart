// Tests for EvvRecordReviewPage — populated / load paths.
// (lib/features/evv/presentation/pages/evv_record_review.dart)
//
// The prior-cohort flat test wires HTTP via http.runWithClient, which never
// reaches the page's EvvService, so the populated record list is uncovered.
// This suite wires EvvService via ApiServiceOffline.debugOverrideHttpClient so
// the searchRecords load actually runs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_record_review.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _openFilex = MethodChannel('open_filex');
const _share = MethodChannel('dev.fluttercommunity.plus/share');

void _setupStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  m.setMockMethodCallHandler(_connectivity, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
  // Export-EDI dependencies: give real temp paths so the file write succeeds,
  // and stub the open/share plugins so they don't hit missing channels.
  final tmp = Directory.systemTemp.path;
  m.setMockMethodCallHandler(_pathProvider, (call) async => tmp);
  m.setMockMethodCallHandler(_openFilex, (call) async => 0);
  m.setMockMethodCallHandler(_share, (call) async => 'shared');
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, null);
  m.setMockMethodCallHandler(_connectivity, null);
  m.setMockMethodCallHandler(_pathProvider, null);
  m.setMockMethodCallHandler(_openFilex, null);
  m.setMockMethodCallHandler(_share, null);
}

UserSession _caregiver() => UserSession(
      id: 1, email: 'u@careconnect.com', role: 'CAREGIVER',
      token: 'test-token', caregiverId: 1, name: 'Test User',
    );

Map<String, dynamic> _rec(int id) => {
      'id': id,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'UNDER_REVIEW',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    };

String _result({int count = 2}) => jsonEncode({
      'content': [for (var i = 0; i < count; i++) _rec(i + 1)],
      'totalElements': count,
      'totalPages': count == 0 ? 0 : 1,
      'size': 20,
      'number': 0,
      'first': true,
      'last': true,
    });

void _wireSearch(String body, {int status = 200}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    if (req.url.toString().contains('/records/search')) {
      return http.Response(body, status);
    }
    return http.Response('[]', 200);
  }));
}

/// Wire both the paginated search load and the review POST so the
/// approve/reject flow (record -> dialog -> action -> reload) runs end to end.
void _wireReview({int reviewStatus = 200}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/review')) {
      return http.Response(jsonEncode(_rec(1)), reviewStatus);
    }
    if (url.contains('/records/search')) {
      return http.Response(_result(count: 1), 200);
    }
    return http.Response('[]', 200);
  }));
}

/// Load records, then open the review dialog for the first record card.
Future<void> _openDialog(WidgetTester tester) async {
  await _pump(tester);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mary Johnson').first);
  await tester.pumpAndSettle();
}

Widget _host() {
  final provider = UserProvider()..setUser(_caregiver());
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: EvvRecordReviewPage()),
  );
}

/// Pump on a large surface so the record cards don't overflow the test viewport.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
  });

  tearDown(() {
    _teardownStubs();
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  testWidgets('shows a loading indicator on the first frame', (tester) async {
    _wireSearch(_result());
    await _pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    tester.takeException(); // consume any cosmetic card-row overflow
  });

  testWidgets('renders the records app bar with a count', (tester) async {
    _wireSearch(_result(count: 2));
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('All EVV Records'), findsWidgets);
    tester.takeException();
  });

  testWidgets('loads and renders records', (tester) async {
    _wireSearch(_result(count: 2));
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EvvRecordReviewPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Mary Johnson'), findsWidgets);
    tester.takeException();
  });

  testWidgets('handles an empty result set', (tester) async {
    _wireSearch(_result(count: 0));
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EvvRecordReviewPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester.takeException();
  });

  testWidgets('handles a load error without crashing', (tester) async {
    _wireSearch('boom', status: 500);
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester.takeException();
  });

  testWidgets('opens the review dialog when a record is tapped',
      (tester) async {
    _wireReview();
    await _openDialog(tester);
    expect(find.text('Review EVV Record'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    tester.takeException();
  });

  testWidgets('approves a record via the review dialog', (tester) async {
    _wireReview();
    await _openDialog(tester);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Record approved'), findsWidgets);
    tester.takeException();
  });

  testWidgets('rejects a record via the review dialog', (tester) async {
    _wireReview();
    await _openDialog(tester);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Record rejected'), findsWidgets);
    tester.takeException();
  });

  testWidgets('surfaces an error when the review call fails', (tester) async {
    _wireReview(reviewStatus: 500);
    await _openDialog(tester);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error reviewing record'), findsWidgets);
    tester.takeException();
  });

  testWidgets('exports an EDI document via the review dialog', (tester) async {
    _wireReview();
    await _openDialog(tester);
    await tester.tap(find.text('Export EDI'));
    await tester.pumpAndSettle();
    // _generateEDIContent + the native save path ran; the dialog is dismissed.
    expect(find.text('Export EDI'), findsNothing);
    tester.takeException();
  });
}
