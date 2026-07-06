// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

const String _chimeSdkUrl = String.fromEnvironment(
  'CHIME_SDK_URL',
  defaultValue: '/amazon-chime-sdk.min.js',
);

const bool _allowExternalSdkFallback = bool.fromEnvironment(
  'CHIME_SDK_ALLOW_EXTERNAL_FALLBACK',
  defaultValue: !kReleaseMode,
);

final Map<String, html.IFrameElement> _activeMeetingIframes =
    <String, html.IFrameElement>{};

Future<bool> requestChimeCameraSwitch({String? meetingId}) async {
  Iterable<html.IFrameElement> targets;
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    final frame = _activeMeetingIframes[meetingId.trim()];
    if (frame == null) return false;
    targets = [frame];
  } else {
    targets = _activeMeetingIframes.values;
  }

  var posted = false;
  for (final frame in targets) {
    final win = frame.contentWindow;
    if (win == null) continue;
    win.postMessage({
      'source': 'careconnect-flutter',
      'action': 'switch-camera',
      if (meetingId != null && meetingId.trim().isNotEmpty)
        'meetingId': meetingId.trim(),
    }, '*');
    posted = true;
  }

  return posted;
}

Future<bool> requestChimeAudioToggle({
  required bool muted,
  String? meetingId,
}) async {
  Iterable<html.IFrameElement> targets;
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    final frame = _activeMeetingIframes[meetingId.trim()];
    if (frame == null) return false;
    targets = [frame];
  } else {
    targets = _activeMeetingIframes.values;
  }

  var posted = false;
  for (final frame in targets) {
    final win = frame.contentWindow;
    if (win == null) continue;
    win.postMessage({
      'source': 'careconnect-flutter',
      'action': 'toggle-audio',
      'muted': muted,
      if (meetingId != null && meetingId.trim().isNotEmpty)
        'meetingId': meetingId.trim(),
    }, '*');
    posted = true;
  }
  return posted;
}

Future<bool> requestChimeVideoToggle({
  required bool muted,
  String? meetingId,
}) async {
  Iterable<html.IFrameElement> targets;
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    final frame = _activeMeetingIframes[meetingId.trim()];
    if (frame == null) return false;
    targets = [frame];
  } else {
    targets = _activeMeetingIframes.values;
  }

  var posted = false;
  for (final frame in targets) {
    final win = frame.contentWindow;
    if (win == null) continue;
    win.postMessage({
      'source': 'careconnect-flutter',
      'action': 'toggle-video',
      'muted': muted,
      if (meetingId != null && meetingId.trim().isNotEmpty)
        'meetingId': meetingId.trim(),
    }, '*');
    posted = true;
  }
  return posted;
}

