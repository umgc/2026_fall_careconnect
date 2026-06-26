// Tests for EVV data models defined in evv_service.dart.
// Pure Dart model tests — no HTTP, no mocks, no widgets.
//
// Covers: EvvRecord.fromJson, EvvCorrection.fromJson, EvvOfflineQueue.fromJson,
// EvvRecordRequest constructor, EvvCorrectionRequest.toJson,
// EvvSearchRequest defaults, EvvSearchResult.fromJson.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/services/evv_service.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

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

Map<String, dynamic> _fullRecordJson({int id = 1}) => {
      ..._minimalRecordJson(id: id),
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
      'locationLat': 38.9072,
      'locationLng': -77.0369,
      'locationSource': 'GPS',
      'checkinLocationLat': 38.9072,
      'checkinLocationLng': -77.0369,
      'checkinLocationSource': 'GPS',
      'checkoutLocationLat': 38.91,
      'checkoutLocationLng': -77.04,
      'checkoutLocationSource': 'MANUAL',
      'deviceInfo': {'platform': 'Flutter', 'version': '1.0.0'},
      'isOffline': true,
      'syncStatus': 'PENDING',
      'lastSyncAttempt': '2025-03-01T12:00:00.000Z',
      'eorApprovalRequired': true,
      'eorApprovedBy': 5,
      'eorApprovedAt': '2025-03-02T08:00:00.000Z',
      'eorApprovalComment': 'Approved',
      'isCorrected': true,
      'originalRecordId': 99,
      'correctionReasonCode': 'TIME_ERROR',
      'correctionExplanation': 'Wrong clock-in time',
      'correctedBy': 7,
      'correctedAt': '2025-03-02T09:00:00.000Z',
    };

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // =========================================================================
  // EvvRecord.fromJson
  // =========================================================================

  group('EvvRecord.fromJson', () {
    test('parses all required fields from minimal JSON', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());

      expect(record.id, 1);
      expect(record.patient, isNull);
      expect(record.serviceType, 'Personal Care');
      expect(record.individualName, 'Alice Smith');
      expect(record.caregiverId, 10);
      expect(record.status, 'APPROVED');
      expect(record.stateCode, 'MD');
      expect(record.isOffline, false);
      expect(record.eorApprovalRequired, false);
      expect(record.isCorrected, false);
    });

    test('parses all optional fields from full JSON', () {
      final record = EvvRecord.fromJson(_fullRecordJson());

      expect(record.patient, isNotNull);
      expect(record.patient!.firstName, 'Jane');
      expect(record.locationLat, 38.9072);
      expect(record.locationLng, -77.0369);
      expect(record.locationSource, 'GPS');
      expect(record.checkinLocationLat, 38.9072);
      expect(record.checkinLocationSource, 'GPS');
      expect(record.checkoutLocationLat, 38.91);
      expect(record.checkoutLocationSource, 'MANUAL');
      expect(record.deviceInfo, isNotNull);
      expect(record.isOffline, true);
      expect(record.syncStatus, 'PENDING');
      expect(record.lastSyncAttempt, isNotNull);
      expect(record.eorApprovalRequired, true);
      expect(record.eorApprovedBy, 5);
      expect(record.eorApprovedAt, isNotNull);
      expect(record.eorApprovalComment, 'Approved');
      expect(record.isCorrected, true);
      expect(record.originalRecordId, 99);
      expect(record.correctionReasonCode, 'TIME_ERROR');
    });

    test('location fields default to null when absent', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());
      expect(record.locationLat, isNull);
      expect(record.checkinLocationLat, isNull);
      expect(record.checkoutLocationLat, isNull);
    });

    test('isOffline defaults to false when absent', () {
      final json = _minimalRecordJson();
      json.remove('isOffline');
      expect(EvvRecord.fromJson(json).isOffline, false);
    });

    test('eorApprovalRequired defaults to false when absent', () {
      final json = _minimalRecordJson();
      json.remove('eorApprovalRequired');
      expect(EvvRecord.fromJson(json).eorApprovalRequired, false);
    });

    test('isCorrected defaults to false when absent', () {
      final json = _minimalRecordJson();
      json.remove('isCorrected');
      expect(EvvRecord.fromJson(json).isCorrected, false);
    });

    test('parses dateOfService as DateTime', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());
      expect(record.dateOfService.year, 2025);
      expect(record.dateOfService.month, 3);
      expect(record.dateOfService.day, 1);
    });

    test('parses timeIn and timeOut as DateTime', () {
      final record = EvvRecord.fromJson(_minimalRecordJson());
      expect(record.timeIn.hour, 8);
      expect(record.timeOut.hour, 10);
    });
  });

  // =========================================================================
  // EvvRecord constructor
  // =========================================================================

  group('EvvRecord constructor', () {
    test('creates instance with all required fields', () {
      final now = DateTime.now();
      final record = EvvRecord(
        id: 1,
        serviceType: 'Personal Care',
        individualName: 'Test',
        caregiverId: 5,
        dateOfService: now,
        timeIn: now,
        timeOut: now.add(const Duration(hours: 2)),
        status: 'UNDER_REVIEW',
        stateCode: 'VA',
        isOffline: false,
        eorApprovalRequired: false,
        isCorrected: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(record.id, 1);
      expect(record.patient, isNull);
    });
  });

  // =========================================================================
  // EvvCorrection.fromJson
  // =========================================================================

  group('EvvCorrection.fromJson', () {
    test('parses correction with nested records', () {
      final json = {
        'id': 10,
        'originalRecord': _minimalRecordJson(id: 1),
        'correctedRecord': _minimalRecordJson(id: 2),
        'reasonCode': 'TIME_ERROR',
        'explanation': 'Wrong check-in time',
        'correctedBy': 7,
        'correctedAt': '2025-03-02T09:00:00.000Z',
        'approvalRequired': true,
        'approvedBy': 3,
        'approvedAt': '2025-03-02T10:00:00.000Z',
        'approvalComment': 'Verified',
        'originalValues': {'timeIn': '08:00'},
        'correctedValues': {'timeIn': '09:00'},
      };

      final correction = EvvCorrection.fromJson(json);

      expect(correction.id, 10);
      expect(correction.originalRecord.id, 1);
      expect(correction.correctedRecord.id, 2);
      expect(correction.reasonCode, 'TIME_ERROR');
      expect(correction.explanation, 'Wrong check-in time');
      expect(correction.correctedBy, 7);
      expect(correction.approvalRequired, true);
      expect(correction.approvedBy, 3);
      expect(correction.approvalComment, 'Verified');
      expect(correction.originalValues['timeIn'], '08:00');
      expect(correction.correctedValues['timeIn'], '09:00');
    });

    test('approvalRequired defaults to false', () {
      final json = {
        'id': 1,
        'originalRecord': _minimalRecordJson(),
        'correctedRecord': _minimalRecordJson(),
        'reasonCode': 'OTHER',
        'explanation': 'Test',
        'correctedBy': 1,
        'correctedAt': '2025-03-01T08:00:00.000Z',
      };
      expect(EvvCorrection.fromJson(json).approvalRequired, false);
    });

    test('optional approval fields default to null', () {
      final json = {
        'id': 1,
        'originalRecord': _minimalRecordJson(),
        'correctedRecord': _minimalRecordJson(),
        'reasonCode': 'OTHER',
        'explanation': 'Test',
        'correctedBy': 1,
        'correctedAt': '2025-03-01T08:00:00.000Z',
      };
      final correction = EvvCorrection.fromJson(json);
      expect(correction.approvedBy, isNull);
      expect(correction.approvedAt, isNull);
      expect(correction.approvalComment, isNull);
    });
  });

  // =========================================================================
  // EvvOfflineQueue.fromJson
  // =========================================================================

  group('EvvOfflineQueue.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 5,
        'recordId': 42,
        'operationType': 'CREATE',
        'caregiverId': 10,
        'deviceId': 'device-abc',
        'queuedAt': '2025-03-01T08:00:00.000Z',
        'syncAttempts': 3,
        'lastSyncAttempt': '2025-03-01T09:00:00.000Z',
        'syncStatus': 'FAILED',
        'lastError': 'Connection timeout',
        'priority': 2,
        'recordData': {'serviceType': 'Personal Care'},
      };

      final queue = EvvOfflineQueue.fromJson(json);

      expect(queue.id, 5);
      expect(queue.recordId, 42);
      expect(queue.operationType, 'CREATE');
      expect(queue.caregiverId, 10);
      expect(queue.deviceId, 'device-abc');
      expect(queue.syncAttempts, 3);
      expect(queue.syncStatus, 'FAILED');
      expect(queue.lastError, 'Connection timeout');
      expect(queue.priority, 2);
      expect(queue.recordData['serviceType'], 'Personal Care');
    });

    test('syncAttempts defaults to 0', () {
      final json = {
        'id': 1, 'recordId': 1, 'operationType': 'CREATE',
        'caregiverId': 1, 'queuedAt': '2025-03-01T08:00:00.000Z',
        'syncStatus': 'PENDING',
      };
      expect(EvvOfflineQueue.fromJson(json).syncAttempts, 0);
    });

    test('priority defaults to 1', () {
      final json = {
        'id': 1, 'recordId': 1, 'operationType': 'CREATE',
        'caregiverId': 1, 'queuedAt': '2025-03-01T08:00:00.000Z',
        'syncStatus': 'PENDING',
      };
      expect(EvvOfflineQueue.fromJson(json).priority, 1);
    });

    test('optional fields default to null', () {
      final json = {
        'id': 1, 'recordId': 1, 'operationType': 'CREATE',
        'caregiverId': 1, 'queuedAt': '2025-03-01T08:00:00.000Z',
        'syncStatus': 'PENDING',
      };
      final queue = EvvOfflineQueue.fromJson(json);
      expect(queue.deviceId, isNull);
      expect(queue.lastSyncAttempt, isNull);
      expect(queue.lastError, isNull);
    });
  });

  // =========================================================================
  // EvvCorrectionRequest.toJson
  // =========================================================================

  group('EvvCorrectionRequest.toJson', () {
    test('includes required fields', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 42,
        reasonCode: 'TIME_ERROR',
        explanation: 'Wrong time',
      );
      final json = req.toJson();

      expect(json['originalRecordId'], 42);
      expect(json['reasonCode'], 'TIME_ERROR');
      expect(json['explanation'], 'Wrong time');
    });

    test('includes optional fields when set', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'LOCATION_ERROR',
        explanation: 'Wrong location',
        serviceType: 'Skilled Nursing',
        individualName: 'Jane Doe',
        locationLat: 38.9,
        locationLng: -77.0,
        locationSource: 'MANUAL',
        stateCode: 'DC',
      );
      final json = req.toJson();

      expect(json['serviceType'], 'Skilled Nursing');
      expect(json['individualName'], 'Jane Doe');
      expect(json['locationLat'], 38.9);
      expect(json['locationLng'], -77.0);
      expect(json['locationSource'], 'MANUAL');
      expect(json['stateCode'], 'DC');
    });

    test('omits null optional fields', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'OTHER',
        explanation: 'Test',
      );
      final json = req.toJson();

      expect(json.containsKey('serviceType'), false);
      expect(json.containsKey('individualName'), false);
      expect(json.containsKey('locationLat'), false);
      expect(json.containsKey('stateCode'), false);
      expect(json.containsKey('deviceInfo'), false);
    });

    test('dateOfService formatted as date-only string', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'DATE_ERROR',
        explanation: 'Wrong date',
        dateOfService: DateTime(2025, 6, 15),
      );
      final json = req.toJson();
      expect(json['dateOfService'], '2025-06-15');
    });

    test('timeIn formatted with timezone offset', () {
      final req = EvvCorrectionRequest(
        originalRecordId: 1,
        reasonCode: 'TIME_ERROR',
        explanation: 'Wrong time',
        timeIn: DateTime(2025, 6, 15, 9, 0),
      );
      final json = req.toJson();
      expect(json['timeIn'], isA<String>());
      expect(json['timeIn'], isNot(contains('Z')));
    });
  });

  // =========================================================================
  // EvvSearchRequest
  // =========================================================================

  group('EvvSearchRequest', () {
    test('default values', () {
      final req = EvvSearchRequest();
      expect(req.page, 0);
      expect(req.size, 20);
      expect(req.sortBy, 'createdAt');
      expect(req.sortDirection, 'DESC');
      expect(req.patientName, isNull);
      expect(req.status, isNull);
    });

    test('custom values', () {
      final req = EvvSearchRequest(
        patientName: 'Alice',
        status: 'APPROVED',
        page: 2,
        size: 50,
        sortBy: 'dateOfService',
        sortDirection: 'ASC',
      );
      expect(req.patientName, 'Alice');
      expect(req.status, 'APPROVED');
      expect(req.page, 2);
      expect(req.size, 50);
    });
  });

  // =========================================================================
  // EvvSearchResult.fromJson
  // =========================================================================

  group('EvvSearchResult.fromJson', () {
    test('parses content list and pagination fields', () {
      final json = {
        'content': [_minimalRecordJson(id: 1), _minimalRecordJson(id: 2)],
        'totalElements': 2,
        'totalPages': 1,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };

      final result = EvvSearchResult.fromJson(json);

      expect(result.content.length, 2);
      expect(result.content[0].id, 1);
      expect(result.content[1].id, 2);
      expect(result.totalElements, 2);
      expect(result.totalPages, 1);
      expect(result.first, true);
      expect(result.last, true);
    });

    test('empty content list', () {
      final json = {
        'content': [],
        'totalElements': 0,
        'totalPages': 0,
        'size': 20,
        'number': 0,
        'first': true,
        'last': true,
      };

      final result = EvvSearchResult.fromJson(json);
      expect(result.content, isEmpty);
      expect(result.totalElements, 0);
    });

    test('multi-page result', () {
      final json = {
        'content': [_minimalRecordJson()],
        'totalElements': 100,
        'totalPages': 5,
        'size': 20,
        'number': 2,
        'first': false,
        'last': false,
      };

      final result = EvvSearchResult.fromJson(json);
      expect(result.totalPages, 5);
      expect(result.number, 2);
      expect(result.first, false);
      expect(result.last, false);
    });
  });

  // =========================================================================
  // EvvRecordRequest
  // =========================================================================

  group('EvvRecordRequest', () {
    test('creates request with required fields', () {
      final req = EvvRecordRequest(
        serviceType: 'Personal Care',
        patientId: 10,
        caregiverId: 1,
        dateOfService: DateTime(2025, 3, 1),
        timeIn: DateTime(2025, 3, 1, 8, 0),
        timeOut: DateTime(2025, 3, 1, 10, 0),
        stateCode: 'MD',
      );

      expect(req.serviceType, 'Personal Care');
      expect(req.patientId, 10);
      expect(req.caregiverId, 1);
      expect(req.stateCode, 'MD');
      expect(req.scheduledVisitId, isNull);
    });

    test('creates request with optional location fields', () {
      final req = EvvRecordRequest(
        serviceType: 'Companion Care',
        patientId: 5,
        caregiverId: 2,
        dateOfService: DateTime(2025, 6, 15),
        timeIn: DateTime(2025, 6, 15, 14, 0),
        timeOut: DateTime(2025, 6, 15, 16, 0),
        stateCode: 'VA',
        checkinLocationLat: 38.9,
        checkinLocationLng: -77.0,
        checkinLocationSource: 'GPS',
        checkoutLocationLat: 38.91,
        checkoutLocationLng: -77.04,
        checkoutLocationSource: 'MANUAL',
        scheduledVisitId: 42,
      );

      expect(req.checkinLocationLat, 38.9);
      expect(req.checkoutLocationSource, 'MANUAL');
      expect(req.scheduledVisitId, 42);
    });
  });

  // =========================================================================
  // EvvService static data
  // =========================================================================

  group('EvvService static data', () {
    test('serviceTypes list is not empty', () {
      expect(EvvService.serviceTypes, isNotEmpty);
    });

    test('stateCodes list contains MD, DC, VA', () {
      expect(EvvService.stateCodes, containsAll(['MD', 'DC', 'VA']));
    });

    test('correctionReasonCodes list is not empty', () {
      expect(EvvService.correctionReasonCodes, isNotEmpty);
    });
  });
}
