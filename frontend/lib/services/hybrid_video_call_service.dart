import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Legacy hybrid call service

class HybridVideoCallService {
  static final HybridVideoCallService _instance =
      HybridVideoCallService._internal();
  factory HybridVideoCallService() => _instance;
  HybridVideoCallService._internal();

  // Service instances
  dynamic _mobileService;
  dynamic _webService;

  // Common properties
  bool _isInCall = false;
  String? _currentCallId;

  bool get isInCall => _isInCall;
  String? get currentCallId => _currentCallId;

  /// Initialize the video calling service (platform will be auto-detected)
  Future<void> initialize({
    required String userId,
    Function(dynamic)? onRemoteStreamReceived,
    Function()? onCallEnded,
  }) async {
    if (kIsWeb) {
      // Web initialization - create new instance
      // _webService = platform_service.VideoCallService();
      // await _webService.initialize(
      //   userId: userId,
      //   onRemoteStreamReceived: onRemoteStreamReceived != null
      //       ? (int uid) => onRemoteStreamReceived(uid)
      //       : null,
      //   onCallEnded: onCallEnded,
      // );
    } else {
      // Mobile initialization - use constructor
      // _mobileService = platform_service.VideoCallService();
      // await _mobileService.initialize(
      //   userId: userId,
      //   onRemoteStreamReceived: onRemoteStreamReceived != null
      //       ? (int uid) => onRemoteStreamReceived(uid)
      //       : null,
      //   onCallEnded: onCallEnded,
      // );
    }
  }

  /// Start a video call
  Future<Widget> startCall({
    required String callId,
    required String recipientId,
    bool isVideoEnabled = true,
    bool isAudioEnabled = true,
  }) async {
    if (_isInCall) {
      throw Exception('Already in a call');
    }

    _isInCall = true;
    _currentCallId = callId;

    try {
      if (kIsWeb) {
        // Web implementation using the functional web service
        await _webService.startCallInternal(
          callId,
          'current_user', // This should be the actual user ID
          recipientId,
          videoEnabled: isVideoEnabled,
        );

        return _buildWebCallInterface(callId, recipientId, isVideoEnabled);
      } else {
        // Mobile implementation
        return await _mobileService.startCall(
          callId: callId,
          recipientId: recipientId,
          isVideoEnabled: isVideoEnabled,
          isAudioEnabled: isAudioEnabled,
        );
      }
    } catch (e) {
      _isInCall = false;
      _currentCallId = null;
      rethrow;
    }
  }

  /// Join an existing call
  Future<Widget> joinCall({
    required String callId,
    bool isVideoEnabled = true,
    bool isAudioEnabled = true,
  }) async {
    if (_isInCall) {
      throw Exception('Already in a call');
    }

    _isInCall = true;
    _currentCallId = callId;

    try {
      if (kIsWeb) {
        // Web implementation
        await _webService.answerCall(callId, 'current_user', 'caller');
        return _buildWebCallInterface(callId, null, isVideoEnabled);
      } else {
        // Mobile implementation
        return await _mobileService.joinCallInstance(
          callId: callId,
          isVideoEnabled: isVideoEnabled,
          isAudioEnabled: isAudioEnabled,
        );
      }
    } catch (e) {
      _isInCall = false;
      _currentCallId = null;
      rethrow;
    }
  }

  /// End the current call
  Future<void> endCall() async {
    try {
      if (kIsWeb) {
        await _webService?.endCall();
      } else {
        await _mobileService?.endCall();
      }
    } catch (e) {
      print('Error ending call: $e');
    } finally {
      _isInCall = false;
      _currentCallId = null;
    }
  }

  /// Get call controls widget
  Widget getCallControls() {
    if (kIsWeb) {
      return Container(); // Web controls placeholder
    } else {
      return _mobileService?.getCallControls() ?? Container();
    }
  }

  /// Get local video view
  Widget getLocalVideoView() {
    if (kIsWeb) {
      return Container(); // Web local video placeholder
    } else {
      return _mobileService?.getLocalVideoView() ?? Container();
    }
  }

  /// Get remote video view
  Widget getRemoteVideoView() {
    if (kIsWeb) {
      return Container(); // Web remote video placeholder
    } else {
      return _mobileService?.getRemoteVideoView() ?? Container();
    }
  }

  /// Toggle video
  Future<void> toggleVideo(bool enabled) async {
    if (kIsWeb) {
      await _webService?.toggleVideoWithParam(enabled);
    } else {
      await _mobileService?.toggleVideo(enabled);
    }
  }

  /// Toggle audio
  Future<void> toggleAudio(bool enabled) async {
    if (kIsWeb) {
      await _webService?.toggleAudioWithParam(enabled);
    } else {
      await _mobileService?.toggleAudio(enabled);
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    await endCall();
    if (kIsWeb) {
      await _webService?.dispose();
    } else {
      await _mobileService?.dispose();
    }
  }

  /// Build web call interface widget
  Widget _buildWebCallInterface(
    String callId,
    String? recipientId,
    bool isVideoEnabled,
  ) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<Map<String, dynamic>>(
              stream: _webService.callEventStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final event = snapshot.data!;
                  final status = event['status'] ?? 'Connecting...';

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Video/Audio status indicator
                        Icon(
                          isVideoEnabled ? Icons.videocam : Icons.call,
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Telehealth session',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status: $status',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (recipientId != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Calling: $recipientId',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Connecting to call...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Call controls
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Toggle video
                FloatingActionButton(
                  heroTag: 'video',
                  onPressed: () async {
                    final newVideoState = !isVideoEnabled;
                    await toggleVideo(newVideoState);
                  },
                  backgroundColor: isVideoEnabled ? Colors.blue : Colors.grey,
                  child: Icon(
                    isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    color: Colors.white,
                  ),
                ),
                // End call
                FloatingActionButton(
                  heroTag: 'end',
                  onPressed: endCall,
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
                // Toggle audio
                FloatingActionButton(
                  heroTag: 'audio',
                  onPressed: () async {
                    final newAudioState = !_webService.isAudioEnabled;
                    await toggleAudio(newAudioState);
                  },
                  backgroundColor:
                      _webService.isAudioEnabled ? Colors.green : Colors.grey,
                  child: Icon(
                    _webService.isAudioEnabled ? Icons.mic : Icons.mic_off,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
