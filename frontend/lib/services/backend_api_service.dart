import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../config/env_constant.dart';

/// Service to integrate with your Spring Boot backend at localhost:8080
class BackendApiService {
  static String get baseUrl => '${getBackendBaseUrl()}/v1/api';

  // This should be passed from your authentication system
  static String? _authToken;

  static void setAuthToken(String token) {
    _authToken = token;
  }

  static Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-site',
    };

    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    return headers;
  }

  /// Get patients for a caregiver (from your curl command)
  static Future<List<Map<String, dynamic>>> getCaregiverPatients(
    int caregiverId,
  ) async {
    try {
      final url = '$baseUrl/caregivers/$caregiverId/patients';
      print('🔍 Fetching patients from: $url');

      final response = await http.get(Uri.parse(url), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('🔍 Received patient data: ${data.length} patients');

        // Process the nested structure from your API
        final List<Map<String, dynamic>> patients = [];
        for (final item in data) {
          if (item['patient'] != null) {
            final patient = Map<String, dynamic>.from(item['patient']);
            final link = item['link'] != null
                ? Map<String, dynamic>.from(item['link'])
                : null;

            // Add link information to patient data
            if (link != null) {
              patient['linkId'] = link['id'];
              patient['linkStatus'] = link['status'];
              patient['relationship'] = item['relationship'];
            }

            patients.add(patient);
            print(
              '✅ Processed patient: ${patient['firstName']} ${patient['lastName']} (ID: ${patient['id']})',
            );
          }
        }

        return patients;
      } else {
        print('❌ Failed to fetch patients: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching patients: $e');
      return [];
    }
  }

  /// Get conversation messages (from your curl command)
  static Future<List<Map<String, dynamic>>> getConversation(
    String user1,
    String user2, {
    int limit = 50,
  }) async {
    try {
      final url =
          '$baseUrl/messages/conversation?user1=$user1&user2=$user2&limit=$limit';
      print('💬 Fetching messages from: $url');

      final response = await http.get(Uri.parse(url), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('✅ Retrieved ${data.length} messages');
        return data.cast<Map<String, dynamic>>();
      } else {
        print('❌ Failed to fetch messages: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching messages: $e');
      return [];
    }
  }

  /// Send message (from your curl command)
  static Future<bool> sendMessage({
    required String senderId,
    required String senderName,
    required String recipientId,
    required String message,
    String messageType = 'text',
  }) async {
    try {
      final url = '$baseUrl/messages';
      final messageId =
          '${DateTime.now().millisecondsSinceEpoch}_${_generateRandomId()}';

      final messageData = {
        'id': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'recipientId': recipientId,
        'message': message,
        'messageType': messageType,
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
      };

      print('📤 Sending message: $messageData');

      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode(messageData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Message sent successfully');
        return true;
      } else {
        print('❌ Failed to send message: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      return false;
    }
  }

  /// Send SMS via backend (requires backend SMS service)
  static Future<bool> sendSMS({
    required String senderName,
    required String recipientPhone,
    required String message,
  }) async {
    try {
      final url = '$baseUrl/sms/send';

      final smsData = {
        'senderName': senderName,
        'recipientPhone': recipientPhone,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('📱 Sending SMS via backend: $smsData');

      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode(smsData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ SMS sent successfully via backend');
        return true;
      } else {
        print('❌ Backend SMS failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending SMS via backend: $e');
      return false;
    }
  }

  /// Send video call invitation via backend (for push notifications)
  static Future<bool> sendVideoCallInvitation({
    required String callerId,
    required String callerName,
    required String recipientId,
    required String recipientName,
    required String callId,
    bool isVideoCall = true,
  }) async {
    try {
      final url = '$baseUrl/notifications/video-call-invitation';

      final invitationData = {
        'callerId': callerId,
        'callerName': callerName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'callId': callId,
        'isVideoCall': isVideoCall,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('📞 Sending video call invitation via backend: $invitationData');

      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode(invitationData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Video call invitation sent via backend');
        return true;
      } else {
        print('⚠️  Backend call invitation returned: ${response.statusCode}');
        // Don't fail the call if notification fails
        return true;
      }
    } catch (e) {
      print('⚠️  Backend call invitation error: $e');
      // Don't fail the call if notification fails
      return true;
    }
  }

  /// Store call log in backend
  static Future<bool> logVideoCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String recipientId,
    required String recipientName,
    required DateTime startTime,
    DateTime? endTime,
    required bool wasAnswered,
    required bool isVideoCall,
  }) async {
    try {
      final url = '$baseUrl/calls/log';

      final callData = {
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'wasAnswered': wasAnswered,
        'isVideoCall': isVideoCall,
        'duration':
            endTime != null ? endTime.difference(startTime).inSeconds : 0,
        'platform': kIsWeb
            ? 'web'
            : (defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : (defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'other')),
      };

      print('📊 Logging call to backend: $callData');

      final response = await http.post(
        Uri.parse(url),
        headers: _headers,
        body: json.encode(callData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Call logged successfully');
        return true;
      } else {
        print('⚠️  Call logging returned: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('⚠️  Error logging call: $e');
      return false;
    }
  }

  /// Get call history from backend
  static Future<List<Map<String, dynamic>>> getCallHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final url = '$baseUrl/calls/history?userId=$userId&limit=$limit';

      final response = await http.get(Uri.parse(url), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('✅ Retrieved ${data.length} call history records');
        return data.cast<Map<String, dynamic>>();
      } else {
        print('❌ Failed to fetch call history: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching call history: $e');
      return [];
    }
  }

  /// Test backend connectivity
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        print('✅ Backend connection successful');
        return true;
      } else {
        print('⚠️  Backend returned: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Backend connection failed: $e');
      return false;
    }
  }

  static String _generateRandomId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(random % chars.length)),
    );
  }
}
