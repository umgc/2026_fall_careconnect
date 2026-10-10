import 'package:flutter/material.dart';
import '../widgets/hybrid_video_call_widget.dart';
import '../services/subscription_service.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../config/env_constant.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper class to integrate video calls and SMS with existing patient/caregiver lists
/// This binds call/SMS features directly to each list item without breaking existing code
class CallIntegrationHelper {
  /// Start a video call from caregiver dashboard to a specific patient
  static Future<void> startVideoCallToPatient({
    required BuildContext context,
    required dynamic currentUser, // Current logged-in caregiver
    required dynamic targetPatient, // Patient from the list
    bool isVideoCall = true,
  }) async {
    // Check subscription access for caregivers before initiating call
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user?.isCaregiver == true) {
      final canUseVideoCalls =
          await SubscriptionService.checkPremiumAccessWithDialog(
            context,
            isVideoCall ? 'Video Calls' : 'Voice Calls',
          );

      if (!canUseVideoCalls) {
        return; // User doesn't have premium access, dialog was shown
      }
    }

    if (!context.mounted) {
      return;
    }

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Extract patient data from your existing structure
    final patientData = _extractPatientData(targetPatient);
    final caregiverData = _extractCaregiverData(currentUser);

    debugPrint('🎥 Starting video call:');
    debugPrint('   Caller: ${caregiverData['name']} (${caregiverData['email']})');
    debugPrint('   Recipient: ${patientData['name']} (${patientData['email']})');
    debugPrint('   Call ID: $callId');

