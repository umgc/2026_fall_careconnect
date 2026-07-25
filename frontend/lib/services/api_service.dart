import 'dart:convert';
import 'dart:io';
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../config/env_constant.dart';
import 'api_service_offline.dart';
import 'auth_token_manager.dart';

class ApiConstants {
  //V1 endpoints
  static final String _host = getBackendBaseUrl();
  static final String auth = '$_host/v1/api/auth';
  static final String feed = '$_host/v1/api/feed';
  static final String users = '$_host/v1/api/users';
  static final String friends = '$_host/v1/api/friends';
  static final String analytics = '$_host/v1/api/analytics';
  static final String baseUrl = '$_host/v1/api/';
  static final String familyMembers = '$_host/v3/api/family-members';
  static final String patient = '$_host/v1/api/patient';
  static final String mood = '$_host/v1/api/patient';
  static final String patients = '$_host/v1/api/patients';
  static final String caregivers = '$_host/v1/api/caregivers';
  static final String files = '$_host/v1/api/files';
  static final String connectionRequests = '$_host/v1/api/connection-requests';
  static final String subscriptions = '$_host/v3/api/subscriptions';
  static final String tasks = '$_host/v3/api/tasks';
  static final String patientsV3 = '$_host/v3/api/patients';
  static final String allergies = '$_host/v1/api/allergies';
  static final String symptoms = '$_host/v1/api/symptoms';
  static final String riskTypes = '$_host/v1/api/risk-types';
  static final String callsV3 = '$_host/api/v3/calls';

  // Client activities & logging (client = patient in API)
  static final String clients = '$_host/v1/api/clients';
  static final String activities = '$_host/v1/api/activities';
  static final String config = '$_host/v1/api/config';
  static final String activityLogs = '$_host/v1/api/activity-logs';

  //V2 endpoints
  static final String baseUrlV2 = '$_host/v2/api/';
  static final String tasksV2 = '$_host/v2/api/tasks';

  // AI Services endpoints
  static final String aiChat = '$_host/v1/api/ai-chat';
  static final String aiConfig = '$_host/v1/api/ai-chat/config';
  // Invoices endpoints
  static final String invoices = '$_host/v1/api/invoices';

  // Home Care Document Digitization endpoints
  static final String homeCareDocuments = '$_host/v1/api/homecare-documents';

  // Document Completion & Compliance Tracking endpoints
  static final String documentCompliance = '$_host/v1/api/document-compliance';

  // EVV endpoints
  static final String evv = '$_host/v1/api/evv';

  // Telemetry endpoints
  static final String telemetryV3 = '$_host/v1/api/dev/telemetry';

  // Admin analytics endpoints
  static final String adminAnalytics = '$_host/v1/api/admin/analytics';
}

class ApiService {
  static const storage =
      FlutterSecureStorage(webOptions: WebOptions.defaultOptions);
  static http.Client _httpClient = ApiServiceOffline.httpClient;

  static void configureOfflineQueue({
    required bool Function() canQueueOfflineWrites,
  }) {
    ApiServiceOffline.configure(
      canQueueOfflineWrites: canQueueOfflineWrites,
    );
  }

  static Future<void> initializeOfflineQueue() async {
    await ApiServiceOffline.initialize();
  }

  // Method to dispose of resources
  static void dispose() {
    _httpClient.close();
  }

  @visibleForTesting
  static void debugSetHttpClient(http.Client client) {
    _httpClient.close();
    _httpClient = client;
  }

  @visibleForTesting
  static void debugResetHttpClient() {
    _httpClient.close();
    _httpClient = http.Client();
  }

  // ========================
  // AUTHENTICATION METHODS
  // ========================

  static Future<http.Response> register(
    String name,
    String email,
    String password,
  ) async {
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.auth}/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> registerPatient(
    String firstName,
    String lastName,
    String email,
    String phone,
    String dob,
    String address,
    String relationship,
    int caregiverId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();

    // Debug: Check if JWT token is included
    debugPrint('registerPatient headers: $headers');
    final hasAuth = headers.containsKey('Authorization');
    debugPrint('Authorization header present: $hasAuth');
    if (hasAuth) {
      debugPrint('Auth header value: ${headers['Authorization']}');
    }

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.baseUrl}caregivers/$caregiverId/patients'),
          headers: headers,
          body: jsonEncode({
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'phone': phone,
            'dob': dob,
            'address': address,
            'relationship': relationship,
            'caregiverId': caregiverId,
          }),
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> login(String email, String password) async {
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.auth}/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> logout() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await _httpClient
        .post(Uri.parse('${ApiConstants.auth}/logout'), headers: headers)
        .timeout(const Duration(seconds: 30));

