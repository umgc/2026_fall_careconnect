// Tests for EvvCorrectionsPage
// (lib/features/evv/presentation/pages/evv_corrections.dart)
//
// EvvCorrectionsPage loads pending EVV corrections and pending EOR approvals
// through EvvService (which uses ApiServiceOffline.httpClient — an injectable
// client) and presents them in two tabs, each with an approval dialog. These
// tests route both endpoints through a single MockClient and cover the
// loading, populated, empty, and error states, tab switching, and opening the
// correction-approval dialog.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_corrections.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

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
}

void _teardownStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureStorageChannel, null);
  messenger.setMockMethodCallHandler(_connectivityChannel, null);
}

Map<String, dynamic> _rec(int id) => {
      'id': id,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'COMPLETED',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    };

Map<String, dynamic> _corr(int id) => {
      'id': id,
      'originalRecord': _rec(1),
      'correctedRecord': _rec(1),
      'reasonCode': 'SCHEDULE_CHANGE',
      'explanation': 'Adjusted check-in time',
      'correctedBy': 7,
      'correctedAt': '2026-08-01T11:00:00.000',
      'approvalRequired': true,
      'originalValues': {'timeIn': '09:00'},
      'correctedValues': {'timeIn': '09:15'},
    };

/// Routes the two endpoints EvvCorrectionsPage loads. [corrections]/[eor] are
/// the JSON list bodies; [correctionsStatus] lets a test force a load error.
void _wireEvvClient({
  required String corrections,
  required String eor,
  int correctionsStatus = 200,
}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/corrections/pending')) {
      return http.Response(corrections, correctionsStatus);
    }
    if (url.contains('/records/pending-eor-approvals')) {
      return http.Response(eor, 200);
    }
    return http.Response('[]', 200);
  }));
}

/// Like [_wireEvvClient] but also answers the approve endpoints so the
/// approval actions run end to end. Set [approveStatus] to force a failure.
void _wireWithApprovals({
  String? corrections,
  String? eor,
  int approveStatus = 200,
}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/corrections/pending')) {
      return http.Response(corrections ?? jsonEncode([_corr(1)]), 200);
    }
    if (url.contains('/records/pending-eor-approvals')) {
      return http.Response(eor ?? jsonEncode([_rec(5)]), 200);
    }
    if (url.contains('/corrections/') && url.contains('/approve')) {
      return http.Response(jsonEncode(_corr(1)), approveStatus);
    }
    if (url.contains('/records/eor-approve')) {
      return http.Response(jsonEncode(_rec(5)), approveStatus);
    }
    return http.Response('[]', 200);
  }));
}

Widget _host() => const MaterialApp(home: EvvCorrectionsPage());

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
    _wireEvvClient(corrections: '[]', eor: '[]');
    await tester.pumpWidget(_host());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the app bar and both tabs', (tester) async {
    _wireEvvClient(corrections: jsonEncode([_corr(1)]), eor: jsonEncode([_rec(5)]));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('EVV Corrections & Approvals'), findsOneWidget);
    expect(find.text('Corrections (1)'), findsOneWidget);
    expect(find.text('EOR Approvals (1)'), findsOneWidget);
  });

  testWidgets('lists a pending correction with its reason', (tester) async {
    _wireEvvClient(corrections: jsonEncode([_corr(1)]), eor: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Reason: SCHEDULE_CHANGE'), findsOneWidget);
    expect(find.text('Corrections (1)'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no corrections',
      (tester) async {
    _wireEvvClient(corrections: '[]', eor: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('No pending corrections'), findsOneWidget);
  });

  testWidgets('handles a load error without crashing', (tester) async {
    _wireEvvClient(corrections: 'error', eor: '[]', correctionsStatus: 500);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Load failed → not stuck on the spinner, and the empty corrections tab shows.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No pending corrections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to the EOR tab shows pending approvals',
      (tester) async {
    _wireEvvClient(corrections: '[]', eor: jsonEncode([_rec(5)]));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('EOR Approvals (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('State: VA'), findsWidgets);
  });

  testWidgets('tapping a correction opens the approval dialog', (tester) async {
    _wireEvvClient(corrections: jsonEncode([_corr(1)]), eor: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Approve Correction'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('approving a correction removes it and confirms', (tester) async {
    _wireWithApprovals(eor: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();

    // _approveCorrection ran: success snackbar, correction removed from the tab.
    expect(find.textContaining('Correction approved successfully'), findsWidgets);
    expect(find.text('No pending corrections'), findsOneWidget);
    tester.takeException();
  });

  testWidgets('a failed correction approval surfaces an error', (tester) async {
    _wireWithApprovals(eor: '[]', approveStatus: 500);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error approving correction'), findsWidgets);
    tester.takeException();
  });

  testWidgets('approving an EOR record completes successfully', (tester) async {
    _wireWithApprovals(corrections: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('EOR Approvals (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Approve EOR'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('EOR approval completed successfully'),
        findsWidgets);
    tester.takeException();
  });
}
