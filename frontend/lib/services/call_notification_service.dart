import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../widgets/incoming_call_popup.dart';
import '../config/env_constant.dart';
import '../services/auth_token_manager.dart';

/// Service to handle real-time call notifications for caregivers
class CallNotificationService {
  static WebSocketChannel? _channel;
  static bool _isConnected = false;
  static String? _currentUserId;
  static String? _currentUserRole;
  static String? _currentUserDisplayName;
  static BuildContext? _context;
  static String? _activeCallId;
  static String? _currentIncomingCallId;
  static bool _isIncomingDialogVisible = false;
  static final Map<String, DateTime> _suppressedIncomingCallIds =
      <String, DateTime>{};
  static final Map<String, Completer<bool>> _pendingOutgoingInvitations =
      <String, Completer<bool>>{};

  // Stream controllers for call events
  static final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  static Stream<Map<String, dynamic>> get incomingCallStream =>
      _incomingCallController.stream;
  static bool get isConnected => _isConnected;

  /// Initialize the real-time notification service
  static Future<bool> initialize({
    required String userId,
    required String userRole, // 'CAREGIVER' or 'PATIENT'
    required BuildContext context,
    String? userDisplayName,
    String? websocketUrl, // Optional: pass WebSocket URL for flexibility
  }) async {
    try {
      _currentUserId = userId;
      _currentUserRole = userRole;
      _currentUserDisplayName = _normalizeDisplayName(
        (userDisplayName ?? '').toString(),
        roleFallback: userRole,
        genericFallback: 'Participant',
      );
      _context = context;

      debugPrint(
        '🔔 Initializing CallNotificationService for $userRole: $userId',
      );

      if (_isConnected && _currentUserId == userId && _channel != null) {
        // Reuse existing connection, only refresh context/role references
        return true;
      }

      if (_isConnected) {
        dispose();
      }

      // Connect to backend call WebSocket endpoint
      final String wsUrl = websocketUrl ?? getCallNotificationWebSocketUrl();
      debugPrint('Connecting to notification WebSocket: $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      final token = await AuthTokenManager.getJwtToken();
      if (token == null || token.isEmpty) {
        debugPrint('❌ Cannot initialize call notifications: missing JWT token');
        dispose();
        return false;
      }

      // Authenticate and join user room
      _channel!.sink.add(_encode({'type': 'authenticate', 'token': token}));
      _channel!.sink.add(_encode({'type': 'join-user-room'}));

      // Listen for messages
      _channel!.stream.listen(
        (message) {
          final data = _decode(message);
          if (data == null || data.isEmpty) return;
          _processNotificationMessage(data);
        },
        onDone: () {
          _isConnected = false;
          debugPrint('❌ CallNotificationService WebSocket closed');
        },
        onError: (e) {
          _isConnected = false;
          debugPrint('❌ CallNotificationService WebSocket error: $e');
        },
      );

      return true;
    } catch (e) {
      debugPrint('❌ Error initializing CallNotificationService: $e');
      return false;
    }
  }

  static void _processNotificationMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    if (type == 'incoming-video-call') {
      debugPrint('📞 Received incoming video call: $data');
      _incomingCallController.add(data);
      _handleIncomingCall(data);
    } else if (type == 'call-ended') {
      debugPrint('📞 Call ended: $data');
      _incomingCallController.add(data);
      _dismissIncomingCallForCallId((data['callId'] ?? '').toString());
      _notifyCallEnded(data);
    } else if (type == 'call-invitation-cancelled') {
      debugPrint('📞 Call invitation cancelled: $data');
      _incomingCallController.add(data);
      _dismissIncomingCallForCallId((data['callId'] ?? '').toString());
    } else if (type == 'call-answered') {
      debugPrint('📞 Call answered: $data');
      _incomingCallController.add(data);
      final answeredCallId = (data['callId'] ?? '').toString();
      if (answeredCallId.isNotEmpty) {
        _activeCallId = answeredCallId;
      }
      _notifyCallAnswered(data);
    } else if (type == 'call-declined') {
      debugPrint('📞 Call declined: $data');
      _incomingCallController.add(data);
      final declinedCallId = (data['callId'] ?? '').toString();
      if (declinedCallId.isNotEmpty) {
        _suppressIncomingCallId(declinedCallId);
        if (_activeCallId == declinedCallId) {
          _activeCallId = null;
        }
      }
      _notifyCallDeclined(data);
    } else if (type == 'call-invitation-sent') {
      final callId = (data['callId'] ?? '').toString();
      final pending = _pendingOutgoingInvitations.remove(callId);
      if (pending != null && !pending.isCompleted) {
        pending.complete(true);
      }
    } else if (type == 'call-invitation-failed') {
      final callId = (data['callId'] ?? '').toString();
      final reason = (data['reason'] ?? 'Recipient unavailable')
          .toString()
          .trim();
      final recipientName = (data['recipientName'] ?? '').toString().trim();
      final recipientRole = (data['recipientRole'] ?? '').toString().trim();
      final recipientLabel = recipientName.isNotEmpty
          ? recipientName
          : (_roleLabel(recipientRole) ?? 'Recipient');
      final pending = _pendingOutgoingInvitations.remove(callId);
      if (pending != null && !pending.isCompleted) {
        pending.complete(false);
      }
      if (_activeCallId == callId) {
        _activeCallId = null;
      }
      _showCallFeedback(
        '$recipientLabel is unavailable: $reason.',
        backgroundColor: Colors.orange.shade800,
      );
    } else if (type == 'sentiment-update') {
      _incomingCallController.add(data);
    } else if (type == 'sentiment-channel-state') {
      _incomingCallController.add(data);
    }
  }

