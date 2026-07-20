// Tests for EvvService data models, static constants, and HTTP methods.
//
// Coverage strategy:
//   Pure Dart model classes and static constants are fully testable.
//   HTTP methods are tested via http.runWithClient + MockClient.
//   Connectivity mocked via MethodChannel stub.
//   _getDeviceInfo catches errors internally so works in test without platform.
//
//   Branches tested:
//     EvvService static constants — serviceTypes, stateCodes, correctionReasonCodes.
//     EvvService constructor / dispose.
//     EvvRecord.fromJson — all required fields, optional fields null/present, location fields.
//     EvvRecord constructor — direct instantiation with all fields.
//     EvvCorrection.fromJson — full parse with nested EvvRecord objects.
//     EvvOfflineQueue.fromJson — parses all fields; optional fields null-safe.
//     EvvSearchRequest defaults — page=0, size=20, sortBy='createdAt', sortDirection='DESC'.
//     EvvSearchResult.fromJson — parses content list, pagination fields, multiple records.
//     EvvCorrectionRequest.toJson — required fields present, optional fields omitted when null.
//     EvvCorrectionRequest.toJson — optional fields included when provided.
//     EvvCorrectionRequest.toJson — datetime fields formatted with timezone offset.
//     EvvRecordRequest — constructor stores all fields correctly.
//     EvvService.reviewRecord — 200 success, non-200 throws.
//     EvvService.getRecordsByStatus — 200 success, non-200 throws.
//     EvvService.searchRecords — 200 success with all params, non-200 throws.
//     EvvService.getPendingEorApprovals — 200 success, non-200 throws.
//     EvvService.approveEor — 200 success, non-200 throws.
//     EvvService.getPendingCorrections — 200 success, non-200 throws.
//     EvvService.approveCorrection — 200 with comment, non-200 throws.
//     EvvService.getOfflineQueue — 200 success, non-200 throws.
//     EvvService.syncOfflineData — 200 success, non-200 throws.
//     EvvService.getOfflineStatus — 200 success, non-200 throws.
//     EvvService.correctRecord — 200 success, non-200 throws.
//     EvvService.createRecord — 201 success, non-200 throws.
//     EvvService._getDeviceId — creates and persists device ID.
//     EvvService._formatDateTimeWithTimezone — tested via createRecord output.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/evv_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

/// Mutable HTTP handler used by the singleton OfflineQueueHttpClient.
late Future<http.Response> Function(http.Request) _httpHandler;

Future<http.Response> _defaultHandler(http.Request request) async =>
    http.Response('{}', 200);

/// Drop-in replacement for http.runWithClient that routes the MockClient's
/// handler through the singleton's delegating client instead.
/// Works by calling send() on the test's mock client and converting the
/// StreamedResponse back to a Response for the delegating mock.
T _runWithMockHandler<T>(
  T Function() callback,
  http.Client Function() clientFactory,
) {
  final client = clientFactory();
  _httpHandler = (http.Request request) async {
    final streamed = await client.send(request);
    return http.Response.fromStream(streamed);
  };
  return callback();
}

// ─── Stubs ──────────────────────────────────────────────────────────────────

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
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
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, null);
}

// Minimal EvvRecord JSON used by multiple tests.
Map<String, dynamic> _minimalRecordJson({int id = 1}) => {
      'id': id,
      'patient': null,
      'serviceType': 'Personal Care',
      'individualName': 'Alice Smith',
      'caregiverId': 10,
      'dateOfService': '2025-03-01',
      'timeIn': '2025-03-01T08:00:00.000Z',
      'timeOut': '2025-03-01T10:00:00.000Z',
      'status': 'APPROVED',
      'stateCode': 'MD',
      'isOffline': false,
      'eorApprovalRequired': false,
      'isCorrected': false,
      'createdAt': '2025-03-01T08:00:00.000Z',
      'updatedAt': '2025-03-01T10:00:00.000Z',
    };

// Full EvvRecord JSON with all optional fields populated.
Map<String, dynamic> _fullRecordJson({int id = 1}) => {
      'id': id,
      'patient': {
        'id': 42,
        'firstName': 'Jane',
        'lastName': 'Doe',
        'email': 'jane@example.com',
        'phone': '555-1234',
        'dob': '1990-01-15',
        'relationship': 'Self',
      },
      'serviceType': 'Skilled Nursing',
      'individualName': 'Jane Doe',
      'caregiverId': 20,
      'dateOfService': '2025-06-15',
      'timeIn': '2025-06-15T09:00:00.000Z',
      'timeOut': '2025-06-15T11:30:00.000Z',
      'locationLat': 38.9072,
      'locationLng': -77.0369,
      'locationSource': 'GPS',
      'checkinLocationLat': 38.9072,
      'checkinLocationLng': -77.0369,
      'checkinLocationSource': 'GPS',
      'checkoutLocationLat': 38.9100,
      'checkoutLocationLng': -77.0400,
      'checkoutLocationSource': 'MANUAL',
      'status': 'PENDING',
      'stateCode': 'DC',
      'deviceInfo': {'platform': 'Flutter', 'version': '1.0.0'},
      'isOffline': true,
      'syncStatus': 'PENDING',
      'lastSyncAttempt': '2025-06-15T12:00:00.000Z',
      'eorApprovalRequired': true,
      'eorApprovedBy': 5,
      'eorApprovedAt': '2025-06-16T08:00:00.000Z',
      'eorApprovalComment': 'Looks good',
      'isCorrected': true,
      'originalRecordId': 99,
      'correctionReasonCode': 'TIME_ERROR',
      'correctionExplanation': 'Wrong clock-in time',
      'correctedBy': 7,
      'correctedAt': '2025-06-16T09:00:00.000Z',
      'createdAt': '2025-06-15T09:00:00.000Z',
      'updatedAt': '2025-06-16T09:00:00.000Z',
    };

Map<String, dynamic> _offlineQueueJson({int id = 1}) => {
      'id': id,
      'recordId': 10,
      'operationType': 'CREATE',
      'caregiverId': 3,
      'deviceId': 'device-abc',
      'queuedAt': '2025-03-01T08:00:00.000Z',
      'syncAttempts': 2,
      'lastSyncAttempt': '2025-03-01T09:00:00.000Z',
      'syncStatus': 'PENDING',
      'lastError': 'Connection refused',
      'priority': 2,
      'recordData': {'key': 'value'},
    };

