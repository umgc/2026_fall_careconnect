import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

final Map<String, _StubMeetingController> _activeStubMeetings =
    <String, _StubMeetingController>{};

_StubMeetingController? _resolveController(String? meetingId) {
  if (meetingId != null && meetingId.trim().isNotEmpty) {
    return _activeStubMeetings[meetingId.trim()];
  }
  if (_activeStubMeetings.isEmpty) {
    return null;
  }
  return _activeStubMeetings.values.first;
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
  final controller = _activeStubMeetings.putIfAbsent(
    meetingId,
    () => _StubMeetingController(meetingId: meetingId),
  );

  return _ChimeMeetingEmbedStub(
    controller: controller,
    initialVideoEnabled: videoEnabled,
    initialAudioEnabled: audioEnabled,
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
  return controller.setAudioMuted(muted);
}

Future<bool> requestChimeVideoToggle({
  required bool muted,
  String? meetingId,
}) async {
  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.setVideoMuted(muted);
}

Future<bool> requestChimeCameraSwitch({String? meetingId}) async {
  final controller = _resolveController(meetingId);
  if (controller == null) {
    return false;
  }
  return controller.switchCamera();
}

Future<bool> requestChimeSentimentChannelRestart({
  required String channel,
  String? meetingId,
}) async {
  return false;
}

class _ChimeMeetingEmbedStub extends StatefulWidget {
  const _ChimeMeetingEmbedStub({
    required this.controller,
    required this.initialVideoEnabled,
    required this.initialAudioEnabled,
  });

  final _StubMeetingController controller;
  final bool initialVideoEnabled;
  final bool initialAudioEnabled;

  @override
  State<_ChimeMeetingEmbedStub> createState() => _ChimeMeetingEmbedStubState();
}

class _ChimeMeetingEmbedStubState extends State<_ChimeMeetingEmbedStub> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.ensureInitialized(
      videoEnabled: widget.initialVideoEnabled,
      audioEnabled: widget.initialAudioEnabled,
    );
  }

  @override
  void didUpdateWidget(covariant _ChimeMeetingEmbedStub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
      widget.controller.ensureInitialized(
        videoEnabled: widget.initialVideoEnabled,
        audioEnabled: widget.initialAudioEnabled,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _activeStubMeetings.remove(widget.controller.meetingId);
    widget.controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final camera = controller.cameraController;
    final isReady =
        camera != null && camera.value.isInitialized && !controller.videoMuted;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isReady)
            CameraPreview(camera)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  controller.errorMessage ??
                      'Camera preview unavailable in this session. You can still join and end the call.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                controller.statusLine,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StubMeetingController extends ChangeNotifier {
  _StubMeetingController({required this.meetingId});

  final String meetingId;
  CameraController? cameraController;
  List<CameraDescription> _cameras = <CameraDescription>[];
  int _cameraIndex = 0;

  bool _initialized = false;
  bool audioMuted = false;
  bool videoMuted = false;
  String? errorMessage;

  bool get hasMultipleCameras => _cameras.length > 1;

  String get statusLine {
    final mic = audioMuted ? 'Mic off' : 'Mic on';
    final cam = videoMuted ? 'Cam off' : 'Cam on';
    final lens = hasMultipleCameras ? 'Switchable camera' : 'Single camera';
    return '$mic | $cam | $lens';
  }

  Future<void> ensureInitialized({
    required bool videoEnabled,
    required bool audioEnabled,
  }) async {
    if (_initialized) return;

    audioMuted = !audioEnabled;
    videoMuted = !videoEnabled;

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        errorMessage = 'No camera is available on this emulator/device.';
      } else {
        await _setCamera(_cameraIndex);
        if (videoMuted) {
          await cameraController?.pausePreview();
        }
      }
    } catch (e) {
      errorMessage = 'Unable to initialize camera preview: $e';
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _setCamera(int index) async {
    final selected = _cameras[index];
    final previous = cameraController;
    final next = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: !audioMuted,
    );

    await next.initialize();
    cameraController = next;
    await previous?.dispose();
  }

  Future<bool> setAudioMuted(bool muted) async {
    audioMuted = muted;

    // Camera plugin only applies audio capture flag at controller creation,
    // so we recreate the active camera controller to reflect mic state.
    try {
      if (_cameras.isNotEmpty) {
        await _setCamera(_cameraIndex);
        if (videoMuted) {
          await cameraController?.pausePreview();
        }
      }
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Unable to apply microphone state: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setVideoMuted(bool muted) async {
    videoMuted = muted;
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) {
      notifyListeners();
      return false;
    }

    try {
      if (muted) {
        await controller.pausePreview();
      } else {
        await controller.resumePreview();
      }
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Unable to change camera state: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> switchCamera() async {
    if (_cameras.length < 2) {
      return false;
    }

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _setCamera(_cameraIndex);
      if (videoMuted) {
        await cameraController?.pausePreview();
      }
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Unable to switch camera: $e';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    final controller = cameraController;
    cameraController = null;
    controller?.dispose();
    super.dispose();
  }
}
