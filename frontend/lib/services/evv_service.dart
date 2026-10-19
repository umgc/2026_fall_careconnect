import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../features/dashboard/models/patient_model.dart';
import 'auth_token_manager.dart';

import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

class EvvService {
  static final String _baseUrl = ApiConstants.evv;
  static const String _deviceIdKey = 'evv_device_id';

  final http.Client _client = ApiServiceOffline.httpClient;
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Uuid _uuid = const Uuid();

  // Helper function to format datetime with timezone for backend compatibility
  String _formatDateTimeWithTimezone(DateTime dateTime) {
    // Convert to UTC and format with timezone offset
    final utc = dateTime.toUtc();
    final offset = dateTime.timeZoneOffset;
    final hours = offset.inHours.abs();
    final minutes = offset.inMinutes.abs() % 60;
    final sign = offset.isNegative ? '-' : '+';
    final timezoneOffset =
        '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

    return utc.toIso8601String().replaceAll('Z', timezoneOffset);
  }

  // EVV Data Models
  static const List<String> serviceTypes = [
    'Personal Care',
    'Companion Care',
    'Respite Care',
    'Homemaker Services',
    'Skilled Nursing',
    'Physical Therapy',
    'Occupational Therapy',
    'Speech Therapy',
    'Medical Social Work',
    'Home Health Aide'
  ];

  static const List<String> stateCodes = ['MD', 'DC', 'VA'];

  static const List<String> correctionReasonCodes = [
    'TIME_ERROR',
    'LOCATION_ERROR',
    'SERVICE_TYPE_ERROR',
    'PATIENT_ERROR',
    'CAREGIVER_ERROR',
    'SYSTEM_ERROR',
    'OTHER'
  ];