    // Clear all auth models
    // Clear all auth data
    await AuthTokenManager.clearAuthData();
    return response;
  }

  static Future<http.Response> requestPasswordReset(String email) async {
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.auth}/password/forgot'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.auth}/password/reset'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token, 'password': newPassword}),
        )
        .timeout(const Duration(seconds: 30));
  }

  // ========================
  // PROFILE METHODS
  // ========================

  static Future<http.Response> getProfile() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse('${ApiConstants.auth}/profile'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  // ========================
  // FEED METHODS
  // ========================

  static Future<http.Response> getAllPosts() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse('${ApiConstants.feed}/all'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> getUserPosts(int userId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse('${ApiConstants.feed}/user/$userId'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> createPost(
    int userId,
    String content, [
    File? image,
  ]) async {
    final uri = Uri.parse('${ApiConstants.feed}/create');
    final headers = await AuthTokenManager.getAuthHeaders();

    var request = http.MultipartRequest('POST', uri)
      ..fields['userId'] = userId.toString()
      ..fields['content'] = content;

    // Add auth headers to multipart request
    request.headers.addAll(headers);

    if (image != null) {
      final imageStream = http.ByteStream(image.openRead());
      final imageLength = await image.length();
      final multipartFile = http.MultipartFile(
        'image',
        imageStream,
        imageLength,
        filename: path.basename(image.path),
      );
      request.files.add(multipartFile);
    }

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
  }

  // ========================
  // FRIEND METHODS
  // ========================

  static Future<http.Response> searchUsers(
    String query,
    int currentUserId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse(
      '${ApiConstants.users}/search?query=$query&currentUserId=$currentUserId',
    );

    return await _httpClient
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> sendFriendRequest(
    int fromUserId,
    int toUserId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.friends}/request');
    return await _httpClient
        .post(
          url,
          headers: headers,
          body: jsonEncode({'fromUserId': fromUserId, 'toUserId': toUserId}),
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> getPendingFriendRequests(int userId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.friends}/requests/$userId');
    return await _httpClient
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> acceptFriendRequest(int requestId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.friends}/accept');
    return await _httpClient
        .post(url, headers: headers, body: jsonEncode({'requestId': requestId}))
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> rejectFriendRequest(int requestId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.friends}/reject');
    return await _httpClient
        .post(url, headers: headers, body: jsonEncode({'requestId': requestId}))
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> getFriends(int userId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.friends}/list/$userId');
    return await _httpClient
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  // ========================
  // DASHBOARD METHODS
  // ========================

  static Future<http.Response> getCaregiverPatients(int caregiverId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.baseUrl}caregivers/$caregiverId/patients'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<List<int>> getCaregiverLinkedPatientUserIds(
    int caregiverId,
  ) async {
    try {
      final response = await getCaregiverPatients(caregiverId);
      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .map<int?>((item) {
            if (item is! Map<String, dynamic>) return null;
            final link = item['link'];
            if (link is! Map<String, dynamic>) return null;
            final patientUserId = link['patientUserId'];
            if (patientUserId is int) return patientUserId;
            if (patientUserId is String) return int.tryParse(patientUserId);
            return null;
          })
          .whereType<int>()
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<int>> getPatientLinkedCaregiverUserIds(
    int patientUserId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}caregiver-patient-links/patients/$patientUserId/caregivers',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .map<int?>((item) {
            if (item is! Map<String, dynamic>) return null;
            final caregiverUserId = item['caregiverUserId'];
            if (caregiverUserId is int) return caregiverUserId;
            if (caregiverUserId is String) return int.tryParse(caregiverUserId);
            return null;
          })
          .whereType<int>()
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getPatientLinkedCaregiverLinks(
    int patientUserId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}caregiver-patient-links/patients/$patientUserId/caregivers',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> canInitiateVideoCall({
    required int currentUserId,
    required String currentUserRole,
    required int targetUserId,
    int? caregiverId,
  }) async {
    if (currentUserId == targetUserId) {
      return false;
    }

    if (currentUserRole == 'PATIENT') {
      final linkedCaregiverIds = await getPatientLinkedCaregiverUserIds(
        currentUserId,
      );
      return linkedCaregiverIds.contains(targetUserId);
    }

    if (currentUserRole == 'CAREGIVER') {
      if (caregiverId == null) {
        return false;
      }

      final linkedPatientUserIds = await getCaregiverLinkedPatientUserIds(
        caregiverId,
      );

      if (linkedPatientUserIds.contains(targetUserId)) {
        return true;
      }

      final reachableCaregiverIds = <int>{};
      for (final patientUserId in linkedPatientUserIds) {
        final caregiverIds = await getPatientLinkedCaregiverUserIds(
          patientUserId,
        );
        reachableCaregiverIds.addAll(caregiverIds);
      }

      return reachableCaregiverIds.contains(targetUserId);
    }

    return false;
  }

  static Future<bool> setPatientVideoCallsEnabledForLink({
    required int linkId,
    required bool enabled,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      final response = await _httpClient
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}caregiver-patient-links/$linkId/patient-video-calls',
            ),
            headers: headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setPatientMessagingEnabledForLink({
    required int linkId,
    required bool enabled,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      final response = await _httpClient
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}caregiver-patient-links/$linkId/patient-messaging',
            ),
            headers: headers,
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Check if a user with the given email exists
  static Future<Map<String, dynamic>> checkEmailExists(String email) async {
    final headers = await AuthTokenManager.getAuthHeaders();

    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.users}/check-email?email=${Uri.encodeComponent(email)}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Check email response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'exists': false,
          'error': 'Failed to check email: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('Error checking email: $e');
      return {'exists': false, 'error': e.toString()};
    }
  }

  /// Send a connection request from a caregiver to a patient
  static Future<http.Response> sendConnectionRequest({
    required int caregiverId,
    required String patientEmail,
    required String relationshipType,
    String? message,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    debugPrint('Sending connection request to $patientEmail');

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.connectionRequests}/create'),
          headers: headers,
          body: jsonEncode({
            'caregiverId': caregiverId,
            'patientEmail': patientEmail,
            'relationshipType': relationshipType,
            'message':
                message ?? 'I would like to connect with you on CareConnect',
          }),
        )
        .timeout(const Duration(seconds: 20));
  }

  /// Get pending connection requests for a caregiver
  static Future<http.Response> getPendingRequestsByCaregiver(
    int caregiverId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();

    return await _httpClient
        .get(
          Uri.parse(
            '${ApiConstants.connectionRequests}/pending/caregiver/$caregiverId',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));
  }

  static Future<http.Response> suspendCaregiverPatientLink(int linkId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json'; // Add content type header

    debugPrint('Calling suspendCaregiverPatientLink for linkId: $linkId');

    // Try both formats to determine which one works with the backend
    final url1 =
        '${ApiConstants.baseUrl}caregiver-patient-links/$linkId/suspend';
    final url2 = '${ApiConstants.baseUrl}caregivers/links/$linkId/suspend';

    debugPrint('URL Option 1: $url1');
    debugPrint('URL Option 2: $url2');
    debugPrint('Headers: $headers');

    // Use the first URL format by default
    final String finalUrl = url1;

    return await _httpClient
        .post(
          Uri.parse(finalUrl),
          headers: headers,
          body: jsonEncode({}), // Send empty JSON body
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> reactivateCaregiverPatientLink(
    int linkId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json'; // Add content type header

    debugPrint(' Calling reactivateCaregiverPatientLink for linkId: $linkId');

    // Try both formats to determine which one works with the backend
    final url1 =
        '${ApiConstants.baseUrl}caregiver-patient-links/$linkId/reactivate';
    final url2 = '${ApiConstants.baseUrl}caregivers/links/$linkId/reactivate';

    debugPrint(' URL Option 1: $url1');
    debugPrint(' URL Option 2: $url2');
    debugPrint(' Headers: $headers');

    // Use the first URL format by default
    final String finalUrl = url1;

    return await _httpClient
        .post(
          Uri.parse(finalUrl),
          headers: headers,
          body: jsonEncode({}), // Send empty JSON body
        )
        .timeout(const Duration(seconds: 30));
  }

  // ========================
  // CAREGIVER MOOD SUMMARY
  // ========================
  static Future<Map<String, dynamic>> getCaregiverMoodSummaries(
      int caregiverId) async {
    final headers = {'Content-Type': 'application/json'};
    final url = Uri.parse('${ApiConstants.mood}/caregiver/$caregiverId/moods');

    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
            'ΓÜá∩╕Å getCaregiverMoodSummaries failed: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      debugPrint('Γ¥î getCaregiverMoodSummaries error: $e');
      return {};
    }
  }

  // ========================
  // MEDICATIONS
  // ========================
  static Future<List<dynamic>> getActiveMedications(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    final url = Uri.parse('${ApiConstants.patients}/$userId/active');

    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      } else {
        debugPrint(
            'ΓÜá∩╕Å getActiveMedications failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Γ¥î getActiveMedications error: $e');
      return [];
    }
  }

  // ========================
  // MEDICATION REMINDERS
  // ========================
  static Future<List<dynamic>> getTodaysMedications(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    final url = Uri.parse('${ApiConstants.patient}/$userId/medications/today');

    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      } else {
        debugPrint(
            'ΓÜá∩╕Å getTodaysMedications failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Γ¥î getTodaysMedications error: $e');
      return [];
    }
  }

  // ========================
  // MOOD TRACKER METHODS
  // ========================

  static Future<http.Response> saveMoodScore({
    required int userId,
    required int score,
    required String label,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final url = Uri.parse('${ApiConstants.mood}/$userId/mood');

    final body = jsonEncode({'score': score, 'label': label});

    try {
      final response = await _httpClient
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      debugPrint(
          ' saveMoodScore response: ${response.statusCode} - ${response.body}');
      return response;
    } catch (e) {
      debugPrint('Γ¥î saveMoodScore error: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> getMoodHistory(int userId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.mood}/$userId/mood');

    try {
      final response = await _httpClient
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      } else {
        debugPrint('ΓÜá∩╕Å getMoodHistory failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Γ¥î getMoodHistory error: $e');
      return [];
    }
  }

  // ========================
  // TELEMETRY METHODS
  // ========================

  static Future<http.Response> sendTelemetryEventV3({
    required Map<String, dynamic> payload,
  }) async {
    return await _httpClient
        .post(
          Uri.parse(ApiConstants.telemetryV3),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));
  }

  // ========================
  // OFFLINE SYNC QUEUE METHODS
  // ========================

  static Future<List<OfflineSyncQueueItem>> getOfflineSyncQueue({
    int limit = 200,
  }) async {
    return ApiServiceOffline.getPendingQueue(limit: limit);
  }

  static Future<int> getOfflineSyncPendingCount() async {
    return ApiServiceOffline.getPendingCount();
  }

  static Future<bool> syncOfflineQueuedRequestById(String id) async {
    return ApiServiceOffline.syncQueuedRequestById(id);
  }

  static Future<bool> deleteOfflineQueuedRequestById(String id) async {
    return ApiServiceOffline.deleteQueuedRequestById(id);
  }

  static Future<OfflineSyncRunSummary> syncOfflineQueue(
      {int limit = 200}) async {
    return ApiServiceOffline.syncPendingQueue(limit: limit);
  }

  // ========================
  // UTILITY METHODS
  // ========================

  // Get auth headers with Authorization bearer token
  static Future<Map<String, String>> getAuthHeaders() async {
    return await AuthTokenManager.getAuthHeaders();
  }

  // allergies tracker
  static Future<String> getJwtToken() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final auth = (headers['Authorization'] ?? '').trim();

    const prefix = 'Bearer ';
    if (auth.toLowerCase().startsWith(prefix.toLowerCase())) {
      return auth.substring(prefix.length).trim();
    }
    return '';
  }

  // Save JWT token from Set-Cookie header or response body
  static Future<void> saveJWTToken(String token) async {
    // This method is now deprecated - use AuthTokenManager.saveAuthData instead
    debugPrint(
      'Warning: saveJWTToken is deprecated. Use AuthTokenManager.saveAuthData instead.',
    );
  }

  // Clear auth cookie/token
  static Future<void> clearAuthCookie() async {
    await AuthTokenManager.clearAuthData();
  }

  // ========================
  //   SYMPTOMS (CRUD)
  // ========================

  // GET /v1/api/symptoms/patient/{patientId}
  static Future<List<Map<String, dynamic>>> getSymptomsForPatient(
      int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.symptoms}/patient/$patientId');

    final res = await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception(
          'getSymptomsForPatient failed: ${res.statusCode} ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    final list = (decoded is Map && decoded['data'] is List)
        ? decoded['data'] as List
        : const [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  // Γ£à NEW - GET /v1/api/symptoms/{id}
  static Future<Map<String, dynamic>> getSymptomById(int id) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.symptoms}/$id');

    final res = await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('getSymptomById failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    return (decoded is Map && decoded['data'] is Map)
        ? decoded['data'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  // POST /v1/api/symptoms
  static Future<Map<String, dynamic>> createSymptom({
    required int patientId,
    required String symptomKey,
    String? symptomValue,
    required int severity,
    String? clinicalNotes,
    bool completed = true,
    DateTime? takenAt,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final payload = <String, dynamic>{
      'patientId': patientId,
      'symptomKey': symptomKey,
      if (symptomValue != null) 'symptomValue': symptomValue,
      'severity': severity,
      'completed': completed,
      'takenAt': (takenAt ?? DateTime.now()).toUtc().toIso8601String(),
      if (clinicalNotes != null && clinicalNotes.trim().isNotEmpty)
        'clinicalNotes': clinicalNotes.trim(),
    };

    final res = await _httpClient
        .post(Uri.parse(ApiConstants.symptoms),
            headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('createSymptom failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    return (decoded is Map && decoded['data'] is Map)
        ? decoded['data'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  // PUT /v1/api/symptoms/{id}
  static Future<Map<String, dynamic>> updateSymptom({
    required int id,
    String? symptomKey,
    String? symptomValue,
    int? severity,
    String? clinicalNotes,
    bool? completed,
    DateTime? takenAt,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final payload = <String, dynamic>{
      if (symptomKey != null) 'symptomKey': symptomKey,
      if (symptomValue != null) 'symptomValue': symptomValue,
      if (severity != null) 'severity': severity,
      if (clinicalNotes != null) 'clinicalNotes': clinicalNotes,
      if (completed != null) 'completed': completed,
      if (takenAt != null) 'takenAt': takenAt.toUtc().toIso8601String(),
    };

    final res = await _httpClient
        .put(Uri.parse('${ApiConstants.symptoms}/$id'),
            headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('updateSymptom failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    return (decoded is Map && decoded['data'] is Map)
        ? decoded['data'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  // DELETE /v1/api/symptoms/{id}
  static Future<void> deleteSymptom(int id) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final res = await _httpClient
        .delete(Uri.parse('${ApiConstants.symptoms}/$id'), headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('deleteSymptom failed: ${res.statusCode} ${res.body}');
    }
  }

  // ========================
  // SUBSCRIPTION METHODS
  // ========================

  // Get the current subscription for a user
  static Future<http.Response> getCurrentSubscription() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    // Get the user session to extract the user ID
    final userSession = await AuthTokenManager.getUserSession();
    final userId = userSession != null ? userSession['id']?.toString() : null;

    if (userId == null) {
      throw Exception('User ID not found. Please ensure you are logged in.');
    }

    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.subscriptions}/user/$userId/active'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Get all available subscription plans
  static Future<http.Response> getAvailablePlans() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    return await _httpClient
        .get(Uri.parse('${ApiConstants.subscriptions}/plans'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  // Create a subscription for an existing customer
  static Future<http.Response> createSubscription(
    String customerId,
    String priceId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    final uri = Uri.parse('${ApiConstants.subscriptions}/create-direct');

    // Create form models as required by the API
    // Create form data as required by the API
    final formData = {'customerId': customerId, 'priceId': priceId};

    return await _httpClient
        .post(uri, headers: headers, body: formData)
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> createSubscriptionByUser(
    String userId,
    String priceId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    final uri = Uri.parse('${ApiConstants.subscriptions}/create-by-user');
    final formData = {'userId': userId, 'priceId': priceId};
    return await _httpClient
        .post(uri, headers: headers, body: formData)
        .timeout(const Duration(seconds: 30));
  }

  // Cancel a subscription
  static Future<http.Response> cancelSubscription(String subscriptionId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.subscriptions}/$subscriptionId/cancel'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Change subscription plan
  static Future<http.Response> changeSubscriptionPlan(
    String oldSubscriptionId,
    String newPriceId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    // Create form models as required by the API
    // Create form data as required by the API
    final formData = {
      'oldSubscriptionId': oldSubscriptionId,
      'newPriceId': newPriceId,
    };

    final uri = Uri.parse('${ApiConstants.subscriptions}/upgrade-or-downgrade');

    // Send form models as required by the API
    // Send form data as required by the API
    return await _httpClient
        .post(uri, headers: headers, body: formData)
        .timeout(const Duration(seconds: 30));
  }

  // Upgrade or downgrade a subscription
  static Future<http.Response> upgradeOrDowngradeSubscription(
    String oldSubscriptionId,
    String newPriceId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    final uri = Uri.parse('${ApiConstants.subscriptions}/upgrade-or-downgrade');

    // Create form models
    // Create form data
    final formData = {
      'oldSubscriptionId': oldSubscriptionId,
      'newPriceId': newPriceId,
    };

    return await _httpClient
        .post(uri, headers: headers, body: formData)
        .timeout(const Duration(seconds: 30));
  }

  // Get subscription information for the current user
  static Future<http.Response> getUserSubscriptions() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    // Get the user session to extract the user ID
    final userSession = await AuthTokenManager.getUserSession();
    final userId = userSession != null ? userSession['id']?.toString() : null;

    if (userId == null) {
      throw Exception('User ID not found. Please ensure you are logged in.');
    }

    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.subscriptions}/user/$userId/active'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // FAMILY
  // FAMILY
  static Future<List<Map<String, dynamic>>> getAccessiblePatients() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.familyMembers}/patients',
            ), // Use ApiConstants.familyMembers
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else if (isAccessDenied(response)) {
        throw Exception('You do not have access to view patients');
      } else {
        throw Exception(handleErrorResponse(response));
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid response format from server');
      }
      rethrow;
    }
  }

  // Get specific patient models (family member access)
  // Get specific patient data (family member access)
  static Future<Map<String, dynamic>> getPatientData(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.familyMembers}/patients/$patientId',
      ),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 403) {
      throw Exception('Access denied to patient models');
    } else {
      throw Exception('Failed to fetch patient models');
    }
  }

  /// Get a specific patient under a caregiver's care
  static Future<Map<String, dynamic>> getPatientForCaregiver(
    int caregiverId,
    int patientId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}caregivers/$caregiverId/patients/$patientId',
      ),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 403) {
      throw Exception('Access denied to patient models');
    } else if (response.statusCode == 404) {
      throw Exception('Patient not found');
    } else {
      throw Exception('Failed to fetch patient models');
    }
  }

  // Check if family member has access to patient
  static Future<bool> hasAccessToPatient(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.familyMembers}/patients/$patientId/access',
      ),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return false;
  }

  // Get patient dashboard (read-only)
  static Future<Map<String, dynamic>> getPatientDashboard(
    int patientId, {
    int days = 30,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.familyMembers}/patients/$patientId/dashboard?days=$days',
      ),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 403) {
      throw Exception('Access denied to patient models');
    } else {
      throw Exception('Failed to fetch patient dashboard');
    }
  }

  // Get patient vitals (read-only)
  static Future<http.Response> getPatientVitals(
    int patientId, {
    int days = 7,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      return await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}analytics/vitals?patientId=$patientId&days=$days',
            ),
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      // Convert any errors to an error response
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentVitalAlerts(
    int patientId, {
    int limit = 5,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}analytics/alerts/recent?patientId=$patientId&limit=$limit',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! List) {
        return const [];
      }

      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> getPatientStatus(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http
        .get(
          Uri.parse(
            '${ApiConstants.familyMembers}/patients/$patientId/status',
          ),
          headers: headers,
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
        );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 403) {
      throw Exception('Access denied to patient status');
    } else if (response.statusCode == 408) {
      throw Exception('Request timed out');
    } else {
      throw Exception('Failed to fetch patient status: ${response.statusCode}');
    }
  }

  // Add method to check if response indicates access denied
  static bool isAccessDenied(http.Response response) {
    return response.statusCode == 403;
  }

  // Add method to handle common error responses
  static String handleErrorResponse(http.Response response) {
    try {
      final errorData = jsonDecode(response.body);
      return errorData['message'] ??
          errorData['error'] ??
          'Unknown error occurred';
    } catch (e) {
      return 'Failed with status code: ${response.statusCode}';
    }
  }

  static Future<http.Response> getFamilyMembers(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await http.get(
      Uri.parse('${ApiConstants._host}/v1/api/patients/$patientId'),
      headers: headers,
    );
  }

  static Future<List<Map<String, dynamic>>> getPatientFamilyMembers(
    int patientId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await _httpClient
        .get(
          Uri.parse('${ApiConstants.patients}/$patientId/family-members'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  static Future<http.Response> getPatientCompleteProfile(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.patients}/$patientId/profile'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> getPatientDetails(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants._host}/v1/api/patients/$patientId');
    return await http.get(url, headers: headers);
  }

  static Future<http.Response> addFamilyMember(
    int patientId,
    Map<String, dynamic> familyMemberData,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient.post(
      Uri.parse(
        '${ApiConstants._host}/v1/api/patients/$patientId/family-members',
      ),
      headers: headers,
      body: jsonEncode(familyMemberData),
    );
  }

  static Future<http.Response> submitMoodAndPainLog({
    required int moodValue,
    required int painValue,
    required String note,
    required DateTime timestamp,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse(
      '${ApiConstants._host}/v1/api/patients/mood-pain-log',
    );

    return await _httpClient.post(
      url,
      headers: headers,
      body: jsonEncode({
        'moodValue': moodValue,
        'painValue': painValue,
        'note': note,
        'timestamp': timestamp.toIso8601String(),
      }),
    );
  }

  static Future<http.Response> registerPatientForCaregiver({
    required int caregiverId,
    required Map<String, dynamic> patientData,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();

    debugPrint(' registerPatientForCaregiver caregiverId: $caregiverId');
    debugPrint(
        ' patientData with structured address: ${jsonEncode(patientData)}');

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.baseUrl}caregivers/$caregiverId/patients'),
          headers: headers,
          body: jsonEncode(patientData),
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Add an existing patient to a caregiver's care list by email
  static Future<http.Response> addExistingPatientToCaregiver({
    required int caregiverId,
    required String patientEmail,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    debugPrint('addExistingPatientToCaregiver caregiverId: $caregiverId');
    final url = '${ApiConstants.baseUrl}caregivers/$caregiverId/patients/add';

    return await _httpClient
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode({'email': patientEmail}),
        )
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
        );
  }

  // ========================
  // PROFILE MANAGEMENT METHODS
  // ========================

  /// Get caregiver profile models
  /// Get caregiver profile data
  static Future<http.Response> getCaregiverProfile(int caregiverId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.caregivers}/$caregiverId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  /// Update caregiver profile
  static Future<http.Response> updateCaregiverProfile(
    int caregiverId,
    Map<String, dynamic> updatedProfile,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .put(
          Uri.parse('${ApiConstants.caregivers}/$caregiverId'),
          headers: headers,
          body: jsonEncode(updatedProfile),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// Get patient profile models
  /// Get patient profile data
  static Future<http.Response> getPatientProfile(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse('${ApiConstants.patients}/$patientId'), headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  // ========================
  // AUDIT LOG
  // ========================

  static Future<http.Response> getAuditLog(
    int clientId, {
    DateTime? startDate,
    DateTime? endDate,
    String? type,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final query = <String, String>{};
    if (startDate != null) {
      query['startDate'] = _formatDate(startDate);
    }
    if (endDate != null) {
      query['endDate'] = _formatDate(endDate);
    }
    if (type != null && type.isNotEmpty) {
      query['type'] = type;
    }
    final uri = Uri.parse('${ApiConstants.clients}/$clientId/audit-log')
        .replace(queryParameters: query.isEmpty ? null : query);
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  /// Update patient profile
  static Future<http.Response> updatePatientProfile(
    int patientId,
    Map<String, dynamic> updatedProfile,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .put(
          Uri.parse('${ApiConstants.patients}/$patientId/profile'),
          headers: headers,
          body: jsonEncode(updatedProfile),
        )
        .timeout(const Duration(seconds: 15));
  }

  // --- Known Risks (risk types + patient risks) ---
  static Future<http.Response> getRiskTypes() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse(ApiConstants.riskTypes), headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> getPatientRisks(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.patients}/$patientId/risks'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> flagPatientRisk(
      int patientId, int riskTypeId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.patients}/$patientId/risks'),
          headers: headers,
          body: jsonEncode({'riskTypeId': riskTypeId}),
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> unflagPatientRisk(
      int patientId, int riskId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .delete(
          Uri.parse('${ApiConstants.patients}/$patientId/risks/$riskId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  // --- Client activities (ADL/IADL) ---
  /// Resolve relative image URL to full URL. Returns null if input is null or empty.
  static String? resolveImageUrl(String? relativeUrl) {
    if (relativeUrl == null || relativeUrl.trim().isEmpty) return null;
    final trimmed = relativeUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = getBackendBaseUrl().replaceAll(RegExp(r'/+$'), '');
    return trimmed.startsWith('/') ? '$base$trimmed' : '$base/$trimmed';
  }

  static Future<http.Response> getClientActivities(int clientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.clients}/$clientId/activities'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /activities ΓÇö all activities, optionally filtered by category (ADL | IADL).
  static Future<http.Response> getActivities({String? category}) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = category != null
        ? Uri.parse('${ApiConstants.activities}?category=$category')
        : Uri.parse(ApiConstants.activities);
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  /// PUT /clients/{id}/activity-config/{activityId} ΓÇö enable/disable activity for client.
  static Future<http.Response> putClientActivityConfig(
    int clientId,
    int activityId, {
    required bool isEnabled,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .put(
          Uri.parse(
              '${ApiConstants.clients}/$clientId/activity-config/$activityId'),
          headers: headers,
          body: jsonEncode({'isEnabled': isEnabled}),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// POST /clients/{id}/activity-config/{activityId}/icon ΓÇö upload custom icon.
  static Future<http.Response> postClientActivityIcon(
    int clientId,
    int activityId,
    File imageFile,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers.remove('Content-Type');
    var request = http.MultipartRequest(
      'POST',
      Uri.parse(
          '${ApiConstants.clients}/$clientId/activity-config/$activityId/icon'),
    );
    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      imageFile.path,
      filename: path.basename(imageFile.path),
    ));
    var streamed = await request.send().timeout(const Duration(seconds: 30));
    return await http.Response.fromStream(streamed);
  }

  static Future<http.Response> getCompetencyScale() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.config}/competency-scale'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<http.Response> postActivityLog({
    required int clientId,
    required int activityId,
    required int competencyScore,
    int? satisfactionRating,
    String? notes,
    String? activityName,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = <String, dynamic>{
      'clientId': clientId,
      'activityId': activityId,
      'competencyScore': competencyScore,
    };
    if (satisfactionRating != null) {
      body['satisfactionRating'] = satisfactionRating;
    }
    if (notes != null && notes.trim().isNotEmpty) body['notes'] = notes.trim();
    if (activityName != null && activityName.trim().isNotEmpty) {
      body['activityName'] = activityName.trim();
    }
    return await _httpClient
        .post(
          Uri.parse(ApiConstants.activityLogs),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /activity-logs?clientId=X&limit=N ΓÇö list activity logs for a client.
  static Future<http.Response> getActivityLogs(int clientId,
      {int limit = 100}) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse(ApiConstants.activityLogs).replace(
      queryParameters: {
        'clientId': clientId.toString(),
        'limit': limit.toString()
      },
    );
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  /// POST /clients/{id}/behavioral-incidents ΓÇö create behavioral incident.
  static Future<http.Response> postBehavioralIncident({
    required int clientId,
    required String observedBehavior,
    required DateTime occurredAt,
    String? triggerNotes,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = <String, dynamic>{
      'observed_behavior': observedBehavior,
      'occurred_at': occurredAt.toIso8601String(),
    };
    if (triggerNotes != null && triggerNotes.trim().isNotEmpty) {
      body['trigger_notes'] = triggerNotes.trim();
    }
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.clients}/$clientId/behavioral-incidents'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /clients/{id}/behavioral-incidents ΓÇö list behavioral incidents.
  static Future<http.Response> getBehavioralIncidents(int clientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.clients}/$clientId/behavioral-incidents'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  /// POST /clients/{id}/events ΓÇö log a client-facing activity tap.
  static Future<http.Response> postClientEvent({
    required int clientId,
    required int activityId,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = {'activity_id': activityId};
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.clients}/$clientId/events'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// POST /clients/{id}/incident-reports ΓÇö create structured incident report.
  static Future<http.Response> postIncidentReport({
    required int clientId,
    required String incidentType,
    required DateTime occurredAt,
    required String location,
    String? triggerNotes,
    required List<String> actionsTaken,
    required String outcome,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = <String, dynamic>{
      'incident_type': incidentType,
      'occurred_at': occurredAt.toIso8601String(),
      'location': location,
      'outcome': outcome,
      'actions_taken': actionsTaken,
    };
    if (triggerNotes != null && triggerNotes.trim().isNotEmpty) {
      body['trigger_notes'] = triggerNotes.trim();
    }
    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.clients}/$clientId/incident-reports'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /clients/{id}/incident-reports ΓÇö list incident reports for a client.
  static Future<http.Response> getIncidentReports(int clientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.clients}/$clientId/incident-reports'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /clients/{id}/incident-reports/{reportId}` ΓÇö single report with actions.
  static Future<http.Response> getIncidentReport(
      int clientId, int reportId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse(
              '${ApiConstants.clients}/$clientId/incident-reports/$reportId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
  }

  /// GET /clients/{id}/reports/competency-trends ΓÇö average competency per activity per week.
  /// Optional [startDate] and [endDate] (default: last 8 weeks). Dates as yyyy-MM-dd.
  static Future<http.Response> getCompetencyTrends(
    int clientId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = _formatDate(startDate);
    if (endDate != null) queryParams['endDate'] = _formatDate(endDate);
    final uri =
        Uri.parse('${ApiConstants.clients}/$clientId/reports/competency-trends')
            .replace(
                queryParameters: queryParams.isNotEmpty ? queryParams : null);
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// GET /clients/{id}/reports/behavioral-trends ΓÇö incident count per week, top keywords, trend.
  static Future<http.Response> getBehavioralTrends(
    int clientId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = _formatDate(startDate);
    if (endDate != null) queryParams['endDate'] = _formatDate(endDate);
    final uri =
        Uri.parse('${ApiConstants.clients}/$clientId/reports/behavioral-trends')
            .replace(
                queryParameters: queryParams.isNotEmpty ? queryParams : null);
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  /// GET /clients/{id}/reports/participation ΓÇö activity log counts and last logged per activity.
  static Future<http.Response> getParticipation(
    int clientId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final queryParams = <String, String>{};
    if (startDate != null) queryParams['startDate'] = _formatDate(startDate);
    if (endDate != null) queryParams['endDate'] = _formatDate(endDate);
    final uri =
        Uri.parse('${ApiConstants.clients}/$clientId/reports/participation')
            .replace(
                queryParameters: queryParams.isNotEmpty ? queryParams : null);
    return await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
  }

  /// Upload profile picture or other files
  static Future<http.Response> uploadUserFile({
    required int userId,
    required File file,
    required String category,
    String? role,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    // Remove Content-Type as it will be set by multipart request
    headers.remove('Content-Type');

    // Use users endpoint for file uploads
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConstants.files}/users/$userId/upload'),
    );

    // Add headers
    request.headers.addAll(headers);

    // Add file
    var fileStream = http.ByteStream(file.openRead());
    var fileLength = await file.length();
    var multipartFile = http.MultipartFile(
      'file',
      fileStream,
      fileLength,
      filename: path.basename(file.path),
    );

    // Add form fields
    request.files.add(multipartFile);
    request.fields['category'] = category;

    // Send the request
    var streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
        );
    var response = await http.Response.fromStream(streamedResponse);

    return response;
  }

  /// Get user profile picture URL based on role
  static Future<String?> getUserProfilePictureUrl(
    int userId, [
    String? role,
  ]) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    // Use the users endpoint to get files consistently
    const endpoint = 'users';

    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              '${ApiConstants.files}/$endpoint/$userId?category=profilePicture',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          return data.first['fileUrl'];
        } else if (data is Map && data.containsKey('fileUrl')) {
          return data['fileUrl'];
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting profile picture URL: $e');
      return null;
    }
  }

  // ========================
  // PRIMARY CARE PROVIDER
  // ========================
  static Future<Map<String, dynamic>> getPrimaryCareProvider(int userId) async {
    final headers = {'Content-Type': 'application/json'};
    final url = Uri.parse('${ApiConstants.patients}/$userId/provider');

    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
        return {};
      } else {
        debugPrint(
            'ΓÜá∩╕Å getPrimaryCareProvider failed: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      debugPrint('Γ¥î getPrimaryCareProvider error: $e');
      return {};
    }
  }

  // ========================
  // MESSAGING METHODS
  // ========================

  static Future<http.Response> sendMessage({
    required int senderId,
    required int receiverId,
    required String content,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final body = jsonEncode({
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
    });

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.baseUrl}messages/send'),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 15));
  }

  static Future<List<dynamic>> getConversation({
    required int user1,
    required int user2,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse(
      '${ApiConstants.baseUrl}messages/conversation?user1=$user1&user2=$user2',
    );

    final response = await _httpClient.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load conversation');
    }
  }

  static Future<List<dynamic>> getInbox(int userId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final url = Uri.parse('${ApiConstants.baseUrl}messages/inbox/$userId');

    final response = await _httpClient.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load inbox');
    }
  }

  // ========================
  // TASK METHODS
  // ========================

  // Get patient tasks
  static Future<http.Response> getPatientTasks(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.tasks}/patient/$patientId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Delete a task by task ID
  static Future<http.Response> deleteTask(int taskId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .delete(Uri.parse('${ApiConstants.tasks}/$taskId'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  // Edit a task by task ID
  static Future<http.Response> editTask(
    int taskId,
    Map<String, dynamic> taskData,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    return await _httpClient
        .put(
          Uri.parse('${ApiConstants.tasks}/$taskId'),
          headers: headers,
          body: jsonEncode(taskData),
        )
        .timeout(const Duration(seconds: 30));
  }

  // Get task templates
  static Future<http.Response> getTaskTemplates(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.baseUrl}templates/all'), // get all for now
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  static Future<http.Response> getTaskTemplate(int templateId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.baseUrl}templates/$templateId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Create a task
  static Future<http.Response> createTask(int patientId, String task) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.tasks}/patient/$patientId'),
          headers: headers,
          body: task,
        )
        .timeout(const Duration(seconds: 30));
  }
  // ========================
  // TASK METHODS (V2)
  // ========================

  // Get patient tasks (v2)
  static Future<http.Response> getPatientTasksV2(int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(
          Uri.parse('${ApiConstants.tasksV2}/patient/$patientId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Delete a task by task ID (v2)
  // Delete a task by task ID (v2), with optional deleteSeries flag
  static Future<http.Response> deleteTaskV2(
    int taskId, {
    bool deleteSeries = false,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();

    final url = Uri.parse(
      '${ApiConstants.tasksV2}/$taskId',
    ).replace(queryParameters: {'deleteSeries': deleteSeries.toString()});

    return await _httpClient
        .delete(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  // Edit a task by task ID (v2)
  static Future<http.Response> editTaskV2(
    int taskId,
    Map<String, dynamic> body, {
    bool updateSeries = false,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final payload = Map<String, dynamic>.from(body);
    payload['updateSeries'] = updateSeries;
    return await _httpClient
        .put(
          Uri.parse('${ApiConstants.tasksV2}/$taskId'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Update a task's completion status (V2)
  ///
  /// Sends a PUT request to /v2/api/tasks/{id}/complete with a JSON body:
  /// `{ "isComplete": true/false }`
  ///
  /// Throws an [Exception] if the request fails.
  static Future<void> updateTaskCompletionV2(
    int taskId,
    bool isComplete,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final url = Uri.parse('${ApiConstants.tasksV2}/$taskId/complete');
    final body = jsonEncode({'isComplete': isComplete});

    final response = await _httpClient
        .put(url, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to update task completion: ${response.statusCode} ${response.body}',
      );
    }
  }

  // Create a task (v2)
  static Future<http.Response> createTaskV2(
    int patientId,
    String taskJson,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    return await _httpClient
        .post(
          Uri.parse('${ApiConstants.tasksV2}/patient/$patientId'),
          headers: headers,
          body: taskJson,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Preview notification content for a task without sending notifications
  static Future<http.Response> previewTaskNotification(
    int patientId,
    String taskJson,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    return await _httpClient
        .post(
          Uri.parse(
              '${ApiConstants.tasks}/patient/$patientId/preview-notification'),
          headers: headers,
          body: taskJson,
        )
        .timeout(const Duration(seconds: 30));
  }

  // Get a single task by ID (v2)
  static Future<http.Response> getTaskByIdV2(int taskId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await _httpClient
        .get(Uri.parse('${ApiConstants.tasksV2}/$taskId'), headers: headers)
        .timeout(const Duration(seconds: 30));
  }

  static Future<Map<String, dynamic>?> getEnhancedPatientProfile(
    int patientId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final url = Uri.parse(
        '${ApiConstants.patients}/$patientId/profile/enhanced',
      );
      final response = await _httpClient
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
          return decoded['data'] as Map<String, dynamic>?;
        } else {
          return decoded as Map<String, dynamic>?;
        }
      } else {
        debugPrint('Failed to fetch enhanced profile: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching enhanced patient profile: ${e.toString()}');
      return null;
    }
  }

  static Future<http.Response> getPatientMedicationsForPatient(
      int patientId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri =
          Uri.parse('${ApiConstants.patientsV3}/$patientId/medications');
      return await _httpClient.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  /// Add a new medication for a patient
  static Future<http.Response> addPatientMedication(
    int patientId,
    Map<String, dynamic> medicationData,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.patientsV3}/$patientId/medications',
      );

      return await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(medicationData),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  /// Remove (deactivate) a medication for a patient (Patient-side soft delete)
  static Future<http.Response> removePatientMedication(
    int patientId,
    int medicationId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.patientsV3}/$patientId/medications/$medicationId',
      );

      return await _httpClient.delete(uri, headers: headers).timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  // Get latest mood and related data
  static Future<Map<String, dynamic>?> getMoodData(int userId) async {
    final String baseUrl = ApiConstants._host;
    final response = await http.get(
      Uri.parse('$baseUrl/patient/$userId/mood'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return null;
    }
  }

  // Get today's average mood and check-ins
  static Future<Map<String, dynamic>?> getDailyMoodAverage(int userId) async {
    final String baseUrl = ApiConstants._host;
    final response = await http.get(
      Uri.parse('$baseUrl/patient/$userId/mood/average'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return null;
    }
  }

  /// Delete medication by caregiver (Caregiver-side hard delete)
  static Future<http.Response> deleteMedicationByCaregiver(
    int patientId,
    int medicationId,
    int caregiverId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.patientsV3}/$patientId/medications/$medicationId/caregiver/$caregiverId',
      );

      return await _httpClient.delete(uri, headers: headers).timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  /// Approve a medication for a patient (sets isActive=true, approval_status='APPROVED')
  static Future<http.Response> approveMedication(
    int patientId,
    int medicationId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.patientsV3}/$patientId/medications/$medicationId/approve',
      );

      return await _httpClient.put(uri, headers: headers).timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  /// Persist medication taken timestamp for reminder dose windows.
  static Future<http.Response> markMedicationTaken(
    int patientId,
    int medicationId, {
    DateTime? takenAt,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      final uri = Uri.parse(
        '${ApiConstants.patients}/$patientId/medications/$medicationId/last-taken',
      );
      final payload = jsonEncode({
        'lastTaken': (takenAt ?? DateTime.now()).toUtc().toIso8601String(),
      });

      return await _httpClient
          .put(uri, headers: headers, body: payload)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  /// Clear persisted medication taken timestamp.
  static Future<http.Response> clearMedicationTakenStatus(
    int patientId,
    int medicationId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.patients}/$patientId/medications/$medicationId/last-taken',
      );

      return await _httpClient.delete(uri, headers: headers).timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
    } catch (e) {
      return http.Response(jsonEncode({'error': e.toString()}), 500);
    }
  }

  // fetch from backend
  static Future<List<dynamic>> fetchAllergies(final int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.allergies}/patient/$patientId');

    final response = await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> list = data['data'] ?? [];
      return list;
    } else {
      throw HttpException('Failed to fetch allergies: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> addAllergy(
      final Map<String, dynamic> allergyData, final int patientId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final body = jsonEncode({
      'patientId': patientId,
      'allergen': allergyData['drug'],
      'severity': allergyData['severity'],
      'reaction': allergyData['reaction'],
      'notes': allergyData['note'],
      'isActive': true
    });

    final response = await _httpClient
        .post(
          Uri.parse(ApiConstants.allergies),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 20));

    final queuedOffline = ApiServiceOffline.isQueuedOfflineResponse(response);
    if ((response.statusCode >= 200 && response.statusCode < 300) ||
        queuedOffline) {
      final decoded = jsonDecode(response.body);
      if (queuedOffline) {
        return <String, dynamic>{
          'queued': true,
          'requestId':
              decoded is Map<String, dynamic> ? decoded['requestId'] : null,
        };
      }
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded['data'] ?? decoded);
      }
      return <String, dynamic>{};
    } else {
      throw HttpException("Failed to add allergy for patient.");
    }
  }

  static Future<bool> removeAllergy(int allergyId) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final uri = Uri.parse('${ApiConstants.allergies}/$allergyId');

    final response = await _httpClient
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    return response.statusCode == 200 || response.statusCode == 204;
  }

  static Future<List<Map<String, dynamic>>> getCallTelemetry(
    String callId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(Uri.parse('${ApiConstants.callsV3}/$callId/telemetry'),
              headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getCallSummary(String callId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(Uri.parse('${ApiConstants.callsV3}/$callId/summary'),
              headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }

      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Confirms or declines a single extracted call summary item
  /// (action item, appointment, or care instruction). Throws on non-2xx.
  static Future<Map<String, dynamic>> confirmCallSummaryItem(
    String callId,
    String itemId, {
    required String decision,
    String? destination,
    String? notes,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await _httpClient
        .post(
          Uri.parse(
            '${ApiConstants.callsV3}/$callId/summary/items/$itemId/confirm',
          ),
          headers: headers,
          body: jsonEncode({
            'decision': decision,
            if (destination != null) 'destination': destination,
            if (notes != null) 'notes': notes,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String details = '';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final message =
              (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
          if (message.isNotEmpty) {
            details = ' - $message';
          }
        }
      } catch (_) {}
      throw Exception(
        'Failed to confirm summary item: HTTP ${response.statusCode}$details',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Confirm summary item response is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<List<Map<String, dynamic>>> getCallTranscriptSegments(
    String callId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConstants.callsV3}/$callId/transcript/segments'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the latest recording record for [callId], or null if none exists.
  static Future<Map<String, dynamic>?> getCallRecording(String callId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConstants.callsV3}/$callId/recording'),
            headers: headers,
          )
          // Status used to block on S3 refresh (~15–20s) and this timeout wiped the
          // Call Recording card. Backend now returns READY metadata without S3; keep
          // headroom for processing calls that still refresh.
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getCallRecordingPlaybackData(
      String callId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConstants.callsV3}/$callId/recording/playback-url'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> getCallRecordingPlaybackUrl(String callId) async {
    final data = await getCallRecordingPlaybackData(callId);
    final url = data?['playbackUrl'];
    if (url is String) return url;
    return url?.toString();
  }

  static Future<List<Map<String, dynamic>>> getMyCallTelemetry() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await _httpClient
          .get(Uri.parse('${ApiConstants.callsV3}/telemetry/my'),
              headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getSentimentHistory(
    int userId,
  ) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final uri = Uri.parse(
        '${ApiConstants.callsV3}/sentiment-history?userId=$userId',
      );
      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> deletePatientCallHistoryDev(
    int patientUserId,
  ) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await _httpClient
        .delete(
          Uri.parse(
              '${ApiConstants.callsV3}/patients/$patientUserId/telemetry'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      String details = '';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final message =
              (decoded['message'] ?? decoded['error'] ?? '').toString().trim();
          if (message.isNotEmpty) {
            details = ' - $message';
          }
        }
      } catch (_) {}
      throw HttpException(
        'Failed to delete patient call history (${response.statusCode})$details',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return {};
  }
}

// Save speech-to-text to a file and upload it to S3
Future<http.Response> uploadUserFileFromBytes({
  required int userId,
  required Uint8List fileBytes,
  required String fileName,
  required String category,
  String? role,
}) async {
  final headers = await AuthTokenManager.getAuthHeaders();
  headers.remove('Content-Type'); // Multipart will handle it

  var request = http.MultipartRequest(
    'POST',
    Uri.parse('${ApiConstants.files}/users/$userId/upload'),
  );

  // Add headers
  request.headers.addAll(headers);

  // Create MultipartFile from bytes
  var fileStream = http.ByteStream(Stream.fromIterable([fileBytes]));
  var fileLength = await fileStream.length;
  var multipartFile = http.MultipartFile(
    'file',
    fileStream,
    fileLength,
    filename: fileName,
  );

  request.files.add(multipartFile);
  request.fields['category'] = category;

  // Send the request
  var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
  var response = await http.Response.fromStream(streamedResponse);

  return response;
}

// Get list of files from saved S3 storage
Future<http.Response> getUserFilesByCategory(int userId) async {
  try {
    final headers = await AuthTokenManager.getAuthHeaders();

    final uri = Uri.parse('${ApiConstants.baseUrl}files/users/$userId/list');

    return await ApiService._httpClient.get(uri, headers: headers).timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
        );
  } catch (e) {
    return http.Response(jsonEncode({'error': e.toString()}), 500);
  }
}