    // Direct video call without WebSocket dependency
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HybridVideoCallWidget(
          userId: caregiverData['id'].toString(),
          callId: callId,
          recipientId: patientData['id'].toString(),
          isInitiator: true,
          isVideoEnabled: isVideoCall,

          // Caller (caregiver) details
          userName: caregiverData['name'],
          userEmail: caregiverData['email'],
          userPhone: caregiverData['phone'],

          // Recipient (patient) details
          recipientName: patientData['name'],
          recipientEmail: patientData['email'],
          recipientPhone: patientData['phone'],
        ),
      ),
    );
  }

  /// Start a video call from patient dashboard to a specific caregiver/family member
  static Future<void> startVideoCallToCaregiver({
    required BuildContext context,
    required dynamic currentUser, // Current logged-in patient
    required dynamic targetCaregiver, // Caregiver/family member from the list
    bool isVideoCall = true,
  }) async {
    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Extract caregiver and patient models
    final caregiverData = _extractCaregiverData(targetCaregiver);
    final patientData = _extractPatientData(currentUser);

    debugPrint('🎥 Starting video call:');
    debugPrint('   Caller: ${patientData['name']} (${patientData['email']})');
    debugPrint('   Recipient: ${caregiverData['name']} (${caregiverData['email']})');
    debugPrint('   Call ID: $callId');

    // Direct video call without WebSocket dependency
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HybridVideoCallWidget(
          userId: patientData['id'].toString(),
          callId: callId,
          recipientId: caregiverData['id'].toString(),
          isInitiator: true,
          isVideoEnabled: isVideoCall,

          // Caller (patient) details
          userName: patientData['name'],
          userEmail: patientData['email'],
          userPhone: patientData['phone'],

          // Recipient (caregiver) details
          recipientName: caregiverData['name'],
          recipientEmail: caregiverData['email'],
          recipientPhone: caregiverData['phone'],
        ),
      ),
    );
  }

  /// Send SMS to patient from caregiver dashboard
  static Future<void> sendSMSToPatient({
    required dynamic currentUser, // Current logged-in caregiver
    required dynamic targetPatient, // Patient from the list
    required String message,
  }) async {
    final patientData = _extractPatientData(targetPatient);
    final caregiverData = _extractCaregiverData(currentUser);

    debugPrint('📱 Sending SMS:');
    debugPrint('   From: ${caregiverData['name']} (${caregiverData['phone']})');
    debugPrint('   To: ${patientData['name']} (${patientData['phone']})');
    debugPrint('   Message: $message');

    // Send via direct SMS service
    await _sendDirectSMS(phoneNumber: patientData['phone'], message: message);
  }

  /// Send SMS to caregiver from patient dashboard
  static Future<void> sendSMSToCaregiver({
    required dynamic currentUser, // Current logged-in patient
    required dynamic targetCaregiver, // Caregiver from the list
    required String message,
  }) async {
    final caregiverData = _extractCaregiverData(targetCaregiver);
    final patientData = _extractPatientData(currentUser);

    debugPrint('📱 Sending SMS:');
    debugPrint('   From: ${patientData['name']} (${patientData['phone']})');
    debugPrint('   To: ${caregiverData['name']} (${caregiverData['phone']})');
    debugPrint('   Message: $message');

    // Send via direct SMS service
    await _sendDirectSMS(phoneNumber: caregiverData['phone'], message: message);
  }

  /// Extract patient models from various possible structures
  /// Handles both direct patient objects and nested structures from your API
  static Map<String, dynamic> _extractPatientData(dynamic patientObject) {
    if (patientObject == null) {
      return {
        'id': 'unknown',
        'name': 'Unknown Patient',
        'email': 'unknown@example.com',
        'phone': '0000000000',
      };
    }

    // Handle nested structure from your API: {patient: {...}, link: {...}}
    if (patientObject is Map && patientObject.containsKey('patient')) {
      final patient = patientObject['patient'];
      return {
        'id': patient['id'] ?? 'unknown',
        'name': '${patient['firstName'] ?? ''} ${patient['lastName'] ?? ''}'
            .trim(),
        'email': patient['email'] ?? 'unknown@example.com',
        'phone': patient['phone'] ?? '0000000000',
      };
    }

    // Handle direct patient object
    if (patientObject is Map) {
      return {
        'id': patientObject['id'] ?? 'unknown',
        'name':
            patientObject['name'] ??
            '${patientObject['firstName'] ?? ''} ${patientObject['lastName'] ?? ''}'
                .trim(),
        'email': patientObject['email'] ?? 'unknown@example.com',
        'phone': patientObject['phone'] ?? '0000000000',
      };
    }

    // Fallback
    return {
      'id': 'unknown',
      'name': 'Unknown Patient',
      'email': 'unknown@example.com',
      'phone': '0000000000',
    };
  }

  /// Extract caregiver models from various possible structures
  static Map<String, dynamic> _extractCaregiverData(dynamic caregiverObject) {
    if (caregiverObject == null) {
      return {
        'id': 'unknown',
        'name': 'Unknown Caregiver',
        'email': 'unknown@example.com',
        'phone': '0000000000',
      };
    }

    // Handle nested structure if any
    if (caregiverObject is Map && caregiverObject.containsKey('caregiver')) {
      final caregiver = caregiverObject['caregiver'];
      return {
        'id': caregiver['id'] ?? 'unknown',
        'name':
            caregiver['name'] ??
            '${caregiver['firstName'] ?? ''} ${caregiver['lastName'] ?? ''}'
                .trim(),
        'email': caregiver['email'] ?? 'unknown@example.com',
        'phone': caregiver['phone'] ?? '0000000000',
      };
    }

    // Handle direct caregiver object
    if (caregiverObject is Map) {
      return {
        'id': caregiverObject['id'] ?? 'unknown',
        'name':
            caregiverObject['name'] ??
            '${caregiverObject['firstName'] ?? ''} ${caregiverObject['lastName'] ?? ''}'
                .trim(),
        'email': caregiverObject['email'] ?? 'unknown@example.com',
        'phone': caregiverObject['phone'] ?? '0000000000',
      };
    }

    // Fallback
    return {
      'id': 'unknown',
      'name': 'Unknown Caregiver',
      'email': 'unknown@example.com',
      'phone': '0000000000',
    };
  }

  /// Create action buttons for patient cards in caregiver dashboard
  static Widget createPatientActionButtons({
    required BuildContext context,
    required dynamic currentCaregiver,
    required dynamic targetPatient,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Video call button
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.blue),
          onPressed: () => startVideoCallToPatient(
            context: context,
            currentUser: currentCaregiver,
            targetPatient: targetPatient,
            isVideoCall: true,
          ),
          tooltip: 'Video Call',
        ),

        // Audio call button
        IconButton(
          icon: const Icon(Icons.call, color: Colors.green),
          onPressed: () => startVideoCallToPatient(
            context: context,
            currentUser: currentCaregiver,
            targetPatient: targetPatient,
            isVideoCall: false,
          ),
          tooltip: 'Audio Call',
        ),

        // SMS button
        IconButton(
          icon: const Icon(Icons.sms, color: Colors.orange),
          onPressed: () => _showSMSDialog(
            context: context,
            recipientName: _extractPatientData(targetPatient)['name'],
            onSendSMS: (message) => sendSMSToPatient(
              currentUser: currentCaregiver,
              targetPatient: targetPatient,
              message: message,
            ),
          ),
          tooltip: 'Send SMS',
        ),
      ],
    );
  }

  /// Create action buttons for caregiver cards in patient dashboard
  static Widget createCaregiverActionButtons({
    required BuildContext context,
    required dynamic currentPatient,
    required dynamic targetCaregiver,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Video call button
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.blue),
          onPressed: () => startVideoCallToCaregiver(
            context: context,
            currentUser: currentPatient,
            targetCaregiver: targetCaregiver,
            isVideoCall: true,
          ),
          tooltip: 'Video Call',
        ),

        // Audio call button
        IconButton(
          icon: const Icon(Icons.call, color: Colors.green),
          onPressed: () => startVideoCallToCaregiver(
            context: context,
            currentUser: currentPatient,
            targetCaregiver: targetCaregiver,
            isVideoCall: false,
          ),
          tooltip: 'Audio Call',
        ),

        // SMS button
        IconButton(
          icon: const Icon(Icons.sms, color: Colors.orange),
          onPressed: () => _showSMSDialog(
            context: context,
            recipientName: _extractCaregiverData(targetCaregiver)['name'],
            onSendSMS: (message) => sendSMSToCaregiver(
              currentUser: currentPatient,
              targetCaregiver: targetCaregiver,
              message: message,
            ),
          ),
          tooltip: 'Send SMS',
        ),
      ],
    );
  }

  /// Show SMS dialog
  static void _showSMSDialog({
    required BuildContext context,
    required String recipientName,
    required Function(String) onSendSMS,
  }) {
    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send SMS to $recipientName'),
        content: TextField(
          controller: messageController,
          decoration: const InputDecoration(
            hintText: 'Enter your message...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (messageController.text.trim().isNotEmpty) {
                onSendSMS(messageController.text.trim());
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('SMS sent to $recipientName')),
                );
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  /// Send SOS emergency alert - automatically gets location, only prompts for additional info
  static Future<void> sendSOSEmergencyAlert({
    required BuildContext context,
    required dynamic currentUser, // Current patient
    String? additionalInfo,
  }) async {
    final patientData = _extractPatientData(currentUser);
    final callId = 'sos-${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('🚨 SOS Emergency Alert Triggered:');
    debugPrint('   Patient: ${patientData['name']} (${patientData['id']})');
    debugPrint('   Call ID: $callId');

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Getting location and sending alert...'),
          ],
        ),
      ),
    );

    try {
      // Get current location automatically (works on both mobile and web)
      String locationString = await _getCurrentLocation();

      // Use default additional info if none provided
      final defaultInfo = additionalInfo?.isNotEmpty == true
          ? additionalInfo
          : 'Emergency situation - needs urgent response';

      // Send SOS request to the new API endpoint
      final authHeaders = await ApiService.getAuthHeaders();

      final sosRequest = {
        "patientUserId": patientData['id'].toString(),
        "patientName": patientData['name'],
        "callId": callId,
        "emergencyType": "GENERAL",
        "location": locationString,
        "additionalInfo": defaultInfo,
        "isVideoCall": false, // Video call is optional, not primary
      };

      debugPrint('📡 Sending SOS request to API: $sosRequest');

      final response = await http.post(
        Uri.parse('${getBackendBaseUrl()}/api/websocket/sos-call'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(sosRequest),
      );

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ SOS Emergency alert sent successfully');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚨 SOS Alert sent to caregivers!'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );

          // Show enhanced emergency dialog with video call option
          _showEnhancedEmergencyConfirmationDialog(
            context: context,
            patientData: patientData,
            emergencyType: "GENERAL",
            location: locationString,
            callId: callId,
            additionalInfo: defaultInfo,
          );
        }
      } else {
        debugPrint('❌ Failed to send SOS alert. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Failed to send SOS alert (${response.statusCode}). Please call 911 directly.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending SOS alert: $e');

      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ Network error sending SOS alert. Please call 911 directly.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Get current location automatically (works on mobile and web)
  static Future<String> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Location services disabled - please enable location';
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return 'Location permission denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return 'Location permission permanently denied';
      }

      // Get current position (works on both mobile and web browsers)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return 'Lat: ${position.latitude.toStringAsFixed(6)}, '
          'Lng: ${position.longitude.toStringAsFixed(6)}';
    } catch (e) {
      debugPrint('❌ Error getting location: $e');
      return 'Location unavailable - error: $e';
    }
  }

  /// Show enhanced emergency confirmation dialog with video call option
  static void _showEnhancedEmergencyConfirmationDialog({
    required BuildContext context,
    required Map<String, dynamic> patientData,
    required String emergencyType,
    required String location,
    required String callId,
    String? additionalInfo,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 8),
            Text('SOS Alert Sent', style: TextStyle(color: Colors.green)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✅ Emergency alert has been sent to your caregivers.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            Text('Patient: ${patientData['name']}'),
            Text('Emergency: $emergencyType'),
            Text('Location: $location'),
            if (additionalInfo != null && additionalInfo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Info: $additionalInfo'),
            ],
            const SizedBox(height: 16),
            const Text(
              'Your caregivers have been notified and will respond shortly.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // Start video call as optional feature
              startVideoCallToPatient(
                context: context,
                currentUser: patientData,
                targetPatient: patientData,
                isVideoCall: true,
              );
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Start Video Call'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Quick SOS button for patient dashboard
  static Widget createSOSButton({
    required BuildContext context,
    required dynamic currentPatient,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: () =>
            showSOSDialog(context: context, currentPatient: currentPatient),
        icon: Icon(Icons.emergency, color: theme.colorScheme.onError, size: 28),
        label: Text(
          'SOS EMERGENCY',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onError,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 8,
        ),
      ),
    );
  }

  /// Show SOS emergency type selection dialog
  static void showSOSDialog({
    required BuildContext context,
    required dynamic currentPatient,
  }) {
    final List<Map<String, dynamic>> emergencyTypes = [
      {
        'type': 'FALL',
        'title': 'Fall Emergency',
        'description': 'Patient has fallen and needs assistance',
        'icon': Icons.accessibility_new,
      },
      {
        'type': 'MEDICAL',
        'title': 'Medical Emergency',
        'description': 'Medical condition requiring immediate attention',
        'icon': Icons.medical_services,
      },
      {
        'type': 'PANIC',
        'title': 'Panic/Anxiety',
        'description': 'Panic attack or severe anxiety episode',
        'icon': Icons.psychology,
      },
      {
        'type': 'OTHER',
        'title': 'Other Emergency',
        'description': 'Other type of emergency situation',
        'icon': Icons.warning,
      },
    ];

    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '🚨 SOS Emergency',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          // Set a max height to prevent overflow
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height *
                    0.6, // 60% of screen height
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select the type of emergency:',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ...emergencyTypes.map(
                    (emergency) => Card(
                      child: ListTile(
                        leading: Icon(
                          emergency['icon'] as IconData,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          emergency['title'] as String,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          emergency['description'] as String,
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          sendSOSEmergencyAlert(
                            context: context,
                            currentUser: currentPatient,
                            additionalInfo: emergency['description'] as String,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Send direct SMS using platform's native SMS functionality
  static Future<void> _sendDirectSMS({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final smsUri = Uri(
        scheme: 'sms',
        path: phoneNumber,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        debugPrint('✅ SMS launched successfully to $phoneNumber');
      } else {
        debugPrint('❌ Could not launch SMS to $phoneNumber');
      }
    } catch (e) {
      debugPrint('❌ Error sending SMS: $e');
    }
  }
}