  // Device Information
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      // Simplified device info to avoid platform detection issues
      Map<String, dynamic> info = {
        'platform': 'Flutter',
        'app': 'CareConnect EVV',
        'version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Try to get basic device info without platform-specific calls
      try {
        final deviceInfo = _deviceInfo;

        // Safe platform detection without using Platform.isAndroid/isIOS
        if (Platform.isAndroid) {
          try {
            final androidInfo = await deviceInfo.androidInfo;
            // ignore: dead_null_aware_expression
            info['deviceModel'] = androidInfo.model ?? 'Unknown Android';
            // ignore: dead_null_aware_expression
            info['deviceManufacturer'] = androidInfo.manufacturer ?? 'Unknown';
          } catch (e) {
            print('⚠️ Android info failed: $e');
          }
        } else if (Platform.isIOS) {
          try {
            final iosInfo = await deviceInfo.iosInfo;
            // ignore: dead_null_aware_expression
            info['deviceModel'] = iosInfo.model ?? 'Unknown iOS';
            // ignore: dead_null_aware_expression
            info['deviceName'] = iosInfo.name ?? 'Unknown';
          } catch (e) {
            print('⚠️ iOS info failed: $e');
          }
        }
      } catch (e) {
        print('⚠️ Device info collection failed: $e');
        // Continue with basic info
      }

      return info;
    } catch (e) {
      print('❌ Device info error: $e');
      // Return minimal safe info
      return {
        'platform': 'Flutter',
        'app': 'CareConnect EVV',
        'timestamp': DateTime.now().toIso8601String(),
        'error': 'Device info collection failed',
      };
    }
  }

  // Get or create device ID
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      deviceId = _uuid.v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  // Check connectivity
  Future<bool> _isOnline() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Get headers with JWT authentication
  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    try {
      // Retrieve stored JWT token
      final jwtToken = await AuthTokenManager.getJwtToken();

      if (jwtToken != null && jwtToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $jwtToken';
        print('✅ EVV Service: JWT token added to headers');
      } else {
        print('⚠️  EVV Service: No JWT token found. Authentication may fail.');
      }
    } catch (e) {
      print('❌ EVV Service: Error retrieving JWT token: $e');
    }

    return headers;
  }

  // Create EVV Record
  Future<EvvRecord> createRecord(EvvRecordRequest request) async {
    final headers = await _getHeaders();
    final deviceId = await _getDeviceId();
    final deviceInfo = await _getDeviceInfo();

    // Add device ID to headers for offline tracking
    headers['X-Device-ID'] = deviceId;

    final timeInFormatted = _formatDateTimeWithTimezone(request.timeIn);
    final timeOutFormatted = _formatDateTimeWithTimezone(request.timeOut);

    print('🔍 EVV Service: Formatted timeIn: $timeInFormatted');
    print('🔍 EVV Service: Formatted timeOut: $timeOutFormatted');
    print('🔍 EVV Service: ScheduledVisitId: ${request.scheduledVisitId}');

    final body = jsonEncode({
      'serviceType': request.serviceType,
      'patientId': request.patientId,
      'caregiverId': request.caregiverId,
      'dateOfService': request.dateOfService.toIso8601String().split('T')[0],
      'timeIn': timeInFormatted,
      'timeOut': timeOutFormatted,
      // Legacy location fields
      'locationLat': request.locationLat,
      'locationLng': request.locationLng,
      'locationSource': request.locationSource,
      // New check-in/check-out location fields
      'checkinLocationLat': request.checkinLocationLat,
      'checkinLocationLng': request.checkinLocationLng,
      'checkinLocationSource': request.checkinLocationSource,
      'checkoutLocationLat': request.checkoutLocationLat,
      'checkoutLocationLng': request.checkoutLocationLng,
      'checkoutLocationSource': request.checkoutLocationSource,
      'stateCode': request.stateCode,
      'deviceInfo': deviceInfo,
      'scheduledVisitId': request.scheduledVisitId,
      if (request.checkinNoGpsReason != null)
        'checkinNoGpsReason': request.checkinNoGpsReason,
      if (request.checkoutNoGpsReason != null)
        'checkoutNoGpsReason': request.checkoutNoGpsReason,
      if (request.checkinAccuracyM != null)
        'checkinAccuracyM': request.checkinAccuracyM,
      if (request.checkoutAccuracyM != null)
        'checkoutAccuracyM': request.checkoutAccuracyM,
    });

    print('📤 EVV Service: Request body: $body');

    final isOnline = await _isOnline();
    final endpoint =
        isOnline ? '$_baseUrl/records' : '$_baseUrl/records/offline';

    final response = await _client.post(
      Uri.parse(endpoint),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return EvvRecord.fromJson(data);
    } else {
      throw Exception('Failed to create record: ${response.body}');
    }
  }

  // Review EVV Record
  Future<EvvRecord> reviewRecord({
    required int recordId,
    required bool approve,
    String? comment,
  }) async {
    final headers = await _getHeaders();
    final body = jsonEncode({
      'approve': approve,
      'comment': comment,
    });

    final response = await _client.post(
      Uri.parse('$_baseUrl/records/$recordId/review'),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EvvRecord.fromJson(data);
    } else {
      throw Exception('Failed to review record: ${response.body}');
    }
  }

  // Correct EVV Record
  Future<EvvRecord> correctRecord(EvvCorrectionRequest request) async {
    final headers = await _getHeaders();
    final body = jsonEncode(request.toJson());

    final response = await _client.post(
      Uri.parse('$_baseUrl/records/correct'),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EvvRecord.fromJson(data);
    } else {
      throw Exception('Failed to correct record: ${response.body}');
    }
  }

  // Get Records by Status (simpler endpoint)
  Future<List<EvvRecord>> getRecordsByStatus(String status) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{'status': status};

    final uri =
        Uri.parse('$_baseUrl/records').replace(queryParameters: queryParams);

    final response = await _client.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvRecord.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get records by status: ${response.body}');
    }
  }

  // Search EVV Records
  Future<EvvSearchResult> searchRecords(EvvSearchRequest request) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{};

    if (request.patientName != null)
      queryParams['patientName'] = request.patientName!;
    if (request.serviceType != null)
      queryParams['serviceType'] = request.serviceType!;
    if (request.caregiverId != null)
      queryParams['caregiverId'] = request.caregiverId.toString();
    if (request.startDate != null)
      queryParams['startDate'] =
          request.startDate!.toIso8601String().split('T')[0];
    if (request.endDate != null)
      queryParams['endDate'] = request.endDate!.toIso8601String().split('T')[0];
    if (request.stateCode != null)
      queryParams['stateCode'] = request.stateCode!;
    if (request.status != null) queryParams['status'] = request.status!;
    queryParams['page'] = request.page.toString();
    queryParams['size'] = request.size.toString();
    queryParams['sortBy'] = request.sortBy;
    queryParams['sortDirection'] = request.sortDirection;

    final uri = Uri.parse('$_baseUrl/records/search')
        .replace(queryParameters: queryParams);

    final response = await _client.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EvvSearchResult.fromJson(data);
    } else {
      throw Exception('Failed to search records: ${response.body}');
    }
  }

  // Get Pending EOR Approvals
  Future<List<EvvRecord>> getPendingEorApprovals() async {
    final headers = await _getHeaders();

    final response = await _client.get(
      Uri.parse('$_baseUrl/records/pending-eor-approvals'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvRecord.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get pending EOR approvals: ${response.body}');
    }
  }

  // Approve EOR
  Future<EvvRecord> approveEor({
    required int recordId,
    String? comment,
  }) async {
    final headers = await _getHeaders();
    final body = jsonEncode({
      'recordId': recordId,
      'comment': comment,
    });

    final response = await _client.post(
      Uri.parse('$_baseUrl/records/eor-approve'),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EvvRecord.fromJson(data);
    } else {
      throw Exception('Failed to approve EOR: ${response.body}');
    }
  }

  // Get Pending Corrections
  Future<List<EvvCorrection>> getPendingCorrections() async {
    final headers = await _getHeaders();

    final response = await _client.get(
      Uri.parse('$_baseUrl/corrections/pending'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvCorrection.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get pending corrections: ${response.body}');
    }
  }

  // Approve Correction
  Future<EvvCorrection> approveCorrection({
    required int correctionId,
    String? comment,
  }) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{};
    if (comment != null) queryParams['comment'] = comment;

    final uri = Uri.parse('$_baseUrl/corrections/$correctionId/approve')
        .replace(queryParameters: queryParams);

    final response = await _client.post(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EvvCorrection.fromJson(data);
    } else {
      throw Exception('Failed to approve correction: ${response.body}');
    }
  }

  // Get Offline Queue
  Future<List<EvvOfflineQueue>> getOfflineQueue() async {
    final headers = await _getHeaders();

    final response = await _client.get(
      Uri.parse('$_baseUrl/offline/queue'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvOfflineQueue.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get offline queue: ${response.body}');
    }
  }

  // Get HHAExchange-eligible records (status = APPROVED, stateCode = VA)
  Future<List<EvvRecord>> getHhaExchangeEligibleRecords() async {
    final headers = await _getHeaders();

    final response = await _client.get(
      Uri.parse('$_baseUrl/records/hhaexchange-eligible'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvRecord.fromJson(item)).toList();
    } else {
      throw Exception(
          'Failed to get HHAExchange eligible records: ${response.body}');
    }
  }

  // Submit selected records to HHAExchange
  Future<Map<String, dynamic>> submitToHhaExchange(List<int> recordIds) async {
    final headers = await _getHeaders();

    final response = await _client.post(
      Uri.parse('$_baseUrl/records/submit-to-hhaexchange'),
      headers: headers,
      body: jsonEncode(recordIds),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Submission failed: ${response.body}');
    }
  }

  // Fetch the HHAExchange payload JSON without submitting (for local download/audit)
  Future<String> getHhaExchangePayload(List<int> recordIds) async {
    final headers = await _getHeaders();
    final response = await _client.post(
      Uri.parse('$_baseUrl/records/hhaexchange-payload'),
      headers: headers,
      body: jsonEncode(recordIds),
    );
    if (response.statusCode == 200) {
      return response.body; // raw JSON string
    } else {
      throw Exception('Failed to get payload: ${response.body}');
    }
  }

  // Sync Offline Data
  Future<String> syncOfflineData() async {
    final headers = await _getHeaders();

    final response = await _client.post(
      Uri.parse('$_baseUrl/offline/sync'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to sync offline data: ${response.body}');
    }
  }

  // Get Offline Status
  Future<List<EvvOfflineQueue>> getOfflineStatus() async {
    final headers = await _getHeaders();

    final response = await _client.get(
      Uri.parse('$_baseUrl/offline/status'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => EvvOfflineQueue.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get offline status: ${response.body}');
    }
  }

  void dispose() {
    // _client is the shared ApiServiceOffline.httpClient singleton — do not close it here.
    // Closing it would invalidate the client for all other EvvService instances app-wide.
  }
}

// Data Models
class EvvRecord {
  final int id;
  final Patient? patient;
  final String serviceType;
  final String individualName;
  final int caregiverId;
  final DateTime dateOfService;
  final DateTime timeIn;
  final DateTime timeOut;

  // Legacy location fields
  final double? locationLat;
  final double? locationLng;
  final String? locationSource;

  // New check-in/check-out location fields
  final double? checkinLocationLat;
  final double? checkinLocationLng;
  final String? checkinLocationSource;
  final double? checkoutLocationLat;
  final double? checkoutLocationLng;
  final String? checkoutLocationSource;

  final String status;
  final String stateCode;
  final Map<String, dynamic>? deviceInfo;
  final bool isOffline;
  final String? syncStatus;
  final DateTime? lastSyncAttempt;
  final bool eorApprovalRequired;
  final int? eorApprovedBy;
  final DateTime? eorApprovedAt;
  final String? eorApprovalComment;
  final bool isCorrected;
  final int? originalRecordId;
  final String? correctionReasonCode;
  final String? correctionExplanation;
  final int? correctedBy;
  final DateTime? correctedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  EvvRecord({
    required this.id,
    this.patient,
    required this.serviceType,
    required this.individualName,
    required this.caregiverId,
    required this.dateOfService,
    required this.timeIn,
    required this.timeOut,
    this.locationLat,
    this.locationLng,
    this.locationSource,
    this.checkinLocationLat,
    this.checkinLocationLng,
    this.checkinLocationSource,
    this.checkoutLocationLat,
    this.checkoutLocationLng,
    this.checkoutLocationSource,
    required this.status,
    required this.stateCode,
    this.deviceInfo,
    required this.isOffline,
    this.syncStatus,
    this.lastSyncAttempt,
    required this.eorApprovalRequired,
    this.eorApprovedBy,
    this.eorApprovedAt,
    this.eorApprovalComment,
    required this.isCorrected,
    this.originalRecordId,
    this.correctionReasonCode,
    this.correctionExplanation,
    this.correctedBy,
    this.correctedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EvvRecord.fromJson(Map<String, dynamic> json) {
    return EvvRecord(
      id: json['id'],
      patient:
          json['patient'] != null ? Patient.fromJson(json['patient']) : null,
      serviceType: json['serviceType'],
      individualName: json['individualName'],
      caregiverId: json['caregiverId'],
      dateOfService: DateTime.parse(json['dateOfService']),
      timeIn: DateTime.parse(json['timeIn']),
      timeOut: DateTime.parse(json['timeOut']),
      // Legacy location fields
      locationLat: json['locationLat']?.toDouble(),
      locationLng: json['locationLng']?.toDouble(),
      locationSource: json['locationSource'],
      // New check-in/check-out location fields
      checkinLocationLat: json['checkinLocationLat']?.toDouble(),
      checkinLocationLng: json['checkinLocationLng']?.toDouble(),
      checkinLocationSource: json['checkinLocationSource'],
      checkoutLocationLat: json['checkoutLocationLat']?.toDouble(),
      checkoutLocationLng: json['checkoutLocationLng']?.toDouble(),
      checkoutLocationSource: json['checkoutLocationSource'],
      status: json['status'],
      stateCode: json['stateCode'],
      deviceInfo: json['deviceInfo'],
      isOffline: json['isOffline'] ?? false,
      syncStatus: json['syncStatus'],
      lastSyncAttempt: json['lastSyncAttempt'] != null
          ? DateTime.parse(json['lastSyncAttempt'])
          : null,
      eorApprovalRequired: json['eorApprovalRequired'] ?? false,
      eorApprovedBy: json['eorApprovedBy'],
      eorApprovedAt: json['eorApprovedAt'] != null
          ? DateTime.parse(json['eorApprovedAt'])
          : null,
      eorApprovalComment: json['eorApprovalComment'],
      isCorrected: json['isCorrected'] ?? false,
      originalRecordId: json['originalRecordId'],
      correctionReasonCode: json['correctionReasonCode'],
      correctionExplanation: json['correctionExplanation'],
      correctedBy: json['correctedBy'],
      correctedAt: json['correctedAt'] != null
          ? DateTime.parse(json['correctedAt'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class EvvCorrection {
  final int id;
  final EvvRecord originalRecord;
  final EvvRecord correctedRecord;
  final String reasonCode;
  final String explanation;
  final int correctedBy;
  final DateTime correctedAt;
  final bool approvalRequired;
  final int? approvedBy;
  final DateTime? approvedAt;
  final String? approvalComment;
  final Map<String, dynamic> originalValues;
  final Map<String, dynamic> correctedValues;

  EvvCorrection({
    required this.id,
    required this.originalRecord,
    required this.correctedRecord,
    required this.reasonCode,
    required this.explanation,
    required this.correctedBy,
    required this.correctedAt,
    required this.approvalRequired,
    this.approvedBy,
    this.approvedAt,
    this.approvalComment,
    required this.originalValues,
    required this.correctedValues,
  });

  factory EvvCorrection.fromJson(Map<String, dynamic> json) {
    return EvvCorrection(
      id: json['id'],
      originalRecord: EvvRecord.fromJson(json['originalRecord']),
      correctedRecord: EvvRecord.fromJson(json['correctedRecord']),
      reasonCode: json['reasonCode'],
      explanation: json['explanation'],
      correctedBy: json['correctedBy'],
      correctedAt: DateTime.parse(json['correctedAt']),
      approvalRequired: json['approvalRequired'] ?? false,
      approvedBy: json['approvedBy'],
      approvedAt: json['approvedAt'] != null
          ? DateTime.parse(json['approvedAt'])
          : null,
      approvalComment: json['approvalComment'],
      originalValues: json['originalValues'] ?? {},
      correctedValues: json['correctedValues'] ?? {},
    );
  }
}

class EvvOfflineQueue {
  final int id;
  final int recordId;
  final String operationType;
  final int caregiverId;
  final String? deviceId;
  final DateTime queuedAt;
  final int syncAttempts;
  final DateTime? lastSyncAttempt;
  final String syncStatus;
  final String? lastError;
  final int priority;
  final Map<String, dynamic> recordData;

  EvvOfflineQueue({
    required this.id,
    required this.recordId,
    required this.operationType,
    required this.caregiverId,
    this.deviceId,
    required this.queuedAt,
    required this.syncAttempts,
    this.lastSyncAttempt,
    required this.syncStatus,
    this.lastError,
    required this.priority,
    required this.recordData,
  });

  factory EvvOfflineQueue.fromJson(Map<String, dynamic> json) {
    return EvvOfflineQueue(
      id: json['id'],
      recordId: json['recordId'],
      operationType: json['operationType'],
      caregiverId: json['caregiverId'],
      deviceId: json['deviceId'],
      queuedAt: DateTime.parse(json['queuedAt']),
      syncAttempts: json['syncAttempts'] ?? 0,
      lastSyncAttempt: json['lastSyncAttempt'] != null
          ? DateTime.parse(json['lastSyncAttempt'])
          : null,
      syncStatus: json['syncStatus'],
      lastError: json['lastError'],
      priority: json['priority'] ?? 1,
      recordData: json['recordData'] ?? {},
    );
  }
}

// Request Models
class EvvRecordRequest {
  final String serviceType;
  final int patientId; // Direct reference to patient
  final int caregiverId;
  final DateTime dateOfService;
  final DateTime timeIn;
  final DateTime timeOut;

  // Legacy location fields (for backward compatibility)
  final double? locationLat;
  final double? locationLng;
  final String? locationSource;

  // New check-in/check-out location fields
  final double? checkinLocationLat;
  final double? checkinLocationLng;
  final String? checkinLocationSource;
  final double? checkoutLocationLat;
  final double? checkoutLocationLng;
  final String? checkoutLocationSource;

  final String stateCode;

  // Optional link to scheduled visit
  final int? scheduledVisitId;

  // EVV location detail fields
  final String? checkinNoGpsReason;
  final String? checkoutNoGpsReason;
  final double? checkinAccuracyM;
  final double? checkoutAccuracyM;

  EvvRecordRequest({
    required this.serviceType,
    required this.patientId,
    required this.caregiverId,
    required this.dateOfService,
    required this.timeIn,
    required this.timeOut,
    this.locationLat,
    this.locationLng,
    this.locationSource,
    this.checkinLocationLat,
    this.checkinLocationLng,
    this.checkinLocationSource,
    this.checkoutLocationLat,
    this.checkoutLocationLng,
    this.checkoutLocationSource,
    required this.stateCode,
    this.scheduledVisitId,
    this.checkinNoGpsReason,
    this.checkoutNoGpsReason,
    this.checkinAccuracyM,
    this.checkoutAccuracyM,
  });
}

class EvvCorrectionRequest {
  final int originalRecordId;
  final String reasonCode;
  final String explanation;
  final String? serviceType;
  final String? individualName;
  final DateTime? dateOfService;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final double? locationLat;
  final double? locationLng;
  final String? locationSource;
  final String? stateCode;
  final Map<String, dynamic>? deviceInfo;

  EvvCorrectionRequest({
    required this.originalRecordId,
    required this.reasonCode,
    required this.explanation,
    this.serviceType,
    this.individualName,
    this.dateOfService,
    this.timeIn,
    this.timeOut,
    this.locationLat,
    this.locationLng,
    this.locationSource,
    this.stateCode,
    this.deviceInfo,
  });

  Map<String, dynamic> toJson() {
    // Helper function to format datetime with timezone for backend compatibility
    String formatDateTimeWithTimezone(DateTime dateTime) {
      final utc = dateTime.toUtc();
      final offset = dateTime.timeZoneOffset;
      final hours = offset.inHours.abs();
      final minutes = offset.inMinutes.abs() % 60;
      final sign = offset.isNegative ? '-' : '+';
      final timezoneOffset =
          '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

      return utc.toIso8601String().replaceAll('Z', timezoneOffset);
    }

    return {
      'originalRecordId': originalRecordId,
      'reasonCode': reasonCode,
      'explanation': explanation,
      if (serviceType != null) 'serviceType': serviceType,
      if (individualName != null) 'individualName': individualName,
      if (dateOfService != null)
        'dateOfService': dateOfService!.toIso8601String().split('T')[0],
      if (timeIn != null) 'timeIn': formatDateTimeWithTimezone(timeIn!),
      if (timeOut != null) 'timeOut': formatDateTimeWithTimezone(timeOut!),
      if (locationLat != null) 'locationLat': locationLat,
      if (locationLng != null) 'locationLng': locationLng,
      if (locationSource != null) 'locationSource': locationSource,
      if (stateCode != null) 'stateCode': stateCode,
      if (deviceInfo != null) 'deviceInfo': deviceInfo,
    };
  }
}

class EvvSearchRequest {
  final String? patientName;
  final String? serviceType;
  final int? caregiverId;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? stateCode;
  final String? status;
  final int page;
  final int size;
  final String sortBy;
  final String sortDirection;

  EvvSearchRequest({
    this.patientName,
    this.serviceType,
    this.caregiverId,
    this.startDate,
    this.endDate,
    this.stateCode,
    this.status,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.sortDirection = 'DESC',
  });
}

class EvvSearchResult {
  final List<EvvRecord> content;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;
  final bool first;
  final bool last;

  EvvSearchResult({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.size,
    required this.number,
    required this.first,
    required this.last,
  });

  factory EvvSearchResult.fromJson(Map<String, dynamic> json) {
    return EvvSearchResult(
      content: (json['content'] as List)
          .map((item) => EvvRecord.fromJson(item))
          .toList(),
      totalElements: json['totalElements'],
      totalPages: json['totalPages'],
      size: json['size'],
      number: json['number'],
      first: json['first'],
      last: json['last'],
    );
  }
}
