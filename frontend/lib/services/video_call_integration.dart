import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import '../widgets/hybrid_video_call_widget.dart';
import '../services/backend_api_service.dart';
import '../services/subscription_service.dart';
import '../providers/user_provider.dart';
import 'package:provider/provider.dart';

/// Helper class to integrate video calling with your real dashboard data
class VideoCallIntegration {
  /// Initialize with your authentication token from login
  static void initialize(String authToken) {
    BackendApiService.setAuthToken(authToken);
  }

  /// Start a video call from caregiver dashboard to patient
  /// Uses real patient data from your API: /v1/api/caregivers/{id}/patients
  static Future<void> startCallToPatient({
    required BuildContext context,
    required String caregiverId,
    required String caregiverName,
    required String caregiverEmail,
    required Map<String, dynamic> patientData, // From your backend API
  }) async {
    // Check subscription for caregivers only
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userProvider.user?.role == 'CAREGIVER') {
      final hasAccess = await SubscriptionService.checkPremiumAccessWithDialog(
        context,
        'Video calls are only available with premium subscriptions.',
      );
      if (!hasAccess) return;
    }

    if (!context.mounted) {
      return;
    }

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Extract patient info from your API structure
    final patientId = patientData['id']?.toString() ?? 'unknown';
    final patientName =
        '${patientData['firstName'] ?? ''} ${patientData['lastName'] ?? ''}'
            .trim();
    final patientEmail = patientData['email'] ?? '';
    final patientPhone = patientData['phone'] ?? '';

    debugPrint('📞 Initiating call from caregiver to patient:');
    debugPrint('   Caregiver: $caregiverName ($caregiverEmail)');
    debugPrint('   Patient: $patientName ($patientEmail)');
    debugPrint('   Call ID: $callId');

    // Navigate to video call widget with real data
    Navigator.of(context).push(
      TitledMaterialPageRoute(
        title: 'Video Call',
        builder: (context) => HybridVideoCallWidget(
          userId: caregiverId,
          callId: callId,
          recipientId: patientId,
          isInitiator: true,
          isVideoEnabled: true,
          isAudioEnabled: true,

          // Real caregiver data
          userName: caregiverName,
          userEmail: caregiverEmail,
          userPhone: null, // Add if available
          // Real patient data from backend
          recipientName: patientName,
          recipientEmail: patientEmail,
          recipientPhone: patientPhone,
        ),
      ),
    );
  }

  /// Start a voice call from caregiver dashboard to patient
  static Future<void> startVoiceCallToPatient({
    required BuildContext context,
    required String caregiverId,
    required String caregiverName,
    required String caregiverEmail,
    required Map<String, dynamic> patientData,
  }) async {
    // Check subscription for caregivers only
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userProvider.user?.role == 'CAREGIVER') {
      final hasAccess = await SubscriptionService.checkPremiumAccessWithDialog(
        context,
        'Voice calls are only available with premium subscriptions.',
      );
      if (!hasAccess) return;
    }

    if (!context.mounted) {
      return;
    }

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    final patientId = patientData['id']?.toString() ?? 'unknown';
    final patientName =
        '${patientData['firstName'] ?? ''} ${patientData['lastName'] ?? ''}'
            .trim();
    final patientEmail = patientData['email'] ?? '';
    final patientPhone = patientData['phone'] ?? '';

    debugPrint('📞 Initiating voice call from caregiver to patient:');
    debugPrint('   Caregiver: $caregiverName ($caregiverEmail)');
    debugPrint('   Patient: $patientName ($patientEmail)');

    Navigator.of(context).push(
      TitledMaterialPageRoute(
        title: 'Video Call',
        builder: (context) => HybridVideoCallWidget(
          userId: caregiverId,
          callId: callId,
          recipientId: patientId,
          isInitiator: true,
          isVideoEnabled: false, // Voice only
          isAudioEnabled: true,

          userName: caregiverName,
          userEmail: caregiverEmail,
          recipientName: patientName,
          recipientEmail: patientEmail,
          recipientPhone: patientPhone,
        ),
      ),
    );
  }

  /// Send SMS to patient via backend
  static Future<bool> sendSMSToPatient({
    required String caregiverName,
    required Map<String, dynamic> patientData,
    required String message,
  }) async {
    final patientPhone = patientData['phone'] ?? '';

    if (patientPhone.isEmpty) {
      debugPrint('❌ Cannot send SMS: Patient phone number not available');
      return false;
    }

    debugPrint('📱 Sending SMS via backend:');
    debugPrint('   From: $caregiverName');
    debugPrint('   To: $patientPhone');
    debugPrint('   Message: $message');

    return await BackendApiService.sendSMS(
      senderName: caregiverName,
      recipientPhone: patientPhone,
      message: message,
    );
  }

  /// Get patients for caregiver dashboard
  static Future<List<Map<String, dynamic>>> getCaregiverPatients(
    int caregiverId,
  ) async {
    return await BackendApiService.getCaregiverPatients(caregiverId);
  }

  /// Get conversation history for messaging
  static Future<List<Map<String, dynamic>>> getConversation(
    String user1,
    String user2,
  ) async {
    return await BackendApiService.getConversation(user1, user2);
  }

  /// Send a message via backend
  static Future<bool> sendMessage({
    required String senderId,
    required String senderName,
    required String recipientId,
    required String message,
  }) async {
    return await BackendApiService.sendMessage(
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      message: message,
    );
  }

  /// Get call history from backend
  static Future<List<Map<String, dynamic>>> getCallHistory(
    String userId,
  ) async {
    return await BackendApiService.getCallHistory(userId);
  }

  /// Test backend connection
  static Future<bool> testBackendConnection() async {
    return await BackendApiService.testConnection();
  }
}

/// Widget to show backend integration status
class BackendStatusWidget extends StatefulWidget {
  const BackendStatusWidget({super.key});

  @override
  State<BackendStatusWidget> createState() => _BackendStatusWidgetState();
}

class _BackendStatusWidgetState extends State<BackendStatusWidget> {
  bool _isConnected = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final connected = await VideoCallIntegration.testBackendConnection();
    setState(() {
      _isConnected = connected;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Checking backend...', style: TextStyle(fontSize: 12)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _isConnected ? Icons.cloud_done : Icons.cloud_off,
          color: _isConnected ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          _isConnected ? 'Backend Connected' : 'Backend Offline',
          style: TextStyle(
            fontSize: 12,
            color: _isConnected ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }
}
