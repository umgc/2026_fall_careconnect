import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _mobileChimeSdkUrl = String.fromEnvironment(
  'CHIME_SDK_URL',
  defaultValue:
      'https://sdk.amazonaws.com/js/amazon-chime-sdk/3.26.0/amazon-chime-sdk.min.js',
);

final Map<String, _MobileMeetingController> _activeMobileControllers =
    <String, _MobileMeetingController>{};

_MobileMeetingController? _resolveController(String? meetingId) {
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    return _activeMobileControllers[meetingId.trim()];
  }
  if (_activeMobileControllers.isEmpty) {
    return null;
  }
  return _activeMobileControllers.values.first;
}

Widget buildChimeMeetingEmbed({
  required String meetingId,
  required String attendeeId,
  required String joinToken,
  required Map<String, dynamic> mediaPlacement,
  String? mediaRegion,
  String? externalUserId,
  required bool videoEnabled,
  required bool audioEnabled,
  bool enableAutoSentimentCapture = false,
  int sentimentCaptureIntervalMs = 15000,
  VoidCallback? onEndCallRequested,
  void Function(Map<String, dynamic> transcriptSample)? onTranscriptSample,
  void Function(String status, String? detail)? onTranscriptStatus,
  void Function(double averageLevel, double speechRatio, double variability)? onVoiceMetricsSample,
  void Function(String imageBase64)? onVideoSample,
  void Function(String channel, bool muted)? onSentimentChannelState,
}) {
  final controller = _activeMobileControllers.putIfAbsent(
    meetingId,
    () => _MobileMeetingController(meetingId: meetingId),
  );

  return _ChimeMeetingEmbedMobile(
    controller: controller,
    meetingId: meetingId,
    attendeeId: attendeeId,
    joinToken: joinToken,
    mediaPlacement: mediaPlacement,
    mediaRegion: mediaRegion,
    externalUserId: externalUserId,
    videoEnabled: videoEnabled,
    audioEnabled: audioEnabled,
    enableAutoSentimentCapture: enableAutoSentimentCapture,
    sentimentCaptureIntervalMs: sentimentCaptureIntervalMs,
    onEndCallRequested: onEndCallRequested,
    onTranscriptSample: onTranscriptSample,
    onTranscriptStatus: onTranscriptStatus,
    onVoiceMetricsSample: onVoiceMetricsSample,
    onVideoSample: onVideoSample,
    onSentimentChannelState: onSentimentChannelState,
  );
}

Future<bool> requestChimeAudioToggle({
  required bool muted,
  String? meetingId,
}) async {
  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.postFlutterAction({'action': 'toggle-audio', 'muted': muted});
}

Future<bool> requestChimeVideoToggle({
  required bool muted,
  String? meetingId,
}) async {
  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.postFlutterAction({'action': 'toggle-video', 'muted': muted});
}

Future<bool> requestChimeCameraSwitch({String? meetingId}) async {
  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.postFlutterAction({'action': 'switch-camera'});
}

Future<bool> requestChimeSentimentChannelRestart({
  required String channel,
  String? meetingId,
}) async {
  final normalized = channel.trim().toLowerCase();
  if (normalized != 'text' && normalized != 'voice' && normalized != 'video') {
    return false;
  }

  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.postFlutterAction({
    'action': 'restart-sentiment-channel',
    'channel': normalized,
  });
}

class _ChimeMeetingEmbedMobile extends StatefulWidget {
  const _ChimeMeetingEmbedMobile({
    required this.controller,
    required this.meetingId,
    required this.attendeeId,
    required this.joinToken,
    required this.mediaPlacement,
    required this.mediaRegion,
    required this.externalUserId,
    required this.videoEnabled,
    required this.audioEnabled,
    required this.enableAutoSentimentCapture,
    required this.sentimentCaptureIntervalMs,
    required this.onEndCallRequested,
    required this.onTranscriptSample,
    required this.onTranscriptStatus,
    required this.onVoiceMetricsSample,
    required this.onVideoSample,
    required this.onSentimentChannelState,
  });

  final _MobileMeetingController controller;
  final String meetingId;
  final String attendeeId;
  final String joinToken;
  final Map<String, dynamic> mediaPlacement;
  final String? mediaRegion;
  final String? externalUserId;
  final bool videoEnabled;
  final bool audioEnabled;
  final bool enableAutoSentimentCapture;
  final int sentimentCaptureIntervalMs;
  final VoidCallback? onEndCallRequested;
  final void Function(Map<String, dynamic> transcriptSample)? onTranscriptSample;
  final void Function(String status, String? detail)? onTranscriptStatus;
  final void Function(double averageLevel, double speechRatio, double variability)?
  onVoiceMetricsSample;
  final void Function(String imageBase64)? onVideoSample;
  final void Function(String channel, bool muted)? onSentimentChannelState;

  @override
  State<_ChimeMeetingEmbedMobile> createState() => _ChimeMeetingEmbedMobileState();
}

class _ChimeMeetingEmbedMobileState extends State<_ChimeMeetingEmbedMobile> {
  WebViewController? _webViewController;
  String? _error;
  String _status = 'Setting up your call...';

        static const String _androidLocalSdkUrlPrimary =
          'file:///android_asset/flutter_assets/web/amazon-chime-sdk.min.js';
        static const String _androidLocalSdkUrlSecondary =
          'https://appassets.androidplatform.net/assets/flutter_assets/web/amazon-chime-sdk.min.js';

  @override
  void initState() {
    super.initState();

    if (!_supportsMobilePlatform) {
      _error = 'Real-time Chime media is supported on Android/iOS for mobile builds.';
      return;
    }

    final meetingConfig = {
      'meetingId': widget.meetingId,
      'attendeeId': widget.attendeeId,
      'joinToken': widget.joinToken,
      'mediaPlacement': widget.mediaPlacement,
      'mediaRegion': widget.mediaRegion ?? 'us-east-1',
      'externalUserId':
          widget.externalUserId ?? 'careconnect-${widget.attendeeId.substring(0, 8)}',
      'videoEnabled': widget.videoEnabled,
      'audioEnabled': widget.audioEnabled,
      'enableAutoSentimentCapture': widget.enableAutoSentimentCapture,
      'sentimentCaptureIntervalMs': widget.sentimentCaptureIntervalMs,
      'sdkUrl': _mobileChimeSdkUrl,
      'localSdkUrls': [
        _androidLocalSdkUrlPrimary,
        _androidLocalSdkUrlSecondary,
      ],
    };

    unawaited(_initializeWebView(meetingConfig));
  }