Map<String, dynamic> _correctionJson({int id = 1}) => {
      'id': id,
      'originalRecord': _minimalRecordJson(id: 100),
      'correctedRecord': _minimalRecordJson(id: 101),
      'reasonCode': 'TIME_ERROR',
      'explanation': 'Clock was wrong',
      'correctedBy': 3,
      'correctedAt': '2025-03-02T08:00:00.000Z',
      'approvalRequired': true,
      'approvedBy': 5,
      'approvedAt': '2025-03-02T10:00:00.000Z',
      'approvalComment': 'Approved',
      'originalValues': {'timeIn': '2025-03-01T08:00:00Z'},
      'correctedValues': {'timeIn': '2025-03-01T08:30:00Z'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _httpHandler = _defaultHandler;
    final delegatingClient =
        MockClient((request) => _httpHandler(request));
    _runWithMockHandler(() {
      ApiServiceOffline.httpClient;
    }, () => delegatingClient);
  });

  setUp(() {
    _httpHandler = _defaultHandler;
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
  });

  tearDown(() {
    _teardownStubs();
  });

  // ─── Static constants ─────────────────────────────────────────────────────

  group('EvvService static constants', () {
    test('serviceTypes contains expected service names', () {
      expect(EvvService.serviceTypes, contains('Personal Care'));
      expect(EvvService.serviceTypes, contains('Skilled Nursing'));
      expect(EvvService.serviceTypes, contains('Home Health Aide'));
      expect(EvvService.serviceTypes.length, greaterThan(5));
    });

    test('serviceTypes contains all 10 service types', () {
      expect(EvvService.serviceTypes.length, 10);
      expect(EvvService.serviceTypes, contains('Companion Care'));
      expect(EvvService.serviceTypes, contains('Respite Care'));
      expect(EvvService.serviceTypes, contains('Homemaker Services'));
      expect(EvvService.serviceTypes, contains('Physical Therapy'));
      expect(EvvService.serviceTypes, contains('Occupational Therapy'));
      expect(EvvService.serviceTypes, contains('Speech Therapy'));
      expect(EvvService.serviceTypes, contains('Medical Social Work'));
    });

    test('stateCodes contains MD, DC, VA', () {
      expect(EvvService.stateCodes, containsAll(['MD', 'DC', 'VA']));
      expect(EvvService.stateCodes.length, 3);
    });

    test('correctionReasonCodes contains expected codes', () {
      expect(EvvService.correctionReasonCodes, contains('TIME_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('LOCATION_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('SERVICE_TYPE_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('PATIENT_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('CAREGIVER_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('SYSTEM_ERROR'));
      expect(EvvService.correctionReasonCodes, contains('OTHER'));
      expect(EvvService.correctionReasonCodes.length, 7);
    });
  });

  // ─── EvvService constructor / dispose ───────────────────────────────────

  group('EvvService constructor and dispose', () {
    test('can be instantiated', () {
      final service = EvvService();
      expect(service, isNotNull);
    });

    test('dispose does not throw', () {
      final service = EvvService();
      expect(() => service.dispose(), returnsNormally);
    });
  });

  // ─── EvvRecord.fromJson ─────────────────────────────────────────────────

  group('EvvRecord.fromJson', () {
    test('parses minimal record with required fields', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());
      expect(record.id, 1);
      expect(record.patient, isNull);
      expect(record.serviceType, 'Personal Care');
      expect(record.individualName, 'Alice Smith');
      expect(record.caregiverId, 10);
      expect(record.dateOfService, DateTime.parse('2025-03-01'));
      expect(record.timeIn, DateTime.parse('2025-03-01T08:00:00.000Z'));
      expect(record.timeOut, DateTime.parse('2025-03-01T10:00:00.000Z'));
      expect(record.status, 'APPROVED');
      expect(record.stateCode, 'MD');
      expect(record.isOffline, false);
      expect(record.eorApprovalRequired, false);
      expect(record.isCorrected, false);
      expect(record.createdAt, isNotNull);
      expect(record.updatedAt, isNotNull);
    });

    test('optional fields are null when not provided', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());
      expect(record.locationLat, isNull);
      expect(record.locationLng, isNull);
      expect(record.locationSource, isNull);
      expect(record.checkinLocationLat, isNull);
      expect(record.checkinLocationLng, isNull);
      expect(record.checkinLocationSource, isNull);
      expect(record.checkoutLocationLat, isNull);
      expect(record.checkoutLocationLng, isNull);
      expect(record.checkoutLocationSource, isNull);
      expect(record.deviceInfo, isNull);
      expect(record.syncStatus, isNull);
      expect(record.lastSyncAttempt, isNull);
      expect(record.eorApprovedBy, isNull);
      expect(record.eorApprovedAt, isNull);
      expect(record.eorApprovalComment, isNull);
      expect(record.originalRecordId, isNull);
      expect(record.correctionReasonCode, isNull);
      expect(record.correctionExplanation, isNull);
      expect(record.correctedBy, isNull);
      expect(record.correctedAt, isNull);
    });

    test('parses full record with all optional fields', () {
      final record = EvvRecord.fromJson(_fullRecordJson());
      expect(record.id, 1);
      expect(record.patient, isNotNull);
      expect(record.patient!.firstName, 'Jane');
      expect(record.patient!.lastName, 'Doe');
      expect(record.serviceType, 'Skilled Nursing');
      expect(record.individualName, 'Jane Doe');
      expect(record.caregiverId, 20);
      expect(record.locationLat, 38.9072);
      expect(record.locationLng, -77.0369);
      expect(record.locationSource, 'GPS');
      expect(record.checkinLocationLat, 38.9072);
      expect(record.checkinLocationLng, -77.0369);
      expect(record.checkinLocationSource, 'GPS');
      expect(record.checkoutLocationLat, 38.9100);
      expect(record.checkoutLocationLng, -77.0400);
      expect(record.checkoutLocationSource, 'MANUAL');
      expect(record.status, 'PENDING');
      expect(record.stateCode, 'DC');
      expect(record.deviceInfo, isNotNull);
      expect(record.deviceInfo!['platform'], 'Flutter');
      expect(record.isOffline, true);
      expect(record.syncStatus, 'PENDING');
      expect(record.lastSyncAttempt, isNotNull);
      expect(record.eorApprovalRequired, true);
      expect(record.eorApprovedBy, 5);
      expect(record.eorApprovedAt, isNotNull);
      expect(record.eorApprovalComment, 'Looks good');
      expect(record.isCorrected, true);
      expect(record.originalRecordId, 99);
      expect(record.correctionReasonCode, 'TIME_ERROR');
      expect(record.correctionExplanation, 'Wrong clock-in time');
      expect(record.correctedBy, 7);
      expect(record.correctedAt, isNotNull);
    });

    test('isOffline defaults to false when missing', () {
      final json = _minimalRecordJson();
      json.remove('isOffline');
      final record = EvvRecord.fromJson(json);
      expect(record.isOffline, false);
    });

    test('eorApprovalRequired defaults to false when missing', () {
      final json = _minimalRecordJson();
      json.remove('eorApprovalRequired');
      final record = EvvRecord.fromJson(json);
      expect(record.eorApprovalRequired, false);
    });

    test('isCorrected defaults to false when missing', () {
      final json = _minimalRecordJson();
      json.remove('isCorrected');
      final record = EvvRecord.fromJson(json);
      expect(record.isCorrected, false);
    });

    test('locationLat/Lng converts int to double via toDouble()', () {
      final json = _minimalRecordJson();
      json['locationLat'] = 39;
      json['locationLng'] = -77;
      final record = EvvRecord.fromJson(json);
      expect(record.locationLat, 39.0);
      expect(record.locationLng, -77.0);
      expect(record.locationLat, isA<double>());
      expect(record.locationLng, isA<double>());
    });

    test('checkin/checkout location lat/lng converts int to double', () {
      final json = _minimalRecordJson();
      json['checkinLocationLat'] = 39;
      json['checkinLocationLng'] = -77;
      json['checkoutLocationLat'] = 40;
      json['checkoutLocationLng'] = -76;
      final record = EvvRecord.fromJson(json);
      expect(record.checkinLocationLat, 39.0);
      expect(record.checkinLocationLng, -77.0);
      expect(record.checkoutLocationLat, 40.0);
      expect(record.checkoutLocationLng, -76.0);
    });
  });

  // ─── EvvRecord constructor ──────────────────────────────────────────────

  group('EvvRecord constructor', () {
    test('can be instantiated directly with required fields', () {
      final record = EvvRecord(
        id: 1,
        serviceType: 'Personal Care',
        individualName: 'Test User',
        caregiverId: 5,
        dateOfService: DateTime(2025, 3, 1),
        timeIn: DateTime(2025, 3, 1, 8, 0),
        timeOut: DateTime(2025, 3, 1, 10, 0),
        status: 'APPROVED',
        stateCode: 'MD',
        isOffline: false,
        eorApprovalRequired: false,
        isCorrected: false,
        createdAt: DateTime(2025, 3, 1),
        updatedAt: DateTime(2025, 3, 1),
      );
      expect(record.id, 1);
      expect(record.serviceType, 'Personal Care');
      expect(record.patient, isNull);
      expect(record.locationLat, isNull);
    });

    test('can be instantiated with all optional fields', () {
      final now = DateTime.now();
      final record = EvvRecord(
        id: 2,
        serviceType: 'Companion Care',
        individualName: 'Full User',
        caregiverId: 10,
        dateOfService: now,
        timeIn: now,
        timeOut: now.add(const Duration(hours: 2)),
        status: 'PENDING',
        stateCode: 'VA',
        isOffline: true,
        eorApprovalRequired: true,
        isCorrected: true,
        createdAt: now,
        updatedAt: now,
        locationLat: 38.0,
        locationLng: -77.0,
        locationSource: 'GPS',
        checkinLocationLat: 38.1,
        checkinLocationLng: -77.1,
        checkinLocationSource: 'GPS',
        checkoutLocationLat: 38.2,
        checkoutLocationLng: -77.2,
        checkoutLocationSource: 'MANUAL',
        deviceInfo: {'test': true},
        syncStatus: 'SYNCED',
        lastSyncAttempt: now,
        eorApprovedBy: 3,
        eorApprovedAt: now,
        eorApprovalComment: 'OK',
        originalRecordId: 1,
        correctionReasonCode: 'TIME_ERROR',
        correctionExplanation: 'Fix',
        correctedBy: 4,
        correctedAt: now,
      );
      expect(record.locationLat, 38.0);
      expect(record.checkinLocationSource, 'GPS');
      expect(record.checkoutLocationSource, 'MANUAL');
      expect(record.syncStatus, 'SYNCED');
      expect(record.eorApprovalComment, 'OK');
      expect(record.correctionReasonCode, 'TIME_ERROR');
    });
  });

  // ─── EvvCorrection.fromJson ─────────────────────────────────────────────

  group('EvvCorrection.fromJson', () {
    test('parses full correction with nested records', () {
      final json = {
        'id': 10,
        'originalRecord': _minimalRecordJson(id: 1),
        'correctedRecord': _minimalRecordJson(id: 2),
        'reasonCode': 'TIME_ERROR',
        'explanation': 'Clock was wrong',
        'correctedBy': 3,
        'correctedAt': '2025-03-02T08:00:00.000Z',
        'approvalRequired': true,
        'approvedBy': 5,
        'approvedAt': '2025-03-02T10:00:00.000Z',
        'approvalComment': 'Approved',
        'originalValues': {'timeIn': '2025-03-01T08:00:00Z'},
        'correctedValues': {'timeIn': '2025-03-01T08:30:00Z'},
      };
      final correction = EvvCorrection.fromJson(json);
      expect(correction.id, 10);
      expect(correction.originalRecord.id, 1);
      expect(correction.correctedRecord.id, 2);
      expect(correction.reasonCode, 'TIME_ERROR');
      expect(correction.explanation, 'Clock was wrong');
      expect(correction.correctedBy, 3);
      expect(correction.correctedAt, DateTime.parse('2025-03-02T08:00:00.000Z'));
      expect(correction.approvalRequired, true);
      expect(correction.approvedBy, 5);
      expect(correction.approvedAt, isNotNull);
      expect(correction.approvalComment, 'Approved');
      expect(correction.originalValues['timeIn'], '2025-03-01T08:00:00Z');
      expect(correction.correctedValues['timeIn'], '2025-03-01T08:30:00Z');
    });

    test('optional approval fields default gracefully', () {
      final json = {
        'id': 20,
        'originalRecord': _minimalRecordJson(id: 3),
        'correctedRecord': _minimalRecordJson(id: 4),
        'reasonCode': 'LOCATION_ERROR',
        'explanation': 'Wrong place',
        'correctedBy': 6,
        'correctedAt': '2025-04-01T12:00:00.000Z',
      };
      final correction = EvvCorrection.fromJson(json);
      expect(correction.approvalRequired, false);
      expect(correction.approvedBy, isNull);
      expect(correction.approvedAt, isNull);
      expect(correction.approvalComment, isNull);
      expect(correction.originalValues, isEmpty);
      expect(correction.correctedValues, isEmpty);
    });
  });

  // ─── EvvOfflineQueue.fromJson ─────────────────────────────────────────────

  group('EvvOfflineQueue.fromJson', () {
    test('parses all required fields', () {
      final q = EvvOfflineQueue.fromJson(_offlineQueueJson());
      expect(q.id, 1);
      expect(q.recordId, 10);
      expect(q.operationType, 'CREATE');
      expect(q.caregiverId, 3);
      expect(q.deviceId, 'device-abc');
      expect(q.syncAttempts, 2);
      expect(q.syncStatus, 'PENDING');
      expect(q.lastError, 'Connection refused');
      expect(q.priority, 2);
      expect(q.recordData['key'], 'value');
      expect(q.queuedAt, DateTime.parse('2025-03-01T08:00:00.000Z'));
      expect(q.lastSyncAttempt, DateTime.parse('2025-03-01T09:00:00.000Z'));
    });

    test('optional fields default gracefully when absent', () {
      final json = {
        'id': 1,
        'recordId': 2,
        'operationType': 'UPDATE',
        'caregiverId': 4,
        'queuedAt': '2025-03-01T08:00:00.000Z',
        'syncStatus': 'SYNCED',
        'recordData': <String, dynamic>{},
      };
      final q = EvvOfflineQueue.fromJson(json);
      expect(q.deviceId, isNull);
      expect(q.lastSyncAttempt, isNull);
      expect(q.lastError, isNull);
      expect(q.syncAttempts, 0);
      expect(q.priority, 1);
      expect(q.recordData, isEmpty);
    });
  });

  // ─── EvvOfflineQueue constructor ────────────────────────────────────────

  group('EvvOfflineQueue constructor', () {
    test('can be instantiated directly', () {
      final q = EvvOfflineQueue(
        id: 1,
        recordId: 2,
        operationType: 'CREATE',
        caregiverId: 3,
        queuedAt: DateTime(2025, 1, 1),
        syncAttempts: 0,
        syncStatus: 'PENDING',
        priority: 1,
        recordData: {'test': 'data'},
      );
      expect(q.id, 1);
      expect(q.deviceId, isNull);
      expect(q.lastSyncAttempt, isNull);
      expect(q.lastError, isNull);
    });
  });

  // ─── EvvSearchRequest defaults ────────────────────────────────────────────

  group('EvvSearchRequest defaults', () {
    test('default constructor sets expected page/size/sort values', () {
      final req = EvvSearchRequest();
      expect(req.page, 0);
      expect(req.size, 20);
      expect(req.sortBy, 'createdAt');
      expect(req.sortDirection, 'DESC');
    });

    test('optional fields are null by default', () {
      final req = EvvSearchRequest();
      expect(req.patientName, isNull);
      expect(req.serviceType, isNull);
      expect(req.caregiverId, isNull);
      expect(req.startDate, isNull);
      expect(req.endDate, isNull);
      expect(req.stateCode, isNull);
      expect(req.status, isNull);
    });

    test('custom values are stored correctly', () {
      final start = DateTime(2025, 1, 1);
      final end = DateTime(2025, 1, 31);
      final req = EvvSearchRequest(
        patientName: 'Alice',
        serviceType: 'Personal Care',
        caregiverId: 7,
        startDate: start,
        endDate: end,
        stateCode: 'MD',
        status: 'APPROVED',
        page: 2,
        size: 10,
        sortBy: 'dateOfService',
        sortDirection: 'ASC',
      );
      expect(req.patientName, 'Alice');
      expect(req.serviceType, 'Personal Care');
      expect(req.caregiverId, 7);
      expect(req.startDate, start);
      expect(req.endDate, end);
      expect(req.stateCode, 'MD');
      expect(req.status, 'APPROVED');
      expect(req.page, 2);
      expect(req.size, 10);
      expect(req.sortBy, 'dateOfService');
      expect(req.sortDirection, 'ASC');
    });
  });

  // ─── EvvSearchResult.fromJson ─────────────────────────────────────────────

  group('EvvSearchResult.fromJson', () {
    test('parses pagination and content list', () {
      final json = {
        'content': [_minimalRecordJson()],
        'totalElements': 50,
        'totalPages': 3,
        'size': 20,
        'number': 0,
        'first': true,
        'last': false,
      };
      final result = EvvSearchResult.fromJson(json);
      expect(result.content.length, 1);
      expect(result.totalElements, 50);
      expect(result.totalPages, 3);
      expect(result.size, 20);
      expect(result.number, 0);
      expect(result.first, isTrue);
      expect(result.last, isFalse);
    });

    test('empty content list produces empty content', () {
      final json = {
        'content': <dynamic>[],
        'totalElements': 0,
        'totalPages': 0,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };
      final result = EvvSearchResult.fromJson(json);
      expect(result.content, isEmpty);
    });

    test('parses multiple records in content', () {
      final json = {
        'content': [
          _minimalRecordJson(id: 1),
          _minimalRecordJson(id: 2),
          _minimalRecordJson(id: 3),
        ],
        'totalElements': 3,
        'totalPages': 1,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };
      final result = EvvSearchResult.fromJson(json);
      expect(result.content.length, 3);
      expect(result.content[0].id, 1);
      expect(result.content[1].id, 2);
      expect(result.content[2].id, 3);
    });

    test('last page has last=true and first=false', () {
      final json = {
        'content': [_minimalRecordJson()],
        'totalElements': 25,
        'totalPages': 2,
        'size': 20,
        'number': 1,
        'first': false,
        'last': true,
      };
      final result = EvvSearchResult.fromJson(json);
      expect(result.first, isFalse);
      expect(result.last, isTrue);
      expect(result.number, 1);
    });
  });

  // ─── EvvSearchResult constructor ────────────────────────────────────────

  group('EvvSearchResult constructor', () {
    test('can be instantiated directly', () {
      final result = EvvSearchResult(
        content: [],
        totalElements: 0,
        totalPages: 0,
        size: 10,
        number: 0,
        first: true,
        last: true,
      );
      expect(result.content, isEmpty);
      expect(result.totalElements, 0);
    });
  });

  // ─── EvvCorrectionRequest.toJson ─────────────────────────────────────────

  group('EvvCorrectionRequest.toJson', () {
    test('required fields always present in output', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 5,
        reasonCode: 'TIME_ERROR',
        explanation: 'Wrong clock-in time',
      );
      final json = req.toJson();
      expect(json['originalRecordId'], 5);
      expect(json['reasonCode'], 'TIME_ERROR');
      expect(json['explanation'], 'Wrong clock-in time');
    });

    test('optional fields omitted when null', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 5,
        reasonCode: 'OTHER',
        explanation: 'Misc',
      );
      final json = req.toJson();
      expect(json.containsKey('serviceType'), isFalse);
      expect(json.containsKey('individualName'), isFalse);
      expect(json.containsKey('dateOfService'), isFalse);
      expect(json.containsKey('timeIn'), isFalse);
      expect(json.containsKey('timeOut'), isFalse);
      expect(json.containsKey('locationLat'), isFalse);
      expect(json.containsKey('locationLng'), isFalse);
      expect(json.containsKey('locationSource'), isFalse);
      expect(json.containsKey('stateCode'), isFalse);
      expect(json.containsKey('deviceInfo'), isFalse);
    });

    test('optional fields included when provided', () {
      final timeIn = DateTime.utc(2025, 3, 1, 8, 0, 0);
      final timeOut = DateTime.utc(2025, 3, 1, 10, 0, 0);
      final req = EvvCorrectionRequest(
        originalRecordId: 7,
        reasonCode: 'LOCATION_ERROR',
        explanation: 'Wrong address',
        serviceType: 'Personal Care',
        individualName: 'Bob',
        dateOfService: DateTime(2025, 3, 1),
        timeIn: timeIn,
        timeOut: timeOut,
        locationLat: 38.9,
        locationLng: -77.0,
        locationSource: 'GPS',
        stateCode: 'MD',
      );
      final json = req.toJson();
      expect(json['serviceType'], 'Personal Care');
      expect(json['individualName'], 'Bob');
      expect(json['locationLat'], 38.9);
      expect(json['locationLng'], -77.0);
      expect(json['locationSource'], 'GPS');
      expect(json['stateCode'], 'MD');
      // Date formatted as YYYY-MM-DD.
      expect(json['dateOfService'], startsWith('2025-03-01'));
      // Time fields should be non-null strings.
      expect(json['timeIn'], isA<String>());
      expect(json['timeOut'], isA<String>());
    });

    test('deviceInfo included when provided', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'SYSTEM_ERROR',
        explanation: 'Crash',
        deviceInfo: {'platform': 'Flutter', 'version': '1.0'},
      );
      final json = req.toJson();
      expect((json['deviceInfo'] as Map)['platform'], 'Flutter');
    });

    test('toJson dateOfService formatted as date-only string', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'test',
        dateOfService: DateTime(2025, 12, 25, 14, 30, 0),
      );
      final json = req.toJson();
      expect(json['dateOfService'], '2025-12-25');
    });

    test('toJson timeIn/timeOut contain timezone offset format', () {
      final timeIn = DateTime.utc(2025, 6, 15, 14, 0, 0);
      final timeOut = DateTime.utc(2025, 6, 15, 16, 30, 0);
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'test',
        timeIn: timeIn,
        timeOut: timeOut,
      );
      final json = req.toJson();
      final timeInStr = json['timeIn'] as String;
      final timeOutStr = json['timeOut'] as String;
      expect(timeInStr, contains('2025-06-15'));
      expect(timeOutStr, contains('2025-06-15'));
      expect(timeInStr.contains('+') || timeInStr.contains('-'), isTrue);
      expect(timeOutStr.contains('+') || timeOutStr.contains('-'), isTrue);
    });

    test('only timeIn provided without timeOut', () {
      final timeIn = DateTime.utc(2025, 3, 1, 8, 0, 0);
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'test',
        timeIn: timeIn,
      );
      final json = req.toJson();
      expect(json.containsKey('timeIn'), isTrue);
      expect(json.containsKey('timeOut'), isFalse);
    });

    test('only timeOut provided without timeIn', () {
      final timeOut = DateTime.utc(2025, 3, 1, 10, 0, 0);
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'test',
        timeOut: timeOut,
      );
      final json = req.toJson();
      expect(json.containsKey('timeIn'), isFalse);
      expect(json.containsKey('timeOut'), isTrue);
    });
  });

  // ─── EvvCorrectionRequest constructor ───────────────────────────────────

  group('EvvCorrectionRequest constructor', () {
    test('stores all fields correctly', () {
      final timeIn = DateTime(2025, 3, 1, 8, 0);
      final timeOut = DateTime(2025, 3, 1, 10, 0);
      final dateOfService = DateTime(2025, 3, 1);
      final req = EvvCorrectionRequest(
        originalRecordId: 42,
        reasonCode: 'CAREGIVER_ERROR',
        explanation: 'Wrong caregiver assigned',
        serviceType: 'Respite Care',
        individualName: 'Charlie',
        dateOfService: dateOfService,
        timeIn: timeIn,
        timeOut: timeOut,
        locationLat: 39.0,
        locationLng: -76.5,
        locationSource: 'WIFI',
        stateCode: 'VA',
        deviceInfo: {'model': 'Pixel'},
      );
      expect(req.originalRecordId, 42);
      expect(req.reasonCode, 'CAREGIVER_ERROR');
      expect(req.explanation, 'Wrong caregiver assigned');
      expect(req.serviceType, 'Respite Care');
      expect(req.individualName, 'Charlie');
      expect(req.dateOfService, dateOfService);
      expect(req.timeIn, timeIn);
      expect(req.timeOut, timeOut);
      expect(req.locationLat, 39.0);
      expect(req.locationLng, -76.5);
      expect(req.locationSource, 'WIFI');
      expect(req.stateCode, 'VA');
      expect(req.deviceInfo!['model'], 'Pixel');
    });
  });

  // ─── EvvRecordRequest ───────────────────────────────────────────────────

  group('EvvRecordRequest', () {
    test('constructor stores required fields correctly', () {
      final dateOfService = DateTime(2025, 3, 1);
      final timeIn = DateTime(2025, 3, 1, 8, 0);
      final timeOut = DateTime(2025, 3, 1, 10, 0);
      final req = EvvRecordRequest(
        serviceType: 'Personal Care',
        patientId: 100,
        caregiverId: 200,
        dateOfService: dateOfService,
        timeIn: timeIn,
        timeOut: timeOut,
        stateCode: 'MD',
      );
      expect(req.serviceType, 'Personal Care');
      expect(req.patientId, 100);
      expect(req.caregiverId, 200);
      expect(req.dateOfService, dateOfService);
      expect(req.timeIn, timeIn);
      expect(req.timeOut, timeOut);
      expect(req.stateCode, 'MD');
    });

    test('optional location fields are null by default', () {
      final req = EvvRecordRequest(
        serviceType: 'Personal Care',
        patientId: 1,
        caregiverId: 2,
        dateOfService: DateTime(2025, 1, 1),
        timeIn: DateTime(2025, 1, 1, 8, 0),
        timeOut: DateTime(2025, 1, 1, 10, 0),
        stateCode: 'MD',
      );
      expect(req.locationLat, isNull);
      expect(req.locationLng, isNull);
      expect(req.locationSource, isNull);
      expect(req.checkinLocationLat, isNull);
      expect(req.checkinLocationLng, isNull);
      expect(req.checkinLocationSource, isNull);
      expect(req.checkoutLocationLat, isNull);
      expect(req.checkoutLocationLng, isNull);
      expect(req.checkoutLocationSource, isNull);
      expect(req.scheduledVisitId, isNull);
    });

    test('all optional fields stored when provided', () {
      final req = EvvRecordRequest(
        serviceType: 'Skilled Nursing',
        patientId: 10,
        caregiverId: 20,
        dateOfService: DateTime(2025, 6, 15),
        timeIn: DateTime(2025, 6, 15, 9, 0),
        timeOut: DateTime(2025, 6, 15, 11, 30),
        stateCode: 'DC',
        locationLat: 38.9072,
        locationLng: -77.0369,
        locationSource: 'GPS',
        checkinLocationLat: 38.9072,
        checkinLocationLng: -77.0369,
        checkinLocationSource: 'GPS',
        checkoutLocationLat: 38.9100,
        checkoutLocationLng: -77.0400,
        checkoutLocationSource: 'MANUAL',
        scheduledVisitId: 555,
      );
      expect(req.locationLat, 38.9072);
      expect(req.locationLng, -77.0369);
      expect(req.locationSource, 'GPS');
      expect(req.checkinLocationLat, 38.9072);
      expect(req.checkinLocationLng, -77.0369);
      expect(req.checkinLocationSource, 'GPS');
      expect(req.checkoutLocationLat, 38.9100);
      expect(req.checkoutLocationLng, -77.0400);
      expect(req.checkoutLocationSource, 'MANUAL');
      expect(req.scheduledVisitId, 555);
    });
  });

  // ─── EvvCorrection constructor ──────────────────────────────────────────

  group('EvvCorrection constructor', () {
    test('can be instantiated directly with required fields', () {
      final now = DateTime.now();
      final record1 = EvvRecord(
        id: 1,
        serviceType: 'Personal Care',
        individualName: 'A',
        caregiverId: 1,
        dateOfService: now,
        timeIn: now,
        timeOut: now,
        status: 'APPROVED',
        stateCode: 'MD',
        isOffline: false,
        eorApprovalRequired: false,
        isCorrected: false,
        createdAt: now,
        updatedAt: now,
      );
      final correction = EvvCorrection(
        id: 100,
        originalRecord: record1,
        correctedRecord: record1,
        reasonCode: 'OTHER',
        explanation: 'Test',
        correctedBy: 5,
        correctedAt: now,
        approvalRequired: false,
        originalValues: {'field': 'old'},
        correctedValues: {'field': 'new'},
      );
      expect(correction.id, 100);
      expect(correction.reasonCode, 'OTHER');
      expect(correction.approvedBy, isNull);
      expect(correction.approvedAt, isNull);
      expect(correction.approvalComment, isNull);
      expect(correction.originalValues['field'], 'old');
      expect(correction.correctedValues['field'], 'new');
    });
  });

  // ─── HTTP method tests ──────────────────────────────────────────────────

  group('EvvService.reviewRecord', () {
    test('200 returns EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.reviewRecord(recordId: 1, approve: true, comment: 'OK');
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/records/1/review'));
          final body = jsonDecode(request.body);
          expect(body['approve'], true);
          expect(body['comment'], 'OK');
          return http.Response(jsonEncode(_minimalRecordJson()), 200);
        }),
      );
      expect(result, isA<EvvRecord>());
      expect(result.id, 1);
    });

    test('200 with approve=false and no comment', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.reviewRecord(recordId: 5, approve: false);
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['approve'], false);
          expect(body['comment'], isNull);
          return http.Response(jsonEncode(_minimalRecordJson(id: 5)), 200);
        }),
      );
      expect(result.id, 5);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.reviewRecord(recordId: 1, approve: true);
          },
          () => MockClient((_) async => http.Response('error', 500)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.getRecordsByStatus', () {
    test('200 returns list of EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getRecordsByStatus('APPROVED');
        },
        () => MockClient((request) async {
          expect(request.url.queryParameters['status'], 'APPROVED');
          return http.Response(
            jsonEncode([_minimalRecordJson(id: 1), _minimalRecordJson(id: 2)]),
            200,
          );
        }),
      );
      expect(result.length, 2);
      expect(result[0].id, 1);
      expect(result[1].id, 2);
    });

    test('200 returns empty list', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getRecordsByStatus('REJECTED');
        },
        () => MockClient((_) async => http.Response(jsonEncode([]), 200)),
      );
      expect(result, isEmpty);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.getRecordsByStatus('BAD');
          },
          () => MockClient((_) async => http.Response('error', 400)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.searchRecords', () {
    test('200 returns EvvSearchResult with all params', () async {
      final searchResult = {
        'content': [_minimalRecordJson()],
        'totalElements': 1,
        'totalPages': 1,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.searchRecords(EvvSearchRequest(
            patientName: 'Alice',
            serviceType: 'Personal Care',
            caregiverId: 7,
            startDate: DateTime(2025, 1, 1),
            endDate: DateTime(2025, 1, 31),
            stateCode: 'MD',
            status: 'APPROVED',
            page: 1,
            size: 10,
            sortBy: 'dateOfService',
            sortDirection: 'ASC',
          ));
        },
        () => MockClient((request) async {
          expect(request.url.queryParameters['patientName'], 'Alice');
          expect(request.url.queryParameters['serviceType'], 'Personal Care');
          expect(request.url.queryParameters['caregiverId'], '7');
          expect(request.url.queryParameters['stateCode'], 'MD');
          expect(request.url.queryParameters['status'], 'APPROVED');
          expect(request.url.queryParameters['page'], '1');
          expect(request.url.queryParameters['size'], '10');
          expect(request.url.queryParameters['sortBy'], 'dateOfService');
          expect(request.url.queryParameters['sortDirection'], 'ASC');
          expect(request.url.queryParameters.containsKey('startDate'), isTrue);
          expect(request.url.queryParameters.containsKey('endDate'), isTrue);
          return http.Response(jsonEncode(searchResult), 200);
        }),
      );
      expect(result, isA<EvvSearchResult>());
      expect(result.content.length, 1);
      expect(result.totalElements, 1);
    });

    test('200 with minimal params (defaults)', () async {
      final searchResult = {
        'content': <dynamic>[],
        'totalElements': 0,
        'totalPages': 0,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.searchRecords(EvvSearchRequest());
        },
        () => MockClient((request) async {
          // No optional params should be present
          expect(request.url.queryParameters.containsKey('patientName'), isFalse);
          expect(request.url.queryParameters.containsKey('serviceType'), isFalse);
          expect(request.url.queryParameters.containsKey('caregiverId'), isFalse);
          expect(request.url.queryParameters['page'], '0');
          expect(request.url.queryParameters['size'], '20');
          return http.Response(jsonEncode(searchResult), 200);
        }),
      );
      expect(result.content, isEmpty);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.searchRecords(EvvSearchRequest());
          },
          () => MockClient((_) async => http.Response('error', 500)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.getPendingEorApprovals', () {
    test('200 returns list of EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getPendingEorApprovals();
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/pending-eor-approvals'));
          return http.Response(
            jsonEncode([_minimalRecordJson()]),
            200,
          );
        }),
      );
      expect(result.length, 1);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.getPendingEorApprovals();
          },
          () => MockClient((_) async => http.Response('forbidden', 403)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.approveEor', () {
    test('200 returns EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.approveEor(recordId: 42, comment: 'Approved');
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/eor-approve'));
          final body = jsonDecode(request.body);
          expect(body['recordId'], 42);
          expect(body['comment'], 'Approved');
          return http.Response(jsonEncode(_minimalRecordJson(id: 42)), 200);
        }),
      );
      expect(result.id, 42);
    });

    test('200 without comment', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.approveEor(recordId: 10);
        },
        () => MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['comment'], isNull);
          return http.Response(jsonEncode(_minimalRecordJson(id: 10)), 200);
        }),
      );
      expect(result.id, 10);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.approveEor(recordId: 1);
          },
          () => MockClient((_) async => http.Response('error', 400)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.getPendingCorrections', () {
    test('200 returns list of EvvCorrection', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getPendingCorrections();
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/corrections/pending'));
          return http.Response(
            jsonEncode([_correctionJson()]),
            200,
          );
        }),
      );
      expect(result.length, 1);
      expect(result[0], isA<EvvCorrection>());
      expect(result[0].id, 1);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.getPendingCorrections();
          },
          () => MockClient((_) async => http.Response('error', 500)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.approveCorrection', () {
    test('200 with comment returns EvvCorrection', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.approveCorrection(correctionId: 5, comment: 'LGTM');
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/corrections/5/approve'));
          expect(request.url.queryParameters['comment'], 'LGTM');
          return http.Response(jsonEncode(_correctionJson(id: 5)), 200);
        }),
      );
      expect(result.id, 5);
    });

    test('200 without comment', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.approveCorrection(correctionId: 3);
        },
        () => MockClient((request) async {
          // No comment query param when null
          expect(request.url.queryParameters.containsKey('comment'), isFalse);
          return http.Response(jsonEncode(_correctionJson(id: 3)), 200);
        }),
      );
      expect(result.id, 3);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.approveCorrection(correctionId: 1);
          },
          () => MockClient((_) async => http.Response('error', 404)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.getOfflineQueue', () {
    test('200 returns list of EvvOfflineQueue', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getOfflineQueue();
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/offline/queue'));
          return http.Response(
            jsonEncode([_offlineQueueJson(id: 1), _offlineQueueJson(id: 2)]),
            200,
          );
        }),
      );
      expect(result.length, 2);
      expect(result[0], isA<EvvOfflineQueue>());
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.getOfflineQueue();
          },
          () => MockClient((_) async => http.Response('error', 500)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.syncOfflineData', () {
    test('200 returns response body', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.syncOfflineData();
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/offline/sync'));
          return http.Response('Sync complete: 3 records', 200);
        }),
      );
      expect(result, 'Sync complete: 3 records');
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.syncOfflineData();
          },
          () => MockClient((_) async => http.Response('error', 503)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.getOfflineStatus', () {
    test('200 returns list of EvvOfflineQueue', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getOfflineStatus();
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/offline/status'));
          return http.Response(
            jsonEncode([_offlineQueueJson()]),
            200,
          );
        }),
      );
      expect(result.length, 1);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.getOfflineStatus();
          },
          () => MockClient((_) async => http.Response('error', 500)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.correctRecord', () {
    test('200 returns EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.correctRecord(EvvCorrectionRequest(
            originalRecordId: 10,
            reasonCode: 'TIME_ERROR',
            explanation: 'Wrong time',
            serviceType: 'Personal Care',
            locationLat: 38.9,
            locationLng: -77.0,
          ));
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/records/correct'));
          final body = jsonDecode(request.body);
          expect(body['originalRecordId'], 10);
          expect(body['reasonCode'], 'TIME_ERROR');
          expect(body['serviceType'], 'Personal Care');
          return http.Response(jsonEncode(_minimalRecordJson(id: 10)), 200);
        }),
      );
      expect(result.id, 10);
    });

    test('non-200 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.correctRecord(EvvCorrectionRequest(
              originalRecordId: 1,
              reasonCode: 'OTHER',
              explanation: 'test',
            ));
          },
          () => MockClient((_) async => http.Response('error', 400)),
        ),
        throwsException,
      );
    });
  });

  group('EvvService.createRecord', () {
    test('201 returns EvvRecord', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.createRecord(EvvRecordRequest(
            serviceType: 'Personal Care',
            patientId: 100,
            caregiverId: 200,
            dateOfService: DateTime(2025, 3, 1),
            timeIn: DateTime(2025, 3, 1, 8, 0),
            timeOut: DateTime(2025, 3, 1, 10, 0),
            stateCode: 'MD',
            locationLat: 38.9,
            locationLng: -77.0,
            locationSource: 'GPS',
            checkinLocationLat: 38.9,
            checkinLocationLng: -77.0,
            checkinLocationSource: 'GPS',
            checkoutLocationLat: 38.91,
            checkoutLocationLng: -77.04,
            checkoutLocationSource: 'MANUAL',
            scheduledVisitId: 42,
          ));
        },
        () => MockClient((request) async {
          expect(request.url.path, contains('/records'));
          final body = jsonDecode(request.body);
          expect(body['serviceType'], 'Personal Care');
          expect(body['patientId'], 100);
          expect(body['caregiverId'], 200);
          expect(body['stateCode'], 'MD');
          expect(body['locationLat'], 38.9);
          expect(body['locationLng'], -77.0);
          expect(body['locationSource'], 'GPS');
          expect(body['checkinLocationLat'], 38.9);
          expect(body['checkinLocationLng'], -77.0);
          expect(body['checkinLocationSource'], 'GPS');
          expect(body['checkoutLocationLat'], 38.91);
          expect(body['checkoutLocationLng'], -77.04);
          expect(body['checkoutLocationSource'], 'MANUAL');
          expect(body['scheduledVisitId'], 42);
          expect(body['dateOfService'], startsWith('2025-03-01'));
          expect(body['timeIn'], isA<String>());
          expect(body['timeOut'], isA<String>());
          expect(body['deviceInfo'], isA<Map>());
          return http.Response(jsonEncode(_minimalRecordJson()), 201);
        }),
      );
      expect(result, isA<EvvRecord>());
      expect(result.id, 1);
    });

    test('200 also accepted', () async {
      final result = await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.createRecord(EvvRecordRequest(
            serviceType: 'Companion Care',
            patientId: 1,
            caregiverId: 2,
            dateOfService: DateTime(2025, 1, 1),
            timeIn: DateTime(2025, 1, 1, 8, 0),
            timeOut: DateTime(2025, 1, 1, 10, 0),
            stateCode: 'DC',
          ));
        },
        () => MockClient((_) async =>
            http.Response(jsonEncode(_minimalRecordJson()), 200)),
      );
      expect(result, isA<EvvRecord>());
    });

    test('non-200/201 throws exception', () async {
      expect(
        () => _runWithMockHandler(
          () {
            final service = EvvService();
            return service.createRecord(EvvRecordRequest(
              serviceType: 'Personal Care',
              patientId: 1,
              caregiverId: 2,
              dateOfService: DateTime(2025, 1, 1),
              timeIn: DateTime(2025, 1, 1, 8, 0),
              timeOut: DateTime(2025, 1, 1, 10, 0),
              stateCode: 'MD',
            ));
          },
          () => MockClient((_) async => http.Response('error', 422)),
        ),
        throwsException,
      );
    });

    test('device ID is persisted in SharedPreferences', () async {
      await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.createRecord(EvvRecordRequest(
            serviceType: 'Personal Care',
            patientId: 1,
            caregiverId: 2,
            dateOfService: DateTime(2025, 1, 1),
            timeIn: DateTime(2025, 1, 1, 8, 0),
            timeOut: DateTime(2025, 1, 1, 10, 0),
            stateCode: 'MD',
          ));
        },
        () => MockClient((request) async {
          // Verify X-Device-ID header is present
          expect(request.headers.containsKey('X-Device-ID'), isTrue);
          expect(request.headers['X-Device-ID'], isNotEmpty);
          return http.Response(jsonEncode(_minimalRecordJson()), 201);
        }),
      );
      // After createRecord, device ID should be persisted
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('evv_device_id');
      expect(deviceId, isNotNull);
      expect(deviceId, isNotEmpty);
    });

    test('reuses existing device ID from SharedPreferences', () async {
      // Pre-seed a device ID
      SharedPreferences.setMockInitialValues({'evv_device_id': 'my-test-id'});

      await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.createRecord(EvvRecordRequest(
            serviceType: 'Personal Care',
            patientId: 1,
            caregiverId: 2,
            dateOfService: DateTime(2025, 1, 1),
            timeIn: DateTime(2025, 1, 1, 8, 0),
            timeOut: DateTime(2025, 1, 1, 10, 0),
            stateCode: 'MD',
          ));
        },
        () => MockClient((request) async {
          expect(request.headers['X-Device-ID'], 'my-test-id');
          return http.Response(jsonEncode(_minimalRecordJson()), 201);
        }),
      );
    });
  });

  group('EvvService._getHeaders', () {
    test('headers include Content-Type', () async {
      await _runWithMockHandler(
        () {
          final service = EvvService();
          return service.getRecordsByStatus('APPROVED');
        },
        () => MockClient((request) async {
          expect(request.headers['Content-Type'], 'application/json');
          return http.Response(jsonEncode([]), 200);
        }),
      );
    });
  });
}
