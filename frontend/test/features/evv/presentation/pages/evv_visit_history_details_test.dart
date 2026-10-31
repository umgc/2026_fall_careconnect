// Interaction tests for EvvVisitHistoryPage
// (lib/features/evv/presentation/pages/evv_visit_history.dart): search
// filters, paging, record details dialog and location rendering.

import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/evv_visit_history.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Future<http.Response> Function(http.Request) _handler;
final _client = MockClient((r) => _handler(r));

Map<String, dynamic> _record(
  int id, {
  String status = 'APPROVED',
  bool offline = false,
  String? checkinSource,
  double? lat,
  double? lng,
  String? checkoutSource,
  Map<String, dynamic>? address,
}) =>
    {
      'id': id,
      'patient': {
        'id': 50,
        'firstName': 'Ann',
        'lastName': 'Lee',
        'maNumber': 'MA-$id',
        if (address != null) 'address': address,
      },
      'serviceType': 'Service $id',
      'individualName': 'Person $id',
      'caregiverId': 7,
      'dateOfService': '2026-02-0${id}T00:00:00',
      'timeIn': '2026-02-0${id}T08:00:00',
      'timeOut': '2026-02-0${id}T09:30:00',
      'status': status,
      'stateCode': 'MD',
      'isOffline': offline,
      if (checkinSource != null) 'checkinLocationSource': checkinSource,
      if (lat != null) 'checkinLocationLat': lat,
      if (lng != null) 'checkinLocationLng': lng,
      if (checkoutSource != null) 'checkoutLocationSource': checkoutSource,
      'createdAt': '2026-02-0${id}T10:00:00',
      'updatedAt': '2026-02-0${id}T11:00:00',
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> content,
        {bool last = true, int number = 0}) =>
    {
      'content': content,
      'totalElements': 5,
      'totalPages': last ? 1 : 2,
      'size': 20,
      'number': number,
      'first': number == 0,
      'last': last,
    };

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: const EvvVisitHistoryPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => ApiServiceOffline.debugOverrideHttpClient(_client));
  tearDownAll(() => ApiServiceOffline.debugOverrideHttpClient(null));

  late List<Uri> requests;

  setUp(() {
    requests = [];
    _handler = (r) async {
      requests.add(r.url);
      final page = int.parse(r.url.queryParameters['page'] ?? '0');
      if (page == 0) {
        return http.Response(
          jsonEncode(
            _page(
              [
                _record(1,
                    status: 'UNDER_REVIEW',
                    offline: true,
                    checkinSource: 'GPS',
                    lat: 39.1,
                    lng: -76.5,
                    checkoutSource: 'GPS'),
                _record(2,
                    status: 'REJECTED',
                    checkinSource: 'PATIENT_ADDRESS',
                    checkoutSource: 'MANUAL',
                    address: {
                      'line1': '1 Main St',
                      'line2': 'Unit 4',
                      'city': 'Towson',
                      'state': 'MD',
                      'zip': '21204',
                    }),
                _record(3, status: 'DRAFT', checkinSource: 'PATIENT_ADDRESS'),
                _record(4,
                    checkinSource: 'PATIENT_ADDRESS', address: <String, dynamic>{}),
              ],
              last: false,
            ),
          ),
          200,
        );
      }
      return http.Response(jsonEncode(_page([_record(5)], number: 1)), 200);
    };
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  Future<void> openDetails(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.text('Record Details'), findsOneWidget);
  }

  Future<void> closeDetails(WidgetTester tester) async {
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders records with status chips and paging', (tester) async {
    await _pump(tester);
    expect(find.text('Found 5 records'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Person 1'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('MA: MA-1'), findsOneWidget);
    expect(find.text('08:00 - 09:30'), findsWidgets);
    expect(find.byIcon(Icons.pending), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.help), findsOneWidget);

    await tester.tap(find.text('Load More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(requests.last.queryParameters['page'], '1');
    expect(find.text('Person 5'), findsOneWidget);
    expect(find.text('Load More'), findsNothing);
  });

  testWidgets('details dialog shows GPS and offline information',
      (tester) async {
    await _pump(tester);
    await openDetails(tester, 'Person 1');
    expect(find.text('GPS: 39.100000, -76.500000'), findsOneWidget);
    expect(find.text('GPS (coordinates not available)'), findsOneWidget);
    expect(find.text('This record was created offline'), findsOneWidget);
    expect(find.text('1/2/2026 10:00'), findsOneWidget);
    await closeDetails(tester);
  });

  testWidgets('details dialog shows address and other location sources',
      (tester) async {
    await _pump(tester);
    await openDetails(tester, 'Person 2');
    expect(find.text('1 Main St, Unit 4, Towson, MD, 21204'), findsOneWidget);
    expect(find.text('MANUAL'), findsWidgets);
    await closeDetails(tester);

    await openDetails(tester, 'Person 3');
    expect(find.text('Patient Address (not available)'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    await closeDetails(tester);

    await openDetails(tester, 'Person 4');
    expect(find.text('Address not available'), findsOneWidget);
    await closeDetails(tester);
  });

  testWidgets('search sends filters and clear resets them', (tester) async {
    await _pump(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Patient Name'), 'Ann');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Service Type'), 'Bathing');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Caregiver ID'), '42');

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'State'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VA - Virginia').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(DropdownButtonFormField<String>, 'Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejected').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final q = requests.last.queryParameters;
    expect(q['patientName'], 'Ann');
    expect(q['serviceType'], 'Bathing');
    expect(q['caregiverId'], '42');
    expect(q['stateCode'], 'VA');
    expect(q['status'], 'REJECTED');

    await tester.tap(find.byTooltip('Clear Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final cleared = requests.last.queryParameters;
    expect(cleared.containsKey('patientName'), isFalse);
    expect(cleared.containsKey('stateCode'), isFalse);
  });

  testWidgets('date range picker sets start and end dates', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Select Date Range'));
    await tester.pumpAndSettle();
    // Switch to text input mode and type a range.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    await tester.enterText(
        find.widgetWithText(TextField, 'Start Date'), fmt(start));
    await tester.enterText(find.widgetWithText(TextField, 'End Date'), fmt(now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${start.day}/${start.month}/${start.year} - ${now.day}/${now.month}/${now.year}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(requests.last.queryParameters.containsKey('startDate'), isTrue);
  });

  testWidgets('search failure shows error snackbar and empty state',
      (tester) async {
    _handler = (r) async => http.Response('boom', 500);
    await _pump(tester);
    expect(find.textContaining('Error searching records:'), findsOneWidget);
    expect(find.text('No records found'), findsOneWidget);
  });
}
