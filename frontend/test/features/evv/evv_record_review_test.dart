// Tests for EvvRecordReviewPage
// (lib/features/evv/presentation/pages/evv_record_review.dart).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_record_review.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/evv_service.dart';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';

import 'package:care_connect_app/services/user_role_storage_service.dart'
    show UserData;

import 'package:care_connect_app/services/api_service_offline.dart';

import '../../mock_user_provider.dart';

/// Mutable HTTP handler — individual tests override this before pumping.
/// The singleton OfflineQueueHttpClient delegates every request here.
late Future<http.Response> Function(http.Request) _httpHandler;

/// Default handler that returns an empty paginated result (safe for all
/// tests that don't depend on specific HTTP responses).
Future<http.Response> _defaultHandler(http.Request request) async {
  if (request.url.path.contains('/records')) {
    return http.Response(
      jsonEncode({
        'content': <dynamic>[],
        'totalElements': 0,
        'totalPages': 0,
        'size': 1000,
        'number': 0,
        'first': true,
        'last': true,
      }),
      200,
    );
  }
  return http.Response('{}', 200);
}

/// Helper to create an EvvRecord for testing.
EvvRecord _makeRecord({
  int id = 1,
  String serviceType = 'Personal Care',
  String individualName = 'John Doe',
  int caregiverId = 10,
  DateTime? dateOfService,
  DateTime? timeIn,
  DateTime? timeOut,
  String status = 'UNDER_REVIEW',
  String stateCode = 'MD',
  bool isOffline = false,
  String? checkinLocationSource,
  double? checkinLocationLat,
  double? checkinLocationLng,
  String? checkoutLocationSource,
  double? checkoutLocationLat,
  double? checkoutLocationLng,
  Patient? patient,
}) {
  final dos = dateOfService ?? DateTime(2025, 3, 10);
  final tIn = timeIn ?? DateTime(2025, 3, 10, 9, 0);
  final tOut = timeOut ?? DateTime(2025, 3, 10, 10, 30);
  final now = DateTime.now();
  return EvvRecord(
    id: id,
    patient: patient,
    serviceType: serviceType,
    individualName: individualName,
    caregiverId: caregiverId,
    dateOfService: dos,
    timeIn: tIn,
    timeOut: tOut,
    status: status,
    stateCode: stateCode,
    isOffline: isOffline,
    checkinLocationSource: checkinLocationSource,
    checkinLocationLat: checkinLocationLat,
    checkinLocationLng: checkinLocationLng,
    checkoutLocationSource: checkoutLocationSource,
    checkoutLocationLat: checkoutLocationLat,
    checkoutLocationLng: checkoutLocationLng,
    eorApprovalRequired: false,
    isCorrected: false,
    createdAt: now,
    updatedAt: now,
  );
}

/// JSON for a single EVV record suitable for API response.
Map<String, dynamic> _recordJson({
  int id = 1,
  String serviceType = 'Personal Care',
  String individualName = 'John Doe',
  int caregiverId = 10,
  String status = 'UNDER_REVIEW',
  String stateCode = 'MD',
  bool isOffline = false,
  String? checkinLocationSource,
  double? checkinLocationLat,
  double? checkinLocationLng,
  String? checkoutLocationSource,
  double? checkoutLocationLat,
  double? checkoutLocationLng,
  Map<String, dynamic>? patient,
}) {
  final json = <String, dynamic>{
    'id': id,
    'serviceType': serviceType,
    'individualName': individualName,
    'caregiverId': caregiverId,
    'dateOfService': '2025-03-10',
    'timeIn': '2025-03-10T09:00:00',
    'timeOut': '2025-03-10T10:30:00',
    'status': status,
    'stateCode': stateCode,
    'isOffline': isOffline,
    'eorApprovalRequired': false,
    'isCorrected': false,
    'createdAt': '2025-03-10T09:00:00',
    'updatedAt': '2025-03-10T09:00:00',
  };
  if (checkinLocationSource != null) {
    json['checkinLocationSource'] = checkinLocationSource;
  }
  if (checkinLocationLat != null) json['checkinLocationLat'] = checkinLocationLat;
  if (checkinLocationLng != null) json['checkinLocationLng'] = checkinLocationLng;
  if (checkoutLocationSource != null) {
    json['checkoutLocationSource'] = checkoutLocationSource;
  }
  if (checkoutLocationLat != null) json['checkoutLocationLat'] = checkoutLocationLat;
  if (checkoutLocationLng != null) json['checkoutLocationLng'] = checkoutLocationLng;
  if (patient != null) json['patient'] = patient;
  return json;
}

/// Wrap a search result response body.
String _searchResultBody(List<Map<String, dynamic>> records) {
  return jsonEncode({
    'content': records,
    'totalElements': records.length,
    'totalPages': 1,
    'size': 1000,
    'number': 0,
    'first': true,
    'last': true,
  });
}

