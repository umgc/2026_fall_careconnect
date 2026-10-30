// Happy-path tests for the EVV admin pages
// (lib/features/evv/presentation/pages/evv_dashboard.dart,
//  evv_corrections.dart, evv_offline_sync.dart) with populated data.

import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/evv_corrections.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_dashboard.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_offline_sync.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

Map<String, dynamic> _record(int id) => {
      'id': id,
      'patient': {'id': 3, 'firstName': 'Al', 'lastName': 'Ray', 'maNumber': 'MA-3'},
      'serviceType': 'Companionship',
      'individualName': 'Al Ray',
      'caregiverId': 2,
      'dateOfService': '2026-04-02T00:00:00',
      'timeIn': '2026-04-02T09:00:00',
      'timeOut': '2026-04-02T10:00:00',
      'status': 'UNDER_REVIEW',
      'stateCode': 'MD',
      'createdAt': '2026-04-02T11:00:00',
      'updatedAt': '2026-04-02T11:00:00',
    };

Map<String, dynamic> _correction() => {
      'id': 1,
      'originalRecord': _record(1),
      'correctedRecord': _record(1),
      'reasonCode': 'TIME_ADJUSTMENT',
      'explanation': 'Clock skew',
      'correctedBy': 2,
      'correctedAt': '2026-04-03T08:00:00',
      'originalValues': {'timeIn': '09:00'},
      'correctedValues': {'timeIn': '09:15'},
    };

Map<String, dynamic> _queueItem(int id, String status, int priority) => {
      'id': id,
      'recordId': 100 + id,
      'operationType': 'CREATE',
      'caregiverId': 2,
      'deviceId': 'device-1',
      'queuedAt': '2026-04-04T07:00:00',
      'syncAttempts': 2,
      'lastSyncAttempt': '2026-04-04T07:30:00',
      'syncStatus': status,
      'lastError': status == 'FAILED' ? 'timeout' : null,
      'priority': priority,
      'recordData': {'k': 'v'},
    };

final _requests = <String>[];

Future<http.Response> _handle(http.Request r) async {
  _requests.add('${r.method} ${r.url.path}');
  final p = r.url.path;
  if (p.endsWith('/records/pending-eor-approvals')) {
    return http.Response(jsonEncode([_record(5)]), 200);
  }
  if (p.endsWith('/corrections/pending')) {
    return http.Response(jsonEncode([_correction()]), 200);
  }
  if (p.endsWith('/offline/queue')) {
    return http.Response(
      jsonEncode([
        _queueItem(1, 'FAILED', 1),
        _queueItem(2, 'PENDING', 2),
        _queueItem(3, 'SYNCED', 3),
      ]),
      200,
    );
  }
  if (p.endsWith('/records/eor-approve')) {
    return http.Response(jsonEncode(_record(5)), 200);
  }
  if (p.contains('/corrections/') && p.endsWith('/approve')) {
    return http.Response(jsonEncode(_correction()), 200);
  }
  if (p.endsWith('/records/search')) {
    return http.Response(
      jsonEncode({
        'content': [],
        'totalElements': 0,
        'totalPages': 0,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      }),
      200,
    );
  }
  return http.Response('[]', 200);
}

final _client = MockClient(_handle);

Future<void> _pump(WidgetTester tester, Widget page,
    {String role = 'ADMIN'}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser: MockUser(id: 1, role: role, caregiverId: 2),
      ),
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        // The test font is wider than real fonts; shrink text to avoid
        // overflow reports in the dashboard tiles.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.7)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    ApiServiceOffline.debugOverrideHttpClient(_client);
    ApiService.debugSetHttpClient(_client);
  });
  tearDownAll(() => ApiServiceOffline.debugOverrideHttpClient(null));

  setUp(() {
    _requests.clear();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  group('EvvDashboard (admin with data)', () {
    testWidgets('shows pending items and offline queue', (tester) async {
      await _pump(tester, const EvvDashboard());
      expect(find.text('EOR Approvals'), findsOneWidget);
      expect(find.text('Corrections'), findsOneWidget);
      expect(find.text('3 records waiting to sync'), findsOneWidget);
      expect(find.byTooltip('Offline Sync'), findsOneWidget);
      // The approvals tile has no destination yet; tapping it is a no-op.
      await tester.tap(find.text('EOR Approvals'));
      await tester.pump();
    });

    // Each navigation target is checked in its own test: tap it once and
    // confirm a route was pushed on top of the dashboard.
    const targets = <String, List<String>>{
      'ADMIN': [
        'text:Corrections',
        'text:Sync Now',
        'tooltip:Offline Sync',
        'text:Submit to HHAExchange',
        'text:Visit History',
        'text:Manage Corrections',
        'last:Offline Sync',
      ],
      'CAREGIVER': ['text:Start Visit', 'text:Review Records', 'fab:'],
      'PATIENT': ['text:Visit Schedules'],
    };

    Finder finderFor(String spec) {
      final kind = spec.split(':').first;
      final value = spec.substring(kind.length + 1);
      switch (kind) {
        case 'tooltip':
          return find.byTooltip(value);
        case 'last':
          return find.text(value).last;
        case 'fab':
          return find.byType(FloatingActionButton);
        default:
          return find.text(value).first;
      }
    }

    targets.forEach((role, specs) {
      for (final spec in specs) {
        testWidgets('$role dashboard target $spec pushes a page',
            (tester) async {
          await _pump(tester, const EvvDashboard(), role: role);
          final target = finderFor(spec);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            find.byType(EvvDashboard, skipOffstage: false),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(
            Navigator.of(tester.element(find.byType(EvvDashboard,
                    skipOffstage: false)))
                .canPop(),
            isTrue,
          );
        });
      }
    });
  });

  group('EvvCorrectionsPage', () {
    testWidgets('approves a correction', (tester) async {
      await _pump(tester, const EvvCorrectionsPage());
      expect(find.text('Corrections (1)'), findsOneWidget);
      expect(find.text('Reason: TIME_ADJUSTMENT'), findsOneWidget);
      await tester.tap(find.text('Reason: TIME_ADJUSTMENT'));
      await tester.pumpAndSettle();
      expect(find.text('Approve Correction'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Correction approved successfully'), findsOneWidget);
      expect(_requests.any((r) => r.endsWith('/corrections/1/approve')),
          isTrue);
    });

    testWidgets('approves an EOR record', (tester) async {
      await _pump(tester, const EvvCorrectionsPage());
      await tester.tap(find.text('EOR Approvals (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Al Ray'));
      await tester.pumpAndSettle();
      expect(find.text('Approve EOR'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('EOR approval completed successfully'), findsOneWidget);
    });
  });

  group('EvvOfflineSyncPage', () {
    testWidgets('shows queue items, details and retry', (tester) async {
      await _pump(tester, const EvvOfflineSyncPage());
      expect(find.text('Error: timeout'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details').last);
      await tester.pumpAndSettle();
      expect(find.text('Offline Queue Item Details'), findsOneWidget);
      expect(find.text('device-1'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry').last);
      await tester.pumpAndSettle();
      expect(find.text('Retry functionality would be implemented here'),
          findsOneWidget);
    });
  });
}