  Future<void> _initializeWebView(Map<String, dynamic> meetingConfig) async {
    await _ensureMediaPermissions();

    if (mounted) {
      setState(() {
        _status = 'Preparing secure connection...';
      });
    }

    if (!mounted) return;

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(
        'CareConnectChimeBridge',
        onMessageReceived: (msg) {
          _handleBridgeMessage(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _status = 'Opening video call...';
            });
          },
          onPageFinished: (_) {
            widget.controller.attach(controller);
            if (!mounted) return;
            setState(() {
              _status = 'Connecting to participant...';
            });
          },
          onWebResourceError: (error) {
            final isMainFrame = error.isForMainFrame;
            if (isMainFrame != true || !mounted) {
              return;
            }
            setState(() {
              _error = 'WebView load error: ${error.description}';
            });
          },
        ),
      )
      ..loadHtmlString(
        _buildMobileMeetingHtml(jsonEncode(meetingConfig)),
        baseUrl: 'https://localhost',
      );

    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setOnPlatformPermissionRequest((request) {
          request.grant();
        });
    }

    _webViewController = controller;
  }

  Future<void> _ensureMediaPermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      final statuses = await <Permission>[
        Permission.camera,
        Permission.microphone,
      ].request();

      final camOk = statuses[Permission.camera]?.isGranted ?? false;
      final micOk = statuses[Permission.microphone]?.isGranted ?? false;

      if (mounted && (!camOk || !micOk)) {
        setState(() {
            _status =
              'Please allow camera and microphone access to start the call';
        });
      }
    } catch (_) {
      // Continue initialization; WebView permission callbacks still run.
    }
  }

  bool get _supportsMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? _toUserFacingStatus(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) {
      return null;
    }

    // Hide low-level transport/device/debug noise from the user banner.
    if (message.startsWith('Trying SDK URL:') ||
        message.startsWith('Chime SDK loaded from:') ||
        message.startsWith('Audio input devices:') ||
        message.startsWith('Audio input started:') ||
        message.startsWith('audioVideo.start() invoked') ||
        message.startsWith('audioVideoDidStart') ||
        message.startsWith('Presence update:') ||
        message.startsWith('Local video tile bound') ||
        message.startsWith('Remote video tile bound') ||
        message.startsWith('Requested local video tile start') ||
        message.startsWith('Video play() interrupted for')) {
      return null;
    }

    if (message.startsWith('Loading Chime SDK')) {
      return 'Preparing secure call connection...';
    }
    if (message == 'Creating meeting session...') {
      return 'Joining call session...';
    }
    if (message == 'Preparing audio/video devices...') {
      return 'Checking camera and microphone...';
    }
    if (message == 'Starting Chime media session...') {
      return 'Starting audio and video...';
    }
    if (message == 'Failed to initialize call media') {
      return 'Unable to start video right now. Please rejoin the call.';
    }

    if (message == 'Participant joined (audio only)') {
      return 'Connected with participant (audio only)';
    }
    if (message == 'Connected with participant (audio only)') {
      return 'Connected with participant (audio only)';
    }
    if (message == 'In call lobby: waiting for participant video...') {
      return 'In call lobby: waiting for another participant to join...';
    }
    if (message == 'In call lobby: waiting for the other person to join...') {
      return 'In call lobby: waiting for another participant to join...';
    }
    if (message == 'Call ended') {
      return 'Disconnected';
    }
    if (message == 'Connected with participant') {
      return 'Connected with participant';
    }

    return message;
  }

  void _handleBridgeMessage(String raw) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      data = decoded;
    } catch (_) {
      return;
    }

    if (data['source'] != 'careconnect-chime') {
      return;
    }

    final action = (data['action'] ?? '').toString();
    final payload = data['payload'];

    if (action == 'end-call-request') {
      widget.onEndCallRequested?.call();
      return;
    }

    final level = (data['level'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString();
    if (message.isNotEmpty) {
      if (level == 'error') {
        debugPrint('[CareConnect][Chime][mobile][error] $message');
      } else if (level == 'warn' || level == 'warning') {
        debugPrint('[CareConnect][Chime][mobile][warn] $message');
      } else {
        debugPrint('[CareConnect][Chime][mobile][info] $message');
      }
      _emitTranscriptStatusFromLog(level, message);
    }
    final userFacingStatus = _toUserFacingStatus(message);
    if (userFacingStatus != null && mounted) {
      setState(() {
        _status = userFacingStatus;
      });
    }

    if (action == 'sentiment-transcript') {
      Map<String, dynamic> payloadMap = const {};
      if (payload is Map<String, dynamic>) {
        payloadMap = payload;
      } else if (payload is Map) {
        payloadMap = payload.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else if (payload is String && payload.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            payloadMap = decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            );
          }
        } catch (_) {}
      }
      final transcript = (payloadMap['text'] ?? '').toString().trim();
      if (transcript.isNotEmpty) {
        debugPrint(
          '[CareConnect][Transcript][mobile] received len=${transcript.length}',
        );
        final source = (payloadMap['source'] ?? '').toString().toLowerCase();
        if (source.contains('speech')) {
          widget.onTranscriptStatus?.call('FALLBACK', 'Speech recognition');
        } else {
          widget.onTranscriptStatus?.call('CONNECTED', 'Live transcript');
        }
        if (!payloadMap.containsKey('speakerLabel')) {
          payloadMap['speakerLabel'] = 'PARTICIPANT';
        }
        widget.onTranscriptSample?.call(Map<String, dynamic>.from(payloadMap));
      }
      return;
    }

    if (action == 'sentiment-voice-metrics' && payload is Map<String, dynamic>) {
      final averageLevel = double.tryParse((payload['averageLevel'] ?? '').toString());
      final speechRatio = double.tryParse((payload['speechRatio'] ?? '').toString());
      final variability = double.tryParse((payload['variability'] ?? '').toString());
      if (averageLevel != null && speechRatio != null && variability != null) {
        widget.onVoiceMetricsSample?.call(averageLevel, speechRatio, variability);
      }
      return;
    }

    if (action == 'sentiment-video-sample' && payload is Map<String, dynamic>) {
      final imageBase64 = (payload['imageBase64'] ?? '').toString().trim();
      if (imageBase64.isNotEmpty) {
        widget.onVideoSample?.call(imageBase64);
      }
      return;
    }

    if (action == 'sentiment-channel-state' && payload is Map<String, dynamic>) {
      final channel = (payload['channel'] ?? '').toString().trim().toLowerCase();
      final muted = payload['muted'] == true;
      if (channel == 'text' || channel == 'voice' || channel == 'video') {
        widget.onSentimentChannelState?.call(channel, muted);
      }
      return;
    }

    if (level == 'error' && mounted) {
      setState(() {
        _error = message.isEmpty ? 'Unknown Chime media error' : message;
      });
    }
  }

  @override
  void dispose() {
    unawaited(
      widget.controller.postFlutterAction({
        'action': 'teardown',
        'reason': 'flutter-widget-dispose',
      }),
    );
    _activeMobileControllers.remove(widget.meetingId);
    widget.controller.detach();
    super.dispose();
  }

  void _emitTranscriptStatusFromLog(String level, String message) {
    if (message.isEmpty || widget.onTranscriptStatus == null) {
      return;
    }
    final lower = message.toLowerCase();
    if (lower.contains('chime transcript capture subscribed')) {
      widget.onTranscriptStatus!.call('AWAITING', 'Subscribed, waiting for transcript');
      return;
    }
    if (lower.contains('speech transcription capture started')) {
      widget.onTranscriptStatus!.call('FALLBACK', 'Speech recognition');
      return;
    }
    if (lower.contains('speechrecognition api unavailable') ||
        lower.contains('speech recognition error: not-allowed') ||
        lower.contains('speech recognition error: service-not-allowed')) {
      widget.onTranscriptStatus!.call('BLOCKED', 'Microphone or browser blocked');
      return;
    }
    if ((level == 'warn' || level == 'warning') &&
        lower.contains('no usable transcript text captured')) {
      widget.onTranscriptStatus!.call('FALLBACK', 'No live transcript text');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _webViewController;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }

    return Stack(
      children: [
        WebViewWidget(controller: controller),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _status,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileMeetingController {
  _MobileMeetingController({required this.meetingId});

  final String meetingId;
  WebViewController? _controller;

  void attach(WebViewController controller) {
    _controller = controller;
  }

  void detach() {
    _controller = null;
  }

  Future<bool> postFlutterAction(Map<String, dynamic> actionData) async {
    final controller = _controller;
    if (controller == null) {
      return false;
    }

    final eventData = <String, dynamic>{
      'source': 'careconnect-flutter',
      ...actionData,
      'meetingId': meetingId,
    };

    final payload = jsonEncode(eventData);
    try {
      await controller.runJavaScript(
        'window.dispatchEvent(new MessageEvent("message", { data: $payload }));',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

String _buildMobileMeetingHtml(String configJson) {
  return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <style>
      html, body { margin:0; padding:0; width:100%; height:100%; background:#000; overflow:hidden; }
      #stage { position:relative; width:100%; height:100%; background:#000; }
      #videoGridScroll {
        position:absolute; top:0; left:0; right:0; bottom:0;
        overflow-y:auto; overflow-x:hidden; background:#000;
      }
      #videoGrid {
        display:grid; width:100%; height:100%; min-height:100%; background:#000; gap:2px;
        place-items:stretch;
      }
      #videoGrid.layout-single {
        grid-template-columns:1fr; grid-template-rows:1fr;
      }
      #videoGrid.layout-grid {
        height:100%;
        grid-auto-rows:1fr;
      }
      #videoGrid.layout-grid.layout-scroll {
        height:auto;
        min-height:100%;
        grid-auto-rows:minmax(160px, 1fr);
        align-content:start;
      }
      .remote-video { width:100%; height:100%; object-fit:contain; background:#111; min-height:0; }
      #localVideo {
        position:absolute; right:14px; top:14px; width:18%; max-width:110px;
        aspect-ratio:9/16; object-fit:cover; border-radius:10px;
        border:2px solid rgba(255,255,255,0.72); background:#111;
      }
    </style>
  </head>
  <body>
    <div id="stage">
      <div id="videoGridScroll">
        <div id="videoGrid"></div>
      </div>
      <video id="localVideo" autoplay playsinline muted></video>
      <audio id="remoteAudio" autoplay></audio>
    </div>
    <script>
      (async function () {
        if (typeof window.global === 'undefined') {
          window.global = window;
        }

        const config = $configJson;
        const statusEl = document.getElementById('status');
        const stage = document.getElementById('stage');
        const localVideo = document.getElementById('localVideo');
        const videoGrid = document.getElementById('videoGrid');
        const remoteAudio = document.getElementById('remoteAudio');

        let meetingSession = null;
        let audioVideo = null;
        let chimeSdkNamespace = null;
        let localVideoTileId = null;
        const remoteTiles = new Map();
        let remoteParticipantPresent = false;
        let availableVideoInputs = [];
        let currentVideoInputDeviceId = null;
        let isAudioMuted = !config.audioEnabled;
        let isVideoMuted = !config.videoEnabled;
        let mediaStarted = false;
        let startupWatchdog = null;
        const shouldAutoSentimentCapture = !!config.enableAutoSentimentCapture;
        const sentimentCaptureIntervalMs =
          Number(config.sentimentCaptureIntervalMs) > 0
            ? Math.max(3000, Number(config.sentimentCaptureIntervalMs))
            : 15000;
        let chimeTranscriptHandler = null;
        let chimeTranscriptDataMessageHandler = null;
        let chimeTranscriptDataTopics = [];
        let chimeTranscriptDataWatchdogTimer = null;
        let chimeTranscriptControllerHandler = null;
        let chimeTranscriptActive = false;
        let speechRecognizer = null;
        let speechRestartTimer = null;
        let speechResultWatchdogTimer = null;
        let speechPermissionDenied = false;
        let lastSpeechRecognitionStartAt = 0;
        let voiceMetricsTimer = null;
        let voiceCaptureWatchdogTimer = null;
        let volumeIndicatorHandler = null;
        let autoSentimentCaptureStarted = false;
        let transcriptDataMessageProbeCount = 0;
        let transcriptControllerProbeCount = 0;
        let transcriptTextSampleCount = 0;
        let voiceFrames = 0;
        let voiceSpeechFrames = 0;
        let voiceSum = 0;
        let voiceSumSquares = 0;
        let lastVoiceFrameAt = 0;
        let lastVoiceEmitAt = 0;
        let voiceFallbackLogAt = 0;
        let auxVoiceStream = null;
        let auxVoiceContext = null;
        let auxVoiceSource = null;
        let auxVoiceAnalyser = null;
        let auxVoiceData = null;
        let sentimentVideoTimer = null;
        let sentimentVideoCanvas = null;
        let sentimentVideoCtx = null;
        let lastTranscriptSignature = '';
        let lastTranscriptAt = 0;
        let transcriptNoTextWatchdogTimer = null;
        let flutterMessageHandler = null;
        let meetingObserver = null;
        let isShuttingDown = false;

        function setStatus(msg) {
          if (statusEl) {
            statusEl.textContent = msg;
          }
          report('info', msg);
        }

        function effectiveEmptySlots(count, cols) {
          const remainder = count % cols;
          if (remainder === 0) return 0;
          if (remainder === 1) return 0;
          return cols - remainder;
        }

        function computeGridCols(count) {
          const width = stage ? (stage.clientWidth || window.innerWidth || 360) : 360;
          if (count <= 1) return 1;
          if (count === 2) return width >= 600 ? 2 : 1;
          if (count === 3) return width >= 600 ? 2 : 1;
          if (count === 4) return width >= 600 ? 2 : 2;

          const maxCols = width >= 600 ? Math.min(count, 4) : Math.min(count, 2);
          let bestCols = 1;
          let bestScore = Infinity;
          for (let cols = 1; cols <= maxCols; cols++) {
            const rows = Math.ceil(count / cols);
            const empty = effectiveEmptySlots(count, cols);
            const stackPenalty = width >= 600 && cols === 1 ? 30 : 0;
            const score = empty * 100 + rows * 2 + stackPenalty - (width >= 600 ? cols * 3 : 0);
            if (score < bestScore) {
              bestScore = score;
              bestCols = cols;
            }
          }
          return bestCols;
        }

        function applyGridOrphans(cols) {
          const items = Array.from(videoGrid.querySelectorAll('.remote-video'));
          items.forEach((el) => { el.style.gridColumn = ''; });
          const count = items.length;
          if (count <= cols) return;
          const remainder = count % cols;
          if (remainder === 1) {
            items[count - 1].style.gridColumn = '1 / -1';
          }
        }

        function updateVideoGridLayout() {
          const count = remoteTiles.size;
          videoGrid.style.gridTemplateColumns = '';
          videoGrid.style.gridTemplateRows = '';
          videoGrid.style.gridAutoRows = '';
          if (count === 0) {
            videoGrid.className = '';
            return;
          }
          if (count === 1) {
            videoGrid.className = 'layout-single';
            return;
          }
          const cols = computeGridCols(count);
          const scrollable = count > 6;
          videoGrid.className = scrollable ? 'layout-grid layout-scroll' : 'layout-grid';
          videoGrid.style.gridTemplateColumns = 'repeat(' + cols + ', 1fr)';
          applyGridOrphans(cols);
        }

        if (stage && typeof ResizeObserver !== 'undefined') {
          new ResizeObserver(() => updateVideoGridLayout()).observe(stage);
        } else {
          window.addEventListener('resize', updateVideoGridLayout);
        }

        function updateParticipantStatus() {
          if (remoteTiles.size > 0) {
            setStatus(
              remoteTiles.size === 1
                ? 'Connected with participant'
                : 'Connected with ' + remoteTiles.size + ' participants',
            );
            return;
          }

          if (remoteParticipantPresent) {
            setStatus('Connected with participant (audio only)');
            return;
          }

          setStatus('In call lobby: waiting for another participant to join...');
        }

        function emitBridge(data) {
          try {
            CareConnectChimeBridge.postMessage(JSON.stringify(data));
          } catch (_) {}
        }

        function report(level, message) {
          emitBridge({ source: 'careconnect-chime', level: level, message: message });
        }

        function resolveSdkFingerprint(sdk) {
          try {
            if (!sdk) {
              return 'missing-sdk';
            }

            const candidates = [];
            try {
              if (sdk.Versioning && sdk.Versioning.sdkVersion) {
                candidates.push('Versioning.sdkVersion=' + String(sdk.Versioning.sdkVersion));
              }
            } catch (_) {}
            try {
              if (sdk.version) {
                candidates.push('version=' + String(sdk.version));
              }
            } catch (_) {}
            try {
              if (sdk.sdkVersion) {
                candidates.push('sdkVersion=' + String(sdk.sdkVersion));
              }
            } catch (_) {}

            const keyCount = (() => {
              try {
                return Object.keys(sdk).length;
              } catch (_) {
                return -1;
              }
            })();

            candidates.push(
              'keys=' + String(keyCount) +
                ',hasDefaultMeetingSession=' + String(typeof sdk.DefaultMeetingSession === 'function') +
                ',hasTranscriptEventConverter=' + String(!!sdk.TranscriptEventConverter),
            );

            return candidates.join('|');
          } catch (_) {
            return 'fingerprint-error';
          }
        }

        report(
          'info',
          'Auto sentiment capture ' +
            (shouldAutoSentimentCapture ? 'enabled' : 'disabled') +
            ' (interval=' + String(sentimentCaptureIntervalMs) + 'ms)',
        );

        function emitAction(action, payload) {
          emitBridge({
            source: 'careconnect-chime',
            action: action,
            payload: payload || {},
            meetingId: config.meetingId,
          });
        }

        function emitSentimentChannelState(channel, muted, reason) {
          emitAction('sentiment-channel-state', {
            channel: channel,
            muted: !!muted,
            reason: reason || 'mobile-auto-capture',
            capturedAt: new Date().toISOString(),
          });
        }

        function extractTranscriptTextFromChimeEvent(transcriptEvent) {
          try {
            const results = transcriptEvent && transcriptEvent.transcript && Array.isArray(transcriptEvent.transcript.results)
              ? transcriptEvent.transcript.results
              : (transcriptEvent && Array.isArray(transcriptEvent.results) ? transcriptEvent.results : null);

            if (!results) {
              return '';
            }

            const lines = [];
            for (const result of results) {
              if (!result || result.isPartial === true) {
                continue;
              }
              if (!result || !Array.isArray(result.alternatives) || result.alternatives.length === 0) {
                continue;
              }

              const firstAlternative = result.alternatives[0];
              if (!firstAlternative) {
                continue;
              }

              if (typeof firstAlternative.transcript === 'string') {
                const direct = firstAlternative.transcript.trim();
                if (direct.length > 0) {
                  lines.push(direct);
                  continue;
                }
              }

              if (Array.isArray(firstAlternative.items)) {
                const text = firstAlternative.items
                  .map((item) => (item && item.content ? String(item.content) : ''))
                  .join(' ')
                  .replace(/\\s+/g, ' ')
                  .trim();
                if (text.length > 0) {
                  lines.push(text);
                }
              }
            }

            return lines.join(' ').trim();
          } catch (_) {
            return '';
          }
        }

        function emitTranscriptSample(rawSample, source) {
          const sample = rawSample && typeof rawSample === 'object'
            ? rawSample
            : { text: rawSample };
          const text = String(sample.text || '').trim();
          if (text.length < 3) {
            return;
          }

          const signature = text.toLowerCase().replace(/\\s+/g, ' ').trim();
          const now = Date.now();
          if (signature === lastTranscriptSignature && (now - lastTranscriptAt) < 12000) {
            return;
          }

          lastTranscriptSignature = signature;
          lastTranscriptAt = now;
          transcriptTextSampleCount += 1;
          report('info', 'Transcript sample emitted via ' + String(source || 'unknown'));
          emitAction('sentiment-transcript', {
            text: text,
            speakerLabel: (sample.speakerLabel || 'PARTICIPANT'),
            startMs: sample.startMs ?? null,
            endMs: sample.endMs ?? null,
            source: source || 'chime-transcript',
            capturedAt: new Date().toISOString(),
          });
        }

        function stopChimeTranscriptCapture() {
          if (!audioVideo) {
            chimeTranscriptActive = false;
            return;
          }

          try {
            if (chimeTranscriptHandler && typeof audioVideo.realtimeUnsubscribeFromTranscriptEvent === 'function') {
              audioVideo.realtimeUnsubscribeFromTranscriptEvent(chimeTranscriptHandler);
            }
          } catch (_) {}

          try {
            if (
              chimeTranscriptControllerHandler &&
              audioVideo.transcriptionController &&
              typeof audioVideo.transcriptionController.unsubscribeFromTranscriptEvent === 'function'
            ) {
              audioVideo.transcriptionController.unsubscribeFromTranscriptEvent(
                chimeTranscriptControllerHandler,
              );
            }
          } catch (_) {}

          try {
            if (
              chimeTranscriptDataMessageHandler &&
              typeof audioVideo.realtimeUnsubscribeFromReceiveDataMessage === 'function' &&
              Array.isArray(chimeTranscriptDataTopics)
            ) {
              for (const topic of chimeTranscriptDataTopics) {
                try {
                  audioVideo.realtimeUnsubscribeFromReceiveDataMessage(topic, chimeTranscriptDataMessageHandler);
                } catch (_) {}
              }
            }
          } catch (_) {}

          if (chimeTranscriptDataWatchdogTimer) {
            clearTimeout(chimeTranscriptDataWatchdogTimer);
            chimeTranscriptDataWatchdogTimer = null;
          }

          if (transcriptNoTextWatchdogTimer) {
            clearTimeout(transcriptNoTextWatchdogTimer);
            transcriptNoTextWatchdogTimer = null;
          }

          chimeTranscriptHandler = null;
          chimeTranscriptControllerHandler = null;
          chimeTranscriptDataMessageHandler = null;
          chimeTranscriptDataTopics = [];
          chimeTranscriptActive = false;
        }

        function summarizeTranscriptEvent(transcriptEvent) {
          try {
            const ctorName =
              transcriptEvent && transcriptEvent.constructor && transcriptEvent.constructor.name
                ? String(transcriptEvent.constructor.name)
                : typeof transcriptEvent;
            const directResults = transcriptEvent && Array.isArray(transcriptEvent.results)
              ? transcriptEvent.results.length
              : 0;
            const nestedResults =
              transcriptEvent &&
              transcriptEvent.transcript &&
              Array.isArray(transcriptEvent.transcript.results)
                ? transcriptEvent.transcript.results.length
                : 0;
            const status =
              transcriptEvent &&
              (transcriptEvent.status || transcriptEvent.type || transcriptEvent.eventType)
                ? String(transcriptEvent.status || transcriptEvent.type || transcriptEvent.eventType)
                : '';
            return 'ctor=' + ctorName + ' directResults=' + String(directResults) +
              ' nestedResults=' + String(nestedResults) +
              (status ? ' status=' + status : '');
          } catch (_) {
            return 'uninspectable';
          }
        }

        function extractTranscriptTextFromDataMessage(dataMessage) {
          try {
            if (
              chimeSdkNamespace &&
              chimeSdkNamespace.TranscriptEventConverter &&
              typeof chimeSdkNamespace.TranscriptEventConverter.from === 'function'
            ) {
              try {
                const transcriptEvents = chimeSdkNamespace.TranscriptEventConverter.from(dataMessage) || [];
                if (Array.isArray(transcriptEvents) && transcriptEvents.length > 0) {
                  const texts = [];
                  for (const eventItem of transcriptEvents) {
                    const eventText = extractTranscriptTextFromChimeEvent(eventItem);
                    if (eventText.length > 0) {
                      texts.push(eventText);
                    }
                  }
                  if (texts.length > 0) {
                    return texts.join(' ').trim();
                  }
                }
              } catch (_) {}
            }

            let raw = '';
            if (dataMessage && typeof dataMessage.text === 'function') {
              raw = String(dataMessage.text() || '');
            } else if (dataMessage && typeof dataMessage.data === 'string') {
              raw = dataMessage.data;
            } else if (
              dataMessage &&
              dataMessage.data &&
              typeof dataMessage.data.byteLength === 'number' &&
              typeof TextDecoder !== 'undefined'
            ) {
              raw = new TextDecoder('utf-8').decode(dataMessage.data);
            }

            const trimmed = String(raw || '').trim();
            if (!trimmed) {
              return '';
            }

            try {
              const parsed = JSON.parse(trimmed);
              const fromEvent = extractTranscriptTextFromChimeEvent(parsed);
              if (fromEvent.length > 0) {
                return fromEvent;
              }
              if (typeof parsed.transcript === 'string' && parsed.transcript.trim().length > 0) {
                return parsed.transcript.trim();
              }
              if (typeof parsed.text === 'string' && parsed.text.trim().length > 0) {
                return parsed.text.trim();
              }
            } catch (_) {}

            return trimmed;
          } catch (_) {
            return '';
          }
        }

        function stopSpeechRecognitionCapture() {
          if (speechRestartTimer) {
            clearTimeout(speechRestartTimer);
            speechRestartTimer = null;
          }

          if (speechResultWatchdogTimer) {
            clearInterval(speechResultWatchdogTimer);
            speechResultWatchdogTimer = null;
          }

          if (speechRecognizer) {
            try {
              speechRecognizer.onresult = null;
              speechRecognizer.onstart = null;
              speechRecognizer.onerror = null;
              speechRecognizer.onend = null;
              speechRecognizer.stop();
            } catch (_) {}
            speechRecognizer = null;
          }
        }

        function startSpeechRecognitionCapture() {
          if (!shouldAutoSentimentCapture) {
            return false;
          }
          if (speechPermissionDenied) {
            return false;
          }
          if (chimeTranscriptActive) {
            return true;
          }

          const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
          if (!SpeechRecognition) {
            report('warn', 'SpeechRecognition API unavailable; transcript sentiment auto-capture disabled.');
            return false;
          }

          stopSpeechRecognitionCapture();
          speechRecognizer = new SpeechRecognition();
          speechRecognizer.continuous = true;
          speechRecognizer.interimResults = true;
          speechRecognizer.maxAlternatives = 1;
          speechRecognizer.lang = config.speechLocale || navigator.language || 'en-US';

          speechRecognizer.onstart = () => {
            lastSpeechRecognitionStartAt = Date.now();
            report('info', 'Speech recognition active');
          };

          speechRecognizer.onresult = (event) => {
            let transcript = '';
            for (let i = event.resultIndex; i < event.results.length; i += 1) {
              const result = event.results[i];
              if (result && result[0] && result[0].transcript) {
                transcript += ' ' + result[0].transcript;
              }
            }
            if (transcript.trim()) {
              const likelyFinal =
                event.results && event.results.length > 0
                  ? !!event.results[event.results.length - 1].isFinal
                  : false;
              report(
                'info',
                'Speech transcript result len=' + transcript.trim().length + ' final=' + String(likelyFinal),
              );
              emitTranscriptSample(
                transcript.trim(),
                likelyFinal ? 'speech-recognition-final' : 'speech-recognition-interim',
              );
            }
          };

          speechRecognizer.onerror = (event) => {
            const errorCode = String(event && event.error ? event.error : 'unknown');
            report('warn', 'Speech recognition error: ' + errorCode);
            if (errorCode === 'not-allowed' || errorCode === 'service-not-allowed') {
              speechPermissionDenied = true;
              stopSpeechRecognitionCapture();
            }
          };

          speechRecognizer.onend = () => {
            if (!shouldAutoSentimentCapture) {
              return;
            }
            if (speechRestartTimer) {
              clearTimeout(speechRestartTimer);
            }
            speechRestartTimer = setTimeout(() => {
              try {
                if (speechRecognizer) {
                  lastSpeechRecognitionStartAt = Date.now();
                  speechRecognizer.start();
                }
              } catch (_) {}
            }, 1200);
          };

          try {
            speechRecognizer.start();
            lastSpeechRecognitionStartAt = Date.now();
            emitSentimentChannelState('text', false, 'capture-started-speech-recognition');
            report('info', 'Speech transcription capture started');

            if (speechResultWatchdogTimer) {
              clearInterval(speechResultWatchdogTimer);
            }
            speechResultWatchdogTimer = setInterval(() => {
              if (!speechRecognizer || !shouldAutoSentimentCapture) {
                return;
              }

              const now = Date.now();
              const msSinceTranscript = now - lastTranscriptAt;
              const msSinceStart = now - lastSpeechRecognitionStartAt;
              if (lastTranscriptAt === 0 && msSinceStart < 15000) {
                return;
              }
              if (lastTranscriptAt > 0 && msSinceTranscript < 20000) {
                return;
              }

              report('warn', 'No transcript result received recently; restarting speech recognition');
              try {
                speechRecognizer.stop();
              } catch (_) {}
              try {
                lastSpeechRecognitionStartAt = Date.now();
                speechRecognizer.start();
              } catch (_) {}
            }, 8000);

            return true;
          } catch (speechStartErr) {
            report('warn', 'Unable to start speech recognition: ' + String(speechStartErr));
            return false;
          }
        }

        function startChimeTranscriptCapture() {
          if (!shouldAutoSentimentCapture) {
            return false;
          }
          if (!audioVideo) {
            report('warn', 'Transcript API unavailable on this mobile runtime');
            return false;
          }

          stopChimeTranscriptCapture();
          transcriptDataMessageProbeCount = 0;
          transcriptControllerProbeCount = 0;
          transcriptTextSampleCount = 0;
          chimeTranscriptHandler = (transcriptEvent) => {
            const text = extractTranscriptTextFromChimeEvent(transcriptEvent);
            if (text.length > 0) {
              emitTranscriptSample(text, 'chime-transcript');
            }
          };

          try {
            stopSpeechRecognitionCapture();
            let subscribedByAnyPath = false;

            if (typeof audioVideo.realtimeSubscribeToTranscriptEvent === 'function') {
              audioVideo.realtimeSubscribeToTranscriptEvent(chimeTranscriptHandler);
              chimeTranscriptActive = true;
              subscribedByAnyPath = true;
              emitSentimentChannelState('text', false, 'capture-started');
              report('info', 'Chime transcript capture subscribed via realtime transcript event');
            }

            if (
              audioVideo.transcriptionController &&
              typeof audioVideo.transcriptionController.subscribeToTranscriptEvent === 'function'
            ) {
              chimeTranscriptControllerHandler = (transcriptEvent) => {
                if (transcriptControllerProbeCount < 5) {
                  transcriptControllerProbeCount += 1;
                  report(
                    'info',
                    'Transcript controller event sample=' + String(transcriptControllerProbeCount) +
                      ' ' + summarizeTranscriptEvent(transcriptEvent),
                  );
                }

                const text = extractTranscriptTextFromChimeEvent(transcriptEvent);
                if (text.length > 0) {
                  emitTranscriptSample(text, 'chime-transcription-controller');
                }
              };

              audioVideo.transcriptionController.subscribeToTranscriptEvent(
                chimeTranscriptControllerHandler,
              );
              chimeTranscriptActive = true;
              subscribedByAnyPath = true;
              emitSentimentChannelState('text', false, 'capture-started-controller');
              report('info', 'Chime transcript capture subscribed via transcriptionController');
            }

            if (typeof audioVideo.realtimeSubscribeToReceiveDataMessage === 'function') {
              const topics = [
                'aws:chime:transcription',
                'transcription',
                'transcript',
                'Transcript',
                'meeting-transcript',
                'meeting-transcription',
                'aws/meeting-transcript',
                'aws/meeting-transcription',
                'aws/chime/transcription',
                'amazon-chime-transcription',
                'aws/amazon-chime-sdk/transcription',
                'aws/amazon-chime-sdk/caption',
              ];

              chimeTranscriptDataMessageHandler = (dataMessage) => {
                const text = extractTranscriptTextFromDataMessage(dataMessage);
                if (transcriptDataMessageProbeCount < 5) {
                  transcriptDataMessageProbeCount += 1;
                  let topic = '';
                  try {
                    topic = String(
                      dataMessage && dataMessage.topic !== undefined
                        ? dataMessage.topic
                        : (dataMessage && typeof dataMessage.topic === 'function'
                            ? dataMessage.topic()
                            : ''),
                    );
                  } catch (_) {}
                  report(
                    'info',
                    'Transcript data message received sample=' +
                      transcriptDataMessageProbeCount +
                      ' topic=' +
                      topic +
                      ' parsedLen=' +
                      String(text.length),
                  );
                }
                if (text.length > 0) {
                  emitTranscriptSample(text, 'chime-data-message');
                }
              };

              for (const topic of topics) {
                try {
                  audioVideo.realtimeSubscribeToReceiveDataMessage(topic, chimeTranscriptDataMessageHandler);
                  chimeTranscriptDataTopics.push(topic);
                } catch (_) {}
              }

              if (chimeTranscriptDataTopics.length > 0) {
                chimeTranscriptActive = true;
                subscribedByAnyPath = true;
                emitSentimentChannelState('text', false, 'capture-started-data-message');
                report(
                  'info',
                  'Chime transcript capture subscribed via data messages topics=' +
                    chimeTranscriptDataTopics.join(','),
                );

                if (chimeTranscriptDataWatchdogTimer) {
                  clearTimeout(chimeTranscriptDataWatchdogTimer);
                }
                chimeTranscriptDataWatchdogTimer = setTimeout(() => {
                  if (!chimeTranscriptActive || !shouldAutoSentimentCapture) {
                    return;
                  }
                  if (transcriptDataMessageProbeCount === 0) {
                    report(
                      'warn',
                      'No transcript data messages received after subscribe; verify Chime StartMeetingTranscription and IAM permissions',
                    );
                  }
                }, 25000);

              }
            }

            if (subscribedByAnyPath) {
              if (transcriptNoTextWatchdogTimer) {
                clearTimeout(transcriptNoTextWatchdogTimer);
              }
              transcriptNoTextWatchdogTimer = setTimeout(() => {
                if (!chimeTranscriptActive || !shouldAutoSentimentCapture) {
                  return;
                }
                if (transcriptTextSampleCount === 0) {
                  report(
                    'warn',
                    'No usable transcript text captured after subscribe; verify StartMeetingTranscription state and IAM Transcribe permissions',
                  );
                }
              }, 30000);
              return true;
            }

            report('warn', 'Transcript API unavailable on this mobile runtime');
            return false;
          } catch (transcriptErr) {
            report('warn', 'Chime transcript subscribe failed: ' + String(transcriptErr));
            chimeTranscriptHandler = null;
            chimeTranscriptDataMessageHandler = null;
            chimeTranscriptDataTopics = [];
            chimeTranscriptActive = false;
            return false;
          }
        }

        function resetVoiceMetricBuffers() {
          voiceFrames = 0;
          voiceSpeechFrames = 0;
          voiceSum = 0;
          voiceSumSquares = 0;
        }

        function stopAuxVoiceFallbackCapture() {
          if (auxVoiceSource) {
            try {
              auxVoiceSource.disconnect();
            } catch (_) {}
            auxVoiceSource = null;
          }

          if (auxVoiceAnalyser) {
            try {
              auxVoiceAnalyser.disconnect();
            } catch (_) {}
            auxVoiceAnalyser = null;
          }

          if (auxVoiceContext) {
            try {
              auxVoiceContext.close();
            } catch (_) {}
            auxVoiceContext = null;
          }

          if (auxVoiceStream) {
            try {
              auxVoiceStream.getTracks().forEach((track) => track.stop());
            } catch (_) {}
            auxVoiceStream = null;
          }

          auxVoiceData = null;
        }

        async function startAuxVoiceFallbackCapture() {
          if (auxVoiceAnalyser || !config.audioEnabled || isAudioMuted) {
            return;
          }

          try {
            const stream = await navigator.mediaDevices.getUserMedia({
              audio: {
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
              },
              video: false,
            });

            const AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (!AudioCtx) {
              stopAuxVoiceFallbackCapture();
              return;
            }

            const context = new AudioCtx();
            const source = context.createMediaStreamSource(stream);
            const analyser = context.createAnalyser();
            analyser.fftSize = 512;
            analyser.smoothingTimeConstant = 0.7;
            const data = new Uint8Array(analyser.fftSize);

            source.connect(analyser);

            auxVoiceStream = stream;
            auxVoiceContext = context;
            auxVoiceSource = source;
            auxVoiceAnalyser = analyser;
            auxVoiceData = data;
            report('info', 'Aux voice fallback capture ready');
          } catch (err) {
            stopAuxVoiceFallbackCapture();
            report('warn', 'Aux voice fallback unavailable: ' + String(err));
          }
        }

        function readAuxVoiceSample() {
          if (!auxVoiceAnalyser || !auxVoiceData) {
            return null;
          }

          try {
            auxVoiceAnalyser.getByteTimeDomainData(auxVoiceData);
            let sum = 0;
            for (let i = 0; i < auxVoiceData.length; i += 1) {
              const centered = (auxVoiceData[i] - 128) / 128;
              sum += centered * centered;
            }

            const rms = Math.sqrt(sum / auxVoiceData.length);
            const normalized = Math.max(0, Math.min(1, rms * 8.0));
            return {
              avg: normalized,
              speech: normalized > 0.08 ? 1 : 0,
              variability: Math.max(0, Math.min(1, normalized * 1.8)),
            };
          } catch (_) {
            return null;
          }
        }

        function stopChimeVoiceMetricsCapture() {
          if (voiceMetricsTimer) {
            clearInterval(voiceMetricsTimer);
            voiceMetricsTimer = null;
          }

          if (voiceCaptureWatchdogTimer) {
            clearInterval(voiceCaptureWatchdogTimer);
            voiceCaptureWatchdogTimer = null;
          }

          if (audioVideo && volumeIndicatorHandler &&
              typeof audioVideo.realtimeUnsubscribeFromVolumeIndicator === 'function') {
            try {
              audioVideo.realtimeUnsubscribeFromVolumeIndicator(config.attendeeId, volumeIndicatorHandler);
            } catch (_) {}
          }

          stopAuxVoiceFallbackCapture();
          volumeIndicatorHandler = null;
          resetVoiceMetricBuffers();
          emitSentimentChannelState('voice', true, 'capture-stopped');
        }

        function startChimeVoiceMetricsCapture() {
          if (!shouldAutoSentimentCapture || isAudioMuted || !config.audioEnabled) {
            return false;
          }
          if (!audioVideo || typeof audioVideo.realtimeSubscribeToVolumeIndicator !== 'function') {
            report('warn', 'Voice metrics API unavailable on this mobile runtime');
            return false;
          }

          stopChimeVoiceMetricsCapture();
          volumeIndicatorHandler = (attendeeId, volume) => {
            if (isAudioMuted) {
              return;
            }
            if (!attendeeId) {
              return;
            }
            const attendeeText = String(attendeeId);
            const localAttendeeId = String(config.attendeeId || '');
            // On some runtimes the attendee id may include modality suffixes.
            if (!(attendeeText === localAttendeeId || attendeeText.startsWith(localAttendeeId + '#'))) {
              return;
            }

            const value = Math.max(0, Math.min(1, Number(volume) || 0));
            lastVoiceFrameAt = Date.now();
            voiceFrames += 1;
            voiceSum += value;
            voiceSumSquares += value * value;
            if (value > 0.1) {
              voiceSpeechFrames += 1;
            }
          };

          try {
            audioVideo.realtimeSubscribeToVolumeIndicator(config.attendeeId, volumeIndicatorHandler);
          } catch (metricErr) {
            report('warn', 'Chime volume subscribe failed: ' + String(metricErr));
            volumeIndicatorHandler = null;
            return false;
          }

          try {
            startAuxVoiceFallbackCapture();
          } catch (_) {}

          const emitIntervalMs = Math.max(2500, Math.min(sentimentCaptureIntervalMs, 5000));
          voiceMetricsTimer = setInterval(() => {
            if (isAudioMuted) {
              resetVoiceMetricBuffers();
              return;
            }
            let avg = 0;
            let speakingRatio = 0;
            let variability = 0;
            let usedFallback = false;

            if (voiceFrames > 0) {
              avg = voiceSum / voiceFrames;
              const variance = Math.max(0, (voiceSumSquares / voiceFrames) - (avg * avg));
              const stdDev = Math.sqrt(variance);
              speakingRatio = voiceSpeechFrames / voiceFrames;
              variability = Math.min(1, stdDev * 3);
            } else {
              const auxSample = readAuxVoiceSample();
              if (auxSample) {
                avg = auxSample.avg;
                speakingRatio = auxSample.speech;
                variability = auxSample.variability;
                usedFallback = true;
              } else {
                // Some mobile WebView + Chime combinations intermittently stop
                // volume callbacks. Emit a low-activity fallback sample so the
                // backend stream does not go silent.
                usedFallback = true;
              }
            }

            emitAction('sentiment-voice-metrics', {
              averageLevel: Number(avg.toFixed(4)),
              speechRatio: Number(speakingRatio.toFixed(4)),
              variability: Number(variability.toFixed(4)),
              fallback: usedFallback,
              capturedAt: new Date().toISOString(),
            });
            lastVoiceEmitAt = Date.now();
            if (usedFallback) {
              const now = Date.now();
              if ((now - voiceFallbackLogAt) > 30000) {
                voiceFallbackLogAt = now;
                report('warn', 'Voice metrics emitted with fallback path');
              }
            }

            resetVoiceMetricBuffers();
          }, emitIntervalMs);

          if (voiceCaptureWatchdogTimer) {
            clearInterval(voiceCaptureWatchdogTimer);
          }
          voiceCaptureWatchdogTimer = setInterval(() => {
            if (isAudioMuted || !shouldAutoSentimentCapture || !audioVideo) {
              return;
            }

            const now = Date.now();
            const msSinceFrame = lastVoiceFrameAt > 0 ? now - lastVoiceFrameAt : Number.MAX_SAFE_INTEGER;
            const msSinceEmit = lastVoiceEmitAt > 0 ? now - lastVoiceEmitAt : Number.MAX_SAFE_INTEGER;
            if (msSinceFrame < 15000 || msSinceEmit < 20000) {
              return;
            }

            report('warn', 'No recent voice volume callbacks; resubscribing voice metrics capture');
            try {
              if (audioVideo && volumeIndicatorHandler &&
                  typeof audioVideo.realtimeUnsubscribeFromVolumeIndicator === 'function') {
                audioVideo.realtimeUnsubscribeFromVolumeIndicator(config.attendeeId, volumeIndicatorHandler);
              }
            } catch (_) {}

            try {
              if (audioVideo && volumeIndicatorHandler &&
                  typeof audioVideo.realtimeSubscribeToVolumeIndicator === 'function') {
                audioVideo.realtimeSubscribeToVolumeIndicator(config.attendeeId, volumeIndicatorHandler);
              }
            } catch (resubErr) {
              report('warn', 'Voice metrics resubscribe failed: ' + String(resubErr));
            }
          }, 8000);

          emitSentimentChannelState('voice', false, 'capture-started');
          report('info', 'Chime voice metrics capture started (' + emitIntervalMs + 'ms)');
          return true;
        }

        function stopVideoSentimentCapture() {
          if (sentimentVideoTimer) {
            clearInterval(sentimentVideoTimer);
            sentimentVideoTimer = null;
          }
          emitSentimentChannelState('video', true, 'capture-stopped');
        }

        function captureVideoSampleFrame() {
          try {
            if (isVideoMuted) {
              return;
            }

            if (!localVideo || localVideo.readyState < 2 || localVideo.videoWidth === 0 || localVideo.videoHeight === 0) {
              return;
            }

            const maxWidth = 640;
            const scale = Math.min(1, maxWidth / localVideo.videoWidth);
            const width = Math.max(1, Math.floor(localVideo.videoWidth * scale));
            const height = Math.max(1, Math.floor(localVideo.videoHeight * scale));

            if (!sentimentVideoCanvas) {
              sentimentVideoCanvas = document.createElement('canvas');
            }
            if (
              sentimentVideoCanvas.width !== width ||
              sentimentVideoCanvas.height !== height
            ) {
              sentimentVideoCanvas.width = width;
              sentimentVideoCanvas.height = height;
              sentimentVideoCtx = null;
            }

            if (!sentimentVideoCtx) {
              sentimentVideoCtx = sentimentVideoCanvas.getContext('2d', { alpha: false });
            }
            if (!sentimentVideoCtx) {
              return;
            }

            sentimentVideoCtx.drawImage(localVideo, 0, 0, width, height);
            const dataUrl = sentimentVideoCanvas.toDataURL('image/jpeg', 0.68);
            const commaIndex = dataUrl.indexOf(',');
            if (commaIndex <= 0) {
              return;
            }

            const imageBase64 = dataUrl.substring(commaIndex + 1);
            if (!imageBase64 || imageBase64.length < 1024) {
              return;
            }

            emitAction('sentiment-video-sample', {
              imageBase64: imageBase64,
              imageFormat: 'jpeg',
              capturedAt: new Date().toISOString(),
            });
          } catch (videoFrameErr) {
            report('warn', 'Unable to capture video sentiment frame: ' + String(videoFrameErr));
          }
        }

        function startVideoSentimentCapture() {
          if (!shouldAutoSentimentCapture || !config.videoEnabled || isVideoMuted) {
            return false;
          }

          if (sentimentVideoTimer) {
            clearInterval(sentimentVideoTimer);
          }

          captureVideoSampleFrame();
          sentimentVideoTimer = setInterval(() => {
            captureVideoSampleFrame();
          }, sentimentCaptureIntervalMs);
          emitSentimentChannelState('video', false, 'capture-started');
          report('info', 'Video sentiment capture started (' + sentimentCaptureIntervalMs + 'ms frames)');
          return true;
        }

        function restartSentimentChannelCapture(channel, reason) {
          const normalized = String(channel || '').trim().toLowerCase();
          if (normalized === 'voice') {
            return startChimeVoiceMetricsCapture();
          }
          if (normalized === 'video') {
            stopVideoSentimentCapture();
            return startVideoSentimentCapture();
          }
          if (normalized === 'text') {
            const chimeStarted = startChimeTranscriptCapture();
            if (!chimeStarted) {
              return startSpeechRecognitionCapture();
            }
            return true;
          }
          return false;
        }

        function stopAutoSentimentCapture() {
          stopChimeTranscriptCapture();
          stopSpeechRecognitionCapture();
          emitSentimentChannelState('text', true, 'capture-stopped');
          stopChimeVoiceMetricsCapture();
          stopVideoSentimentCapture();
          autoSentimentCaptureStarted = false;
        }

        function startAutoSentimentCapture() {
          if (!shouldAutoSentimentCapture) {
            return;
          }

          if (autoSentimentCaptureStarted) {
            report('info', 'Auto sentiment capture already active; skipping duplicate start');
            return;
          }

          autoSentimentCaptureStarted = true;

          const chimeTranscriptStarted = startChimeTranscriptCapture();
          if (!chimeTranscriptStarted) {
            startSpeechRecognitionCapture();
          }
          startChimeVoiceMetricsCapture();
          startVideoSentimentCapture();
        }

        function buildMeetingPayload() {
          const placement = config && config.mediaPlacement ? config.mediaPlacement : {};
          const pickPlacementValue = (...keys) => {
            for (const key of keys) {
              const value = placement ? placement[key] : null;
              if (value === null || value === undefined) {
                continue;
              }
              const text = String(value).trim();
              if (text) {
                return text;
              }
            }
            return '';
          };

          return {
            Meeting: {
              MeetingId: config.meetingId,
              MediaPlacement: {
                AudioHostUrl: pickPlacementValue('audioHostUrl', 'AudioHostUrl'),
                AudioFallbackUrl: pickPlacementValue('audioFallbackUrl', 'AudioFallbackUrl'),
                ScreenDataUrl: pickPlacementValue('screenDataUrl', 'ScreenDataUrl'),
                ScreenSharingUrl: pickPlacementValue('screenSharingUrl', 'ScreenSharingUrl'),
                ScreenViewingUrl: pickPlacementValue('screenViewingUrl', 'ScreenViewingUrl'),
                SignalingUrl: pickPlacementValue('signalingUrl', 'SignalingUrl'),
                TurnControlUrl: pickPlacementValue('turnControlUrl', 'TurnControlUrl'),
                EventIngestionUrl: pickPlacementValue('eventIngestionUrl', 'EventIngestionUrl'),
              },
              MediaRegion: config.mediaRegion || 'us-east-1',
            },
          };
        }

        function tryParseUrl(value) {
          try {
            const normalized = String(value || '').trim();
            if (!normalized) {
              return null;
            }
            return new URL(normalized);
          } catch (_) {
            return null;
          }
        }

        function reportMediaPlacementDiagnostics() {
          const placement = config && config.mediaPlacement ? config.mediaPlacement : {};
          const pickPlacementValue = (...keys) => {
            for (const key of keys) {
              const value = placement ? placement[key] : null;
              if (value === null || value === undefined) {
                continue;
              }
              const text = String(value).trim();
              if (text) {
                return text;
              }
            }
            return '';
          };

          const signalingRaw = pickPlacementValue('signalingUrl', 'SignalingUrl');
          const turnControlRaw = pickPlacementValue('turnControlUrl', 'TurnControlUrl');
          const audioHostRaw = pickPlacementValue('audioHostUrl', 'AudioHostUrl');
          const fallbackAudioRaw = pickPlacementValue('audioFallbackUrl', 'AudioFallbackUrl');

          const signaling = tryParseUrl(signalingRaw);
          const turnControl = tryParseUrl(turnControlRaw);
          const audioHost = tryParseUrl(audioHostRaw);
          const fallbackAudio = tryParseUrl(fallbackAudioRaw);

          report(
            'info',
            'Media placement: signaling=' +
              (signaling ? (signaling.protocol + '//' + signaling.host) : 'invalid') +
              ', turn=' +
              (turnControl ? (turnControl.protocol + '//' + turnControl.host) : 'invalid') +
              ', audio=' +
              (audioHost ? (audioHost.protocol + '//' + audioHost.host) : 'invalid') +
              ', fallbackAudio=' +
              (fallbackAudio ? (fallbackAudio.protocol + '//' + fallbackAudio.host) : 'invalid')
          );
          report('info', 'Media placement keys: ' + Object.keys(placement || {}).join(','));
          report(
            'info',
            'Media placement raw: signalingUrl=' + String(signalingRaw || '<empty>') +
              ', audioHostUrl=' + String(audioHostRaw || '<empty>')
          );

          if (!signaling) {
            report('warn', 'Media placement signalingUrl is missing or invalid');
          } else if (signaling.protocol !== 'wss:') {
            report('warn', 'Media placement signalingUrl should use wss, got: ' + signaling.protocol);
          }

          if (!turnControl) {
            report('warn', 'Media placement turnControlUrl is missing or invalid');
          }
        }

        function buildAttendeePayload() {
          return {
            Attendee: {
              AttendeeId: config.attendeeId,
              JoinToken: config.joinToken,
              ExternalUserId: config.externalUserId || ('careconnect-' + String(config.attendeeId || '').slice(0, 8)),
            },
          };
        }

        function isLikelyAndroidEmulator() {
          try {
            const ua = String(navigator.userAgent || '').toLowerCase();
            return ua.includes('sdk_gphone') ||
              ua.includes('emulator') ||
              ua.includes('android sdk built for');
          } catch (_) {
            return false;
          }
        }

        async function ensureVideoInput() {
          try {
            availableVideoInputs = await audioVideo.listVideoInputDevices();
            if (!availableVideoInputs || availableVideoInputs.length === 0) {
              report('warn', 'No video inputs available');
              return false;
            }
            if (!currentVideoInputDeviceId) {
              currentVideoInputDeviceId = availableVideoInputs[0].deviceId;
            }
            let selected = await selectVideoInput(currentVideoInputDeviceId);
            if (!selected && isLikelyAndroidEmulator()) {
              // Some emulator images expose unstable primary ids; try alternates.
              for (const input of availableVideoInputs) {
                if (!input || !input.deviceId) {
                  continue;
                }
                selected = await selectVideoInput(input.deviceId);
                if (selected) {
                  currentVideoInputDeviceId = input.deviceId;
                  report('info', 'Video input selected via emulator fallback');
                  break;
                }
              }
            }
            if (!selected) {
              report('warn', 'No supported video input selection API was found');
              return false;
            }
            return true;
          } catch (e) {
            report('error', 'Unable to start video input: ' + String(e));
            return false;
          }
        }

        function ensureLocalVideoTile() {
          if (isVideoMuted || !config.videoEnabled) {
            return;
          }
          if (typeof audioVideo.startLocalVideoTile === 'function') {
            audioVideo.startLocalVideoTile();
            report('info', 'Requested local video tile start');
          }
        }

        async function selectVideoInput(deviceId) {
          if (!deviceId) return false;
          if (typeof audioVideo.startVideoInput === 'function') {
            await audioVideo.startVideoInput(deviceId);
            currentVideoInputDeviceId = deviceId;
            return true;
          }
          if (typeof audioVideo.chooseVideoInputDevice === 'function') {
            await audioVideo.chooseVideoInputDevice(deviceId);
            currentVideoInputDeviceId = deviceId;
            return true;
          }
          return false;
        }

        async function selectAudioInput(deviceId) {
          if (!deviceId) return false;
          if (typeof audioVideo.startAudioInput === 'function') {
            await audioVideo.startAudioInput(deviceId);
            return true;
          }
          if (typeof audioVideo.chooseAudioInputDevice === 'function') {
            await audioVideo.chooseAudioInputDevice(deviceId);
            return true;
          }
          return false;
        }

        async function toggleAudio(muted) {
          if (!audioVideo) return;
          isAudioMuted = !!muted;
          if (isAudioMuted) {
            if (typeof audioVideo.realtimeMuteLocalAudio === 'function') {
              audioVideo.realtimeMuteLocalAudio();
            } else if (typeof audioVideo.muteLocalAudio === 'function') {
              audioVideo.muteLocalAudio();
            }
          } else {
            if (typeof audioVideo.realtimeUnmuteLocalAudio === 'function') {
              audioVideo.realtimeUnmuteLocalAudio();
            } else if (typeof audioVideo.unmuteLocalAudio === 'function') {
              audioVideo.unmuteLocalAudio();
            }
          }
          if (shouldAutoSentimentCapture) {
            if (isAudioMuted) {
              stopChimeTranscriptCapture();
              stopSpeechRecognitionCapture();
              emitSentimentChannelState('text', true, 'capture-stopped-muted');
              stopChimeVoiceMetricsCapture();
            } else {
              startChimeVoiceMetricsCapture();
              const chimeTranscriptStarted = startChimeTranscriptCapture();
              if (!chimeTranscriptStarted) {
                startSpeechRecognitionCapture();
              }
            }
          }
          emitAction('sentiment-channel-state', { channel: 'voice', muted: isAudioMuted });
        }

        async function toggleVideo(muted) {
          if (!audioVideo) return;
          isVideoMuted = !!muted;
          if (isVideoMuted) {
            if (typeof audioVideo.stopLocalVideoTile === 'function') {
              audioVideo.stopLocalVideoTile();
            }
          } else {
            const ready = await ensureVideoInput();
            if (ready && typeof audioVideo.startLocalVideoTile === 'function') {
              audioVideo.startLocalVideoTile();
            }
          }
          if (shouldAutoSentimentCapture) {
            if (isVideoMuted) {
              stopVideoSentimentCapture();
            } else {
              startVideoSentimentCapture();
            }
          }
          emitAction('sentiment-channel-state', { channel: 'video', muted: isVideoMuted });
        }

        async function switchCamera() {
          if (!audioVideo) return false;
          availableVideoInputs = await audioVideo.listVideoInputDevices();
          if (!availableVideoInputs || availableVideoInputs.length < 2) {
            return false;
          }

          const currentIndex = availableVideoInputs.findIndex((device) => device.deviceId === currentVideoInputDeviceId);
          const nextIndex = currentIndex >= 0
            ? (currentIndex + 1) % availableVideoInputs.length
            : 0;

          currentVideoInputDeviceId = availableVideoInputs[nextIndex].deviceId;
          await selectVideoInput(currentVideoInputDeviceId);

          if (!isVideoMuted && typeof audioVideo.startLocalVideoTile === 'function') {
            audioVideo.startLocalVideoTile();
          }

          return true;
        }

        function teardownMeeting(reason, emitEndRequest) {
          if (isShuttingDown) {
            return;
          }
          isShuttingDown = true;

          if (startupWatchdog) {
            clearTimeout(startupWatchdog);
            startupWatchdog = null;
          }

          stopAutoSentimentCapture();

          if (audioVideo) {
            try {
              if (meetingObserver && typeof audioVideo.removeObserver === 'function') {
                audioVideo.removeObserver(meetingObserver);
              }
            } catch (_) {}

            try {
              if (typeof audioVideo.stopLocalVideoTile === 'function') {
                audioVideo.stopLocalVideoTile();
              }
            } catch (_) {}

            try {
              if (typeof audioVideo.stop === 'function') {
                audioVideo.stop();
              }
            } catch (_) {}
          }

          if (remoteAudio) {
            try {
              remoteAudio.pause();
            } catch (_) {}
            remoteAudio.srcObject = null;
          }
          if (localVideo) {
            localVideo.srcObject = null;
          }
          remoteTiles.forEach((el) => {
            try {
              el.srcObject = null;
              el.remove();
            } catch (_) {}
          });
          remoteTiles.clear();

          if (flutterMessageHandler) {
            try {
              window.removeEventListener('message', flutterMessageHandler);
            } catch (_) {}
            flutterMessageHandler = null;
          }

          meetingObserver = null;
          audioVideo = null;
          meetingSession = null;
          sentimentVideoCtx = null;
          sentimentVideoCanvas = null;
          report('info', 'Mobile meeting teardown completed: ' + String(reason || 'unknown'));
          if (emitEndRequest) {
            emitAction('end-call-request', { reason: String(reason || 'teardown') });
          }
        }

        flutterMessageHandler = async (event) => {
          const data = event && event.data ? event.data : null;
          if (!data || data.source !== 'careconnect-flutter') {
            return;
          }

          if (data.action === 'teardown') {
            teardownMeeting(data.reason || 'flutter-teardown', false);
            return;
          }

          if (data.action === 'toggle-audio') {
            try {
              await toggleAudio(!!data.muted);
            } catch (e) {
              report('warn', 'toggle-audio failed: ' + String(e));
            }
            return;
          }

          if (data.action === 'toggle-video') {
            try {
              await toggleVideo(!!data.muted);
            } catch (e) {
              report('warn', 'toggle-video failed: ' + String(e));
            }
            return;
          }

          if (data.action === 'switch-camera') {
            try {
              const switched = await switchCamera();
              if (!switched) {
                report('warn', 'No alternate camera available to switch');
              }
            } catch (e) {
              report('warn', 'switch-camera failed: ' + String(e));
            }
            return;
          }

          if (data.action === 'restart-sentiment-channel') {
            try {
              const channel = String(data.channel || '').trim().toLowerCase();
              const restarted = restartSentimentChannelCapture(channel, 'flutter-restart-request');
              if (restarted) {
                report('info', 'Sentiment channel restarted: ' + channel);
              } else {
                report('warn', 'Sentiment channel restart skipped or failed: ' + channel);
              }
            } catch (e) {
              report('warn', 'Sentiment channel restart failed: ' + String(e));
            }
          }
        };

        window.addEventListener('message', flutterMessageHandler);

        async function bindAndPlayVideo(tileId, element, kind) {
          try {
            audioVideo.bindVideoElement(tileId, element);
          } catch (bindErr) {
            report('warn', 'Failed to bind ' + kind + ' video tile ' + tileId + ': ' + String(bindErr));
            return;
          }

          try {
            element.autoplay = true;
            element.playsInline = true;
            if (kind === 'remote') {
              // Remote audio is handled by bound audio element; keep video muted.
              element.muted = true;
            }

            const playPromise = element.play();
            if (playPromise && typeof playPromise.then === 'function') {
              await playPromise;
            }
          } catch (playErr) {
            const playErrorText = String(playErr);
            if (playErrorText.indexOf('AbortError') >= 0) {
              report('info', 'Video play() interrupted for ' + kind + ' tile ' + tileId + ' (likely rebind/teardown)');
            } else {
              report('warn', 'Video play() failed for ' + kind + ' tile ' + tileId + ': ' + playErrorText);
            }
          }
        }

        async function loadScriptWithTimeout(url, timeoutMs) {
          return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            let done = false;
            const timer = setTimeout(() => {
              if (done) return;
              done = true;
              try {
                script.remove();
              } catch (_) {}
              reject(new Error('Timed out loading ' + String(url)));
            }, timeoutMs);

            script.src = url;
            script.async = true;
            script.onload = () => {
              if (done) return;
              done = true;
              clearTimeout(timer);
              resolve(true);
            };
            script.onerror = () => {
              if (done) return;
              done = true;
              clearTimeout(timer);
              reject(new Error('Failed loading ' + String(url)));
            };

            document.head.appendChild(script);
          });
        }

        async function loadChimeSdk() {
          if (window.AmazonChimeSDK || window.ChimeSDK) {
            report('info', 'Using bundled local Chime SDK');
            return;
          }

          const candidates = [];
          const localSdkUrls = Array.isArray(config.localSdkUrls) ? config.localSdkUrls : [];
          for (const localUrl of localSdkUrls) {
            const normalized = String(localUrl || '').trim();
            if (normalized) {
              candidates.push(normalized);
            }
          }

          const primary = String(config.sdkUrl || '').trim();
          if (primary) {
            candidates.push(primary);
          }

          const fallbacks = [
            'https://sdk.amazonaws.com/js/amazon-chime-sdk/3.26.0/amazon-chime-sdk.min.js',
            'https://cdn.jsdelivr.net/npm/amazon-chime-sdk-js@3.26.0/build/amazon-chime-sdk.min.js',
            'https://unpkg.com/amazon-chime-sdk-js@3.26.0/build/amazon-chime-sdk.min.js',
          ];

          for (const fallback of fallbacks) {
            if (!candidates.includes(fallback)) {
              candidates.push(fallback);
            }
          }

          let lastError = null;
          for (let i = 0; i < candidates.length; i += 1) {
            const url = candidates[i];
            setStatus('Loading Chime SDK (' + (i + 1) + '/' + candidates.length + ')...');
            report('info', 'Trying SDK URL: ' + url);
            try {
              await loadScriptWithTimeout(url, 12000);
              if (window.AmazonChimeSDK || window.ChimeSDK) {
                report('info', 'Chime SDK loaded from: ' + url);
                return;
              }
              lastError = new Error('SDK script loaded but ChimeSDK global missing');
            } catch (err) {
              if (window.AmazonChimeSDK || window.ChimeSDK) {
                report('info', 'Chime SDK became available while loading fallbacks');
                return;
              }
              lastError = err;
              report('warn', String(err));
            }
          }

          throw lastError || new Error('Unable to load Chime SDK from any source');
        }

        try {
          await loadChimeSdk();

          const ChimeSDK = window.AmazonChimeSDK || window.ChimeSDK;
          if (!ChimeSDK) {
            throw new Error('Chime SDK failed to load');
          }
          chimeSdkNamespace = ChimeSDK;
          report('info', 'Chime SDK fingerprint: ' + resolveSdkFingerprint(ChimeSDK));
          reportMediaPlacementDiagnostics();

          setStatus('Creating meeting session...');
          const logger = new ChimeSDK.ConsoleLogger('CareConnectMobileChime', ChimeSDK.LogLevel.WARN);
          const deviceController = new ChimeSDK.DefaultDeviceController(logger);
          const meetingSessionConfiguration = new ChimeSDK.MeetingSessionConfiguration(
            buildMeetingPayload(),
            buildAttendeePayload(),
          );

          meetingSession = new ChimeSDK.DefaultMeetingSession(
            meetingSessionConfiguration,
            logger,
            deviceController,
          );

          audioVideo = meetingSession.audioVideo;
          report(
            'info',
            'Transcript capabilities: event=' +
              String(typeof audioVideo.realtimeSubscribeToTranscriptEvent === 'function') +
              ', controller=' +
              String(
                !!audioVideo.transcriptionController &&
                  typeof audioVideo.transcriptionController.subscribeToTranscriptEvent === 'function',
              ) +
              ', dataMessage=' +
              String(typeof audioVideo.realtimeSubscribeToReceiveDataMessage === 'function'),
          );
          setStatus('Preparing audio/video devices...');

          meetingObserver = {
            audioVideoDidStart: () => {
              mediaStarted = true;
              if (startupWatchdog) {
                clearTimeout(startupWatchdog);
                startupWatchdog = null;
              }
              updateParticipantStatus();
              ensureLocalVideoTile();
              startAutoSentimentCapture();
              report('info', 'audioVideoDidStart');
            },
            audioVideoDidStop: (sessionStatus) => {
              setStatus('Disconnected');
              report('info', 'audioVideoDidStop: ' + (sessionStatus && sessionStatus.statusCode ? sessionStatus.statusCode() : 'unknown'));
              teardownMeeting('audioVideoDidStop', true);
            },
            videoTileDidUpdate: (tileState) => {
              if (!tileState || !tileState.tileId || tileState.isContent) {
                return;
              }

              const tileAttendeeId = tileState.boundAttendeeId || tileState.attendeeId || '';
              const isLocalByAttendee = !!tileAttendeeId && tileAttendeeId === config.attendeeId;
              const isLocalTile = !!tileState.localTile || isLocalByAttendee;

              if (isLocalTile) {
                localVideoTileId = tileState.tileId;
                bindAndPlayVideo(tileState.tileId, localVideo, 'local');
                report('info', 'Local video tile bound');
              } else {
                remoteParticipantPresent = true;
                if (!remoteTiles.has(tileState.tileId)) {
                  const el = document.createElement('video');
                  el.autoplay = true;
                  el.playsInline = true;
                  el.muted = true;
                  el.className = 'remote-video';
                  videoGrid.appendChild(el);
                  remoteTiles.set(tileState.tileId, el);
                  updateVideoGridLayout();
                }
                bindAndPlayVideo(tileState.tileId, remoteTiles.get(tileState.tileId), 'remote');
                updateParticipantStatus();
                report('info', 'Remote video tile bound: ' + tileState.tileId + ' (total=' + remoteTiles.size + ')');
              }
            },
            videoTileWasRemoved: (tileId) => {
              if (localVideoTileId === tileId) {
                localVideoTileId = null;
                localVideo.srcObject = null;
              }
              const remoteEl = remoteTiles.get(tileId);
              if (remoteEl) {
                remoteEl.srcObject = null;
                remoteEl.remove();
                remoteTiles.delete(tileId);
                updateVideoGridLayout();
                remoteParticipantPresent = remoteTiles.size > 0;
                updateParticipantStatus();
              }
            },
          };

          audioVideo.addObserver(meetingObserver);

          if (typeof audioVideo.realtimeSubscribeToAttendeeIdPresence === 'function') {
            audioVideo.realtimeSubscribeToAttendeeIdPresence((attendeeId, present) => {
              if (!attendeeId || attendeeId === config.attendeeId) {
                return;
              }
              remoteParticipantPresent = !!present;
              if (!present) {
                remoteParticipantPresent = remoteTiles.size > 0;
              }
              updateParticipantStatus();
              report('info', 'Presence update: attendee=' + attendeeId + ', present=' + String(!!present));
            });
          }

          await ensureVideoInput();

          try {
            const audioInputs = await audioVideo.listAudioInputDevices();
            report('info', 'Audio input devices: ' + (audioInputs ? audioInputs.length : 0));
            if (audioInputs && audioInputs.length > 0) {
              let audioSelected = false;
              for (const input of audioInputs) {
                try {
                  const selected = await selectAudioInput(input.deviceId);
                  if (selected) {
                    audioSelected = true;
                    report('info', 'Audio input started: ' + input.deviceId);
                    break;
                  }
                } catch (audioErr) {
                  report('warn', 'Audio device failed: ' + input.deviceId + ' (' + String(audioErr) + ')');
                }
              }
              if (!audioSelected) {
                report('warn', 'No audio input device could be started');
              }
            } else {
              report('warn', 'No audio input device detected');
            }
          } catch (audioListErr) {
            report('warn', 'Audio input setup failed: ' + String(audioListErr));
          }

          audioVideo.bindAudioElement(remoteAudio);

          setStatus('Starting Chime media session...');
          audioVideo.start();
          report('info', 'audioVideo.start() invoked');

          // Do not block startup on audio element autoplay; WebRTC audio can attach later.
          Promise.resolve(remoteAudio.play()).catch((playErr) => {
            report('warn', 'Remote audio autoplay blocked: ' + String(playErr));
          });

          ensureLocalVideoTile();

          startupWatchdog = setTimeout(() => {
            if (mediaStarted) {
              return;
            }

            report('warn', 'audioVideoDidStart timeout; retrying audioVideo.start() once');
            try {
              audioVideo.start();
            } catch (startErr) {
              report('error', 'audioVideo.start() retry failed: ' + String(startErr));
            }
          }, 10000);

          if (isAudioMuted) {
            await toggleAudio(true);
          }
        } catch (e) {
          setStatus('Failed to initialize call media');
          report('error', String(e));
        }
      })();
    </script>
  </body>
</html>
''';
}