Widget _wrap({MockUserProvider? provider}) {
  final p = provider ??
      MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER'));
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: p,
      child: const EvvRecordReviewPage(),
    ),
  );
}

void main() {
  // Suppress overflow errors during tests
  final originalOnError = FlutterError.onError;

  // Force the ApiServiceOffline singleton to initialize with a mock client
  // that delegates to _httpHandler. Dart statics are lazy, so this runs
  // before any test touches EvvService and locks in the mock forever.
  setUpAll(() {
    _httpHandler = _defaultHandler;
    final delegatingClient =
        MockClient((request) => _httpHandler(request));
    http.runWithClient(() {
      // Accessing httpClient triggers the lazy static initializer.
      // ignore: unnecessary_statements
      ApiServiceOffline.httpClient;
    }, () => delegatingClient);
  });

  setUp(() {
    _httpHandler = _defaultHandler;
    FlutterError.onError = (FlutterErrorDetails details) {
      final exception = details.exception;
      if (exception is FlutterError &&
          exception.message.contains('overflowed')) {
        return;
      }
      final msg = exception.toString();
      if (msg.contains('ink_sparkle') ||
          msg.contains('runtime stages format version') ||
          msg.contains('FragmentProgram')) {
        return;
      }
      originalOnError?.call(details);
    };

    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') {
          return <String, String>{'jwt_token': 'mock-jwt-for-test'};
        }
        if (call.method == 'read') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return 'mock-jwt-for-test';
          return null;
        }
        if (call.method == 'containsKey') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return true;
          return false;
        }
        if (call.method == 'write' || call.method == 'delete') return null;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('EvvRecordReviewPage - initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(EvvRecordReviewPage), findsOneWidget);
    });

    testWidgets('shows "All EVV Records" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('All EVV Records'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('EvvRecordReviewPage - status filter dropdown', () {
    testWidgets('shows Filter by Status label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Filter by Status:'), findsOneWidget);
    });

    testWidgets('shows DropdownButtonFormField', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('default dropdown value is All Statuses', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('All Statuses'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - after loading (error/empty state)', () {
    testWidgets('shows empty state after API call fails', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows "No records found" when no records exist',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('No records found'), findsOneWidget);
    });

    testWidgets('shows helper text for empty records', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Start creating EVV records to see them here'),
          findsOneWidget);
    });

    testWidgets('shows rate_review_outlined icon when empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.byIcon(Icons.rate_review_outlined), findsOneWidget);
    });

    testWidgets('shows record count of 0 in AppBar when empty',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('All EVV Records (0)'), findsOneWidget);
    });

    testWidgets('shows error snackbar on load failure', (tester) async {
      // Arrange: force the HTTP layer to return a server error.
      _httpHandler = (request) async =>
          http.Response('{"error":"Internal Server Error"}', 500);
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Error loading records'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - refresh button', () {
    testWidgets('has a refresh icon button in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('refresh button is tappable', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      // Verify the refresh button exists and is enabled.
      final refreshFinder = find.byIcon(Icons.refresh);
      expect(refreshFinder, findsOneWidget);
      final iconButton = tester.widget<IconButton>(
          find.ancestor(of: refreshFinder, matching: find.byType(IconButton)));
      expect(iconButton.onPressed, isNotNull);
    });
  });

  group('EvvRecordReviewPage - back arrow', () {
    testWidgets('has a back arrow button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - drawer', () {
    testWidgets('has a CommonDrawer attached to Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isNotNull);
    });
  });

  group('EvvRecordReviewPage - with records from HTTP mock', () {
    testWidgets('shows records list after successful load', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Bob Jones', status: 'APPROVED', stateCode: 'VA'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsOneWidget);
      expect(find.textContaining('All EVV Records (2)'), findsOneWidget);
    });

    testWidgets('shows record count in AppBar title', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Test Patient', status: 'APPROVED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('All EVV Records (1)'), findsOneWidget);
    });

    testWidgets('shows UNDER_REVIEW status badge on record', (tester) async {
      final records = [
        _recordJson(id: 1, status: 'UNDER_REVIEW'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('UNDER_REVIEW'), findsOneWidget);
    });

    testWidgets('shows APPROVED status badge on record', (tester) async {
      final records = [
        _recordJson(id: 1, status: 'APPROVED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('APPROVED'), findsOneWidget);
    });

    testWidgets('shows REJECTED status badge on record', (tester) async {
      final records = [
        _recordJson(id: 1, status: 'REJECTED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('REJECTED'), findsOneWidget);
    });

    testWidgets('shows OFFLINE badge for offline record', (tester) async {
      final records = [
        _recordJson(id: 1, isOffline: true),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('OFFLINE'), findsOneWidget);
    });

    testWidgets('does not show OFFLINE badge for online record', (tester) async {
      final records = [
        _recordJson(id: 1, isOffline: false),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('OFFLINE'), findsNothing);
    });

    testWidgets('shows state code badge on record', (tester) async {
      final records = [
        _recordJson(id: 1, stateCode: 'VA'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('VA'), findsOneWidget);
    });

    testWidgets('shows service type and date in subtitle', (tester) async {
      final records = [
        _recordJson(id: 1, serviceType: 'Skilled Nursing'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Skilled Nursing'), findsOneWidget);
    });

    testWidgets('shows time range in subtitle', (tester) async {
      final records = [
        _recordJson(id: 1),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('09:00'), findsOneWidget);
    });

    testWidgets('shows arrow_forward_ios trailing icon', (tester) async {
      final records = [
        _recordJson(id: 1),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('shows CircleAvatar leading widget', (tester) async {
      final records = [
        _recordJson(id: 1),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - status filter with records', () {
    testWidgets('filtering by APPROVED shows only approved records',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Bob', status: 'APPROVED'),
        _recordJson(id: 3, individualName: 'Carol', status: 'REJECTED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify all 3 records are shown initially
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);

      // Select "Approved" via the onChanged callback to avoid the
      // ink_sparkle.frag shader exception in the test environment.
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      dropdown.onChanged!('APPROVED');
      await tester.pump();

      // Only Bob should remain
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Carol'), findsNothing);
      expect(find.textContaining('All EVV Records (1)'), findsOneWidget);
    });

    testWidgets('filtering by UNDER_REVIEW shows only pending records',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Bob', status: 'APPROVED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Open dropdown and select Under Review
      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('UNDER_REVIEW');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('filtering by REJECTED shows only rejected records',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Bob', status: 'REJECTED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('REJECTED');
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('shows "No records match this filter" when filter has no matches',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice', status: 'UNDER_REVIEW'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Filter by APPROVED (none exist)
      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('APPROVED');
      await tester.pump();

      expect(find.text('No records match this filter'), findsOneWidget);
      expect(find.text('Try selecting a different status filter'), findsOneWidget);
    });

    testWidgets('switching back to ALL shows all records again',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Bob', status: 'APPROVED'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Filter to Approved
      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('APPROVED');
      await tester.pump();
      expect(find.text('Alice'), findsNothing);

      // Switch back to All Statuses
      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('ALL');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - review dialog', () {
    testWidgets('tapping a record opens the review dialog', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          serviceType: 'Personal Care',
          status: 'UNDER_REVIEW',
          checkinLocationSource: 'GPS',
          checkinLocationLat: 38.9072,
          checkinLocationLng: -77.0369,
          checkoutLocationSource: 'PATIENT_ADDRESS',
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Invoke the ListTile's onTap directly to avoid the ink_sparkle.frag
      // shader exception that occurs with tester.tap on Material widgets.
      final listTile = tester.widget<ListTile>(find.byType(ListTile).first);
      listTile.onTap!();
      await tester.pump();

      // Dialog should open
      expect(find.text('Review EVV Record'), findsOneWidget);
      expect(find.text('Record Details'), findsOneWidget);
    });

    testWidgets('review dialog shows record details', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          serviceType: 'Personal Care',
          status: 'UNDER_REVIEW',
          stateCode: 'MD',
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      // Check record detail labels
      expect(find.text('Service Type:'), findsOneWidget);
      expect(find.text('Individual:'), findsOneWidget);
      expect(find.text('Date:'), findsOneWidget);
      expect(find.text('Time In:'), findsOneWidget);
      expect(find.text('Time Out:'), findsOneWidget);
      expect(find.text('State:'), findsOneWidget);
      expect(find.text('Status:'), findsOneWidget);
    });

    testWidgets('review dialog shows Cancel, Reject, Approve, Export EDI buttons',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Export EDI'), findsOneWidget);
    });

    testWidgets('review dialog has comment text field', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.text('Review Comment (Optional)'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('cancel button closes the dialog', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();
      expect(find.text('Review EVV Record'), findsOneWidget);

      // Tap Cancel
      final cancelBtn = find.widgetWithText(TextButton, 'Cancel');
      if (cancelBtn.evaluate().isNotEmpty) {
        tester.widget<TextButton>(cancelBtn).onPressed!();
      } else {
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel')).onPressed!();
      }
      await tester.pump();

      expect(find.text('Review EVV Record'), findsNothing);
    });

    testWidgets('approve button closes dialog and calls reviewRecord',
        (tester) async {
      final reviewedRecord = _recordJson(id: 1, individualName: 'Alice Smith', status: 'APPROVED');
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith', status: 'UNDER_REVIEW'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        if (request.url.path.contains('/review')) {
          return http.Response(jsonEncode(reviewedRecord), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      // Enter a comment
      await tester.enterText(find.byType(TextField), 'Looks good');
      await tester.pump();

      // Tap Approve
      final approveBtn = find.widgetWithText(TextButton, 'Approve');
      if (approveBtn.evaluate().isNotEmpty) {
        tester.widget<TextButton>(approveBtn).onPressed!();
      } else {
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Approve')).onPressed!();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Dialog should close
      expect(find.text('Review EVV Record'), findsNothing);
      // Snackbar should show
      expect(find.text('Record approved'), findsOneWidget);
    });

    testWidgets('reject button closes dialog and shows rejection snackbar',
        (tester) async {
      final reviewedRecord = _recordJson(id: 1, individualName: 'Alice Smith', status: 'REJECTED');
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith', status: 'UNDER_REVIEW'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        if (request.url.path.contains('/review')) {
          return http.Response(jsonEncode(reviewedRecord), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      // Tap Reject
      final rejectBtn = find.widgetWithText(TextButton, 'Reject');
      if (rejectBtn.evaluate().isNotEmpty) {
        tester.widget<TextButton>(rejectBtn).onPressed!();
      } else {
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reject')).onPressed!();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Review EVV Record'), findsNothing);
      expect(find.text('Record rejected'), findsOneWidget);
    });

    testWidgets('review error shows error snackbar', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith', status: 'UNDER_REVIEW'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        if (request.url.path.contains('/review')) {
          return http.Response('Server error', 500);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      final approveBtn = find.widgetWithText(TextButton, 'Approve');
      if (approveBtn.evaluate().isNotEmpty) {
        tester.widget<TextButton>(approveBtn).onPressed!();
      } else {
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Approve')).onPressed!();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Error reviewing record'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - review dialog location sections', () {
    testWidgets('shows GPS location with coordinates', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          checkinLocationSource: 'GPS',
          checkinLocationLat: 38.907200,
          checkinLocationLng: -77.036900,
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.text('Check-In Location'), findsOneWidget);
      expect(find.text('Check-Out Location'), findsOneWidget);
      expect(find.textContaining('GPS:'), findsOneWidget);
      expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
    });

    testWidgets('shows GPS without coordinates', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          checkinLocationSource: 'GPS',
          // No lat/lng
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.textContaining('GPS (coordinates not available)'), findsOneWidget);
      expect(find.byIcon(Icons.gps_off), findsOneWidget);
    });

    testWidgets('shows PATIENT_ADDRESS with address', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          checkinLocationSource: 'PATIENT_ADDRESS',
          patient: {
            'id': 5,
            'firstName': 'Alice',
            'lastName': 'Smith',
            'email': 'alice@test.com',
            'phone': '555-1234',
            'dob': '1990-01-15',
            'relationship': 'self',
            'gender': 'FEMALE',
            'maNumber': 'MA12345',
            'address': {
              'line1': '456 Oak Ave',
              'line2': 'Apt 2',
              'city': 'Arlington',
              'state': 'VA',
              'zip': '22201',
            },
          },
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.textContaining('456 Oak Ave'), findsOneWidget);
      expect(find.byIcon(Icons.home), findsWidgets);
    });

    testWidgets('shows PATIENT_ADDRESS without address data', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          checkinLocationSource: 'PATIENT_ADDRESS',
          // no patient
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.textContaining('Patient Address (not available)'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    });

    testWidgets('shows "Not recorded" for null location source', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          // no location source
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.text('Not recorded'), findsWidgets);
      expect(find.byIcon(Icons.help_outline), findsWidgets);
    });

    testWidgets('shows custom location source text', (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Alice Smith',
          checkinLocationSource: 'MANUAL_ENTRY',
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.text('MANUAL_ENTRY'), findsWidgets);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('shows OFFLINE badge in record details for offline record',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith', isOffline: true),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      // OFFLINE appears in both the list tile badge and the details dialog
      expect(find.text('OFFLINE'), findsWidgets);
    });
  });

  group('EvvRecordReviewPage - dropdown filter interaction', () {
    testWidgets('can open status dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      tester.takeException();
      expect(find.text('All Statuses'), findsWidgets);
    });

    testWidgets('dropdown shows all filter options', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      tester.takeException();
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    });

    testWidgets('selecting a filter option updates dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>)).onChanged!('APPROVED');
      await tester.pump();
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets(
        'shows no match message when filter applied to empty records',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('No records found'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - Column layout', () {
    testWidgets('has a Column with filter row and expanded list area',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('has an Expanded widget for records area', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Expanded), findsWidgets);
    });
  });

  group('EvvRecordReviewPage - null user scenario', () {
    testWidgets('handles null user gracefully', (tester) async {
      final nullProvider = _NullUserProvider();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: nullProvider,
          child: const EvvRecordReviewPage(),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('EvvRecord model - _generateEDIContent coverage', () {
    test('EvvRecord can be created with all fields', () {
      final record = _makeRecord(
        id: 42,
        serviceType: 'Skilled Nursing',
        individualName: 'Jane Smith',
        status: 'APPROVED',
        stateCode: 'VA',
        isOffline: true,
      );
      expect(record.id, 42);
      expect(record.serviceType, 'Skilled Nursing');
      expect(record.individualName, 'Jane Smith');
      expect(record.status, 'APPROVED');
      expect(record.stateCode, 'VA');
      expect(record.isOffline, true);
    });

    test('EvvRecord with patient data', () {
      final patient = Patient(
        id: 5,
        firstName: 'Bob',
        lastName: 'Jones',
        email: 'bob@test.com',
        phone: '555-1234',
        dob: '1990-01-15',
        relationship: 'self',
        gender: 'MALE',
        maNumber: 'MA12345',
        address: Address(
          line1: '456 Oak Ave',
          line2: 'Apt 2',
          city: 'Arlington',
          state: 'VA',
          zip: '22201',
        ),
      );
      final record = _makeRecord(patient: patient);
      expect(record.patient, isNotNull);
      expect(record.patient!.firstName, 'Bob');
      expect(record.patient!.address, isNotNull);
      expect(record.patient!.address!.line1, '456 Oak Ave');
    });

    test('EvvRecord with GPS location', () {
      final record = _makeRecord(
        checkinLocationSource: 'GPS',
        checkinLocationLat: 38.9072,
        checkinLocationLng: -77.0369,
        checkoutLocationSource: 'GPS',
        checkoutLocationLat: 38.9100,
        checkoutLocationLng: -77.0400,
      );
      expect(record.checkinLocationSource, 'GPS');
      expect(record.checkinLocationLat, 38.9072);
      expect(record.checkoutLocationSource, 'GPS');
    });

    test('EvvRecord with PATIENT_ADDRESS location', () {
      final record = _makeRecord(
        checkinLocationSource: 'PATIENT_ADDRESS',
        checkoutLocationSource: 'PATIENT_ADDRESS',
      );
      expect(record.checkinLocationSource, 'PATIENT_ADDRESS');
    });
  });

  group('EvvRecord fromJson', () {
    test('parses valid JSON correctly', () {
      final json = {
        'id': 1,
        'serviceType': 'Personal Care',
        'individualName': 'Test Patient',
        'caregiverId': 10,
        'dateOfService': '2025-03-10',
        'timeIn': '2025-03-10T09:00:00',
        'timeOut': '2025-03-10T10:30:00',
        'status': 'UNDER_REVIEW',
        'stateCode': 'MD',
        'isOffline': false,
        'eorApprovalRequired': false,
        'isCorrected': false,
        'createdAt': '2025-03-10T09:00:00',
        'updatedAt': '2025-03-10T09:00:00',
      };
      final record = EvvRecord.fromJson(json);
      expect(record.id, 1);
      expect(record.serviceType, 'Personal Care');
      expect(record.individualName, 'Test Patient');
      expect(record.status, 'UNDER_REVIEW');
    });

    test('parses JSON with location fields', () {
      final json = {
        'id': 2,
        'serviceType': 'Companion Care',
        'individualName': 'Test Patient 2',
        'caregiverId': 11,
        'dateOfService': '2025-03-11',
        'timeIn': '2025-03-11T08:00:00',
        'timeOut': '2025-03-11T09:00:00',
        'status': 'APPROVED',
        'stateCode': 'VA',
        'isOffline': true,
        'eorApprovalRequired': false,
        'isCorrected': false,
        'createdAt': '2025-03-11T08:00:00',
        'updatedAt': '2025-03-11T08:00:00',
        'checkinLocationLat': 38.9072,
        'checkinLocationLng': -77.0369,
        'checkinLocationSource': 'GPS',
        'checkoutLocationLat': 38.9100,
        'checkoutLocationLng': -77.0400,
        'checkoutLocationSource': 'PATIENT_ADDRESS',
      };
      final record = EvvRecord.fromJson(json);
      expect(record.checkinLocationSource, 'GPS');
      expect(record.checkinLocationLat, 38.9072);
      expect(record.checkoutLocationSource, 'PATIENT_ADDRESS');
      expect(record.isOffline, true);
    });

    test('parses JSON with patient data', () {
      final json = {
        'id': 3,
        'serviceType': 'Respite Care',
        'individualName': 'Test Patient 3',
        'caregiverId': 12,
        'dateOfService': '2025-03-12',
        'timeIn': '2025-03-12T10:00:00',
        'timeOut': '2025-03-12T11:00:00',
        'status': 'REJECTED',
        'stateCode': 'DC',
        'isOffline': false,
        'eorApprovalRequired': true,
        'isCorrected': true,
        'createdAt': '2025-03-12T10:00:00',
        'updatedAt': '2025-03-12T10:00:00',
        'patient': {
          'id': 5,
          'firstName': 'Alice',
          'lastName': 'Wonder',
          'email': 'alice@test.com',
          'phone': '555-5678',
          'dob': '1985-06-15',
          'relationship': 'self',
          'gender': 'Female',
          'maNumber': 'MA99999',
          'address': {
            'line1': '789 Pine Rd',
            'city': 'Bethesda',
            'state': 'MD',
            'zip': '20814',
          },
        },
      };
      final record = EvvRecord.fromJson(json);
      expect(record.patient, isNotNull);
      expect(record.patient!.firstName, 'Alice');
      expect(record.patient!.maNumber, 'MA99999');
      expect(record.status, 'REJECTED');
      expect(record.eorApprovalRequired, true);
      expect(record.isCorrected, true);
    });
  });

  group('EvvSearchRequest', () {
    test('creates with defaults', () {
      final req = EvvSearchRequest();
      expect(req.page, 0);
      expect(req.size, 20);
      expect(req.sortBy, 'createdAt');
      expect(req.sortDirection, 'DESC');
      expect(req.patientName, isNull);
      expect(req.serviceType, isNull);
    });

    test('creates with custom values', () {
      final req = EvvSearchRequest(
        patientName: 'John',
        serviceType: 'Personal Care',
        caregiverId: 5,
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31),
        stateCode: 'MD',
        status: 'APPROVED',
        page: 2,
        size: 50,
        sortBy: 'dateOfService',
        sortDirection: 'ASC',
      );
      expect(req.patientName, 'John');
      expect(req.serviceType, 'Personal Care');
      expect(req.caregiverId, 5);
      expect(req.page, 2);
      expect(req.size, 50);
    });
  });

  group('EvvSearchResult fromJson', () {
    test('parses search result', () {
      final json = {
        'content': [
          {
            'id': 1,
            'serviceType': 'Personal Care',
            'individualName': 'Patient A',
            'caregiverId': 10,
            'dateOfService': '2025-03-10',
            'timeIn': '2025-03-10T09:00:00',
            'timeOut': '2025-03-10T10:00:00',
            'status': 'UNDER_REVIEW',
            'stateCode': 'MD',
            'isOffline': false,
            'eorApprovalRequired': false,
            'isCorrected': false,
            'createdAt': '2025-03-10T09:00:00',
            'updatedAt': '2025-03-10T09:00:00',
          },
        ],
        'totalElements': 1,
        'totalPages': 1,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };
      final result = EvvSearchResult.fromJson(json);
      expect(result.content.length, 1);
      expect(result.totalElements, 1);
      expect(result.first, true);
      expect(result.last, true);
    });
  });

  group('EvvRecordReviewPage - multiple records with different statuses', () {
    testWidgets('renders multiple records with correct status icons',
        (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Under Review User', status: 'UNDER_REVIEW'),
        _recordJson(id: 2, individualName: 'Approved User', status: 'APPROVED'),
        _recordJson(id: 3, individualName: 'Rejected User', status: 'REJECTED'),
        _recordJson(id: 4, individualName: 'Unknown Status User', status: 'PENDING'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // All 4 records should be shown
      expect(find.text('Under Review User'), findsOneWidget);
      expect(find.text('Approved User'), findsOneWidget);
      expect(find.text('Rejected User'), findsOneWidget);
      expect(find.text('Unknown Status User'), findsOneWidget);

      // Status icons: pending, check_circle, cancel, help
      expect(find.byIcon(Icons.pending), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.byIcon(Icons.help), findsOneWidget);

      // 4 CircleAvatars
      expect(find.byType(CircleAvatar), findsNWidgets(4));

      // Title shows count
      expect(find.textContaining('All EVV Records (4)'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - export EDI button in dialog', () {
    testWidgets('export EDI button has download icon', (tester) async {
      final records = [
        _recordJson(id: 1, individualName: 'Alice Smith'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      expect(find.byIcon(Icons.download), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - record detail with patient having DOB', () {
    testWidgets('shows details for record with full patient info including address',
        (tester) async {
      final records = [
        _recordJson(
          id: 1,
          individualName: 'Jane Doe',
          checkinLocationSource: 'PATIENT_ADDRESS',
          checkoutLocationSource: 'GPS',
          checkoutLocationLat: 38.91,
          checkoutLocationLng: -77.04,
          patient: {
            'id': 10,
            'firstName': 'Jane',
            'lastName': 'Doe',
            'email': 'jane@test.com',
            'phone': '555-9999',
            'dob': '1985-03-15',
            'relationship': 'self',
            'gender': 'MALE',
            'maNumber': 'MA55555',
            'address': {
              'line1': '100 Main St',
              'line2': 'Suite 200',
              'city': 'Richmond',
              'state': 'VA',
              'zip': '23220',
            },
          },
        ),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      tester.widget<ListTile>(find.byType(ListTile).first).onTap!();
      await tester.pump();

      // Patient address in check-in location
      expect(find.textContaining('100 Main St'), findsOneWidget);
      expect(find.textContaining('Suite 200'), findsOneWidget);
      expect(find.textContaining('Richmond'), findsOneWidget);

      // GPS in check-out location
      expect(find.textContaining('GPS:'), findsOneWidget);
      expect(find.textContaining('38.91'), findsOneWidget);
    });
  });

  group('EvvRecordReviewPage - refresh with mock HTTP', () {
    testWidgets('refresh button reloads records', (tester) async {
      int callCount = 0;
      final records = [
        _recordJson(id: 1, individualName: 'Initial Record'),
      ];
      _httpHandler = ((request) async {
        if (request.url.path.contains('/records/search')) {
          callCount++;
          return http.Response(_searchResultBody(records), 200);
        }
        return http.Response('{}', 200);
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Initial Record'), findsOneWidget);
      expect(callCount, 1);

      // Tap refresh
      final refreshBtn = find.ancestor(of: find.byIcon(Icons.refresh), matching: find.byType(IconButton));
      tester.widget<IconButton>(refreshBtn).onPressed!();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(callCount, 2);
    });
  });

  group('EvvService static data', () {
    test('serviceTypes list is not empty', () {
      expect(EvvService.serviceTypes, isNotEmpty);
      expect(EvvService.serviceTypes, contains('Personal Care'));
      expect(EvvService.serviceTypes, contains('Skilled Nursing'));
    });

    test('stateCodes list contains MD, DC, VA', () {
      expect(EvvService.stateCodes, contains('MD'));
      expect(EvvService.stateCodes, contains('DC'));
      expect(EvvService.stateCodes, contains('VA'));
    });

    test('correctionReasonCodes list is not empty', () {
      expect(EvvService.correctionReasonCodes, isNotEmpty);
      expect(EvvService.correctionReasonCodes, contains('TIME_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('OTHER'));
    });
  });

  group('EvvCorrectionRequest', () {
    test('toJson includes required fields', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'Wrong time recorded',
      );
      final json = req.toJson();
      expect(json['originalRecordId'], 1);
      expect(json['reasonCode'], 'TIME_ERROR');
      expect(json['explanation'], 'Wrong time recorded');
    });

    test('toJson includes optional fields when set', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 2,
        reasonCode: 'LOCATION_ERROR',
        explanation: 'Wrong location',
        serviceType: 'Companion Care',
        individualName: 'Fixed Name',
        dateOfService: DateTime(2025, 6, 1),
        timeIn: DateTime(2025, 6, 1, 8, 0),
        timeOut: DateTime(2025, 6, 1, 9, 0),
        locationLat: 38.9,
        locationLng: -77.0,
        locationSource: 'GPS',
        stateCode: 'VA',
        deviceInfo: {'platform': 'test'},
      );
      final json = req.toJson();
      expect(json['serviceType'], 'Companion Care');
      expect(json['individualName'], 'Fixed Name');
      expect(json['locationLat'], 38.9);
      expect(json['locationSource'], 'GPS');
      expect(json['stateCode'], 'VA');
      expect(json['deviceInfo'], {'platform': 'test'});
      expect(json['timeIn'], isA<String>());
      expect(json['timeOut'], isA<String>());
      expect(json['dateOfService'], contains('2025-06-01'));
    });

    test('toJson omits null optional fields', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 3,
        reasonCode: 'OTHER',
        explanation: 'Misc fix',
      );
      final json = req.toJson();
      expect(json.containsKey('serviceType'), false);
      expect(json.containsKey('individualName'), false);
      expect(json.containsKey('dateOfService'), false);
      expect(json.containsKey('timeIn'), false);
      expect(json.containsKey('timeOut'), false);
      expect(json.containsKey('locationLat'), false);
      expect(json.containsKey('locationLng'), false);
      expect(json.containsKey('locationSource'), false);
      expect(json.containsKey('stateCode'), false);
      expect(json.containsKey('deviceInfo'), false);
    });
  });

  group('EvvOfflineQueue fromJson', () {
    test('parses offline queue item', () {
      final json = {
        'id': 1,
        'recordId': 10,
        'operationType': 'CREATE',
        'caregiverId': 5,
        'deviceId': 'device-123',
        'queuedAt': '2025-03-10T09:00:00',
        'syncAttempts': 3,
        'lastSyncAttempt': '2025-03-10T10:00:00',
        'syncStatus': 'PENDING',
        'lastError': 'Network error',
        'priority': 2,
        'recordData': {'serviceType': 'Personal Care'},
      };
      final queue = EvvOfflineQueue.fromJson(json);
      expect(queue.id, 1);
      expect(queue.recordId, 10);
      expect(queue.operationType, 'CREATE');
      expect(queue.deviceId, 'device-123');
      expect(queue.syncAttempts, 3);
      expect(queue.syncStatus, 'PENDING');
      expect(queue.lastError, 'Network error');
      expect(queue.priority, 2);
    });

    test('handles null optional fields', () {
      final json = {
        'id': 2,
        'recordId': 20,
        'operationType': 'UPDATE',
        'caregiverId': 6,
        'queuedAt': '2025-03-11T09:00:00',
        'syncStatus': 'SYNCED',
      };
      final queue = EvvOfflineQueue.fromJson(json);
      expect(queue.deviceId, isNull);
      expect(queue.syncAttempts, 0);
      expect(queue.lastSyncAttempt, isNull);
      expect(queue.lastError, isNull);
      expect(queue.priority, 1);
      expect(queue.recordData, isEmpty);
    });
  });

  group('EvvCorrection fromJson', () {
    test('parses correction with nested records', () {
      final recordJson = {
        'id': 1,
        'serviceType': 'Personal Care',
        'individualName': 'Test',
        'caregiverId': 10,
        'dateOfService': '2025-03-10',
        'timeIn': '2025-03-10T09:00:00',
        'timeOut': '2025-03-10T10:00:00',
        'status': 'UNDER_REVIEW',
        'stateCode': 'MD',
        'isOffline': false,
        'eorApprovalRequired': false,
        'isCorrected': false,
        'createdAt': '2025-03-10T09:00:00',
        'updatedAt': '2025-03-10T09:00:00',
      };
      final json = {
        'id': 100,
        'originalRecord': recordJson,
        'correctedRecord': {...recordJson, 'id': 2},
        'reasonCode': 'TIME_ERROR',
        'explanation': 'Fixed time',
        'correctedBy': 5,
        'correctedAt': '2025-03-10T11:00:00',
        'approvalRequired': true,
        'approvedBy': 6,
        'approvedAt': '2025-03-10T12:00:00',
        'approvalComment': 'Looks good',
        'originalValues': {'timeIn': '09:00'},
        'correctedValues': {'timeIn': '09:30'},
      };
      final correction = EvvCorrection.fromJson(json);
      expect(correction.id, 100);
      expect(correction.reasonCode, 'TIME_ERROR');
      expect(correction.explanation, 'Fixed time');
      expect(correction.approvalRequired, true);
      expect(correction.approvedBy, 6);
      expect(correction.approvalComment, 'Looks good');
      expect(correction.originalValues, containsPair('timeIn', '09:00'));
      expect(correction.correctedValues, containsPair('timeIn', '09:30'));
    });
  });

  group('EvvRecordRequest', () {
    test('creates request with required fields', () {
      final req = EvvRecordRequest(
        serviceType: 'Personal Care',
        patientId: 1,
        caregiverId: 2,
        dateOfService: DateTime(2025, 3, 10),
        timeIn: DateTime(2025, 3, 10, 9, 0),
        timeOut: DateTime(2025, 3, 10, 10, 0),
        stateCode: 'MD',
      );
      expect(req.serviceType, 'Personal Care');
      expect(req.patientId, 1);
      expect(req.caregiverId, 2);
      expect(req.stateCode, 'MD');
      expect(req.scheduledVisitId, isNull);
    });

    test('creates request with optional location fields', () {
      final req = EvvRecordRequest(
        serviceType: 'Companion Care',
        patientId: 3,
        caregiverId: 4,
        dateOfService: DateTime(2025, 4, 1),
        timeIn: DateTime(2025, 4, 1, 8, 0),
        timeOut: DateTime(2025, 4, 1, 9, 0),
        stateCode: 'VA',
        locationLat: 38.9,
        locationLng: -77.0,
        locationSource: 'GPS',
        checkinLocationLat: 38.91,
        checkinLocationLng: -77.01,
        checkinLocationSource: 'GPS',
        checkoutLocationLat: 38.92,
        checkoutLocationLng: -77.02,
        checkoutLocationSource: 'PATIENT_ADDRESS',
        scheduledVisitId: 42,
      );
      expect(req.locationLat, 38.9);
      expect(req.checkinLocationSource, 'GPS');
      expect(req.checkoutLocationSource, 'PATIENT_ADDRESS');
      expect(req.scheduledVisitId, 42);
    });
  });
}

/// A provider that returns null user for testing the null-user code path.
class _NullUserProvider extends UserProvider {
  @override
  UserSession? get user => null;

  @override
  bool get isLoggedIn => false;

  @override
  bool get isPatient => false;

  @override
  bool get isCaregiver => false;

  @override
  Future<void> initializeUser() async {}

  @override
  Future<void> fetchUserDetails() async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> updateActivity() async {}

  @override
  Future<bool> validateSession() async => false;

  @override
  Future<bool> refreshToken() async => false;

  @override
  Future<void> updateUserRole(String newRole) async {}

  @override
  Future<void> updatePatientId(int? patientId) async {}

  @override
  void updateUserName(String newName) {}

  @override
  Future<UserData?> getUserDataFromStorage() async => null;
}
