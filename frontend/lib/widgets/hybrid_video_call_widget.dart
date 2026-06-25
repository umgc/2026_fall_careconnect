import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as uh;
import 'package:go_router/go_router.dart';
import '../services/video_call_service.dart';
import '../services/auth_token_manager.dart';
import '../services/call_notification_service.dart';
import '../services/user_role_storage_service.dart';
import '../config/theme/app_theme.dart';
import '../widgets/sentiment_dashboard_widget.dart';
import '../widgets/chime_meeting_embed.dart';
import '../features/health/caregiver-patient-list/page/patient_details_page.dart';

/// HybridVideoCallWidget — video call screen with live sentiment monitoring.
///
/// Layout:
///   - Top 60%: Chime video call view
///   - Bottom 40%: Collapsible sentiment dashboard (bar graphs)
///
/// The sentiment panel is shown only for caregivers and updates
/// in real time as the backend pushes WebSocket sentiment-update messages.
class HybridVideoCallWidget extends StatefulWidget {
  final String userId;
  final String callId;
  final String? recipientId;
  final String? recipientRole;
  final String? userRole;
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool isInitiator;
  final String? userEmail;
  final String? userPhone;
  final String? userName;
  final String? recipientEmail;
  final String? recipientPhone;
  final String? recipientName;
  final String? callKind;
  final List<int>? contextPatientUserIds;
  final String? returnPatientDetailsId;
  final bool forcePatientDetailsOnExit;
  final bool returnAsCaregiver;

  const HybridVideoCallWidget({
    super.key,
    required this.userId,
    required this.callId,
    this.recipientId,
    this.recipientRole,
    this.userRole,
    this.isVideoEnabled = true,
    this.isAudioEnabled = true,
    this.isInitiator = false,
    this.userEmail,
    this.userPhone,
    this.userName,
    this.recipientEmail,
    this.recipientPhone,
    this.recipientName,
    this.callKind,
    this.contextPatientUserIds,
    this.returnPatientDetailsId,
    this.forcePatientDetailsOnExit = false,
    this.returnAsCaregiver = false,
  });

  @override
  State<HybridVideoCallWidget> createState() => _HybridVideoCallWidgetState();
}

class _HybridVideoCallWidgetState extends State<HybridVideoCallWidget> {
  static const String _sentimentModeRaw = String.fromEnvironment(
    'CARECONNECT_SENTIMENT_MODE',
    defaultValue: 'balanced',
  );

  static const int _realtimeIntervalMs = 6000;
  static const int _balancedIntervalMs = 15000;
  static const Duration _adaptiveSwitchCooldown = Duration(seconds: 30);
  static const int _restartFailureThreshold = 2;
  static const Duration _restartCooldown = Duration(seconds: 20);
  static const double _voiceResumeSpeechRatioThreshold = 0.08;
  static const double _voiceResumeLevelThreshold = 0.05;

  final VideoCallService _videoCallService = VideoCallService();

  ChimeCallSession? _callSession;
  bool _isLoading = true;
  String? _error;
  bool _sentimentPanelExpanded = true;
  bool _isCaregiverView = false;
  bool _isPatientView = false;
  bool _isCareTeamCall = false;
  bool _showCallRejectedSummary = false;
  String _rejectionSummaryText = 'The recipient declined the call.';
  bool _isRetryingRejectedCall = false;
  bool _isSendingAudioSample = false;
  bool _isSendingVideoSample = false;
  bool _isEndingCall = false;
  bool _isExitingCall = false;

  // Conference invite
  bool _isLoadingInvitees = false;

  // Recording
  bool _isRecording = false;
  bool _isTogglingRecording = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingElapsedTimer;
  Duration _recordingElapsed = Duration.zero;
  DateTime? _lastAudioSampleSentAt;
  DateTime? _lastVideoSampleSentAt;
  bool _localAudioEnabled = true;
  bool _localVideoEnabled = true;
  bool _hasSentInitialInvitation = false;
  int _adaptiveActiveIntervalMs = _realtimeIntervalMs;
  int _adaptiveFailureStreak = 0;
  int _adaptiveSuccessStreak = 0;
  DateTime? _lastAdaptiveSwitchAt;
  int _voiceFailureStreak = 0;
  int _videoFailureStreak = 0;
  DateTime? _lastVoiceRestartAt;
  DateTime? _lastVideoRestartAt;
  DateTime? _lastTranscriptSentAt;
  String? _lastTranscriptSample;
  String _transcriptCaptureStatus = 'AWAITING';

  // Latest sentiment data — updated via WebSocket push
  Map<String, dynamic> _sentimentData = {};

  String get _configuredSentimentMode => _sentimentModeRaw.trim().toLowerCase();

  bool get _isAdaptiveSentimentMode => _configuredSentimentMode == 'adaptive';

  bool get _isRealtimeSentimentMode => _configuredSentimentMode == 'realtime';

