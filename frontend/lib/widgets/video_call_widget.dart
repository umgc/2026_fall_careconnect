import 'package:flutter/material.dart';
// import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/theme/app_theme.dart';

class VideoCallWidget extends StatefulWidget {
  final String callId;
  final String currentUserId;
  final String currentUserName;
  final String otherUserId;
  final String otherUserName;
  final bool isVideoCall;
  final bool isIncoming;

  const VideoCallWidget({
    super.key,
    required this.callId,
    required this.currentUserId,
    required this.currentUserName,
    required this.otherUserId,
    required this.otherUserName,
    this.isVideoCall = true,
    this.isIncoming = false,
  });

  @override
  State<VideoCallWidget> createState() => _VideoCallWidgetState();
}

class _VideoCallWidgetState extends State<VideoCallWidget> {
  // final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  // final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  // MediaStream? _localStream;
  // RTCPeerConnection? _peerConnection;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    if (!widget.isIncoming) {
      // _joinCall();
    }
  }

  Future<void> _initRenderers() async {
    // await _localRenderer.initialize();
    // await _remoteRenderer.initialize();
    await _startLocalStream();
  }

  Future<void> _startLocalStream() async {
    // _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    // _localRenderer.srcObject = _localStream;
    setState(() {});
  }

  // Future<void> _joinCall() async {
  //   try {
  //     // --- Minimal WebRTC peer connection setup ---
  //     final Map<String, dynamic> config = {
  //       'iceServers': [
  //         {'urls': 'stun:stun.l.google.com:19302'},
  //       ],
  //     };
  //     _peerConnection = await createPeerConnection(config);
  //     if (_localStream != null) {
  //       _localStream!.getTracks().forEach((track) {
  //         _peerConnection!.addTrack(track, _localStream!);
  //       });
  //     }
  //     _peerConnection!.onTrack = (event) {
  //       if (event.streams.isNotEmpty) {
  //         _remoteRenderer.srcObject = event.streams[0];
  //       }
  //     };
  //     // --- Signaling (SDP/ICE) must be handled by your VideoCallService ---
  //     await VideoCallService.joinCall(widget.callId, widget.currentUserId);
  //     setState(() {
  //       _isCallConnected = true;
  //       _callStartTime = DateTime.now();
  //     });
  //   } catch (e) {
  //     print('Error joining call: $e');
  //     _endCall('Connection failed');
  //   }
  // }
  //
  // Future<void> _endCall([String? reason]) async {
  //   if (_isCallEnded) return;
  //   setState(() => _isCallEnded = true);
  //   try {
  //     // Release camera/mic resources
  //     await _releaseVideoResources();
  //     await VideoCallService.endCallStatic(widget.callId, widget.currentUserId);
  //   } catch (e) {
  //     print('Error ending call: $e');
  //   }
  //   if (mounted) {
  //     Navigator.of(context).pop();
  //   }
  // }

  // Future<void> _releaseVideoResources() async {
  //   try {
  //     await _localRenderer.dispose();
  //     await _remoteRenderer.dispose();
  //     await _localStream?.dispose();
  //     await _peerConnection?.close();
  //     _peerConnection = null;
  //   } catch (e) {
  //     print('Error releasing video resources: $e');
  //   }
  // }
  //
  // Future<void> _toggleMic() async {
  //   if (_localStream == null) return;
  //   final audioTrack = _localStream!.getAudioTracks().firstOrNull;
  //   if (audioTrack != null) {
  //     final enabled = audioTrack.enabled;
  //     audioTrack.enabled = !enabled;
  //     setState(() => _isMicOn = audioTrack.enabled);
  //   }
  // }
  //
  // Future<void> _toggleCamera() async {
  //   if (!widget.isVideoCall || _localStream == null) return;
  //   final videoTrack = _localStream!.getVideoTracks().firstOrNull;
  //   if (videoTrack != null) {
  //     final enabled = videoTrack.enabled;
  //     videoTrack.enabled = !enabled;
  //     setState(() => _isCameraOn = videoTrack.enabled);
  //   }
  // }
  //
  // String _getCallDuration() {
  //   if (_callStartTime == null) return '00:00';
  //
  //   final duration = DateTime.now().difference(_callStartTime!);
  //   final minutes = duration.inMinutes.toString().padLeft(2, '0');
  //   final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  //   return '$minutes:$seconds';
  // }
  //
  // Widget _buildVideoView() {
  //   final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  //   final backgroundColor = isDarkMode
  //       ? AppTheme.videoCallBackgroundDarkTheme
  //       : AppTheme.videoCallBackground;
  //
  //   return Container(
  //     width: double.infinity,
  //     height: double.infinity,
  //     color: backgroundColor,
  //     child: Stack(
  //       children: [
  //         // Remote user video (main view)
  //         if (widget.isVideoCall && _isCallConnected)
  //           Positioned.fill(
  //             child: RTCVideoView(
  //               _remoteRenderer,
  //               objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  //             ),
  //           )
  //         else
  //           Positioned.fill(
  //             child: Center(
  //               child: Column(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   CircleAvatar(
  //                     radius: 60,
  //                     backgroundColor: Theme.of(context).colorScheme.primary,
  //                     child: Text(
  //                       widget.otherUserName.isNotEmpty
  //                           ? widget.otherUserName[0].toUpperCase()
  //                           : '?',
  //                       style: const TextStyle(
  //                         fontSize: 36,
  //                         fontWeight: FontWeight.bold,
  //                         color: AppTheme.videoCallText,
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 24),
  //                   Text(
  //                     widget.otherUserName,
  //                     style: const TextStyle(
  //                       fontSize: 28,
  //                       fontWeight: FontWeight.bold,
  //                       color: AppTheme.videoCallText,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 8),
  //                   Text(
  //                     _isCallConnected
  //                         ? _getCallDuration()
  //                         : widget.isIncoming
  //                         ? 'Incoming ${widget.isVideoCall ? 'video' : 'audio'} call'
  //                         : 'Calling...',
  //                     style: const TextStyle(
  //                       fontSize: 18,
  //                       color: AppTheme.videoCallTextSecondary,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ),
  //
  //         // Local user video (small preview in corner)
  //         if (widget.isVideoCall && _isCameraOn && _isCallConnected)
  //           Positioned(
  //             top: 50,
  //             right: 20,
  //             child: Container(
  //               width: 120,
  //               height: 160,
  //               decoration: BoxDecoration(
  //                 color: AppTheme.videoCallBackground.withOpacity(0.45),
  //                 borderRadius: BorderRadius.circular(12),
  //                 border: Border.all(color: AppTheme.videoCallText, width: 2),
  //               ),
  //               child: ClipRRect(
  //                 borderRadius: BorderRadius.circular(10),
  //                 child: RTCVideoView(
  //                   _localRenderer,
  //                   mirror: true,
  //                   objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  //                 ),
  //               ),
  //             ),
  //           ),
  //
  //         // Call status overlay
  //         if (!_isCallConnected && !widget.isIncoming)
  //           Container(
  //             width: double.infinity,
  //             height: double.infinity,
  //             color: Theme.of(context).brightness == Brightness.dark
  //                 ? AppTheme.videoCallBackgroundDarkTheme.withOpacity(0.8)
  //                 : AppTheme.videoCallBackground.withOpacity(0.5),
  //             child: const Center(
  //               child: Column(
  //                 mainAxisAlignment: MainAxisAlignment.center,
  //                 children: [
  //                   CircularProgressIndicator(color: AppTheme.videoCallText),
  //                   SizedBox(height: 16),
  //                   Text(
  //                     'Connecting...',
  //                     style: TextStyle(
  //                       color: AppTheme.videoCallText,
  //                       fontSize: 18,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }
  //
  // Widget _buildCallControls() {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
  //     child: Row(
  //       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  //       children: [
  //         // Microphone toggle
  //         FloatingActionButton(
  //           heroTag: 'mic',
  //           onPressed: _toggleMic,
  //           backgroundColor: _isMicOn
  //               ? AppTheme.videoCallText
  //               : (Theme.of(context).brightness == Brightness.dark
  //                     ? AppTheme.videoCallEndCallDarkTheme
  //                     : AppTheme.videoCallEndCall),
  //           child: Icon(
  //             _isMicOn ? Icons.mic : Icons.mic_off,
  //             color: _isMicOn
  //                 ? (Theme.of(context).brightness == Brightness.dark
  //                       ? AppTheme.videoCallBackgroundDarkTheme
  //                       : AppTheme.videoCallBackground)
  //                 : AppTheme.videoCallText,
  //           ),
  //         ),
  //
  //         // End call button
  //         FloatingActionButton(
  //           heroTag: 'endCall',
  //           onPressed: () => _endCall(),
  //           backgroundColor: Theme.of(context).brightness == Brightness.dark
  //               ? AppTheme.videoCallEndCallDarkTheme
  //               : AppTheme.videoCallEndCall,
  //           child: const Icon(Icons.call_end, color: AppTheme.videoCallText),
  //         ),
  //
  //         // Camera toggle (video calls only)
  //         if (widget.isVideoCall)
  //           FloatingActionButton(
  //             heroTag: 'camera',
  //             onPressed: _toggleCamera,
  //             backgroundColor: _isCameraOn
  //                 ? AppTheme.videoCallText
  //                 : (Theme.of(context).brightness == Brightness.dark
  //                       ? AppTheme.backgroundSecondaryDarkTheme
  //                       : Colors.grey[800]),
  //             child: Icon(
  //               _isCameraOn ? Icons.videocam : Icons.videocam_off,
  //               color: _isCameraOn
  //                   ? (Theme.of(context).brightness == Brightness.dark
  //                         ? AppTheme.videoCallBackgroundDarkTheme
  //                         : AppTheme.videoCallBackground)
  //                   : AppTheme.videoCallText,
  //             ),
  //           )
  //         else
  //           // Speaker toggle for audio calls
  //           FloatingActionButton(
  //             heroTag: 'speaker',
  //             onPressed: () {
  //               // Toggle speaker
  //             },
  //             backgroundColor: AppTheme.videoCallText,
  //             child: Icon(
  //               Icons.volume_up,
  //               color: Theme.of(context).brightness == Brightness.dark
  //                   ? AppTheme.videoCallBackgroundDarkTheme
  //                   : AppTheme.videoCallBackground,
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }
  //
  // Widget _buildIncomingCallControls() {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
  //     child: Row(
  //       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  //       children: [
  //         // Decline call
  //         FloatingActionButton(
  //           heroTag: 'decline',
  //           onPressed: () => _endCall('Call declined'),
  //           backgroundColor: Theme.of(context).brightness == Brightness.dark
  //               ? AppTheme.videoCallEndCallDarkTheme
  //               : AppTheme.videoCallEndCall,
  //           child: const Icon(Icons.call_end, color: AppTheme.videoCallText),
  //         ),
  //
  //         // Accept call
  //         FloatingActionButton(
  //           heroTag: 'accept',
  //           onPressed: _joinCall,
  //           backgroundColor: Theme.of(context).brightness == Brightness.dark
  //               ? AppTheme.successDarkTheme
  //               : AppTheme.success,
  //           child: const Icon(Icons.call, color: AppTheme.videoCallText),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  @override
  void dispose() {
    // _releaseVideoResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.videoCallBackgroundDarkTheme
          : AppTheme.videoCallBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Text("Plave holder")),
            // widget.isIncoming && !_isCallConnected
            //     ? _buildIncomingCallControls()
            //     : _buildCallControls(),
          ],
        ),
      ),
    );
  }
}
