import 'dart:async';
import 'package:flutter/material.dart';

class VideoCallService {
  static VideoCallService? _instance;
  static VideoCallService get instance => _instance ??= VideoCallService._();

  // Add public constructor for compatibility with mobile interface
  VideoCallService() : this._();
  VideoCallService._();

  // Call state
  bool _isCallActive = false;
  bool _isVideoEnabled = true;
  bool _isAudioEnabled = true;
  String? _currentCallId;
  String? _currentUserId;
  String? _remoteUserId;

  // Stream controllers for UI updates
  final StreamController<bool> _callStateController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _callEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<bool> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get callEventStream =>
      _callEventController.stream;

  // Static methods for compatibility
  static Future<bool> initializeService() async {
    try {
      debugPrint('Web VideoCallService initialized');
      return true;
    } catch (e) {
      debugPrint('Error initializing web video service: $e');
      return false;
    }
  }

  static Future<bool> checkUserAvailability(String userId) async {
    return true; // For now, assume all users are available
  }

  static Future<Map<String, dynamic>> initiateCall({
    required String callerId,
    required String recipientId,
    bool isVideoCall = true,
  }) async {
    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    final success = await instance.startCallInternal(
      callId,
      callerId,
      recipientId,
      videoEnabled: isVideoCall,
    );

    return {
      'success': success,
      'callId': callId,
      'callerId': callerId,
      'recipientId': recipientId,
      'isVideoCall': isVideoCall,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Future<bool> joinCall(String callId, String userId) async {
    return await instance.answerCall(callId, userId, 'caller');
  }

  static Future<void> endCallStatic(String callId, String userId) async {
    await instance.endCall();
  }

  // Getters for state
  bool get isCallActive => _isCallActive;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isAudioEnabled => _isAudioEnabled;
  String? get currentCallId => _currentCallId;
  String? get currentUserId => _currentUserId;
  String? get remoteUserId => _remoteUserId;

  // Initialize method with mobile-compatible signature
  Future<void> initialize({
    required String userId,
    Function(int uid)? onRemoteStreamReceived,
    Function()? onCallEnded,
  }) async {
    _currentUserId = userId;
    debugPrint(
        'Web VideoCallService initialized with mobile-compatible interface');
  }

  // Start a video call (internal method)
  Future<bool> startCallInternal(
    String callId,
    String userId,
    String targetUserId, {
    bool videoEnabled = true,
    bool audioEnabled = true,
  }) async {
    try {
      debugPrint('📞 Starting web call: $callId');

      _currentCallId = callId;
      _currentUserId = userId;
      _remoteUserId = targetUserId;
      _isVideoEnabled = videoEnabled;
      _isAudioEnabled = audioEnabled;
      _isCallActive = true;
      _callStateController.add(true);

      debugPrint('✅ Web call started successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error starting web call: $e');
      return false;
    }
  }

  // Answer an incoming call
  Future<bool> answerCall(
    String callId,
    String userId,
    String callerUserId,
  ) async {
    try {
      debugPrint('📞 Answering web call: $callId');

      _currentCallId = callId;
      _currentUserId = userId;
      _remoteUserId = callerUserId;
      _isCallActive = true;
      _callStateController.add(true);

      debugPrint('✅ Web call answered successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error answering web call: $e');
      return false;
    }
  }

  // Toggle video on/off
  Future<void> toggleVideo() async {
    _isVideoEnabled = !_isVideoEnabled;
    debugPrint('📹 Video ${_isVideoEnabled ? 'enabled' : 'disabled'}');
    _callEventController.add({
      'type': 'video-toggled',
      'enabled': _isVideoEnabled,
    });
  }

  // Toggle audio on/off
  Future<void> toggleAudio() async {
    _isAudioEnabled = !_isAudioEnabled;
    debugPrint('🎤 Audio ${_isAudioEnabled ? 'enabled' : 'disabled'}');
    _callEventController.add({
      'type': 'audio-toggled',
      'enabled': _isAudioEnabled,
    });
  }

  // End call
  Future<void> endCall() async {
    try {
      debugPrint('📞 Ending web call...');

      _isCallActive = false;
      _currentCallId = null;
      _currentUserId = null;
      _remoteUserId = null;
      _isVideoEnabled = true;
      _isAudioEnabled = true;

      _callStateController.add(false);
      _callEventController.add({'type': 'call-ended'});

      debugPrint('✅ Web call ended successfully');
    } catch (e) {
      debugPrint('❌ Error ending web call: $e');
    }
  }

  // Methods to match mobile interface
  Future<Widget> startCall({
    required String callId,
    required String recipientId,
    bool isVideoEnabled = true,
    bool isAudioEnabled = true,
  }) async {
    final success = await startCallInternal(
      callId,
      _currentUserId ?? 'unknown',
      recipientId,
      videoEnabled: isVideoEnabled,
      audioEnabled: isAudioEnabled,
    );

    if (success) {
      return Container(
        color: Colors.black,
        child: Stack(
          children: [
            const Center(
              child: Text(
                'Web video calling - waiting for remote user...',
                style: TextStyle(color: Colors.white),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              width: 120,
              height: 160,
              child: Container(
                color: Colors.grey,
                child: const Center(
                  child: Text(
                    'Local',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      throw Exception('Failed to start call');
    }
  }

  Future<Widget> joinCallInstance({
    required String callId,
    bool isVideoEnabled = true,
    bool isAudioEnabled = true,
  }) async {
    final success = await answerCall(
      callId,
      _currentUserId ?? 'unknown',
      'caller',
    );

    if (success) {
      return startCall(
        callId: callId,
        recipientId: 'unknown',
        isVideoEnabled: isVideoEnabled,
        isAudioEnabled: isAudioEnabled,
      );
    } else {
      throw Exception('Failed to join call');
    }
  }

  Widget getLocalVideoView() {
    return Container(
      color: Colors.grey,
      child: const Center(
        child: Text(
          'Local Video (Web)',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Widget getRemoteVideoView() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Remote Video (Web)',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget getCallControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton(
            heroTag: "video",
            onPressed: () async {
              await toggleVideo();
            },
            child: Icon(_isVideoEnabled ? Icons.videocam : Icons.videocam_off),
          ),
          FloatingActionButton(
            heroTag: "audio",
            onPressed: () async {
              await toggleAudio();
            },
            child: Icon(_isAudioEnabled ? Icons.mic : Icons.mic_off),
          ),
          FloatingActionButton(
            heroTag: "end",
            backgroundColor: Colors.red,
            onPressed: () async {
              await endCall();
            },
            child: const Icon(Icons.call_end),
          ),
        ],
      ),
    );
  }

  // Methods with parameters to match mobile interface
  Future<void> toggleVideoWithParam(bool enabled) async {
    _isVideoEnabled = enabled;
    debugPrint('📹 Video set to ${_isVideoEnabled ? 'enabled' : 'disabled'}');
  }

  Future<void> toggleAudioWithParam(bool enabled) async {
    _isAudioEnabled = enabled;
    debugPrint('🎤 Audio set to ${_isAudioEnabled ? 'enabled' : 'disabled'}');
  }

  // Dispose service
  Future<void> dispose() async {
    await endCall();
    await _callStateController.close();
    await _callEventController.close();
    debugPrint('🧹 Web VideoCallService disposed');
  }
}