  int get _sentimentCaptureIntervalMs {
    if (_isAdaptiveSentimentMode) return _adaptiveActiveIntervalMs;
    return _isRealtimeSentimentMode ? _realtimeIntervalMs : _balancedIntervalMs;
  }

  String get _activeCaptureModeTag {
    if (_isAdaptiveSentimentMode) {
      return _adaptiveActiveIntervalMs <= _realtimeIntervalMs
          ? 'ADAPTIVE_REALTIME'
          : 'ADAPTIVE_BALANCED';
    }
    return _isRealtimeSentimentMode ? 'REALTIME' : 'BALANCED';
  }

  Duration get _sampleThrottleWindow {
    if (!kIsWeb) {
      // Mobile transcript APIs can be unavailable; keep voice-driven fallback
      // updates frequent enough for caregiver dashboards.
      return const Duration(seconds: 5);
    }
    final throttleMs = (_sentimentCaptureIntervalMs - 1000).clamp(3000, 14000);
    return Duration(milliseconds: throttleMs);
  }

  String _channelStatus(String channel) {
    final data = _sentimentData[channel.toLowerCase()];
    if (data is Map<String, dynamic>) {
      return ((data['status'] as String?) ?? '').toUpperCase();
    }
    if (data is Map) {
      return ((data['status'] as String?) ?? '').toUpperCase();
    }
    return '';
  }

  bool _shouldPrioritizeVoiceRecovery(double averageLevel, double speechRatio) {
    final status = _channelStatus('voice');
    final needsRecovery =
        status == 'QUIET' || status == 'DEGRADED' || status == 'AWAITING';
    if (!needsRecovery) {
      return false;
    }
    return speechRatio >= _voiceResumeSpeechRatioThreshold ||
        averageLevel >= _voiceResumeLevelThreshold;
  }

  int get _embedCaptureIntervalMs {
    if (_isAdaptiveSentimentMode) {
      return _realtimeIntervalMs;
    }
    return _sentimentCaptureIntervalMs;
  }

  @override
  void initState() {
    super.initState();
    _adaptiveActiveIntervalMs =
        (_isAdaptiveSentimentMode || _isRealtimeSentimentMode)
        ? _realtimeIntervalMs
        : _balancedIntervalMs;
    _loadCurrentRole();
    _initializeCall();
  }

  Future<void> _loadCurrentRole() async {
    try {
      final role = await _resolveCurrentRole();
      final isCaregiver = role?.toUpperCase() == 'CAREGIVER';
      final isPatient = role?.toUpperCase() == 'PATIENT';
      _isCareTeamCall = (widget.callKind ?? '').trim().toUpperCase() == 'CARE_TEAM';
      _videoCallService.setPatientSentimentSourceEnabled(isPatient && !_isCareTeamCall);
      if (!mounted) return;
      setState(() {
        _isCaregiverView = isCaregiver;
        _isPatientView = isPatient;
        if (!isCaregiver || _isCareTeamCall) {
          _sentimentPanelExpanded = false;
        }
      });
    } catch (_) {
      // Keep safe default (no analytics panel) if role cannot be loaded.
    }
  }

