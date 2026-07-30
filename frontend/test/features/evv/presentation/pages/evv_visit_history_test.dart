// Tests for EvvVisitHistoryPage
// (lib/features/evv/presentation/pages/evv_visit_history.dart)
//
// EvvVisitHistoryPage auto-runs a paginated record search on load (via
// EvvService.searchRecords, backed by ApiServiceOffline.httpClient) and offers
// filter fields plus a Search action. These tests route /records/search
// through a MockClient and cover the loading, populated, empty, error, and
// re-search paths. The page's drawer reads UserProvider, so the host supplies
// one.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_visit_history.dart';

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

UserSession _caregiver() => UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    );

Map<String, dynamic> _rec(int id) => {
      'id': id,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'APPROVED',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    };

String _result({int count = 1, bool last = true}) => jsonEncode({
      'content': [for (var i = 0; i < count; i++) _rec(i + 1)],
      'totalElements': count,
      'totalPages': count == 0 ? 0 : 1,
      'size': 20,
      'number': 0,
      'first': true,
      'last': last,
    });

void _wireSearch(String body, {int statusCode = 200}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    if (req.url.toString().contains('/records/search')) {
      return http.Response(body, statusCode);
    }
    return http.Response('[]', 200);
  }));
}

Widget _host() {
  final provider = UserProvider()..setUser(_caregiver());
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: EvvVisitHistoryPage()),
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
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  testWidgets('shows a loading indicator while the initial search runs',
      (tester) async {
    _wireSearch(_result());
    await tester.pumpWidget(_host());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the "EVV Visit History" app bar', (tester) async {
    _wireSearch(_result());
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.text('EVV Visit History'), findsWidgets);
  });

  testWidgets('renders a results header and the Search action', (tester) async {
    _wireSearch(_result(count: 2));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Found 2 records'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Search'), findsWidgets);
  });

  testWidgets('shows the empty state when no records match', (tester) async {
    _wireSearch(_result(count: 0));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Try adjusting your search filters'),
        findsOneWidget);
  });

  testWidgets('handles a search error without crashing', (tester) async {
    _wireSearch('error', statusCode: 500);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Try adjusting your search filters'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Search runs another search', (tester) async {
    var searches = 0;
    ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
      if (req.url.toString().contains('/records/search')) {
        searches++;
        return http.Response(_result(), 200);
      }
      return http.Response('[]', 200);
    }));

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(searches, 1); // initial auto-search

    final searchBtn = find.widgetWithText(TextButton, 'Search').first;
    await tester.ensureVisible(searchBtn);
    await tester.tap(searchBtn);
    await tester.pumpAndSettle();

    expect(searches, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a record opens the details dialog', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _wireSearch(_result(count: 1));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final tile = find.text('Mary Johnson').first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // _showRecordDetails built the dialog (detail rows + location sections).
    expect(find.text('Record Details'), findsOneWidget);
    expect(find.text('Service Type'), findsWidgets);
    expect(find.text('Check-In Location'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Record Details'), findsNothing);
    tester.takeException();
  });

  testWidgets('Load More fetches the next page', (tester) async {
    var searches = 0;
    ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
      if (req.url.toString().contains('/records/search')) {
        searches++;
        // First page has more; the next page is the last.
        return http.Response(_result(count: 1, last: searches > 1), 200);
      }
      return http.Response('[]', 200);
    }));

    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(searches, 1);

    final loadMore = find.widgetWithText(ElevatedButton, 'Load More');
    expect(loadMore, findsOneWidget);
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(searches, 2); // _loadMore ran _performSearch(resetPage: false)
    expect(find.widgetWithText(ElevatedButton, 'Load More'), findsNothing);
    tester.takeException();
  });

  testWidgets('the Clear Filters action re-runs the search', (tester) async {
    var searches = 0;
    ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
      if (req.url.toString().contains('/records/search')) {
        searches++;
        return http.Response(_result(count: 1), 200);
      }
      return http.Response('[]', 200);
    }));

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(searches, 1);

    await tester.tap(find.byTooltip('Clear Filters'));
    await tester.pumpAndSettle();

    expect(searches, 2); // _clearFilters calls _performSearch
    tester.takeException();
  });
}
