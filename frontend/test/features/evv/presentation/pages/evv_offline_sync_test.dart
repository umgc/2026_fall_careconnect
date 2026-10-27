import 'package:care_connect_app/l10n/app_localizations.dart';
// Tests for EvvOfflineSyncPage
// (lib/features/evv/presentation/pages/evv_offline_sync.dart)
//
// EvvOfflineSyncPage loads the offline queue and sync status through
// EvvService (ApiServiceOffline.httpClient — injectable) and offers a
// "Sync All Offline Data" action. These tests route the offline endpoints
// through one MockClient and cover the loading, populated (including a FAILED
// item), empty, load-error, and sync-action paths.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_offline_sync.dart';

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

Map<String, dynamic> _queueItem(
  int id, {
  String status = 'PENDING',
  int attempts = 0,
  String? lastError,
  int priority = 1,
}) =>
    {
      'id': id,
      'recordId': 100 + id,
      'operationType': 'CREATE',
      'caregiverId': 1,
      'queuedAt': '2026-08-01T09:00:00.000',
      'syncAttempts': attempts,
      if (lastError != null) 'lastError': lastError,
      if (attempts > 0) 'lastSyncAttempt': '2026-08-01T09:05:00.000',
      'syncStatus': status,
      'priority': priority,
      'recordData': {'serviceType': 'Personal Care'},
    };

/// Routes the three offline endpoints. [queue]/[status] are JSON list bodies.
void _wireEvvClient({
  required String queue,
  required String status,
  int queueStatus = 200,
  int syncStatus = 200,
}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/offline/queue'))
      return http.Response(queue, queueStatus);
    if (url.contains('/offline/status')) return http.Response(status, 200);
    if (url.contains('/offline/sync')) return http.Response('ok', syncStatus);
    return http.Response('[]', 200);
  }));
}

Widget _host({Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const EvvOfflineSyncPage());

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

  testWidgets('shows the offline sync empty state in Spanish', (tester) async {
    _wireEvvClient(queue: '[]', status: '[]');
    await tester.pumpWidget(_host(locale: const Locale('es')));
    await tester.pumpAndSettle();
    expect(find.text('Sincronización sin conexión'), findsOneWidget);
    expect(find.text('Estado de sincronización'), findsOneWidget);
    expect(
        find.text('Sincronizar todos los datos sin conexión'), findsOneWidget);
    expect(find.text('Todos los datos están sincronizados'), findsOneWidget);
    expect(find.text('No hay registros sin conexión para sincronizar'),
        findsOneWidget);
  });

  testWidgets('shows a failed record in Spanish', (tester) async {
    _wireEvvClient(
        queue: jsonEncode([
          _queueItem(2, status: 'FAILED', attempts: 3, lastError: 'timeout')
        ]),
        status: '[]');
    await tester.pumpWidget(_host(locale: const Locale('es')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Intentos: 3'), findsWidgets);
    expect(find.textContaining('Error: timeout'), findsWidgets);
  });

  testWidgets('shows a loading indicator on the first frame', (tester) async {
    _wireEvvClient(queue: '[]', status: '[]');
    await tester.pumpWidget(_host());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the "Offline Sync" app bar and sync action',
      (tester) async {
    _wireEvvClient(queue: '[]', status: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('Offline Sync'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sync All Offline Data'),
        findsOneWidget);
  });

  testWidgets('shows the all-synced empty state when the queue is empty',
      (tester) async {
    _wireEvvClient(queue: '[]', status: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('All data is synced'), findsOneWidget);
    expect(find.text('No offline records to sync'), findsOneWidget);
  });

  testWidgets('lists a queued offline record', (tester) async {
    _wireEvvClient(queue: jsonEncode([_queueItem(1)]), status: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Caregiver ID: 1'), findsWidgets);
    expect(find.textContaining('Queued:'), findsWidgets);
  });

  testWidgets('renders a FAILED record with its error and retry menu',
      (tester) async {
    _wireEvvClient(
      queue: jsonEncode(
          [_queueItem(2, status: 'FAILED', attempts: 3, lastError: 'timeout')]),
      status: '[]',
    );
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Error: timeout'), findsWidgets);
    expect(find.textContaining('Attempts: 3'), findsWidgets);
  });

  testWidgets('handles a load error without crashing', (tester) async {
    _wireEvvClient(queue: 'error', status: '[]', queueStatus: 500);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('All data is synced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sync All Offline Data triggers a sync and reloads',
      (tester) async {
    _wireEvvClient(queue: jsonEncode([_queueItem(1)]), status: '[]');
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final syncBtn = find.widgetWithText(FilledButton, 'Sync All Offline Data');
    await tester.ensureVisible(syncBtn);
    await tester.tap(syncBtn);
    await tester.pumpAndSettle();

    // Sync completed and the page reloaded without error; the action is back.
    expect(find.widgetWithText(FilledButton, 'Sync All Offline Data'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens localized details for a failed offline record',
      (tester) async {
    _wireEvvClient(
      queue: jsonEncode([
        _queueItem(
          2,
          status: 'FAILED',
          attempts: 3,
          lastError: 'timeout',
          priority: 2,
        ),
      ]),
      status: '[]',
    );

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsWidgets);

    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('102'), findsWidgets);
    expect(find.text('High'), findsWidgets);
    expect(find.text('timeout'), findsWidgets);

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('retry action shows localized notification', (tester) async {
    _wireEvvClient(
      queue: jsonEncode([
        _queueItem(
          3,
          status: 'FAILED',
          attempts: 2,
          lastError: 'network timeout',
          priority: 3,
        ),
      ]),
      status: '[]',
    );

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsWidgets);

    await tester.tap(find.text('Retry').last);
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