  Future<void> _initializeCall() async {
    try {
      if (mounted) {
        setState(() {
          _transcriptCaptureStatus = 'AWAITING';
        });
      }

      final role = await _resolveCurrentRole();
      final isCaregiverRole = role?.toUpperCase() == 'CAREGIVER';
      final isPatientRole = role?.toUpperCase() == 'PATIENT';
      _isCareTeamCall = (widget.callKind ?? '').trim().toUpperCase() == 'CARE_TEAM';

      if (mounted) {
        setState(() {
          _isCaregiverView = isCaregiverRole;
          _isPatientView = isPatientRole;
          if (!isCaregiverRole || _isCareTeamCall) {
            _sentimentPanelExpanded = false;
          }
        });
      }

      // Retrieve JWT from secure storage
      // Replace with your actual auth token retrieval
      final jwtToken = await _getJwtToken();

      await _videoCallService.initialize(
        userId: widget.userId,
        jwtToken: jwtToken,
        enablePatientSentimentCapture: isPatientRole && !_isCareTeamCall,
        onCallEnded: () {
          if (_showCallRejectedSummary) return;
          _exitCallScreen();
        },
        onSentimentUpdate: (data) {
          if (mounted) {
            setState(() => _sentimentData = data);
          }
        },
        onCallDeclined: (event) {
          if (!mounted || !widget.isInitiator) return;
          final declinedBy =
              (event['declinedByName'] ?? widget.recipientName ?? 'Recipient')
                  .toString();
          final reason = (event['reason'] ?? 'declined').toString().trim();
          final reasonSuffix = reason.isEmpty ? '' : ' ($reason)';

          setState(() {
            _showCallRejectedSummary = true;
            _isLoading = false;
            _rejectionSummaryText =
                '$declinedBy declined the call$reasonSuffix.';
          });
        },
      );

      final session = await _videoCallService.joinCall(
        callId: widget.callId,
        otherPartyId: widget.recipientId ?? '',
        isVideoEnabled: widget.isVideoEnabled,
        isAudioEnabled: widget.isAudioEnabled,
        callContextMetadata: {
          'callKind': (widget.callKind ?? 'general').trim().toUpperCase(),
          if (widget.contextPatientUserIds != null &&
              widget.contextPatientUserIds!.isNotEmpty)
            'contextPatientUserIds': widget.contextPatientUserIds,
        },
      );

      _videoCallService.setPatientSentimentSourceEnabled(
        isPatientRole && !_isCareTeamCall,
      );

      if (widget.isInitiator && !_hasSentInitialInvitation) {
        final recipientId = widget.recipientId?.trim();
        if (recipientId == null || recipientId.isEmpty) {
          throw Exception('Missing recipient ID for outgoing call.');
        }

        final currentRole = (role ?? '').toUpperCase();
        String recipientRole = (widget.recipientRole ?? '').trim().toUpperCase();
        if (recipientRole != 'PATIENT' && recipientRole != 'CAREGIVER') {
          recipientRole = currentRole == 'CAREGIVER'
            ? 'PATIENT'
            : 'CAREGIVER';
        }

        final invitationSent = await CallNotificationService.sendCallInvitation(
          recipientId: recipientId,
          recipientRole: recipientRole,
          callId: widget.callId,
          isVideoCall: widget.isVideoEnabled,
          callType: _isCareTeamCall ? 'care-team' : 'general',
        );

        if (!invitationSent) {
          await _videoCallService.endCall();
          throw Exception(
            'Unable to notify callee after joining the call room.',
          );
        }

        _hasSentInitialInvitation = true;
      }

      setState(() {
        _callSession = session;
        _isLoading = false;
        _localAudioEnabled = session.isAudioEnabled;
        _localVideoEnabled = session.isVideoEnabled;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<String> _getJwtToken() async {
    final token = await AuthTokenManager.getJwtToken();
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token found. Please log in again.');
    }
    return token;
  }

  @override
  void dispose() {
    _recordingElapsedTimer?.cancel();
    _videoCallService.dispose();
    super.dispose();
  }

  // ================================================================
  // RECORDING CONTROLS
  // ================================================================

  Future<void> _toggleRecording() async {
    if (_isTogglingRecording) return;
    setState(() => _isTogglingRecording = true);
    try {
      if (_isRecording) {
        await _videoCallService.stopRecording(widget.callId);
        _recordingElapsedTimer?.cancel();
        setState(() {
          _isRecording = false;
          _recordingStartedAt = null;
          _recordingElapsed = Duration.zero;
        });
      } else {
        await _videoCallService.startRecording(widget.callId);
        final started = DateTime.now();
        _recordingElapsedTimer?.cancel();
        _recordingElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _recordingElapsed = DateTime.now().difference(started);
          });
        });
        setState(() {
          _isRecording = true;
          _recordingStartedAt = started;
          _recordingElapsed = Duration.zero;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRecording
                ? 'Failed to stop recording.'
                : 'Recording is unavailable right now. Check the recording setup.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTogglingRecording = false);
    }
  }

  String _formatRecordingElapsed() {
    final s = _recordingElapsed.inSeconds;
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<String?> _resolveCurrentRole() async {
    final roleFromWidget = widget.userRole?.trim();
    if (roleFromWidget != null && roleFromWidget.isNotEmpty) {
      return roleFromWidget.toUpperCase();
    }

    final roleFromStorage = await UserRoleStorageService.instance.getUserRole();
    if (roleFromStorage != null && roleFromStorage.trim().isNotEmpty) {
      return roleFromStorage.trim().toUpperCase();
    }

    final session = await AuthTokenManager.getUserSession();
    final sessionRole = (session?['role'] as String?)?.trim();
    if (sessionRole != null && sessionRole.isNotEmpty) {
      return sessionRole.toUpperCase();
    }

    return null;
  }

  Future<void> _handleTranscriptSample(Map<String, dynamic> sample) async {
    if (_isCareTeamCall) {
      if (mounted && _transcriptCaptureStatus != 'DISABLED') {
        setState(() {
          _transcriptCaptureStatus = 'DISABLED';
        });
      }
      return;
    }

    if (_callSession == null) {
      return;
    }

    final trimmed = (sample['text'] ?? '').toString().trim();
    if (trimmed.length < 2) {
      return;
    }
    if (mounted && _transcriptCaptureStatus != 'CONNECTED') {
      setState(() {
        _transcriptCaptureStatus = 'CONNECTED';
      });
    }
    debugPrint(
      '[CareConnect][Transcript] sample accepted len=${trimmed.length} role=${_isPatientView ? 'PATIENT' : (_isCaregiverView ? 'CAREGIVER' : 'PARTICIPANT')}',
    );

    final now = DateTime.now();
    final sentRecently = _lastTranscriptSentAt != null &&
        now.difference(_lastTranscriptSentAt!) < const Duration(seconds: 3);
    if (sentRecently && _lastTranscriptSample == trimmed) {
      return;
    }

    final uploaded = await _videoCallService.sendTranscriptSegment(
      text: trimmed,
      speakerLabel: _resolveTranscriptSpeakerLabel(sample),
      startMs: _safeTranscriptMs(sample['startMs']),
      endMs: _safeTranscriptMs(sample['endMs']),
      source: (sample['source'] ?? 'chime-transcript').toString(),
    );

    if (uploaded) {
      _lastTranscriptSentAt = now;
      _lastTranscriptSample = trimmed;
    }
  }

  int? _safeTranscriptMs(dynamic value) {
    if (value is int) {
      return value >= 0 ? value : null;
    }
    if (value is num) {
      final rounded = value.round();
      return rounded >= 0 ? rounded : null;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  /// Decodes the speaker label from the Chime externalUserId encoded by the backend.
  ///
  /// Backend format: `{ROLE}_{First-LAST}_{userId}` e.g. `CAREGIVER_John-DOE_42`
  /// Display format: `John DOE`  (first name title-case, last name upper-case)
  /// Falls back to role name if no name segment is present.
  String _resolveTranscriptSpeakerLabel(Map<String, dynamic> sample) {
    final raw = (sample['speakerLabel'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      return _decodeExternalUserIdLabel(raw);
    }
    if (_isPatientView) return 'PATIENT';
    if (_isCaregiverView) return 'CAREGIVER';
    return 'PARTICIPANT';
  }

  static const _knownRoles = ['CAREGIVER', 'PATIENT', 'ADMIN', 'FAMILYMEMBER'];

  String _decodeExternalUserIdLabel(String raw) {
    // Format: ROLE_First-LAST_userId  (3 parts separated by underscores)
    // Also handles legacy ROLE_userId (2 parts) and plain ROLE (1 part).
    final parts = raw.split('_');
    final roleCandidate = parts[0].toUpperCase();
    final isKnownRole = _knownRoles.any((r) => roleCandidate.startsWith(r));

    if (!isKnownRole) return raw; // unknown format — return as-is

    // Try to extract the name segment (middle part when there are 3 parts)
    if (parts.length >= 3) {
      final nameSeg = parts[1]; // e.g. "John-DOE"
      if (nameSeg.isNotEmpty && nameSeg.contains(RegExp(r'[A-Za-z]'))) {
        return _formatNameSegment(nameSeg);
      }
    }

    // Fall back to role label
    if (roleCandidate.startsWith('CAREGIVER') || roleCandidate.startsWith('ADMIN')) {
      return 'CAREGIVER';
    }
    if (roleCandidate.startsWith('PATIENT')) return 'PATIENT';
    if (roleCandidate.startsWith('FAMILYMEMBER')) return 'FAMILY';
    return roleCandidate;
  }

  /// Converts "John-DOE" → "John DOE"
  String _formatNameSegment(String nameSeg) {
    final hyphenParts = nameSeg.split('-');
    if (hyphenParts.length == 1) {
      // Only first name
      final n = hyphenParts[0];
      return n.isEmpty ? nameSeg : n[0].toUpperCase() + n.substring(1).toLowerCase();
    }
    final first = hyphenParts[0];
    final last = hyphenParts.sublist(1).join(' ');
    final firstFormatted = first.isEmpty
        ? ''
        : first[0].toUpperCase() + first.substring(1).toLowerCase();
    return '$firstFormatted ${last.toUpperCase()}'.trim();
  }

  void _handleTranscriptStatus(String status, String? detail) {
    final normalized = status.trim().toUpperCase();
    if (normalized.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _transcriptCaptureStatus = normalized;
    });
  }

  Future<void> _handleChannelFailure(String channel) async {
    if (!_isPatientView || _callSession == null) {
      return;
    }

    if (channel == 'voice') {
      _voiceFailureStreak += 1;
      if (_voiceFailureStreak >= _restartFailureThreshold &&
          _shouldRestartChannel(_lastVoiceRestartAt)) {
        _voiceFailureStreak = 0;
        await _restartSentimentChannel('voice');
      }
      return;
    }

    if (channel == 'video') {
      _videoFailureStreak += 1;
      if (_videoFailureStreak >= _restartFailureThreshold &&
          _shouldRestartChannel(_lastVideoRestartAt)) {
        _videoFailureStreak = 0;
        await _restartSentimentChannel('video');
      }
      return;
    }

    if (channel == 'text') {
      return;
    }
  }

  bool _shouldRestartChannel(DateTime? lastRestartAt) {
    if (lastRestartAt == null) {
      return true;
    }
    return DateTime.now().difference(lastRestartAt) >= _restartCooldown;
  }

  Future<void> _restartSentimentChannel(String channel) async {
    final restarted = await requestChimeSentimentChannelRestart(
      channel: channel,
      meetingId: _callSession?.meetingId,
    );

    if (!restarted) {
      return;
    }

    final now = DateTime.now();
    if (channel == 'voice') {
      _lastVoiceRestartAt = now;
      _lastAudioSampleSentAt = null;
    } else if (channel == 'video') {
      _lastVideoRestartAt = now;
      _lastVideoSampleSentAt = null;
    }
  }

  void _maybeSwitchAdaptiveInterval({
    required bool success,
    required Duration requestLatency,
  }) {
    if (!_isAdaptiveSentimentMode) return;

    final now = DateTime.now();
    final switchedRecently =
        _lastAdaptiveSwitchAt != null &&
        now.difference(_lastAdaptiveSwitchAt!) < _adaptiveSwitchCooldown;

    final isSlowSuccess =
        success && requestLatency > const Duration(milliseconds: 2500);
    final effectiveFailure = !success || isSlowSuccess;

    if (effectiveFailure) {
      _adaptiveFailureStreak += 1;
      _adaptiveSuccessStreak = 0;
    } else {
      _adaptiveSuccessStreak += 1;
      _adaptiveFailureStreak = 0;
    }

    if (!switchedRecently &&
        _adaptiveActiveIntervalMs == _realtimeIntervalMs &&
        _adaptiveFailureStreak >= 2) {
      if (mounted) {
        setState(() {
          _adaptiveActiveIntervalMs = _balancedIntervalMs;
          _adaptiveFailureStreak = 0;
          _adaptiveSuccessStreak = 0;
          _lastAdaptiveSwitchAt = now;
        });
      } else {
        _adaptiveActiveIntervalMs = _balancedIntervalMs;
        _adaptiveFailureStreak = 0;
        _adaptiveSuccessStreak = 0;
        _lastAdaptiveSwitchAt = now;
      }
      return;
    }

    if (!switchedRecently &&
        _adaptiveActiveIntervalMs == _balancedIntervalMs &&
        _adaptiveSuccessStreak >= 6) {
      if (mounted) {
        setState(() {
          _adaptiveActiveIntervalMs = _realtimeIntervalMs;
          _adaptiveFailureStreak = 0;
          _adaptiveSuccessStreak = 0;
          _lastAdaptiveSwitchAt = now;
        });
      } else {
        _adaptiveActiveIntervalMs = _realtimeIntervalMs;
        _adaptiveFailureStreak = 0;
        _adaptiveSuccessStreak = 0;
        _lastAdaptiveSwitchAt = now;
      }
    }
  }

  Future<void> _handleVoiceMetricsSample(
    double averageLevel,
    double speechRatio,
    double variability,
  ) async {
    if (!_isPatientView || _isSendingAudioSample) return;

    final prioritizeRecovery =
        _shouldPrioritizeVoiceRecovery(averageLevel, speechRatio);
    final now = DateTime.now();
    if (!prioritizeRecovery &&
        _lastAudioSampleSentAt != null &&
        now.difference(_lastAudioSampleSentAt!) < _sampleThrottleWindow) {
      debugPrint(
        '[CareConnect][Sentiment][voice] throttled sample avg=$averageLevel ratio=$speechRatio var=$variability',
      );
      return;
    }

    if (prioritizeRecovery) {
      debugPrint(
        '[CareConnect][Sentiment][voice] prioritizing recovery sample avg=$averageLevel ratio=$speechRatio var=$variability',
      );
    }

    debugPrint(
      '[CareConnect][Sentiment][voice] processing sample avg=$averageLevel ratio=$speechRatio var=$variability',
    );

    _isSendingAudioSample = true;
    try {
      final startedAt = DateTime.now();
      final success = await _videoCallService.sendVoiceMetricsForAnalysis(
        averageLevel: averageLevel,
        speechRatio: speechRatio,
        variability: variability,
        captureMode: _activeCaptureModeTag,
      );

      _maybeSwitchAdaptiveInterval(
        success: success,
        requestLatency: DateTime.now().difference(startedAt),
      );

      if (success) {
        _lastAudioSampleSentAt = DateTime.now();
        _voiceFailureStreak = 0;
      } else {
        await _handleChannelFailure('voice');
      }
    } catch (_) {
      await _handleChannelFailure('voice');
    } finally {
      _isSendingAudioSample = false;
    }
  }

  Future<void> _handleVideoSample(String imageBase64) async {
    if (!_isPatientView || _isSendingVideoSample) return;
    if (imageBase64.isEmpty) return;

    final now = DateTime.now();
    if (_lastVideoSampleSentAt != null &&
        now.difference(_lastVideoSampleSentAt!) < _sampleThrottleWindow) {
      return;
    }

    _isSendingVideoSample = true;
    try {
      final startedAt = DateTime.now();
      final success = await _videoCallService.sendVideoFrameForAnalysis(
        imageBase64,
        captureMode: _activeCaptureModeTag,
      );

      _maybeSwitchAdaptiveInterval(
        success: success,
        requestLatency: DateTime.now().difference(startedAt),
      );

      if (success) {
        _lastVideoSampleSentAt = DateTime.now();
        _videoFailureStreak = 0;
      } else {
        await _handleChannelFailure('video');
      }
    } catch (_) {
      await _handleChannelFailure('video');
    } finally {
      _isSendingVideoSample = false;
    }
  }

  Future<void> _toggleLocalAudio() async {
    final nextMuted = _localAudioEnabled;
    final toggled = await requestChimeAudioToggle(
      muted: nextMuted,
      meetingId: _callSession?.meetingId,
    );
    if (!toggled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone toggle is not available for this session.'),
        ),
      );
      return;
    }
    setState(() {
      _localAudioEnabled = !_localAudioEnabled;
    });

    await _handleSentimentChannelState('voice', nextMuted);
  }

  Future<void> _toggleLocalVideo() async {
    final nextMuted = _localVideoEnabled;
    final toggled = await requestChimeVideoToggle(
      muted: nextMuted,
      meetingId: _callSession?.meetingId,
    );
    if (!toggled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera toggle is not available for this session.'),
        ),
      );
      return;
    }
    setState(() {
      _localVideoEnabled = !_localVideoEnabled;
    });
    await _handleSentimentChannelState('video', nextMuted);
  }

  Future<void> _handleSentimentChannelState(String channel, bool muted) async {
    if (!_isPatientView) {
      return;
    }

    await _videoCallService.updateSentimentChannelState(
      channel: channel,
      muted: muted,
      captureMode: _activeCaptureModeTag,
    );
  }

  Future<void> _switchCamera() async {
    final switched = await requestChimeCameraSwitch(
      meetingId: _callSession?.meetingId,
    );
    if (!switched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera switch is not available for this session.'),
        ),
      );
    }
  }

  // ================================================================
  // CONFERENCE — add participant to active call
  // ================================================================

  Future<void> _showAddParticipantDialog() async {
    if (_callSession == null) return;
    setState(() => _isLoadingInvitees = true);

    List<Map<String, dynamic>> invitees = [];
    try {
      invitees = await _videoCallService.getEligibleInvitees(widget.callId);
    } catch (_) {
      invitees = [];
    } finally {
      if (mounted) setState(() => _isLoadingInvitees = false);
    }

    if (!mounted) return;

    if (invitees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No available care-circle members to add.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Disable iframe pointer events so the Flutter dialog receives taps on web
    if (kIsWeb) {
      for (final el in uh.document.querySelectorAll('iframe')) {
        (el as uh.IFrameElement).style.pointerEvents = 'none';
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Participant'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select a care-circle member to join this call:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...invitees.map((person) {
                final name = (person['name'] ?? '').toString();
                final role = (person['role'] ?? '').toString();
                final relationship = (person['relationship'] as String?);
                final subtitle = role == 'FAMILY_MEMBER'
                    ? 'Family Member${relationship != null && relationship.isNotEmpty ? ' · $relationship' : ''}'
                    : 'Caregiver';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: role == 'FAMILY_MEMBER'
                        ? Colors.teal.shade100
                        : Colors.blue.shade100,
                    child: Icon(
                      role == 'FAMILY_MEMBER' ? Icons.people : Icons.medical_services,
                      size: 18,
                      color: role == 'FAMILY_MEMBER'
                          ? Colors.teal.shade700
                          : Colors.blue.shade700,
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _inviteParticipant(
                      userId: person['userId'].toString(),
                      name: name,
                    );
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Restore iframe pointer events after dialog closes
    if (kIsWeb) {
      for (final el in uh.document.querySelectorAll('iframe')) {
        (el as uh.IFrameElement).style.pointerEvents = '';
      }
    }
  }

  Future<void> _inviteParticipant({
    required String userId,
    required String name,
  }) async {
    final status = await _videoCallService.inviteParticipant(widget.callId, userId);
    if (!mounted) return;
    final String message;
    final Color bgColor;
    switch (status) {
      case 'invited':
      case 'offline':
        _videoCallService.trackParticipant(userId);
        message = status == 'invited'
            ? 'Invitation sent to $name.'
            : '$name is not available right now.';
        bgColor = status == 'invited'
            ? Colors.green.shade700
            : Colors.orange.shade700;
        break;
      default:
        message = 'Could not invite $name. Please try again.';
        bgColor = Colors.red.shade700;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgColor,
      ),
    );
  }

  Future<void> _exitCallScreen() async {
    if (_isExitingCall || !mounted) return;
    _isExitingCall = true;

    final returnPatientId = widget.returnPatientDetailsId?.trim();
    final shouldForcePatientDetails =
        widget.forcePatientDetailsOnExit &&
        returnPatientId != null &&
        returnPatientId.isNotEmpty;

    if (shouldForcePatientDetails && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }

    if (shouldForcePatientDetails) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PatientDetailsPage(
            patientId: returnPatientId,
            isCaregiver: widget.returnAsCaregiver,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
      return;
    }

    // Keep deep-link behavior consistent with web when there is no local back stack.
    context.go('/dashboard');
  }

  Future<void> _endCallAndExit() async {
    if (_isEndingCall || !mounted) return;

    setState(() {
      _isEndingCall = true;
    });

    try {
      await _videoCallService.endCall();
      await _exitCallScreen();
    } finally {
      if (mounted) {
        setState(() {
          _isEndingCall = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppTheme.videoCallBackgroundDarkTheme
        : AppTheme.videoCallBackground;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        automaticallyImplyLeading: false,
        title: Text(
          widget.recipientName != null
              ? 'Call with ${widget.recipientName}'
              : 'Video Call',
          style: const TextStyle(color: AppTheme.videoCallText),
        ),
        iconTheme: const IconThemeData(color: AppTheme.videoCallText),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_showCallRejectedSummary) return _buildCallRejectedSummary();
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_callSession == null) {
      return const Center(
        child: Text(
          'No active call session',
          style: TextStyle(color: AppTheme.videoCallText),
        ),
      );
    }
    return _buildCallLayout();
  }

  // ================================================================
  // MAIN LAYOUT — video on top, sentiment panel below
  // ================================================================

  Widget _buildCallLayout() {
    return Column(
      children: [
        // Recording consent banner — visible to all participants when active
        if (_isRecording) _buildRecordingConsentBanner(),

        // Video call area — takes remaining space above sentiment panel
        Expanded(
          flex: (_isCaregiverView && _sentimentPanelExpanded) ? 6 : 10,
          child: Stack(
            children: [
              Positioned.fill(child: _buildChimeView()),
            ],
          ),
        ),

        _buildCallControlsBar(),

        // Sentiment dashboard — collapsible
        if (_isCaregiverView)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _sentimentPanelExpanded ? null : 0,
            child: _sentimentPanelExpanded
                ? SentimentDashboardWidget(
                    sentimentData: _sentimentData,
                    callId: widget.callId,
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildCallRejectedSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedScale(
          scale: 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(alpha: 0.12),
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.redAccent,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Call Rejected',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.videoCallText,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _rejectionSummaryText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.videoCallTextSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Would you like to try calling again?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.videoCallTextSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isRetryingRejectedCall
                            ? null
                            : () {
                                if (Navigator.canPop(context)) {
                                  Navigator.of(context).pop();
                                }
                              },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Return'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRetryingRejectedCall
                            ? null
                            : _retryRejectedCall,
                        icon: _isRetryingRejectedCall
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _isRetryingRejectedCall ? 'Retrying…' : 'Try Again',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryRejectedCall() async {
    if (_isRetryingRejectedCall || !mounted) return;
    final recipientId = widget.recipientId;
    if (recipientId == null || recipientId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to retry: missing recipient info.'),
        ),
      );
      return;
    }

    setState(() {
      _isRetryingRejectedCall = true;
    });

    try {
      await _videoCallService.endCall();

      final newCallId = 'chime_call_${DateTime.now().millisecondsSinceEpoch}';

      if (!mounted) return;
      final role = Uri.encodeComponent((widget.userRole ?? '').toUpperCase());
      final userName = Uri.encodeComponent(widget.userName ?? '');
      final recipientName = Uri.encodeComponent(widget.recipientName ?? '');
      final recipientIdValue = Uri.encodeComponent(widget.recipientId ?? '');

      context.pushReplacement(
        '/video-call-chime'
        '?userId=${Uri.encodeComponent(widget.userId)}'
        '&callId=${Uri.encodeComponent(newCallId)}'
        '&recipientId=$recipientIdValue'
        '&userRole=$role'
        '&userName=$userName'
        '&recipientName=$recipientName'
        '&initiator=true'
        '&video=${widget.isVideoEnabled ? 'true' : 'false'}'
        '&audio=${widget.isAudioEnabled ? 'true' : 'false'}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRetryingRejectedCall = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retry failed. Please try again.')),
      );
    }
  }

  // ================================================================
  // CHIME VIDEO VIEW
  // For the demo, renders the Chime meeting join URL in a container.
  // In a full native implementation, this would use the Chime Flutter SDK.
  // ================================================================

  Widget _buildChimeView() {
    if (_callSession == null) return const SizedBox.shrink();

    // Keep transcript capture always enabled once meeting is active so it does
    // not depend on async role-resolution timing during screen init.
    final shouldEnableSentimentCapture = true;

    final mediaPlacement = _callSession!.mediaPlacement;
    final hasMediaEndpoints = mediaPlacement.values.whereType<String>().any(
      (value) => value.trim().isNotEmpty,
    );
    final isLocalMockSession = _callSession!.joinToken.startsWith(
      'local-join-token-',
    );

    if (hasMediaEndpoints && !isLocalMockSession) {
      return KeyedSubtree(
        key: ValueKey('chime-${_callSession!.meetingId}'),
        child: buildChimeMeetingEmbed(
          meetingId: _callSession!.meetingId,
          attendeeId: _callSession!.attendeeId,
          joinToken: _callSession!.joinToken,
          mediaPlacement: _callSession!.mediaPlacement,
          mediaRegion: _callSession!.mediaRegion,
          externalUserId: _callSession!.externalUserId,
          videoEnabled: _callSession!.isVideoEnabled,
          audioEnabled: _callSession!.isAudioEnabled,
          enableAutoSentimentCapture: shouldEnableSentimentCapture,
          sentimentCaptureIntervalMs: _embedCaptureIntervalMs,
          onEndCallRequested: () async {
            if (!mounted) return;
            await _endCallAndExit();
          },
          onTranscriptSample: _handleTranscriptSample,
          onTranscriptStatus: _handleTranscriptStatus,
          onVoiceMetricsSample: _handleVoiceMetricsSample,
          onVideoSample: _handleVideoSample,
          onSentimentChannelState: (channel, muted) {
            unawaited(_handleSentimentChannelState(channel, muted));
          },
        ),
      );
    }

    return Stack(
      children: [
        // In production: replace with flutter_inappwebview showing chimeUrl
        // or the native Chime Flutter SDK widget
        Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  isLocalMockSession
                      ? 'Connected to local mock session'
                      : 'Connected to call session',
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Participant connection status is not available in this environment.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Meeting: ${_callSession!.meetingId.substring(0, 8)}...',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 24),
                // Duration counter
                _CallDurationTimer(startTime: DateTime.now()),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildRecordingConsentBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade800.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Blinking red dot
          _BlinkingDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recording in progress — ${_formatRecordingElapsed()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          IconButton(
            tooltip: _localAudioEnabled
                ? 'Mute microphone'
                : 'Unmute microphone',
            onPressed: _toggleLocalAudio,
            icon: Icon(
              _localAudioEnabled ? Icons.mic : Icons.mic_off,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _localVideoEnabled ? 'Turn camera off' : 'Turn camera on',
            onPressed: _toggleLocalVideo,
            icon: Icon(
              _localVideoEnabled ? Icons.videocam : Icons.videocam_off,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
          ),
          const SizedBox(width: 8),
          // Add participant button (caregiver only)
          if (_isCaregiverView) ...[
            _isLoadingInvitees
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : IconButton(
                    tooltip: 'Add participant',
                    onPressed: _showAddParticipantDialog,
                    icon: const Icon(Icons.person_add, color: Colors.white),
                  ),
            const SizedBox(width: 8),
          ],
          // Record / stop-recording button (caregiver only)
          if (_isCaregiverView) ...[
            _isTogglingRecording
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : IconButton(
                    tooltip: _isRecording ? 'Stop recording' : 'Start recording',
                    onPressed: _toggleRecording,
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.fiber_manual_record,
                      color: _isRecording ? Colors.redAccent : Colors.white70,
                      size: 28,
                    ),
                  ),
            const SizedBox(width: 8),
          ],
          Container(
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'End call',
              onPressed: _isEndingCall ? null : _endCallAndExit,
              icon: const Icon(Icons.call_end, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // LOADING / ERROR STATES
  // ================================================================

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.videoCallText),
          const SizedBox(height: 16),
          const Text(
            'Connecting to call...',
            style: TextStyle(color: AppTheme.videoCallText),
          ),
          if (widget.recipientName != null) ...[
            const SizedBox(height: 8),
            Text(
              'with ${widget.recipientName}',
              style: const TextStyle(
                color: AppTheme.videoCallTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not connect to call',
              style: const TextStyle(
                color: AppTheme.videoCallText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: const TextStyle(
                color: AppTheme.videoCallTextSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// CALL DURATION TIMER — shows elapsed call time
// ================================================================

class _CallDurationTimer extends StatefulWidget {
  final DateTime startTime;
  const _CallDurationTimer({required this.startTime});

  @override
  State<_CallDurationTimer> createState() => _CallDurationTimerState();
}

class _CallDurationTimerState extends State<_CallDurationTimer> {
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticker,
      builder: (context, snapshot) {
        final elapsed = DateTime.now().difference(widget.startTime);
        final minutes = elapsed.inMinutes
            .remainder(60)
            .toString()
            .padLeft(2, '0');
        final seconds = elapsed.inSeconds
            .remainder(60)
            .toString()
            .padLeft(2, '0');
        return Text(
          '$minutes:$seconds',
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 24,
            fontFamily: 'monospace',
          ),
        );
      },
    );
  }
}

// ================================================================
// BLINKING DOT — used in the recording consent banner
// ================================================================

class _BlinkingDot extends StatefulWidget {
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: const Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
    );
  }
}