  static void _dismissIncomingCallForCallId(String callId) {
    if (callId.isEmpty) return;

    _suppressIncomingCallId(callId);
    if (_activeCallId == callId) {
      _activeCallId = null;
    }

    if (_isIncomingDialogVisible &&
        _currentIncomingCallId != null &&
        _currentIncomingCallId != callId) {
      return;
    }

    final shouldDismissPopup = _isIncomingDialogVisible &&
        (_currentIncomingCallId == null || _currentIncomingCallId == callId);
    if (shouldDismissPopup) {
      _dismissIncomingCallPopup();
    }
  }

  /// Handle incoming call notification
  static void _handleIncomingCall(Map<String, dynamic> callData) {
    if (_context == null) return;

    // Extract call information
    final callId = (callData['callId'] ?? '').toString();
    final callerId = (callData['senderId'] ?? callData['callerId'] ?? '')
        .toString();
    final callerRole =
        (callData['senderRole'] ?? callData['callerRole'] ?? 'PATIENT')
            .toString();
    final callerName = _normalizeDisplayName(
      (callData['senderName'] ?? callData['callerName'] ?? 'Unknown Caller')
          .toString(),
      roleFallback: callerRole,
      genericFallback: 'Unknown Caller',
    );
    final isVideoCall = callData['isVideoCall'] ?? true;
    final isConferenceInvite = callData['isConferenceInvite'] == true;

    if (callId.isEmpty) return;
    _pruneSuppressedIncomingCallIds();

    if (_activeCallId == callId || _isIncomingCallSuppressed(callId)) {
      debugPrint(
        '⏭️ Suppressing duplicate incoming call popup for callId: $callId',
      );
      return;
    }

    if (_isIncomingDialogVisible) {
      if (_currentIncomingCallId == callId) {
        debugPrint('⏭️ Incoming popup already visible for callId: $callId');
        return;
      }
      debugPrint(
        '⏭️ Ignoring incoming call while another incoming popup is visible',
      );
      return;
    }

    debugPrint('📞 Processing incoming call from $callerName ($callerRole)'
        '${isConferenceInvite ? ' [conference invite]' : ''}');

    // Show incoming call popup
    _showIncomingCallPopup(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      isVideoCall: isVideoCall,
      callerRole: callerRole,
      isConferenceInvite: isConferenceInvite,
    );
  }