Future<bool> requestChimeSentimentChannelRestart({
  required String channel,
  String? meetingId,
}) async {
  final normalizedChannel = channel.trim().toLowerCase();
  if (normalizedChannel != 'text' &&
      normalizedChannel != 'voice' &&
      normalizedChannel != 'video') {
    return false;
  }

  Iterable<html.IFrameElement> targets;
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    final frame = _activeMeetingIframes[meetingId.trim()];
    if (frame == null) return false;
    targets = [frame];
  } else {
    targets = _activeMeetingIframes.values;
  }

  var posted = false;
  for (final frame in targets) {
    final win = frame.contentWindow;
    if (win == null) continue;
    win.postMessage({
      'source': 'careconnect-flutter',
      'action': 'restart-sentiment-channel',
      'channel': normalizedChannel,
      if (meetingId != null && meetingId.trim().isNotEmpty)
        'meetingId': meetingId.trim(),
    }, '*');
    posted = true;
  }

  return posted;
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
  void Function(double averageLevel, double speechRatio, double variability)?
  onVoiceMetricsSample,
  void Function(String imageBase64)? onVideoSample,
  void Function(String channel, bool muted)? onSentimentChannelState,
}) {
  return _ChimeMeetingEmbedWeb(
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

class _ChimeMeetingEmbedWeb extends StatefulWidget {
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

  const _ChimeMeetingEmbedWeb({
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

  @override
  State<_ChimeMeetingEmbedWeb> createState() => _ChimeMeetingEmbedWebState();
}

class _ChimeMeetingEmbedWebState extends State<_ChimeMeetingEmbedWeb> {
  late final String _viewType;
  StreamSubscription<html.MessageEvent>? _messageSubscription;
  String? _guardMessage;

  void _postIframeAction(String action, [Map<String, dynamic>? payload]) {
    final iframe = _activeMeetingIframes[widget.meetingId];
    final win = iframe?.contentWindow;
    if (win == null) return;

    win.postMessage({
      'source': 'careconnect-flutter',
      'action': action,
      if (payload != null) ...payload,
      'meetingId': widget.meetingId,
    }, '*');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_ensureMediaPermissions());
    _viewType =
        'chime-meeting-view-${DateTime.now().microsecondsSinceEpoch}-${widget.meetingId}';

    final config = {
      'meetingId': widget.meetingId,
      'attendeeId': widget.attendeeId,
      'joinToken': widget.joinToken,
      'mediaPlacement': widget.mediaPlacement,
      'mediaRegion': widget.mediaRegion ?? 'us-east-1',
      'externalUserId':
          widget.externalUserId ??
          'careconnect-${widget.attendeeId.substring(0, 8)}',
      'videoEnabled': widget.videoEnabled,
      'audioEnabled': widget.audioEnabled,
      'enableAutoSentimentCapture': widget.enableAutoSentimentCapture,
      'sentimentCaptureIntervalMs': widget.sentimentCaptureIntervalMs,
      'preferChimeNativeVoiceAnalysis': true,
      'sdkUrl': _chimeSdkUrl,
      'allowExternalSdkFallback': _allowExternalSdkFallback,
    };

    final configJson = jsonEncode(config);

    _messageSubscription = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is Map && data['source'] == 'careconnect-chime') {
        final level = data['level'] ?? 'info';
        final message = data['message'] ?? '';
        debugPrint('[CareConnect][Chime][$level] $message');
        _emitTranscriptStatusFromLog(level.toString(), message.toString());

        if (!mounted) return;
        if (data['action'] == 'end-call-request') {
          widget.onEndCallRequested?.call();
          return;
        }

        if (data['action'] == 'sentiment-transcript') {
          final rawPayload = data['payload'];
          Map<String, dynamic> payload = const {};
          if (rawPayload is Map<String, dynamic>) {
            payload = rawPayload;
          } else if (rawPayload is Map) {
            payload = rawPayload.map((k, v) => MapEntry(k.toString(), v));
          } else if (rawPayload is String && rawPayload.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(rawPayload);
              if (decoded is Map) {
                payload = decoded.map((k, v) => MapEntry(k.toString(), v));
              }
            } catch (_) {}
          }
          final transcript = (payload['text'] ?? '').toString().trim();
          if (transcript.isNotEmpty) {
            debugPrint(
              '[CareConnect][Transcript][web] received len=${transcript.length}',
            );
            final source = (payload['source'] ?? '').toString().toLowerCase();
            if (source.contains('speech')) {
              widget.onTranscriptStatus?.call('FALLBACK', 'Speech recognition');
            } else {
              widget.onTranscriptStatus?.call('CONNECTED', 'Live transcript');
            }
            widget.onTranscriptSample?.call(Map<String, dynamic>.from(payload));
          }
          return;
        }

        if (data['action'] == 'sentiment-voice-metrics') {
          final payload = data['payload'];
          if (payload is Map) {
            final averageLevel =
                double.tryParse((payload['averageLevel'] ?? '').toString());
            final speechRatio =
                double.tryParse((payload['speechRatio'] ?? '').toString());
            final variability =
                double.tryParse((payload['variability'] ?? '').toString());
            if (averageLevel != null &&
                speechRatio != null &&
                variability != null) {
              widget.onVoiceMetricsSample?.call(
                averageLevel,
                speechRatio,
                variability,
              );
            }
          }
          return;
        }

        if (data['action'] == 'sentiment-video-sample') {
          final payload = data['payload'];
          if (payload is Map) {
            final imageBase64 = (payload['imageBase64'] ?? '')
                .toString()
                .trim();
            if (imageBase64.isNotEmpty) {
              widget.onVideoSample?.call(imageBase64);
            }
          }
          return;
        }

        if (data['action'] == 'sentiment-channel-state') {
          final payload = data['payload'];
          if (payload is Map) {
            final channel = (payload['channel'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final muted = payload['muted'] == true;
            if (channel == 'text' || channel == 'voice' || channel == 'video') {
              widget.onSentimentChannelState?.call(channel, muted);
            }
          }
          return;
        }

        if (level == 'info' &&
            (message.toString().contains('audioVideoDidStart') ||
                message.toString().contains('Local video tile bound') ||
                message.toString().contains('Remote video tile bound'))) {
          if (_guardMessage != null) {
            setState(() {
              _guardMessage = null;
            });
          }
          return;
        }

        if (level == 'error' && message.toString().contains('Chime SDK')) {
          setState(() {
            _guardMessage =
                'Chime SDK is unavailable. Host the SDK at $_chimeSdkUrl or set CHIME_SDK_URL to a valid asset.';
          });
        }
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'camera; microphone; autoplay; fullscreen')
        ..srcdoc = _buildMeetingHtml(configJson);
      _activeMeetingIframes[widget.meetingId] = iframe;
      return iframe;
    });
  }

  Future<void> _ensureMediaPermissions() async {
    final needAudio = widget.audioEnabled;
    final needVideo = widget.videoEnabled;

    if (!needAudio && !needVideo) {
      return;
    }

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        if (mounted) {
          setState(() {
            _guardMessage =
                'Browser media devices are unavailable. Camera/mic access cannot be requested.';
          });
        }
        return;
      }

      final stream = await mediaDevices.getUserMedia({
        'audio': needAudio
            ? {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
                'channelCount': 1,
              }
            : false,
        'video': needVideo,
      });

      for (final track in stream.getTracks()) {
        track.stop();
      }
    } catch (e) {
      final errorText = e.toString();
      String guardMessage;

      if (errorText.contains('NotAllowedError') ||
          errorText.contains('PermissionDeniedError') ||
          errorText.contains('SecurityError')) {
        guardMessage =
            'Camera/mic permission is blocked. Please allow access in Chrome site settings and retry.';
      } else if (errorText.contains('NotReadableError') ||
          errorText.contains('TrackStartError') ||
          errorText.contains('OverconstrainedError')) {
        guardMessage =
            'Camera or microphone is busy/unavailable. Close other apps or use another device, then retry.';
      } else if (errorText.contains('NotFoundError')) {
        guardMessage =
            'No microphone/camera was found for this browser session. Connect a device and retry.';
      } else {
        guardMessage =
            'Unable to initialize camera/mic right now. Verify browser permissions and device availability, then retry.';
      }

      if (mounted) {
        setState(() {
          _guardMessage = guardMessage;
        });
      }
      debugPrint(
        '[CareConnect][Chime][warn] getUserMedia permission check failed: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HtmlElementView(viewType: _viewType),
        if (_guardMessage != null)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _guardMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _postIframeAction('teardown', {'reason': 'flutter-widget-dispose'});
    _messageSubscription?.cancel();
    _activeMeetingIframes.remove(widget.meetingId);
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
    if (level.toLowerCase() == 'warn' &&
        lower.contains('no usable transcript text captured')) {
      widget.onTranscriptStatus!.call('FALLBACK', 'No live transcript text');
    }
  }

  String _buildMeetingHtml(String configJson) {
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
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
        grid-auto-rows:minmax(180px, 1fr);
        align-content:start;
      }
      .remote-video { width:100%; height:100%; object-fit:contain; background:#111; min-height:0; }
      #localVideo {
        position:absolute; right:16px; top:16px; width:22%; max-width:260px;
        aspect-ratio:16/9; object-fit:cover; border-radius:12px;
        border:2px solid rgba(255,255,255,0.75); background:#111;
      }
      @media (max-width: 768px) {
        #localVideo { width:18%; max-width:110px; aspect-ratio:9/16; }
      }
      #status {
        position:absolute; left:16px; bottom:88px; padding:6px 10px;
        border-radius:12px; font:12px system-ui; color:#fff; background:rgba(0,0,0,0.45);
      }
      #controls {
        position:absolute; left:50%; transform:translateX(-50%); bottom:16px;
        display:none !important;
        gap:clamp(12px, 1.8vw, 20px); align-items:center;
        padding:0;
        background:transparent;
        border:none;
      }
      .cc-btn {
        width:clamp(64px, 7.5vh, 88px);
        height:clamp(64px, 7.5vh, 88px);
        padding:0;
        border:1px solid rgba(255,255,255,0.2); border-radius:999px;
        display:flex; align-items:center; justify-content:center;
        color:#ffffff; cursor:pointer;
        background:rgba(98,98,102,0.96);
        box-shadow:0 1px 4px rgba(0,0,0,0.28);
        transition:background 140ms ease, transform 140ms ease, border-color 140ms ease;
      }
      .cc-btn .icon {
        display:inline-flex;
        align-items:center;
        justify-content:center;
      }
      .cc-btn .icon svg {
        width:clamp(30px, 3.7vh, 42px);
        height:clamp(30px, 3.7vh, 42px);
        stroke:currentColor;
        fill:none;
        stroke-width:2.2;
        stroke-linecap:round;
        stroke-linejoin:round;
      }
      #endBtn .icon svg {
        width:clamp(36px, 4.5vh, 52px);
        height:clamp(36px, 4.5vh, 52px);
        stroke-width:2.6;
      }
      .cc-btn.off {
        background:rgba(78,78,82,0.96);
        border-color:rgba(255,255,255,0.26);
      }
      .cc-btn.switch {
        background:rgba(98,98,102,0.96);
        border-color:rgba(255,255,255,0.2);
      }
      .cc-btn.switch:hover {
        background:rgba(112,112,116,0.96);
      }
      .cc-btn.switch:disabled {
        background:rgba(78,78,82,0.88);
        border-color:rgba(255,255,255,0.2);
      }
      .cc-btn.end {
        background:rgba(241,85,84,0.98);
        border-color:rgba(255,214,214,0.5);
      }
      .cc-btn:disabled { opacity:0.5; cursor:not-allowed; }
      .cc-btn:hover:not(:disabled) {
        background:rgba(112,112,116,0.98);
        transform:translateY(-1px);
      }
      .cc-btn.end:hover:not(:disabled) { background:rgba(225,69,68,0.98); }
    </style>
  </head>
  <body>
    <div id="stage">
      <div id="videoGridScroll">
        <div id="videoGrid"></div>
      </div>
      <video id="localVideo" autoplay playsinline muted></video>
      <audio id="remoteAudio" autoplay></audio>
      <div id="status">Connecting media...</div>
      <div id="controls">
        <button id="micBtn" class="cc-btn" type="button" title="Toggle microphone" aria-label="Toggle microphone"><span class="icon"></span></button>
        <button id="camBtn" class="cc-btn" type="button" title="Toggle camera" aria-label="Toggle camera"><span class="icon"></span></button>
        <button id="endBtn" class="cc-btn end" type="button" title="End call" aria-label="End call"><span class="icon"></span></button>
        <button id="switchCamBtn" class="cc-btn switch" type="button" title="Switch camera" aria-label="Switch camera"><span class="icon"></span></button>
      </div>
    </div>
    <script>
      (async function () {
        if (typeof window.global === 'undefined') {
          window.global = window;
        }

        if (!window.__careconnectPatchedGetStats &&
            window.RTCPeerConnection &&
            window.RTCPeerConnection.prototype &&
            typeof window.RTCPeerConnection.prototype.getStats === 'function') {
          const originalGetStats = window.RTCPeerConnection.prototype.getStats;
          const NativeMediaStreamTrack = window.MediaStreamTrack;

          window.RTCPeerConnection.prototype.getStats = function(...args) {
            try {
              if (args.length > 0) {
                const candidate = args[0];
                const isTrack = !!candidate && (
                  (NativeMediaStreamTrack && candidate instanceof NativeMediaStreamTrack) ||
                  (typeof candidate.kind === 'string' &&
                   typeof candidate.id === 'string' &&
                   typeof candidate.enabled === 'boolean')
                );

                if (!isTrack) {
                  return originalGetStats.call(this);
                }
              }

              return originalGetStats.apply(this, args);
            } catch (err) {
              const message = err && err.message ? String(err.message) : String(err);
              if (message.includes("parameter 1 is not of type 'MediaStreamTrack'")) {
                return originalGetStats.call(this);
              }
              throw err;
            }
          };

          window.__careconnectPatchedGetStats = true;
        }

        const config = $configJson;
        const statusEl = document.getElementById('status');
        const stage = document.getElementById('stage');
        const localVideo = document.getElementById('localVideo');
        const videoGrid = document.getElementById('videoGrid');
        const remoteAudio = document.getElementById('remoteAudio');
        const micBtn = document.getElementById('micBtn');
        const switchCamBtn = document.getElementById('switchCamBtn');
        const endBtn = document.getElementById('endBtn');
        const camBtn = document.getElementById('camBtn');
        const shouldAutoSentimentCapture =
          !!config.enableAutoSentimentCapture && (!!config.audioEnabled || !!config.videoEnabled);
        const preferChimeNativeVoiceAnalysis = config.preferChimeNativeVoiceAnalysis !== false;
        const sentimentCaptureIntervalMs =
          Number(config.sentimentCaptureIntervalMs) > 0
            ? Math.max(3000, Number(config.sentimentCaptureIntervalMs))
            : 15000;
        let isAudioMuted = !config.audioEnabled;
        let isVideoMuted = !config.videoEnabled;
        let audioVideo = null;
        let switchVideoInputRef = null;
        let updateControlButtonsRef = null;
        let availableVideoInputs = [];
        let sentimentAudioRecorder = null;
        let sentimentAudioStream = null;
        let sentimentAudioContext = null;
        let sentimentAudioSourceNode = null;
        let sentimentAudioProcessorNode = null;
        let sentimentAudioSilenceGain = null;
        let sentimentAudioFlushTimer = null;
        let sentimentAudioPcmChunks = [];
        let sentimentVideoTimer = null;
        let sentimentVideoCanvas = null;
        let sentimentVideoCtx = null;
        let speechRecognizer = null;
        let speechRestartTimer = null;
        let speechPermissionDenied = false;
        let lastTranscriptSignature = '';
        let lastTranscriptAt = 0;
        let chimeTranscriptHandler = null;
        let chimeTranscriptActive = false;
        // Roster built from presence events: attendeeId → externalUserId.
        // Transcript items often omit externalUserId, so we look it up here.
        const attendeeRoster = {};
        let voiceMetricsTimer = null;
        let voiceFrames = 0;
        let voiceSpeechFrames = 0;
        let voiceSum = 0;
        let voiceSumSquares = 0;
        let volumeIndicatorHandler = null;
        let flutterMessageHandler = null;
        let meetingObserver = null;
        let isShuttingDown = false;
        const maxQueuedSentimentAudioChunks = 96;

        function setStatus(msg) { statusEl.textContent = msg; }
        function report(level, msg) {
          try {
            window.parent.postMessage({ source: 'careconnect-chime', level, message: msg }, '*');
          } catch (_) {}
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

        function normalizeTranscriptSpeakerLabel(rawSpeaker, rawAttendeeId) {
          const source = String(rawSpeaker || rawAttendeeId || '').trim();
          if (!source) {
            return 'PARTICIPANT';
          }
          let normalized = source.replace(/#content/i, '').trim();
          if (!normalized) {
            return 'PARTICIPANT';
          }
          if (!Number.isNaN(Number(normalized)) && normalized.trim().length > 0) {
            normalized = 'participant-' + normalized;
          }
          normalized = normalized.replace(/[^A-Za-z0-9_-]+/g, '-');
          while (normalized.startsWith('-')) { normalized = normalized.substring(1); }
          while (normalized.endsWith('-')) { normalized = normalized.substring(0, normalized.length - 1); }
          return normalized || 'PARTICIPANT';
        }

        function resolveTranscriptMillis(value) {
          if (value === null || value === undefined) {
            return null;
          }
          if (typeof value === 'number' && Number.isFinite(value)) {
            return Math.max(0, Math.round(value));
          }
          const direct = Number(String(value).trim());
          return Number.isFinite(direct) ? Math.max(0, Math.round(direct)) : null;
        }

        function extractTranscriptPayloadsFromChimeEvent(transcriptEvent) {
          try {
            // transcriptionController fires Transcript objects directly (results at top level).
            // Guard against TranscriptionStatus events which have no results.
            const results = transcriptEvent && transcriptEvent.results
              ? transcriptEvent.results
              : (transcriptEvent && transcriptEvent.transcript && transcriptEvent.transcript.results
                  ? transcriptEvent.transcript.results : []);
            if (!Array.isArray(results) || results.length === 0) {
              return [];
            }
            const payloads = [];
            for (const result of results) {
              if (!result || result.isPartial === true) {
                continue;
              }
              const alternatives = Array.isArray(result.alternatives) ? result.alternatives : [];
              if (alternatives.length === 0) {
                continue;
              }
              const firstAlternative = alternatives[0] || {};
              const items = Array.isArray(firstAlternative.items) ? firstAlternative.items : [];
              const text = items.map((item) => (item && item.content ? String(item.content) : '')).join(' ').replace(/\\s+/g, ' ').replace(/\\s+([.,?!:;])/g, '').trim();
              if (!text) {
                continue;
              }
              const attendee = result.attendee || firstAlternative.attendee || {};
              const firstItem = items.length > 0 ? items[0] : null;
              const lastItem = items.length > 0 ? items[items.length - 1] : null;
              const itemAttendee = firstItem && firstItem.attendee ? firstItem.attendee : {};
              // Resolve attendeeId from any available source, then look up externalUserId
              // from the roster built via realtimeSubscribeToAttendeeIdPresence (most reliable).
              const speakerAttendeeId = attendee.attendeeId || result.attendeeId || itemAttendee.attendeeId || '';
              const rosterExternalId = speakerAttendeeId ? (attendeeRoster[speakerAttendeeId] || '') : '';
              const speakerExternalId = rosterExternalId
                || attendee.externalUserId || firstAlternative.externalUserId || itemAttendee.externalUserId || '';
              console.log('[CC-Transcript] Speaker resolve: attendeeId='+speakerAttendeeId+' roster='+rosterExternalId+' itemExt='+String(itemAttendee.externalUserId||'') +' final='+speakerExternalId);
              payloads.push({
                text: text,
                speakerLabel: normalizeTranscriptSpeakerLabel(speakerExternalId, speakerAttendeeId),
                startMs: resolveTranscriptMillis(result.startTimeMs || (firstItem && firstItem.startTimeMs) || result.startTime),
                endMs: resolveTranscriptMillis(result.endTimeMs || (lastItem && lastItem.endTimeMs) || result.endTime),
              });
            }
            return payloads;
          } catch (_) {
            return [];
          }
        }

        function extractTranscriptTextFromChimeEvent(transcriptEvent) {
          try {
            const results = transcriptEvent && transcriptEvent.results
              ? transcriptEvent.results
              : (transcriptEvent && transcriptEvent.transcript && transcriptEvent.transcript.results
                  ? transcriptEvent.transcript.results : []);
            if (!Array.isArray(results) || results.length === 0) {
              return '';
            }

            const lines = [];
            for (const result of results) {
              if (!result || result.isPartial === true) {
                continue;
              }
              const alternatives = Array.isArray(result.alternatives) ? result.alternatives : [];
              if (alternatives.length === 0) {
                continue;
              }
              const items = Array.isArray(alternatives[0].items) ? alternatives[0].items : [];
              const text = items
                .map((item) => (item && item.content ? String(item.content) : ''))
                .join(' ')
                .replace(/s+/g, ' ')
                .trim();
              if (text.length > 0) {
                lines.push(text);
              }
            }

            return lines.join(' ').trim();
          } catch (_) {
            return '';
          }
        }

        function stopChimeTranscriptCapture() {
          if (!audioVideo || !chimeTranscriptHandler) {
            chimeTranscriptActive = false;
            return;
          }

          try {
            if (audioVideo.transcriptionController &&
                typeof audioVideo.transcriptionController.unsubscribeFromTranscriptEvent === 'function') {
              audioVideo.transcriptionController.unsubscribeFromTranscriptEvent(chimeTranscriptHandler);
            }
          } catch (_) {}

          chimeTranscriptHandler = null;
          chimeTranscriptActive = false;
        }

        function startChimeTranscriptCapture() {
          if (!shouldAutoSentimentCapture) {
            return false;
          }
          if (!audioVideo || !audioVideo.transcriptionController ||
              typeof audioVideo.transcriptionController.subscribeToTranscriptEvent !== 'function') {
            return false;
          }

          stopChimeTranscriptCapture();
          chimeTranscriptHandler = (transcriptEvent) => {
            const payloads = extractTranscriptPayloadsFromChimeEvent(transcriptEvent);
            for (const payload of payloads) {
              emitTranscriptSample(payload, 'chime-transcript');
            }
          };

          try {
            audioVideo.transcriptionController.subscribeToTranscriptEvent(chimeTranscriptHandler);
            chimeTranscriptActive = true;
            report('info', 'Chime transcript capture subscribed');
            return true;
          } catch (transcriptErr) {
            report('warn', 'Chime transcript subscribe failed: ' + String(transcriptErr));
            chimeTranscriptHandler = null;
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

        function stopChimeVoiceMetricsCapture() {
          if (voiceMetricsTimer) {
            clearInterval(voiceMetricsTimer);
            voiceMetricsTimer = null;
          }

          if (audioVideo && volumeIndicatorHandler &&
              typeof audioVideo.realtimeUnsubscribeFromVolumeIndicator === 'function') {
            try {
              audioVideo.realtimeUnsubscribeFromVolumeIndicator(config.attendeeId, volumeIndicatorHandler);
            } catch (_) {}
          }

          volumeIndicatorHandler = null;
          resetVoiceMetricBuffers();
        }

        function startChimeVoiceMetricsCapture() {
          if (!shouldAutoSentimentCapture || isAudioMuted || !config.audioEnabled) {
            return false;
          }
          if (!audioVideo || typeof audioVideo.realtimeSubscribeToVolumeIndicator !== 'function') {
            return false;
          }

          stopChimeVoiceMetricsCapture();
          volumeIndicatorHandler = (attendeeId, volume) => {
            if (isAudioMuted) {
              return;
            }
            if (!attendeeId || attendeeId !== config.attendeeId) {
              return;
            }

            const value = Math.max(0, Math.min(1, Number(volume) || 0));
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

          const emitIntervalMs = Math.max(2500, Math.min(sentimentCaptureIntervalMs, 5000));
          voiceMetricsTimer = setInterval(() => {
            if (isAudioMuted) {
              resetVoiceMetricBuffers();
              return;
            }
            if (voiceFrames <= 0) {
              return;
            }

            const avg = voiceSum / voiceFrames;
            const variance = Math.max(0, (voiceSumSquares / voiceFrames) - (avg * avg));
            const stdDev = Math.sqrt(variance);
            const speakingRatio = voiceSpeechFrames / voiceFrames;

            emitAction('sentiment-voice-metrics', {
              averageLevel: Number(avg.toFixed(4)),
              speechRatio: Number(speakingRatio.toFixed(4)),
              variability: Number(Math.min(1, stdDev * 3).toFixed(4)),
              capturedAt: new Date().toISOString(),
            });

            resetVoiceMetricBuffers();
          }, emitIntervalMs);

          report('info', 'Chime voice metrics capture started (' + emitIntervalMs + 'ms)');
          return true;
        }

        function emitAction(action, payload) {
          try {
            window.parent.postMessage(
              {
                source: 'careconnect-chime',
                action,
                payload: payload || {},
                meetingId: config.meetingId,
              },
              '*',
            );
          } catch (_) {}
        }

        function emitSentimentChannelState(channel, muted, reason) {
          emitAction('sentiment-channel-state', {
            channel,
            muted: !!muted,
            reason: reason || 'local-control',
            capturedAt: new Date().toISOString(),
          });
        }

        function teardownMeeting(reason) {
          if (isShuttingDown) {
            return;
          }
          isShuttingDown = true;

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
          remoteTiles.forEach((tileId, el) => { el.srcObject = null; });
          remoteTiles.clear();

          if (flutterMessageHandler) {
            try {
              window.removeEventListener('message', flutterMessageHandler);
            } catch (_) {}
            flutterMessageHandler = null;
          }

          meetingObserver = null;
          audioVideo = null;
          sentimentVideoCtx = null;
          sentimentVideoCanvas = null;
          report('info', 'Meeting teardown completed: ' + String(reason || 'unknown'));
        }

        flutterMessageHandler = async (event) => {
          const data = event && event.data ? event.data : null;
          if (!data || data.source !== 'careconnect-flutter') {
            return;
          }

          if (data.action === 'teardown') {
            teardownMeeting(data.reason || 'flutter-teardown');
            return;
          }

          if (data.action === 'toggle-audio') {
            try {
              if (!audioVideo) {
                report('warn', 'Audio toggle requested before meeting session was ready');
                return;
              }

              const muted = !!data.muted;
              if (muted) {
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
              isAudioMuted = muted;
              if (shouldAutoSentimentCapture) {
                if (muted) {
                  stopAutoSentimentCapture();
                } else {
                  await startAutoSentimentCapture();
                }
              }
              if (typeof updateControlButtonsRef === 'function') {
                updateControlButtonsRef();
              }
              emitSentimentChannelState('voice', muted, 'flutter-overlay');
              report('info', 'Flutter overlay audio ' + (muted ? 'muted' : 'unmuted'));
            } catch (audioErr) {
              report('warn', 'Flutter overlay audio toggle failed: ' + String(audioErr));
            }
            return;
          }

          if (data.action === 'toggle-video') {
            try {
              if (!audioVideo) {
                report('warn', 'Video toggle requested before meeting session was ready');
                return;
              }

              const muted = !!data.muted;
              if (muted) {
                if (typeof audioVideo.stopLocalVideoTile === 'function') {
                  audioVideo.stopLocalVideoTile();
                }
                localVideoBound = false;
                isVideoMuted = true;
                if (sentimentVideoTimer) {
                  clearInterval(sentimentVideoTimer);
                  sentimentVideoTimer = null;
                }
              } else {
                if (typeof audioVideo.startLocalVideoTile === 'function') {
                  audioVideo.startLocalVideoTile();
                }
                localVideoBound = false;
                isVideoMuted = false;
                if (shouldAutoSentimentCapture) {
                  startVideoSentimentCapture();
                }
              }
              if (typeof updateControlButtonsRef === 'function') {
                updateControlButtonsRef();
              }
              emitSentimentChannelState('video', muted, 'flutter-overlay');
              report('info', 'Flutter overlay video ' + (muted ? 'stopped' : 'started'));
            } catch (videoErr) {
              report('warn', 'Flutter overlay video toggle failed: ' + String(videoErr));
            }
            return;
          }

          if (data.action === 'switch-camera') {
            try {
              if (!audioVideo) {
                report('warn', 'Camera switch requested before meeting session was ready');
                return;
              }

              if (typeof audioVideo.listVideoInputDevices === 'function') {
                availableVideoInputs = await audioVideo.listVideoInputDevices();
              }
              const switched =
                typeof switchVideoInputRef === 'function'
                  ? await switchVideoInputRef('flutter-overlay')
                  : false;
              if (switched) {
                localVideoBound = false;
                ensureLocalVideoTile();
                report('info', 'Camera switched by Flutter overlay');
              } else {
                report('warn', 'Flutter overlay requested camera switch but no alternative camera was found');
              }
              if (typeof updateControlButtonsRef === 'function') {
                updateControlButtonsRef();
              }
            } catch (switchErr) {
              report('warn', 'Flutter overlay camera switch failed: ' + String(switchErr));
            }
          }

          if (data.action === 'restart-sentiment-channel') {
            try {
              const channel = String(data.channel || '').trim().toLowerCase();
              const restarted = await restartSentimentChannelCapture(channel, 'flutter-restart-request');
              if (restarted) {
                report('info', 'Sentiment channel restarted: ' + channel);
              } else {
                report('warn', 'Sentiment channel restart skipped or failed: ' + channel);
              }
            } catch (restartErr) {
              report('warn', 'Sentiment channel restart failed: ' + String(restartErr));
            }
            return;
          }
        };

        window.addEventListener('message', flutterMessageHandler);

        function normalizeAudioFormat(mimeType) {
          const lower = String(mimeType || '').toLowerCase();
          if (lower.includes('webm')) return 'webm';
          if (lower.includes('ogg')) return 'ogg';
          if (lower.includes('mpeg') || lower.includes('mp3')) return 'mp3';
          if (lower.includes('mp4') || lower.includes('aac')) return 'mp4';
          if (lower.includes('wav')) return 'wav';
          return 'wav';
        }

        function blobToBase64(blob) {
          return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onloadend = () => {
              const dataUrl = String(reader.result || '');
              const comma = dataUrl.indexOf(',');
              if (comma < 0) {
                reject(new Error('Invalid audio payload'));
                return;
              }
              resolve(dataUrl.substring(comma + 1));
            };
            reader.onerror = reject;
            reader.readAsDataURL(blob);
          });
        }

        function bytesToBase64(bytes) {
          let binary = '';
          const chunkSize = 0x8000;
          for (let i = 0; i < bytes.length; i += chunkSize) {
            const chunk = bytes.subarray(i, i + chunkSize);
            binary += String.fromCharCode.apply(null, chunk);
          }
          return btoa(binary);
        }

        function encodeMonoWavBase64(float32Samples, sampleRate) {
          const channels = 1;
          const bitsPerSample = 16;
          const bytesPerSample = bitsPerSample / 8;
          const dataSize = float32Samples.length * bytesPerSample;
          const wavBuffer = new ArrayBuffer(44 + dataSize);
          const view = new DataView(wavBuffer);

          function writeAscii(offset, text) {
            for (let i = 0; i < text.length; i += 1) {
              view.setUint8(offset + i, text.charCodeAt(i));
            }
          }

          writeAscii(0, 'RIFF');
          view.setUint32(4, 36 + dataSize, true);
          writeAscii(8, 'WAVE');
          writeAscii(12, 'fmt ');
          view.setUint32(16, 16, true);
          view.setUint16(20, 1, true);
          view.setUint16(22, channels, true);
          view.setUint32(24, sampleRate, true);
          view.setUint32(28, sampleRate * channels * bytesPerSample, true);
          view.setUint16(32, channels * bytesPerSample, true);
          view.setUint16(34, bitsPerSample, true);
          writeAscii(36, 'data');
          view.setUint32(40, dataSize, true);

          let offset = 44;
          for (let i = 0; i < float32Samples.length; i += 1) {
            const clamped = Math.max(-1, Math.min(1, float32Samples[i]));
            const pcm = clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff;
            view.setInt16(offset, pcm | 0, true);
            offset += 2;
          }

          return bytesToBase64(new Uint8Array(wavBuffer));
        }

        function downsamplePcm(float32Samples, inputRate, outputRate) {
          if (!float32Samples || float32Samples.length === 0) {
            return new Float32Array(0);
          }
          if (!inputRate || !outputRate || outputRate >= inputRate) {
            return float32Samples;
          }

          const ratio = inputRate / outputRate;
          const outputLength = Math.max(1, Math.floor(float32Samples.length / ratio));
          const output = new Float32Array(outputLength);
          let offset = 0;

          for (let i = 0; i < outputLength; i += 1) {
            const nextOffset = Math.min(float32Samples.length, Math.floor((i + 1) * ratio));
            let sum = 0;
            let count = 0;
            for (let j = offset; j < nextOffset; j += 1) {
              sum += float32Samples[j];
              count += 1;
            }
            output[i] = count > 0 ? sum / count : 0;
            offset = nextOffset;
          }

          return output;
        }

        async function convertBlobToWavBase64(blob, targetSampleRate, maxDurationMs) {
          const AudioCtx = window.AudioContext || window.webkitAudioContext;
          if (!AudioCtx) {
            throw new Error('AudioContext unavailable');
          }

          const sourceBuffer = await blob.arrayBuffer();
          const decodeContext = new AudioCtx();
          let decoded;

          try {
            decoded = await decodeContext.decodeAudioData(sourceBuffer.slice(0));
          } finally {
            try {
              await decodeContext.close();
            } catch (_) {}
          }

          const outputRate = Number(targetSampleRate) > 0 ? Number(targetSampleRate) : 16000;
          const durationCapMs = Number(maxDurationMs) > 0 ? Number(maxDurationMs) : 5000;
          const maxFrameCount = Math.max(1, Math.floor((durationCapMs / 1000) * outputRate));
          const frameCount = Math.max(1, Math.min(maxFrameCount, Math.ceil(decoded.duration * outputRate)));
          const offline = new OfflineAudioContext(1, frameCount, outputRate);
          const source = offline.createBufferSource();
          source.buffer = decoded;
          source.connect(offline.destination);
          source.start(0);
          const rendered = await offline.startRendering();

          return encodeMonoWavBase64(rendered.getChannelData(0), outputRate);
        }

        async function toModelAudioPayload(blob, recorderMime) {
          // Legacy WAV conversion helper kept for compatibility; voice analysis uses metrics.
          try {
            const wavBase64 = await convertBlobToWavBase64(blob, 8000, 1500);
            if (wavBase64 && wavBase64.length >= 512) {
              return { audioBase64: wavBase64, audioFormat: 'wav' };
            }
          } catch (wavErr) {
            report(
              'warn',
              'WAV conversion failed; skipping voice sample. recorderMime=' +
                String(recorderMime || 'unknown') +
                ', error=' +
                String(wavErr),
            );
          }

          return { audioBase64: '', audioFormat: 'wav' };
        }

        function emitTranscriptSample(rawSample, source) {
          const sample = rawSample && typeof rawSample === 'object'
            ? rawSample
            : { text: rawSample };
          const text = String(sample.text || '').trim();
          if (text.length < 8) {
            return;
          }

          const signature = text.toLowerCase().replace(/\\s+/g, ' ').trim();
          const now = Date.now();
          if (signature === lastTranscriptSignature && (now - lastTranscriptAt) < 12000) {
            return;
          }

          lastTranscriptSignature = signature;
          lastTranscriptAt = now;
          emitAction('sentiment-transcript', {
            text,
            speakerLabel: normalizeTranscriptSpeakerLabel(sample.speakerLabel, sample.attendeeId),
            startMs: resolveTranscriptMillis(sample.startMs),
            endMs: resolveTranscriptMillis(sample.endMs),
            source: source || 'speech-recognition',
            capturedAt: new Date().toISOString(),
          });
        }

        function stopAutoSentimentCapture() {
          stopChimeTranscriptCapture();
          stopChimeVoiceMetricsCapture();
          if (speechRestartTimer) {
            clearTimeout(speechRestartTimer);
            speechRestartTimer = null;
          }

          if (speechRecognizer) {
            try {
              speechRecognizer.onresult = null;
              speechRecognizer.onerror = null;
              speechRecognizer.onend = null;
              speechRecognizer.stop();
            } catch (_) {}
            speechRecognizer = null;
          }

          if (sentimentAudioRecorder) {
            try {
              if (sentimentAudioRecorder.state !== 'inactive') {
                sentimentAudioRecorder.stop();
              }
            } catch (_) {}
            sentimentAudioRecorder = null;
          }

          if (sentimentAudioStream) {
            try {
              sentimentAudioStream.getTracks().forEach((track) => track.stop());
            } catch (_) {}
            sentimentAudioStream = null;
          }

          if (sentimentVideoTimer) {
            clearInterval(sentimentVideoTimer);
            sentimentVideoTimer = null;
          }
        }

        function stopSpeechRecognitionCapture() {
          if (speechRestartTimer) {
            clearTimeout(speechRestartTimer);
            speechRestartTimer = null;
          }

          if (speechRecognizer) {
            try {
              speechRecognizer.onresult = null;
              speechRecognizer.onerror = null;
              speechRecognizer.onend = null;
              speechRecognizer.stop();
            } catch (_) {}
            speechRecognizer = null;
          }
        }

        function stopAudioSentimentCapture() {
          if (sentimentAudioFlushTimer) {
            clearInterval(sentimentAudioFlushTimer);
            sentimentAudioFlushTimer = null;
          }

          sentimentAudioPcmChunks = [];

          if (sentimentAudioRecorder) {
            try {
              if (sentimentAudioRecorder.state !== 'inactive') {
                sentimentAudioRecorder.stop();
              }
            } catch (_) {}
            sentimentAudioRecorder = null;
          }

          if (sentimentAudioProcessorNode) {
            try {
              sentimentAudioProcessorNode.onaudioprocess = null;
              sentimentAudioProcessorNode.disconnect();
            } catch (_) {}
            sentimentAudioProcessorNode = null;
          }

          if (sentimentAudioSourceNode) {
            try {
              sentimentAudioSourceNode.disconnect();
            } catch (_) {}
            sentimentAudioSourceNode = null;
          }

          if (sentimentAudioSilenceGain) {
            try {
              sentimentAudioSilenceGain.disconnect();
            } catch (_) {}
            sentimentAudioSilenceGain = null;
          }

          if (sentimentAudioContext) {
            try {
              sentimentAudioContext.close();
            } catch (_) {}
            sentimentAudioContext = null;
          }

          if (sentimentAudioStream) {
            try {
              sentimentAudioStream.getTracks().forEach((track) => track.stop());
            } catch (_) {}
            sentimentAudioStream = null;
          }
        }

        function stopVideoSentimentCapture() {
          if (sentimentVideoTimer) {
            clearInterval(sentimentVideoTimer);
            sentimentVideoTimer = null;
          }
        }

        function startSpeechRecognitionCapture() {
          if (!shouldAutoSentimentCapture) {
            return;
          }
          if (speechPermissionDenied) {
            return;
          }
          if (chimeTranscriptActive) {
            return;
          }

          const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
          if (!SpeechRecognition) {
            report('warn', 'SpeechRecognition API unavailable; transcript sentiment auto-capture disabled.');
            return;
          }

          speechRecognizer = new SpeechRecognition();
          speechRecognizer.continuous = true;
          speechRecognizer.interimResults = false;
          speechRecognizer.lang = config.speechLocale || navigator.language || 'en-US';

          speechRecognizer.onresult = (event) => {
            let transcript = '';
            for (let i = event.resultIndex; i < event.results.length; i += 1) {
              const result = event.results[i];
              if (result && result.isFinal && result[0] && result[0].transcript) {
                transcript += ' ' + result[0].transcript;
              }
            }
            if (transcript.trim()) {
              emitTranscriptSample({ text: transcript.trim(), speakerLabel: config.externalUserId || '' }, 'speech-recognition');
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
                  speechRecognizer.start();
                }
              } catch (_) {}
            }, 1200);
          };

          try {
            speechRecognizer.start();
            report('info', 'Speech transcription capture started');
          } catch (speechStartErr) {
            report('warn', 'Unable to start speech recognition: ' + String(speechStartErr));
          }
        }

        async function startAudioSentimentCapture() {
          if (!shouldAutoSentimentCapture) {
            return;
          }
          if (isAudioMuted) {
            return;
          }
          if (!config.audioEnabled) {
            return;
          }
          if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            report('warn', 'getUserMedia API unavailable; voice sentiment auto-capture disabled.');
            return;
          }

          try {
            sentimentAudioStream = await navigator.mediaDevices.getUserMedia({
              audio: {
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
                channelCount: 1,
              },
              video: false,
            });

            const AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (!AudioCtx) {
              report('warn', 'AudioContext unavailable; voice sentiment auto-capture disabled.');
              return;
            }

            sentimentAudioContext = new AudioCtx();
            sentimentAudioSourceNode = sentimentAudioContext.createMediaStreamSource(sentimentAudioStream);
            sentimentAudioProcessorNode = sentimentAudioContext.createScriptProcessor(4096, 1, 1);
            sentimentAudioSilenceGain = sentimentAudioContext.createGain();
            sentimentAudioSilenceGain.gain.value = 0;
            sentimentAudioPcmChunks = [];

            sentimentAudioProcessorNode.onaudioprocess = (event) => {
              if (isAudioMuted) {
                return;
              }
              const channelData = event.inputBuffer && event.inputBuffer.numberOfChannels > 0
                ? event.inputBuffer.getChannelData(0)
                : null;
              if (!channelData || channelData.length === 0) {
                return;
              }
              sentimentAudioPcmChunks.push(new Float32Array(channelData));
              if (sentimentAudioPcmChunks.length > maxQueuedSentimentAudioChunks) {
                sentimentAudioPcmChunks.splice(
                  0,
                  sentimentAudioPcmChunks.length - maxQueuedSentimentAudioChunks,
                );
              }
            };

            sentimentAudioSourceNode.connect(sentimentAudioProcessorNode);
            sentimentAudioProcessorNode.connect(sentimentAudioSilenceGain);
            sentimentAudioSilenceGain.connect(sentimentAudioContext.destination);

            const audioChunkMs = Math.max(2500, Math.min(sentimentCaptureIntervalMs, 4000));
            const targetSampleRate = 8000;

            sentimentAudioFlushTimer = setInterval(() => {
              if (isAudioMuted) {
                sentimentAudioPcmChunks = [];
                return;
              }
              if (!sentimentAudioPcmChunks || sentimentAudioPcmChunks.length === 0) {
                return;
              }

              try {
                const totalSamples = sentimentAudioPcmChunks.reduce((sum, chunk) => sum + chunk.length, 0);
                if (totalSamples <= 0) {
                  sentimentAudioPcmChunks = [];
                  return;
                }

                const merged = new Float32Array(totalSamples);
                let writeOffset = 0;
                for (const chunk of sentimentAudioPcmChunks) {
                  merged.set(chunk, writeOffset);
                  writeOffset += chunk.length;
                }
                sentimentAudioPcmChunks = [];

                const inputRate = sentimentAudioContext && sentimentAudioContext.sampleRate
                  ? sentimentAudioContext.sampleRate
                  : 48000;
                const downsampled = downsamplePcm(merged, inputRate, targetSampleRate);
                if (!downsampled || downsampled.length < 512) {
                  return;
                }

                const audioBase64 = encodeMonoWavBase64(downsampled, targetSampleRate);
                if (!audioBase64 || audioBase64.length < 512) {
                  return;
                }

                // Legacy raw-audio sentiment emission is intentionally disabled.
              } catch (audioEmitErr) {
                report('warn', 'Failed processing PCM voice chunk: ' + String(audioEmitErr));
              }
            }, audioChunkMs);

            report('info', 'Voice sentiment capture started (' + audioChunkMs + 'ms PCM chunks)');
          } catch (audioCaptureErr) {
            report('warn', 'Unable to start voice sentiment capture: ' + String(audioCaptureErr));
            if (sentimentAudioStream) {
              try {
                sentimentAudioStream.getTracks().forEach((track) => track.stop());
              } catch (_) {}
              sentimentAudioStream = null;
            }
          }
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
              imageBase64,
              imageFormat: 'jpeg',
              capturedAt: new Date().toISOString(),
            });
          } catch (videoFrameErr) {
            report('warn', 'Unable to capture video sentiment frame: ' + String(videoFrameErr));
          }
        }

        function startVideoSentimentCapture() {
          if (!shouldAutoSentimentCapture || !config.videoEnabled || isVideoMuted) {
            return;
          }
          if (sentimentVideoTimer) {
            clearInterval(sentimentVideoTimer);
          }

          captureVideoSampleFrame();
          sentimentVideoTimer = setInterval(() => {
            captureVideoSampleFrame();
          }, sentimentCaptureIntervalMs);
          report('info', 'Video sentiment capture started (' + sentimentCaptureIntervalMs + 'ms frames)');
        }

        async function restartTextSentimentCapture(reason) {
          const chimeStarted = startChimeTranscriptCapture();
          if (!chimeStarted) {
            startSpeechRecognitionCapture();
            emitSentimentChannelState('text', false, reason || 'speech-fallback-started');
            return true;
          }
          emitSentimentChannelState('text', false, reason || 'channel-restart');
          return true;
        }

        async function restartVoiceSentimentCapture(reason) {
          if (!shouldAutoSentimentCapture || isAudioMuted || !config.audioEnabled) {
            return false;
          }

          const restarted = startChimeVoiceMetricsCapture();
          if (restarted) {
            emitSentimentChannelState('voice', false, reason || 'channel-restart');
          }
          return restarted;
        }

        function restartVideoSentimentCapture(reason) {
          if (!shouldAutoSentimentCapture || isVideoMuted || !config.videoEnabled) {
            return false;
          }

          stopVideoSentimentCapture();
          startVideoSentimentCapture();
          const restarted = !!sentimentVideoTimer;
          if (restarted) {
            emitSentimentChannelState('video', false, reason || 'channel-restart');
          }
          return restarted;
        }

        async function restartSentimentChannelCapture(channel, reason) {
          const normalized = String(channel || '').trim().toLowerCase();
          if (normalized === 'voice') {
            return restartVoiceSentimentCapture(reason);
          }
          if (normalized === 'video') {
            return restartVideoSentimentCapture(reason);
          }
          if (normalized === 'text') {
            return restartTextSentimentCapture(reason);
          }
          return false;
        }

        async function startAutoSentimentCapture() {
          if (!shouldAutoSentimentCapture) {
            return;
          }

          const chimeTranscriptStarted = startChimeTranscriptCapture();
          if (!chimeTranscriptStarted) {
            startSpeechRecognitionCapture();
          }
          startChimeVoiceMetricsCapture();

          startVideoSentimentCapture();
          emitSentimentChannelState('text', false, 'capture-started');
        }

        function iconSvg(name) {
          switch (name) {
            case 'mic':
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M6.5 11.5a5.5 5.5 0 0 0 11 0"/><path d="M12 17v3"/><path d="M9.5 20h5"/></svg>';
            case 'mic-off':
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4l16 16"/><rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M6.5 11.5a5.5 5.5 0 0 0 11 0"/><path d="M12 17v3"/><path d="M9.5 20h5"/></svg>';
            case 'video':
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="7" width="12.5" height="10" rx="2"/><path d="M16.2 10 20.5 8v8l-4.3-2z"/></svg>';
            case 'video-off':
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4l16 16"/><rect x="3.5" y="7" width="12.5" height="10" rx="2"/><path d="M16.2 10 20.5 8v8l-4.3-2z"/></svg>';
            case 'hangup':
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4.4 15.2c4.2-4.2 11-4.2 15.2 0"/><path d="M7.2 12.6 5 15.1l2.7 2"/><path d="M16.8 12.6 19 15.1l-2.7 2"/></svg>';
            case 'switch-cam':
            default:
              return '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="7" width="16" height="11" rx="2.4"/><path d="M9.2 7 10.6 5h2.8L14.8 7"/><path d="M8 11.2h3"/><path d="M9.4 9.8 11 11.2 9.4 12.6"/><path d="M16 13.8h-3"/><path d="M14.6 12.4 13 13.8 14.6 15.2"/></svg>';
          }
        }

        function updateControlButtons() {
          if (micBtn) {
            micBtn.innerHTML = '<span class="icon">' + iconSvg(isAudioMuted ? 'mic-off' : 'mic') + '</span>';
            micBtn.classList.toggle('off', isAudioMuted);
            micBtn.disabled = !config.audioEnabled;
          }
          if (camBtn) {
            camBtn.innerHTML = '<span class="icon">' + iconSvg(isVideoMuted ? 'video-off' : 'video') + '</span>';
            camBtn.classList.toggle('off', isVideoMuted);
            camBtn.disabled = !config.videoEnabled;
          }
          if (switchCamBtn) {
            const canSwitchCamera =
              config.videoEnabled &&
              !isVideoMuted &&
              Array.isArray(availableVideoInputs) &&
              availableVideoInputs.length > 1;
            switchCamBtn.innerHTML = '<span class="icon">' + iconSvg('switch-cam') + '</span>';
            switchCamBtn.disabled = !canSwitchCamera;
          }
          if (endBtn) {
            endBtn.innerHTML = '<span class="icon">' + iconSvg('hangup') + '</span>';
          }
        }

        updateControlButtonsRef = updateControlButtons;

        async function loadChimeSdk() {
          if (window.AmazonChimeSDK || window.ChimeSDK) {
            return window.AmazonChimeSDK || window.ChimeSDK;
          }

          const scriptUrls = [config.sdkUrl];

          if (config.allowExternalSdkFallback) {
            scriptUrls.push(
              'https://unpkg.com/amazon-chime-sdk-js@3.26.0/build/amazon-chime-sdk.min.js',
              'https://cdn.jsdelivr.net/npm/amazon-chime-sdk-js@3.26.0/build/amazon-chime-sdk.min.js'
            );
          }

          for (const url of scriptUrls) {
            try {
              await new Promise((resolve, reject) => {
                const script = document.createElement('script');
                script.src = url;
                script.async = true;
                script.onload = resolve;
                script.onerror = reject;
                document.head.appendChild(script);
              });

              if (window.AmazonChimeSDK || window.ChimeSDK) {
                report('info', 'Chime SDK loaded from: ' + url);
                return window.AmazonChimeSDK || window.ChimeSDK;
              }

              report('warn', 'Script loaded but no SDK global exposed: ' + url);
            } catch (_) {
              report('warn', 'Failed loading Chime SDK from: ' + url);
            }
          }

          if (!config.allowExternalSdkFallback) {
            throw new Error(
              'Chime SDK not available at ' + config.sdkUrl +
              '. Provide CHIME_SDK_URL pointing to a hosted SDK asset.'
            );
          }

          const moduleUrls = [
            config.sdkUrl,
            'https://esm.run/amazon-chime-sdk-js@3.26.0',
            'https://ga.jspm.io/npm:amazon-chime-sdk-js@3.26.0/build/index.js'
          ];

          for (const moduleUrl of moduleUrls) {
            try {
              const mod = await import(moduleUrl);
              const sdk = mod.AmazonChimeSDK || mod.default || mod;
              if (sdk) {
                window.AmazonChimeSDK = sdk;
                report('info', 'Chime SDK imported from module: ' + moduleUrl);
                return window.AmazonChimeSDK;
              }
            } catch (_) {
              report('warn', 'Failed importing Chime SDK module: ' + moduleUrl);
            }
          }

          throw new Error('Amazon Chime SDK JS failed to load from all sources.');
        }

        try {
          report('info', 'Initializing Chime media session');
          const ChimeSDK = await loadChimeSdk();
          report('info', 'Chime SDK fingerprint: ' + resolveSdkFingerprint(ChimeSDK));
          const meetingResponse = {
            Meeting: {
              MeetingId: config.meetingId,
              ExternalMeetingId: config.meetingId,
              MediaRegion: config.mediaRegion || 'us-east-1',
              MediaPlacement: {
                AudioHostUrl: config.mediaPlacement.audioHostUrl,
                AudioFallbackUrl: config.mediaPlacement.audioFallbackUrl,
                ScreenDataUrl: config.mediaPlacement.screenDataUrl,
                ScreenSharingUrl: config.mediaPlacement.screenSharingUrl,
                ScreenViewingUrl: config.mediaPlacement.screenViewingUrl,
                SignalingUrl: config.mediaPlacement.signalingUrl,
                TurnControlUrl: config.mediaPlacement.turnControlUrl,
                EventIngestionUrl: config.mediaPlacement.eventIngestionUrl || ''
              }
            }
          };

          const attendeeResponse = {
            Attendee: {
              AttendeeId: config.attendeeId,
              ExternalUserId: config.externalUserId,
              JoinToken: config.joinToken
            }
          };

          const logger = new ChimeSDK.ConsoleLogger('CareConnectChime', ChimeSDK.LogLevel.INFO);
          const deviceController = new ChimeSDK.DefaultDeviceController(logger);
          const meetingConfig = new ChimeSDK.MeetingSessionConfiguration(meetingResponse, attendeeResponse);
          const meetingSession = new ChimeSDK.DefaultMeetingSession(meetingConfig, logger, deviceController);
          audioVideo = meetingSession.audioVideo;
          // Seed roster with local attendee so own speech is also labelled correctly.
          attendeeRoster[config.attendeeId] = config.externalUserId || '';
          console.log('[CC-Transcript] Roster seeded local:', config.attendeeId, '->', config.externalUserId);
          let localVideoBound = false;
          let localVideoStartAttempts = 0;
          let localVideoRetryTimer = null;
          let videoPublishRecoveryAttempts = 0;
          let localTileId = null;
          const remoteTiles = new Map(); // tileId -> HTMLVideoElement
          let remoteParticipantPresent = false;
          availableVideoInputs = [];
          let activeVideoDeviceId = null;
          let localVideoHealthTimer = null;

          function effectiveEmptySlots(count, cols) {
            const remainder = count % cols;
            if (remainder === 0) return 0;
            if (remainder === 1) return 0;
            return cols - remainder;
          }

          function computeGridCols(count) {
            const width = stage.clientWidth || window.innerWidth || 1024;
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
              setStatus(remoteTiles.size === 1 ? 'Connected with participant' : 'Connected with ' + remoteTiles.size + ' participants');
              return;
            }

            if (remoteParticipantPresent) {
              setStatus('Connected with participant (audio only)');
              return;
            }

            setStatus('In call lobby: waiting for the other person to join...');
          }

          function ensureLocalVideoTile() {
            if (!config.videoEnabled || isVideoMuted || localVideoBound) {
              return;
            }
            if (typeof audioVideo.startLocalVideoTile === 'function') {
              audioVideo.startLocalVideoTile();
              localVideoStartAttempts += 1;
              report('info', 'Requested local video tile start (attempt ' + localVideoStartAttempts + ')');

              if (localVideoStartAttempts < 3) {
                if (localVideoRetryTimer) {
                  clearTimeout(localVideoRetryTimer);
                }
                localVideoRetryTimer = setTimeout(() => {
                  if (!localVideoBound) {
                    ensureLocalVideoTile();
                  }
                }, 1200);
              }
            }
          }

          async function recoverVideoPublish() {
            if (!config.videoEnabled || isVideoMuted || localVideoBound) {
              return;
            }

            videoPublishRecoveryAttempts += 1;
            report('warn', 'Attempting video publish recovery #' + videoPublishRecoveryAttempts);

            try {
              await switchVideoInput('recovery');
            } catch (videoRecoveryErr) {
              report('warn', 'Video input recovery failed: ' + String(videoRecoveryErr));
            }

            ensureLocalVideoTile();

            if (!localVideoBound && videoPublishRecoveryAttempts < 2) {
              setTimeout(() => {
                if (!localVideoBound) {
                  recoverVideoPublish();
                }
              }, 2000);
            }
          }

          async function selectVideoInput(deviceId) {
            if (!deviceId) return false;
            if (typeof audioVideo.startVideoInput === 'function') {
              await audioVideo.startVideoInput(deviceId);
              activeVideoDeviceId = deviceId;
              return true;
            }
            if (typeof audioVideo.chooseVideoInputDevice === 'function') {
              await audioVideo.chooseVideoInputDevice(deviceId);
              activeVideoDeviceId = deviceId;
              return true;
            }
            return false;
          }

          async function switchVideoInput(reason) {
            if (!config.videoEnabled) return false;

            if (!availableVideoInputs || availableVideoInputs.length === 0) {
              availableVideoInputs = await audioVideo.listVideoInputDevices();
            }

            if (!availableVideoInputs || availableVideoInputs.length === 0) {
              report('warn', 'No video input devices available during ' + reason);
              return false;
            }

            let startIndex = 0;
            if (activeVideoDeviceId) {
              const currentIndex = availableVideoInputs.findIndex(
                (input) => input.deviceId === activeVideoDeviceId,
              );
              if (currentIndex >= 0) {
                startIndex = (currentIndex + 1) % availableVideoInputs.length;
              }
            }

            for (let offset = 0; offset < availableVideoInputs.length; offset += 1) {
              const candidate = availableVideoInputs[(startIndex + offset) % availableVideoInputs.length];
              try {
                const selected = await selectVideoInput(candidate.deviceId);
                if (selected) {
                  report('info', 'Switched video input for ' + reason + ': ' + candidate.deviceId);
                  return true;
                }
              } catch (switchErr) {
                report('warn', 'Video input switch failed for ' + candidate.deviceId + ': ' + String(switchErr));
              }
            }

            return false;
          }

          switchVideoInputRef = switchVideoInput;

          function scheduleLocalVideoHealthCheck() {
            if (!config.videoEnabled || isVideoMuted) return;
            if (localVideoHealthTimer) {
              clearTimeout(localVideoHealthTimer);
              localVideoHealthTimer = null;
            }

            localVideoHealthTimer = setTimeout(async () => {
              const isBlackPreview =
                !localVideoBound ||
                localVideo.readyState < 2 ||
                localVideo.videoWidth === 0 ||
                localVideo.videoHeight === 0;

              if (!isBlackPreview) {
                return;
              }

              report('warn', 'Local video health check failed (black/empty preview), trying camera failover');
              const switched = await switchVideoInput('health-check');
              if (switched) {
                localVideoBound = false;
                ensureLocalVideoTile();
              }
            }, 2500);
          }

          async function setLocalAudioMuted(muted) {
            try {
              if (muted) {
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
              isAudioMuted = muted;
              if (shouldAutoSentimentCapture) {
                if (muted) {
                  stopAutoSentimentCapture();
                } else {
                  await startAutoSentimentCapture();
                }
              }
              updateControlButtons();
              emitSentimentChannelState('voice', muted, 'embed-control');
              report('info', 'Local audio ' + (muted ? 'muted' : 'unmuted'));
            } catch (audioToggleErr) {
              report('warn', 'Failed to toggle local audio: ' + String(audioToggleErr));
            }
          }

          async function setLocalVideoMuted(muted) {
            try {
              if (muted) {
                if (typeof audioVideo.stopLocalVideoTile === 'function') {
                  audioVideo.stopLocalVideoTile();
                }
                localVideoBound = false;
                isVideoMuted = true;
                if (sentimentVideoTimer) {
                  clearInterval(sentimentVideoTimer);
                  sentimentVideoTimer = null;
                }
              } else {
                if (!activeVideoDeviceId && typeof audioVideo.listVideoInputDevices === 'function') {
                  availableVideoInputs = await audioVideo.listVideoInputDevices();
                  if (availableVideoInputs.length > 0) {
                    await selectVideoInput(availableVideoInputs[0].deviceId);
                  }
                }
                if (typeof audioVideo.startLocalVideoTile === 'function') {
                  audioVideo.startLocalVideoTile();
                }
                ensureLocalVideoTile();
                isVideoMuted = false;
                if (shouldAutoSentimentCapture) {
                  startVideoSentimentCapture();
                }
              }
              updateControlButtons();
              emitSentimentChannelState('video', muted, 'embed-control');
              report('info', 'Local video ' + (muted ? 'stopped' : 'started'));
            } catch (videoToggleErr) {
              report('warn', 'Failed to toggle local video: ' + String(videoToggleErr));
            }
          }

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
                element.muted = true;
              }

              const playPromise = element.play();
              if (playPromise && typeof playPromise.then === 'function') {
                await playPromise;
              }
            } catch (playErr) {
              report('warn', 'Video element play() failed for ' + kind + ' tile ' + tileId + ': ' + String(playErr));
            }
          }

          audioVideo.bindAudioElement(remoteAudio);
          updateControlButtons();

          if (micBtn) {
            micBtn.addEventListener('click', () => {
              setLocalAudioMuted(!isAudioMuted);
            });
          }
          if (camBtn) {
            camBtn.addEventListener('click', () => {
              setLocalVideoMuted(!isVideoMuted);
            });
          }
          if (switchCamBtn) {
            switchCamBtn.addEventListener('click', async () => {
              try {
                availableVideoInputs = await audioVideo.listVideoInputDevices();
                const switched = await switchVideoInput('manual-switch');
                if (switched) {
                  localVideoBound = false;
                  ensureLocalVideoTile();
                  report('info', 'Camera switched by user');
                } else {
                  report('warn', 'Unable to switch camera: no alternative device available');
                }
              } catch (switchErr) {
                report('warn', 'Manual camera switch failed: ' + String(switchErr));
              } finally {
                updateControlButtons();
              }
            });
          }
          if (endBtn) {
            endBtn.addEventListener('click', () => {
              stopAutoSentimentCapture();
              emitAction('end-call-request');
            });
          }

          meetingObserver = {
            audioVideoDidStart: () => {
              updateParticipantStatus();

              if (isAudioMuted) {
                setLocalAudioMuted(true);
              }

              if (!isVideoMuted) {
                ensureLocalVideoTile();
              } else if (typeof audioVideo.stopLocalVideoTile === 'function') {
                audioVideo.stopLocalVideoTile();
              }

              report('info', 'audioVideoDidStart');

              if (!isVideoMuted) {
                setTimeout(() => {
                  if (!localVideoBound && !isVideoMuted) {
                    recoverVideoPublish();
                  }
                }, 1800);
              }
            },
            audioVideoDidStop: (sessionStatus) => {
              setStatus('Disconnected');
              stopAutoSentimentCapture();
              if (localVideoRetryTimer) {
                clearTimeout(localVideoRetryTimer);
                localVideoRetryTimer = null;
              }
              if (localVideoHealthTimer) {
                clearTimeout(localVideoHealthTimer);
                localVideoHealthTimer = null;
              }
              report('warn', 'audioVideoDidStop: ' + (sessionStatus ? sessionStatus.statusCode() : 'unknown'));
            },
            videoTileDidUpdate: (tileState) => {
              if (!tileState.tileId || tileState.isContent) return;

              const tileAttendeeId = tileState.boundAttendeeId || tileState.attendeeId || '';
              const isLocalByAttendee = !!tileAttendeeId && tileAttendeeId === config.attendeeId;
              const isLocalTile = !!tileState.localTile || isLocalByAttendee;

              report(
                'info',
                'Tile update: id=' + tileState.tileId +
                ', localFlag=' + String(!!tileState.localTile) +
                ', attendee=' + (tileAttendeeId || 'unknown') +
                ', classifiedLocal=' + String(isLocalTile),
              );

              if (isLocalTile) {
                if (isVideoMuted) {
                  if (typeof audioVideo.stopLocalVideoTile === 'function') {
                    audioVideo.stopLocalVideoTile();
                  }
                  localVideoBound = false;
                  report('info', 'Local tile update ignored because video is muted by user intent');
                  return;
                }

                localVideoBound = true;
                if (localVideoRetryTimer) {
                  clearTimeout(localVideoRetryTimer);
                  localVideoRetryTimer = null;
                }
                if (localTileId !== tileState.tileId) {
                  localTileId = tileState.tileId;
                  bindAndPlayVideo(tileState.tileId, localVideo, 'local');
                }
                scheduleLocalVideoHealthCheck();
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
              if (tileId === localTileId) {
                localTileId = null;
                localVideoBound = false;
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
            }
          };

          audioVideo.addObserver(meetingObserver);

          if (typeof audioVideo.realtimeSubscribeToAttendeeIdPresence === 'function') {
            audioVideo.realtimeSubscribeToAttendeeIdPresence((attendeeId, present, externalUserId, dropped) => {
              if (!attendeeId || attendeeId === config.attendeeId) {
                return;
              }

              // Keep roster up-to-date so transcript events can resolve speaker names.
              if (present && externalUserId) {
                attendeeRoster[attendeeId] = externalUserId;
              }
              console.log('[CC-Transcript] Presence:', attendeeId, 'present='+present, 'externalUserId='+String(externalUserId||'(none)'));

              if (present) {
                remoteParticipantPresent = true;
              } else {
                remoteParticipantPresent = remoteTiles.size > 0;
              }

              updateParticipantStatus();
              report(
                'info',
                'Presence update: attendee=' + attendeeId +
                  ', present=' + String(!!present) +
                  ', dropped=' + String(!!dropped) +
                  ', externalUserId=' + String(externalUserId || ''),
              );
            });
          }

          if (config.audioEnabled) {
            const audioInputs = await audioVideo.listAudioInputDevices();
            report('info', 'Audio input devices: ' + audioInputs.length);
            if (audioInputs.length > 0) {
              let audioSelected = false;
              for (const input of audioInputs) {
                try {
                  if (typeof audioVideo.startAudioInput === 'function') {
                    await audioVideo.startAudioInput(input.deviceId);
                    audioSelected = true;
                    break;
                  } else if (typeof audioVideo.chooseAudioInputDevice === 'function') {
                    await audioVideo.chooseAudioInputDevice(input.deviceId);
                    audioSelected = true;
                    break;
                  } else {
                    report('warn', 'No supported audio input method found on audioVideo facade');
                    break;
                  }
                } catch (audioErr) {
                  report('warn', 'Audio device failed: ' + input.deviceId + ' (' + String(audioErr) + ')');
                }
              }

              if (!audioSelected) {
                report('warn', 'No audio input device could be started.');
              }
            }
          }

          if (config.videoEnabled) {
            availableVideoInputs = await audioVideo.listVideoInputDevices();
            report('info', 'Video input devices: ' + availableVideoInputs.length);
            if (availableVideoInputs.length > 0) {
              let videoSelected = false;
              for (const input of availableVideoInputs) {
                try {
                  const selected = await selectVideoInput(input.deviceId);
                  if (selected) {
                    videoSelected = true;
                    break;
                  }
                } catch (videoErr) {
                  report('warn', 'Video device failed: ' + input.deviceId + ' (' + String(videoErr) + ')');
                }
              }

              if (!videoSelected) {
                report('warn', 'No video input device could be started.');
              }
            } else {
              report('warn', 'Video is enabled but no video input devices were listed.');
            }
          }

          audioVideo.start();
          report('info', 'audioVideo.start() invoked');
          await startAutoSentimentCapture();

          if (config.videoEnabled && !isVideoMuted) {
            setTimeout(() => {
              if (!localVideoBound && !isVideoMuted) {
                ensureLocalVideoTile();
              }
            }, 900);
          }
        } catch (error) {
          stopAutoSentimentCapture();
          const msg = (error && error.message) ? error.message : String(error);
          setStatus('Media error: ' + msg);
          report('error', 'Media init failed: ' + msg);
          console.error('[CareConnect] Chime media init failed', error);
        }
      })();
    </script>
  </body>
</html>
''';
  }
}