  /// Show incoming call popup UI
  static void _showIncomingCallPopup({
    required String callId,
    required String callerId,
    required String callerName,
    required bool isVideoCall,
    required String callerRole,
    bool isConferenceInvite = false,
  }) {
    if (_context == null) return;

    _currentIncomingCallId = callId;
    _isIncomingDialogVisible = true;

    showDialog(
      context: _context!,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => IncomingCallPopup(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        isVideoCall: isVideoCall,
        callerRole: callerRole,
        isConferenceInvite: isConferenceInvite,
        onAccept: () => _acceptCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          isVideoCall: isVideoCall,
          dialogContext: context,
        ),
        onDecline: () => _declineCall(
          callId: callId,
          callerId: callerId,
          dialogContext: context,
        ),
      ),
    ).whenComplete(() {
      if (_currentIncomingCallId == callId) {
        _isIncomingDialogVisible = false;
        _currentIncomingCallId = null;
      }
    });
  }

  /// Accept incoming call
  static void _acceptCall({
    required String callId,
    required String callerId,
    required String callerName,
    required bool isVideoCall,
    BuildContext? dialogContext,
  }) {
    if (_context == null || _currentUserId == null) return;

    debugPrint('✅ Accepting call: $callId');
    _activeCallId = callId;
    _suppressIncomingCallId(callId, duration: const Duration(seconds: 45));

    // Notify backend that call was accepted
    if (_channel != null && _isConnected) {
      final msg = {
        'type': 'accept-call',
        'callId': callId,
        'senderId': callerId,
      };
      _channel!.sink.add(_encode(msg));
    }

    _dismissIncomingCallPopup(dialogContext: dialogContext);

    // Navigate to video call screen
    final userName = Uri.encodeComponent(_getCurrentUserName());
    final recipientName = Uri.encodeComponent(callerName);
    final role = Uri.encodeComponent((_currentUserRole ?? '').toUpperCase());
    _context!.push(
      '/video-call-chime'
      '?userId=$_currentUserId'
      '&callId=${Uri.encodeComponent(callId)}'
      '&recipientId=${Uri.encodeComponent(callerId)}'
      '&userRole=$role'
      '&userName=$userName'
      '&recipientName=$recipientName'
      '&initiator=false'
      '&video=${isVideoCall ? 'true' : 'false'}'
      '&audio=true',
    );
  }

  /// Decline incoming call
  static void _declineCall({
    required String callId,
    required String callerId,
    BuildContext? dialogContext,
  }) {
    debugPrint('❌ Declining call: $callId');
    _suppressIncomingCallId(callId);

    // Notify backend that call was declined
    if (_channel != null && _isConnected) {
      final msg = {
        'type': 'decline-call',
        'callId': callId,
        'senderId': callerId,
      };
      _channel!.sink.add(_encode(msg));
    }

    _dismissIncomingCallPopup(dialogContext: dialogContext);
  }

  static void _dismissIncomingCallPopup({BuildContext? dialogContext}) {
    if (!_isIncomingDialogVisible) return;

    final dialogNavigator = dialogContext != null
        ? Navigator.maybeOf(dialogContext, rootNavigator: true)
        : null;
    if (dialogNavigator != null && dialogNavigator.canPop()) {
      dialogNavigator.pop();
    } else if (_context != null) {
      final navigator = Navigator.maybeOf(_context!, rootNavigator: true);
      navigator?.maybePop();
    }

    _isIncomingDialogVisible = false;
    _currentIncomingCallId = null;
  }

  static void _suppressIncomingCallId(
    String callId, {
    Duration duration = const Duration(seconds: 30),
  }) {
    if (callId.isEmpty) return;
    _suppressedIncomingCallIds[callId] = DateTime.now().add(duration);
  }

  static bool _isIncomingCallSuppressed(String callId) {
    final expiresAt = _suppressedIncomingCallIds[callId];
    if (expiresAt == null) return false;
    if (DateTime.now().isAfter(expiresAt)) {
      _suppressedIncomingCallIds.remove(callId);
      return false;
    }
    return true;
  }

  static void _pruneSuppressedIncomingCallIds() {
    final now = DateTime.now();
    final expired = <String>[];
    _suppressedIncomingCallIds.forEach((callId, expiresAt) {
      if (now.isAfter(expiresAt)) {
        expired.add(callId);
      }
    });
    for (final callId in expired) {
      _suppressedIncomingCallIds.remove(callId);
    }
  }

  static void _notifyCallDeclined(Map<String, dynamic> data) {
    final context = _context;
    if (context == null) return;

    final declinedByName = _normalizeDisplayName(
      (data['declinedByName'] ?? data['senderName'] ?? 'The recipient')
          .toString(),
      genericFallback: 'The recipient',
    );
    final reason = (data['reason'] ?? 'declined').toString();
    final normalizedReason = reason.trim().isEmpty ? 'declined' : reason;

    _showCallFeedback(
      '$declinedByName declined the call ($normalizedReason).',
      backgroundColor: Colors.orange.shade800,
    );
  }

  static void _notifyCallAnswered(Map<String, dynamic> data) {
    final answeredBy = _normalizeDisplayName(
      (data['answeredByName'] ?? data['senderName'] ?? 'Recipient').toString(),
      genericFallback: 'Recipient',
    );
    _showCallFeedback(
      '$answeredBy answered. Connecting now…',
      backgroundColor: Colors.green.shade700,
    );
  }

  static void _notifyCallEnded(Map<String, dynamic> data) {
    final endedBy = _normalizeDisplayName(
      (data['endedByName'] ?? data['senderName'] ?? 'Other participant')
          .toString(),
      genericFallback: 'Other participant',
    );
    _showCallFeedback(
      'Call ended by $endedBy.',
      backgroundColor: Colors.blueGrey.shade700,
    );
  }

  static void _showCallFeedback(
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
  }) {
    final context = _context;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
        ),
      );
  }

  /// Send outgoing call notification
  static Future<bool> sendCallInvitation({
    required String recipientId,
    required String recipientRole, // 'CAREGIVER' or 'PATIENT'
    required String callId,
    required bool isVideoCall,
    String? callType,
  }) async {
    if (!_isConnected || _channel == null) {
      debugPrint('❌ Cannot send call invitation - not connected');
      _showCallFeedback(
        'Unable to start call: notifications are not connected.',
        backgroundColor: Colors.red.shade700,
      );
      return false;
    }
    try {
      debugPrint('📤 Sending call invitation to $recipientRole: $recipientId');
      final msg = {
        'type': 'send-video-call-invitation',
        'callId': callId,
        'callerId': _currentUserId,
        'callerName': _getCurrentUserName(),
        'callerRole': _currentUserRole,
        'recipientId': recipientId,
        'recipientRole': recipientRole,
        'isVideoCall': isVideoCall,
        'callType': (callType ?? 'general'),
        'timestamp': DateTime.now().toIso8601String(),
      };
      _channel!.sink.add(_encode(msg));
      _activeCallId = callId;

      final completer = Completer<bool>();
      _pendingOutgoingInvitations[callId] = completer;

      _showCallFeedback(
        'Calling $recipientRole… waiting for response.',
        backgroundColor: Colors.blue.shade700,
      );

      final delivered = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          _pendingOutgoingInvitations.remove(callId);
          if (_activeCallId == callId) {
            _activeCallId = null;
          }
          _showCallFeedback(
            '${_roleLabel(recipientRole) ?? 'Recipient'} did not confirm availability. They may be offline.',
            backgroundColor: Colors.orange.shade800,
          );
          return false;
        },
      );

      return delivered;
    } catch (e) {
      debugPrint('❌ Error sending call invitation: $e');
      _pendingOutgoingInvitations.remove(callId);
      _showCallFeedback(
        'Failed to send call invitation. Please try again.',
        backgroundColor: Colors.red.shade700,
      );
      return false;
    }
  }

  static Future<bool> sendSentimentChannelState({
    required String callId,
    required String otherPartyId,
    required String channel,
    required bool muted,
    String? captureMode,
  }) async {
    if (!_isConnected || _channel == null) {
      return false;
    }

    final normalizedChannel = channel.trim().toLowerCase();
    if (normalizedChannel != 'text' &&
        normalizedChannel != 'voice' &&
        normalizedChannel != 'video') {
      return false;
    }

    try {
      final msg = {
        'type': 'sentiment-channel-state',
        'callId': callId,
        'otherPartyId': otherPartyId,
        'channel': normalizedChannel,
        'muted': muted,
        'captureMode': captureMode,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _channel!.sink.add(_encode(msg));
      return true;
    } catch (e) {
      debugPrint('❌ Error sending channel state: $e');
      return false;
    }
  }

  static Future<bool> sendEndCallSignal({
    required String callId,
    required String otherPartyId,
  }) async {
    if (!_isConnected || _channel == null) {
      return false;
    }

    final normalizedCallId = callId.trim();
    final normalizedOther = otherPartyId.trim();
    if (normalizedCallId.isEmpty || normalizedOther.isEmpty) {
      return false;
    }

    try {
      final msg = {
        'type': 'end-call',
        'callId': normalizedCallId,
        'otherPartyId': normalizedOther,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _channel!.sink.add(_encode(msg));
      _suppressIncomingCallId(normalizedCallId, duration: const Duration(seconds: 45));
      if (_activeCallId == normalizedCallId) {
        _activeCallId = null;
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error sending end-call signal: $e');
      return false;
    }
  }

  static void clearActiveCall([String? callId]) {
    final normalized = callId?.trim();
    if (normalized == null || normalized.isEmpty) {
      _activeCallId = null;
      return;
    }
    if (_activeCallId == normalized) {
      _activeCallId = null;
    }
  }

  // Helper to encode/decode JSON
  static String _encode(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  static Map<String, dynamic>? _decode(dynamic message) {
    try {
      if (message is String) {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('❌ Error decoding WebSocket message: $e');
    }
    return null;
    // removed extra closing brace here
  }

  static String _normalizeDisplayName(
    String raw, {
    String? roleFallback,
    String genericFallback = 'Participant',
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return _roleLabel(roleFallback) ?? genericFallback;
    }

    if (_looksLikeEmail(trimmed)) {
      return _roleLabel(roleFallback) ?? genericFallback;
    }

    return trimmed;
  }

  static bool _looksLikeEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  static String? _roleLabel(String? role) {
    final normalized = role?.trim().toUpperCase();
    if (normalized == 'CAREGIVER') return 'Caregiver';
    if (normalized == 'PATIENT') return 'Patient';
    return null;
  }

  /// Get current user name from context or default
  static String _getCurrentUserName() {
    return _normalizeDisplayName(
      (_currentUserDisplayName ?? '').toString(),
      roleFallback: _currentUserRole,
      genericFallback: 'Participant',
    );
  }

  /// Dispose and cleanup
  static void dispose() {
    debugPrint('🧹 Disposing CallNotificationService');

    _channel?.sink.close(status.normalClosure);
    _channel = null;

    _isConnected = false;
    _currentUserId = null;
    _currentUserRole = null;
    _currentUserDisplayName = null;
    _context = null;
    _activeCallId = null;
    _currentIncomingCallId = null;
    _isIncomingDialogVisible = false;
    _suppressedIncomingCallIds.clear();
    for (final pending in _pendingOutgoingInvitations.values) {
      if (!pending.isCompleted) {
        pending.complete(false);
      }
    }
    _pendingOutgoingInvitations.clear();

    // Keep stream controller alive for app lifetime.
  }

  @visibleForTesting
  static void configureForTest({
    required BuildContext context,
    String userId = 'test-user',
    String userRole = 'FAMILY_MEMBER',
    String? userDisplayName,
  }) {
    _context = context;
    _currentUserId = userId;
    _currentUserRole = userRole;
    _currentUserDisplayName = userDisplayName;
    _isConnected = true;
  }

  @visibleForTesting
  static void resetTestState() {
    _isIncomingDialogVisible = false;
    _currentIncomingCallId = null;
    _activeCallId = null;
    _suppressedIncomingCallIds.clear();
  }

  @visibleForTesting
  static void clearIncomingCallIdForTest() {
    _currentIncomingCallId = null;
  }

  @visibleForTesting
  static bool get isIncomingDialogVisibleForTest => _isIncomingDialogVisible;

  @visibleForTesting
  static void processNotificationMessageForTest(Map<String, dynamic> data) {
    _processNotificationMessage(data);
  }
}
