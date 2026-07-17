import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/environment_config.dart';
import '../services/call_notification_service.dart';

/// VideoCallService — AWS Chime SDK video call implementation.
///
/// Replaces legacy non-Chime call implementations.
///
/// Flow:
///   1. Flutter calls joinCall() after call is accepted
///   2. Service hits POST /api/v3/calls/{callId}/join on Spring Boot
///   3. Spring Boot creates/joins the Chime meeting and returns credentials
///   4. Flutter uses those credentials to render the call UI
///   5. Sentiment data is posted periodically during the call
///   6. endCall() hits POST /api/v3/calls/{callId}/end
///
/// Note on Chime rendering: The AWS Chime SDK for Flutter renders video
/// using a platform view. For the capstone demo, we render a web view
/// pointing to the Chime meeting URL, which works on both mobile and web.
class VideoCallService {
  static const Duration _sentimentStaleThreshold = Duration(seconds: 45);
  static const int _maxBufferedTranscriptSegments = 120;
  static const int _maxTranscriptChars = 1200;
  static const Duration _transcriptFlushInterval = Duration(seconds: 4);
  static final Set<String> _completedCallIds = <String>{};

  bool _isInitialized = false;
  bool _isInCall = false;
  bool _isPatientSentimentSource = false;
  String? _currentCallId;
  String? _otherPartyId;
  final Set<String> _participantUserIds = <String>{};
  Map<String, dynamic>? _callContextMetadata;
  String? _jwtToken;
  DateTime? _callStartedAt;
  int _lastTranscriptEndMs = 0;

  // Chime meeting credentials returned by the backend
  Map<String, dynamic>? _meetingCredentials;

  // Callbacks
  VoidCallback? _onCallEnded;
  Function(Map<String, dynamic>)? _onSentimentUpdate;
  Function(Map<String, dynamic>)? _onCallDeclined;

  // Sentiment posting timer — sends analysis data every 15 seconds
  Timer? _sentimentTimer;
  Timer? _transcriptFlushTimer;
  bool _transcriptFlushInProgress = false;
  final List<_BufferedTranscriptSegment> _pendingTranscriptSegments = [];

  // Stream for sentiment updates received via WebSocket
  StreamSubscription? _wsSubscription;

  // Aggregated sentiment state used by caregiver dashboard UI
  final Map<String, dynamic> _aggregatedSentiment = {};

  // ================================================================
  // INITIALIZE
  // ================================================================

  Future<void> initialize({
    required String userId,
    required String jwtToken,
    required bool enablePatientSentimentCapture,
    VoidCallback? onCallEnded,
    Function(Map<String, dynamic>)? onSentimentUpdate,
    Function(Map<String, dynamic>)? onCallDeclined,
  }) async {
    _jwtToken = jwtToken;
    _onCallEnded = onCallEnded;
    _onSentimentUpdate = onSentimentUpdate;
    _onCallDeclined = onCallDeclined;
    _isPatientSentimentSource = enablePatientSentimentCapture;
    _isInitialized = true;

    // Listen for sentiment updates pushed via WebSocket
    _wsSubscription = CallNotificationService.incomingCallStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'sentiment-update' && _onSentimentUpdate != null) {
        final merged = _mergeSentimentUpdate(data);
        _onSentimentUpdate!(merged);
      }
      if (type == 'sentiment-channel-state' && _onSentimentUpdate != null) {
        final merged = _mergeChannelStateEvent(data);
        _onSentimentUpdate!(merged);
      }
      if (type == 'call-declined' && _onCallDeclined != null) {
        final declinedCallId = (data['callId'] ?? '').toString();
        if (declinedCallId.isNotEmpty &&
            (_currentCallId == null || declinedCallId == _currentCallId)) {
          _onCallDeclined!(data);
        }
      }
      if (type == 'call-ended') {
        _handleRemoteCallEnd();
      }
    });

    debugPrint('✅ VideoCallService initialized for user: $userId');
  }

  // ================================================================
  // JOIN CALL
  // Both initiator and recipient call this after call is accepted
  // ================================================================

  Future<ChimeCallSession> joinCall({
    required String callId,
    required String otherPartyId,
    required bool isVideoEnabled,
    required bool isAudioEnabled,
    Map<String, dynamic>? callContextMetadata,
  }) async {
    if (!_isInitialized) throw Exception('VideoCallService not initialized');
    final normalizedCallId = callId.trim();
    if (_completedCallIds.contains(normalizedCallId)) {
      throw Exception('This call has already ended.');
    }

    _currentCallId = normalizedCallId;
    _otherPartyId = otherPartyId;
    _participantUserIds.clear();
    trackParticipant(otherPartyId);
    _callContextMetadata = callContextMetadata == null
        ? null
        : Map<String, dynamic>.from(callContextMetadata);
    _isInCall = true;
    _callStartedAt = DateTime.now();
    _lastTranscriptEndMs = 0;
    _aggregatedSentiment.clear();
    _pendingTranscriptSegments.clear();
    _seedAwaitingSentimentState();
    _startTranscriptFlushTimer();

    debugPrint('📹 Joining Chime call: $normalizedCallId');

    try {
      final requestBody =
          (_callContextMetadata == null || _callContextMetadata!.isEmpty)
          ? null
          : jsonEncode(_callContextMetadata);
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.baseUrl}/api/v3/calls/$normalizedCallId/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: requestBody,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to join call: ${response.statusCode} ${response.body}',
        );
      }

      _meetingCredentials = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('✅ Chime meeting credentials received for call: $callId');

      // Combined sentiment is now posted from real channel capture flow
      // (transcript/voice/video). Do not send periodic empty combined payloads.

      return ChimeCallSession(
        callId: normalizedCallId,
        meetingId: _meetingCredentials!['meetingId'] as String,
        attendeeId: _meetingCredentials!['attendeeId'] as String,
        joinToken: _meetingCredentials!['joinToken'] as String,
        mediaPlacement:
            _meetingCredentials!['mediaPlacement'] as Map<String, dynamic>,
        mediaRegion: _meetingCredentials!['mediaRegion'] as String?,
        externalUserId: _meetingCredentials!['externalUserId'] as String?,
        isVideoEnabled: isVideoEnabled,
        isAudioEnabled: isAudioEnabled,
      );
    } catch (e) {
      _isInCall = false;
      _callStartedAt = null;
      _lastTranscriptEndMs = 0;
      _callContextMetadata = null;
      _stopTranscriptFlushTimer();
      debugPrint('❌ Failed to join Chime call: $e');
      rethrow;
    }
  }

  // ================================================================
  // END CALL
  // ================================================================

  Future<void> endCall() async {
    if (!_isInCall || _currentCallId == null) {
      CallNotificationService.clearActiveCall();
      return;
    }

    final callId = _currentCallId!;
    debugPrint('📴 Ending call: $callId');

    _sentimentTimer?.cancel();
    await _flushPendingTranscriptSegments(
      callIdOverride: callId,
      maxAttempts: 3,
      respectInCallState: false,
    );
    _stopTranscriptFlushTimer();

    String endStatus = 'ended';

    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/end'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'otherPartyId': _otherPartyId,
          if (_participantUserIds.isNotEmpty)
            'participantUserIds': _participantUserIds.toList(),
          ...?_callContextMetadata,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        endStatus = ((body['status'] as String?) ?? 'ended').trim().toLowerCase();
      } else {
        debugPrint(
          'Backend returned ${response.statusCode} while ending call: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error notifying backend of call end: $e');
    }

    _resetLocalCallState(callId: callId, markCompleted: endStatus == 'ended');
    _onCallEnded?.call();
  }

  // ================================================================
  // SENTIMENT — TEXT
  // Called when a chat message is sent during the call
  // ================================================================

  Future<bool> sendTextForAnalysis(String text, {String? captureMode}) async {
    if (!_isPatientSentimentSource || !_isInCall || _currentCallId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.baseUrl}/api/v3/calls/$_currentCallId/sentiment/text',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'text': text,
          'otherPartyId': _otherPartyId,
          'captureMode': captureMode,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }

      debugPrint(
        '⚠️ Text sentiment request failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('⚠️ Text sentiment error: $e');
      return false;
    }
  }

  Future<bool> sendTranscriptSegment({
    required String text,
    String? speakerLabel,
    int? startMs,
    int? endMs,
    String? source,
  }) async {
    if (!_isInCall || _currentCallId == null) {
      return false;
    }

    var trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.length > _maxTranscriptChars) {
      trimmed = trimmed.substring(0, _maxTranscriptChars);
    }
    final resolvedEndMs = _resolveTranscriptEndMs(endMs);
    final resolvedStartMs =
        _resolveTranscriptStartMs(trimmed, startMs, resolvedEndMs);
    if (resolvedEndMs != null && resolvedEndMs > _lastTranscriptEndMs) {
      _lastTranscriptEndMs = resolvedEndMs;
    }

    _enqueueTranscriptSegment(
      _BufferedTranscriptSegment(
        callId: _currentCallId!,
        speakerLabel: speakerLabel ?? 'PATIENT',
        text: trimmed,
        startMs: resolvedStartMs,
        endMs: resolvedEndMs,
        source: source ?? 'chime-transcript',
      ),
    );
    debugPrint(
      '[CareConnect][Transcript] buffered len=${trimmed.length} queue=${_pendingTranscriptSegments.length}',
    );
    unawaited(_flushPendingTranscriptSegments());
    return true;
  }

  Future<bool> sendVoiceMetricsForAnalysis({
    required double averageLevel,
    required double speechRatio,
    required double variability,
    String? captureMode,
  }) async {
    if (!_isPatientSentimentSource || !_isInCall || _currentCallId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.baseUrl}/api/v3/calls/$_currentCallId/sentiment/voice',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'averageLevel': averageLevel.toStringAsFixed(4),
          'speechRatio': speechRatio.toStringAsFixed(4),
          'variability': variability.toStringAsFixed(4),
          'audioFormat': 'chime-metrics',
          'otherPartyId': _otherPartyId,
          'captureMode': captureMode,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint(
          '✅ Voice sentiment posted: call=$_currentCallId avg=${averageLevel.toStringAsFixed(3)} ratio=${speechRatio.toStringAsFixed(3)} var=${variability.toStringAsFixed(3)}',
        );
        return true;
      }

      debugPrint(
        '⚠️ Voice metrics sentiment request failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('⚠️ Voice metrics sentiment error: $e');
      return false;
    }
  }

  // ================================================================
  // SENTIMENT — VIDEO FRAME
  // Called with a base64 JPEG frame capture every ~15 seconds
  // ================================================================

  Future<bool> sendVideoFrameForAnalysis(
    String imageBase64, {
    String? captureMode,
  }) async {
    if (!_isPatientSentimentSource || !_isInCall || _currentCallId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvironmentConfig.baseUrl}/api/v3/calls/$_currentCallId/sentiment/video',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'imageBase64': imageBase64,
          'imageFormat': 'jpeg',
          'otherPartyId': _otherPartyId,
          'captureMode': captureMode,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }

      debugPrint(
        '⚠️ Video sentiment request failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('⚠️ Video sentiment error: $e');
      return false;
    }
  }

  Future<bool> updateSentimentChannelState({
    required String channel,
    required bool muted,
    String? captureMode,
  }) async {
    if (!_isPatientSentimentSource || !_isInCall || _currentCallId == null) {
      return false;
    }

    if (_otherPartyId == null || _otherPartyId!.trim().isEmpty) {
      return false;
    }

    return CallNotificationService.sendSentimentChannelState(
      callId: _currentCallId!,
      otherPartyId: _otherPartyId!,
      channel: channel,
      muted: muted,
      captureMode: captureMode,
    );
  }

  // ================================================================
  // PRIVATE
  // ================================================================

  void _startSentimentTimer() {
    _sentimentTimer?.cancel();
  }

  void _startTranscriptFlushTimer() {
    _stopTranscriptFlushTimer();
    _transcriptFlushTimer = Timer.periodic(_transcriptFlushInterval, (_) {
      unawaited(_flushPendingTranscriptSegments());
    });
  }

  void _stopTranscriptFlushTimer() {
    _transcriptFlushTimer?.cancel();
    _transcriptFlushTimer = null;
  }

  Future<void> _postCombinedSentiment() async {}

  void _handleRemoteCallEnd() {
    if (!_isInCall) return;
    debugPrint('📴 Remote party ended the call');
    final callId = _currentCallId;
    unawaited(_flushPendingTranscriptSegments(
      callIdOverride: callId,
      maxAttempts: 2,
      respectInCallState: false,
    ));
    _resetLocalCallState(callId: callId, markCompleted: true);
    _onCallEnded?.call();
  }

  void _resetLocalCallState({
    required String? callId,
    required bool markCompleted,
  }) {
    _sentimentTimer?.cancel();
    _stopTranscriptFlushTimer();
    _isInCall = false;
    _currentCallId = null;
    _otherPartyId = null;
    _participantUserIds.clear();
    _callContextMetadata = null;
    _callStartedAt = null;
    _lastTranscriptEndMs = 0;
    _meetingCredentials = null;
    _aggregatedSentiment.clear();
    _pendingTranscriptSegments.clear();
    final normalizedCallId = callId?.trim();
    if (markCompleted && normalizedCallId != null && normalizedCallId.isNotEmpty) {
      _completedCallIds.add(normalizedCallId);
    }
    CallNotificationService.clearActiveCall(normalizedCallId);
  }

  void _enqueueTranscriptSegment(_BufferedTranscriptSegment segment) {
    _pendingTranscriptSegments.add(segment);
    if (_pendingTranscriptSegments.length > _maxBufferedTranscriptSegments) {
      _pendingTranscriptSegments.removeAt(0);
    }
  }

  Future<void> _flushPendingTranscriptSegments({
    String? callIdOverride,
    int maxAttempts = 1,
    bool respectInCallState = true,
  }) async {
    if (_transcriptFlushInProgress) {
      return;
    }
    if (_pendingTranscriptSegments.isEmpty) {
      return;
    }
    if (_jwtToken == null || _jwtToken!.isEmpty) {
      return;
    }
    if (respectInCallState && !_isInCall) {
      return;
    }

    final activeCallId = callIdOverride ?? _currentCallId;
    if (activeCallId == null || activeCallId.trim().isEmpty) {
      return;
    }

    _transcriptFlushInProgress = true;
    try {
      var attempts = 0;
      while (_pendingTranscriptSegments.isNotEmpty && attempts < maxAttempts) {
        attempts += 1;
        final segment = _pendingTranscriptSegments.first;
        if (segment.callId != activeCallId) {
          _pendingTranscriptSegments.removeAt(0);
          continue;
        }

        try {
          final response = await http
              .post(
                Uri.parse(
                  '${EnvironmentConfig.baseUrl}/api/v3/calls/${segment.callId}/transcript/segments',
                ),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $_jwtToken',
                },
                body: jsonEncode({
                  'speakerLabel': segment.speakerLabel,
                  'text': segment.text,
                  'startMs': segment.startMs,
                  'endMs': segment.endMs,
                  'source': segment.source,
                }),
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            _pendingTranscriptSegments.removeAt(0);
            attempts = 0;
            continue;
          }

          debugPrint(
            '⚠️ Transcript upload failed: status=${response.statusCode} callId=${segment.callId}',
          );

          if (response.statusCode == 400) {
            _pendingTranscriptSegments.removeAt(0);
            continue;
          }
          break;
        } catch (_) {
          break;
        }
      }
    } finally {
      _transcriptFlushInProgress = false;
    }
  }

  Map<String, dynamic> _mergeSentimentUpdate(Map<String, dynamic> event) {
    final payload = (event['sentiment'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(event['sentiment'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final captureMode = (event['captureMode'] as String?)?.trim();

    final now = DateTime.now().toUtc();

    if (payload.isEmpty) {
      _markStaleChannels(now);
      _aggregatedSentiment['overall'] = _buildOverallFromChannels();
      return Map<String, dynamic>.from(_aggregatedSentiment);
    }

    final channel = (payload['channel'] as String?)?.toLowerCase();
    final hasPerChannelShape =
        payload.containsKey('text') ||
        payload.containsKey('voice') ||
        payload.containsKey('video') ||
        payload.containsKey('overall');

    if (hasPerChannelShape) {
      for (final key in ['text', 'voice', 'video', 'overall']) {
        final section = payload[key];
        if (section is Map<String, dynamic>) {
          _aggregatedSentiment[key] = _normalizeSentimentSection(
            key,
            Map<String, dynamic>.from(section),
            now,
          );
        }
      }
    } else if (channel == 'text' || channel == 'voice' || channel == 'video') {
      debugPrint(
        '[CareConnect][Sentiment] update channel=$channel score=${payload['score']} label=${payload['label']} fallback=${payload['fallback']}',
      );
      _aggregatedSentiment[channel!] = _normalizeSentimentSection(
        channel,
        payload,
        now,
      );
    }

    _markStaleChannels(now);
    _aggregatedSentiment['overall'] = _buildOverallFromChannels();
    if (captureMode != null && captureMode.isNotEmpty) {
      _aggregatedSentiment['_captureMode'] = captureMode.toUpperCase();
    }

    return Map<String, dynamic>.from(_aggregatedSentiment);
  }

  Map<String, dynamic> _mergeChannelStateEvent(Map<String, dynamic> event) {
    final channel = (event['channel'] as String?)?.trim().toLowerCase();
    if (channel != 'text' && channel != 'voice' && channel != 'video') {
      return Map<String, dynamic>.from(_aggregatedSentiment);
    }

    final muted = event['muted'] == true;
    final incomingStatus = (event['status'] as String?)?.trim().toUpperCase();
    final isQuiet = incomingStatus == 'QUIET';
    final now = DateTime.now().toUtc();
    final existing = _aggregatedSentiment[channel] is Map<String, dynamic>
        ? Map<String, dynamic>.from(
            _aggregatedSentiment[channel] as Map<String, dynamic>,
          )
        : <String, dynamic>{};

    final score = (existing['score'] as num?)?.toDouble() ?? 0.5;
    final label = _normalizeClinicalLabel(
      (existing['label'] as String?),
      score,
    );

    final resolvedStatus = isQuiet
        ? 'QUIET'
        : (muted ? 'MUTED' : 'AWAITING');
    final resolvedNotes = (event['notes'] as String?)?.trim();

    _aggregatedSentiment[channel!] = {
      'score': score,
      'label': label,
      'notes': resolvedNotes?.isNotEmpty == true
          ? resolvedNotes
          : (isQuiet
              ? 'No speech detected in this window.'
              : (muted
                  ? 'Channel Muted'
                  : 'Awaiting ${channel.toLowerCase()} sentiment sample.')),
      'status': resolvedStatus,
      'channel': channel,
      'updatedAt': now.toIso8601String(),
      'stale': false,
      'confidence': isQuiet ? 0.0 : (muted ? 0.0 : 0.5),
    };

    _markStaleChannels(now);
    _aggregatedSentiment['overall'] = _buildOverallFromChannels();

    final captureMode = (event['captureMode'] as String?)?.trim();
    if (captureMode != null && captureMode.isNotEmpty) {
      _aggregatedSentiment['_captureMode'] = captureMode.toUpperCase();
    }

    return Map<String, dynamic>.from(_aggregatedSentiment);
  }

  Map<String, dynamic> _buildOverallFromChannels() {
    final channels = ['voice', 'video'];
    var scoreSum = 0.0;
    var count = 0;
    var hasDegraded = false;
    var hasAwaiting = false;

    for (final key in channels) {
      final channelData = _aggregatedSentiment[key];
      if (channelData is Map<String, dynamic>) {
        final status = (channelData['status'] as String? ?? 'AWAITING')
            .toUpperCase();
        if (status == 'DEGRADED') hasDegraded = true;
        if (status == 'AWAITING' || status == 'MUTED') hasAwaiting = true;
        if (status != 'COMPLETED') {
          continue;
        }

        final score = (channelData['score'] as num?)?.toDouble();
        if (score != null) {
          scoreSum += score;
          count += 1;
        }
      }
    }

    if (count == 0) {
      return {
        'score': 0.5,
        'label': 'ANXIOUS',
        'status': hasDegraded ? 'DEGRADED' : 'AWAITING',
        'notes': hasDegraded
            ? 'Sentiment temporarily unavailable; call continues normally.'
            : 'Awaiting sentiment samples',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
    }

    final average = scoreSum / count;
    return {
      'score': average,
      'label': _labelFromScore(average),
      'status': (hasDegraded || hasAwaiting) ? 'DEGRADED' : 'COMPLETED',
      'notes': (hasDegraded || hasAwaiting)
          ? 'Computed from available channels (partial data).'
          : 'Computed from all available channels.',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  void _seedAwaitingSentimentState() {
    final now = DateTime.now().toUtc();
    for (final channel in ['voice', 'video']) {
      _aggregatedSentiment[channel] = {
        'score': 0.5,
        'label': 'ANXIOUS',
        'notes': 'Awaiting $channel sentiment sample.',
        'status': 'AWAITING',
        'channel': channel,
        'updatedAt': now.toIso8601String(),
        'stale': false,
        'confidence': 0.0,
      };
    }
    _aggregatedSentiment['overall'] = {
      'score': 0.5,
      'label': 'ANXIOUS',
      'status': 'AWAITING',
      'notes': 'Awaiting sentiment samples',
      'updatedAt': now.toIso8601String(),
    };
  }

  Map<String, dynamic> _normalizeSentimentSection(
    String sectionKey,
    Map<String, dynamic> raw,
    DateTime now,
  ) {
    final normalizedChannel = (raw['channel'] as String? ?? sectionKey)
        .toLowerCase();
    final rawScore = (raw['score'] as num?)?.toDouble();
    final clampedScore = rawScore == null ? 0.5 : rawScore.clamp(0.0, 1.0);

    final rawStatus = (raw['status'] as String?)?.toUpperCase();
    final rawNotes = (raw['notes'] as String?)?.trim() ?? '';
    final fallback =
        raw['fallback'] == true || _isFallbackSentimentNotes(rawNotes);
    // If a scored sentiment sample is present, treat it as a completed update
    // even when it is marked as fallback, so the dashboard can render it.
    final status =
      rawStatus ?? (rawScore == null ? 'AWAITING' : 'COMPLETED');

    final notes = rawNotes.isNotEmpty
        ? rawNotes
        : (status == 'AWAITING'
              ? 'Awaiting $normalizedChannel sentiment sample.'
              : 'Sentiment sample received.');

    final updatedAt =
        _parseEventTime(raw['updatedAt']) ??
        _parseEventTime(raw['timestamp']) ??
        now;

    final label = _normalizeClinicalLabel(
      raw['label'] as String?,
      clampedScore,
    );

    return {
      'score': clampedScore,
      'label': label,
      'notes': notes,
      'status': status,
      'channel': normalizedChannel,
      'updatedAt': updatedAt.toIso8601String(),
      'stale': false,
      'confidence':
          (raw['confidence'] as num?)?.toDouble() ?? (fallback ? 0.0 : 1.0),
    };
  }

  bool _isFallbackSentimentNotes(String notes) {
    if (notes.isEmpty) {
      return false;
    }

    final lower = notes.toLowerCase();
    return lower.contains('analysis unavailable') ||
        lower.contains('temporarily unavailable') ||
        lower.contains('bedrock disabled') ||
        lower.contains('parse error') ||
        lower.contains('empty response') ||
        lower.contains('no voice sample') ||
        lower.contains('no video sample') ||
        lower.contains('no text sample');
  }

  DateTime? _parseEventTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  void _markStaleChannels(DateTime nowUtc) {
    for (final key in ['voice', 'video']) {
      final channel = _aggregatedSentiment[key];
      if (channel is! Map<String, dynamic>) continue;

      final status = (channel['status'] as String? ?? 'AWAITING').toUpperCase();
      final updatedAt = _parseEventTime(channel['updatedAt']);

      if (status == 'COMPLETED' &&
          updatedAt != null &&
          nowUtc.difference(updatedAt) > _sentimentStaleThreshold) {
        channel['status'] = 'DEGRADED';
        channel['stale'] = true;
        channel['notes'] = 'Sentiment sample is stale; awaiting refresh.';
      } else if (status == 'COMPLETED') {
        channel['stale'] = false;
      }
    }
  }

  String _labelFromScore(double score) {
    if (score >= 0.60) return 'CALM';
    if (score >= 0.35) return 'ANXIOUS';
    return 'DISTRESSED';
  }

  String _normalizeClinicalLabel(String? rawLabel, double score) {
    final expected = _labelFromScore(score);
    if (rawLabel == null || rawLabel.trim().isEmpty) {
      return expected;
    }

    final normalized = rawLabel.trim().toUpperCase();
    final mapped = switch (normalized) {
      'CALM' || 'ANXIOUS' || 'DISTRESSED' => normalized,
      'POSITIVE' => 'CALM',
      'NEUTRAL' => 'ANXIOUS',
      'NEGATIVE' => 'DISTRESSED',
      _ => expected,
    };

    // Keep label aligned with numeric score to avoid contradictory UI.
    if (mapped != expected) {
      return expected;
    }
    return mapped;
  }

  int? _resolveTranscriptEndMs(int? endMs) {
    if (endMs != null) {
      return endMs < 0 ? 0 : endMs;
    }
    if (_callStartedAt == null) {
      return null;
    }
    final elapsed = DateTime.now().difference(_callStartedAt!).inMilliseconds;
    final resolved = elapsed < 0 ? 0 : elapsed;
    return resolved;
  }

  int? _resolveTranscriptStartMs(String text, int? startMs, int? resolvedEndMs) {
    if (startMs != null) {
      return startMs < 0 ? 0 : startMs;
    }
    if (resolvedEndMs == null) {
      return null;
    }

    final estimatedDurationMs = _estimateTranscriptDurationMs(text);
    var resolvedStart = resolvedEndMs - estimatedDurationMs;
    if (resolvedStart < 0) {
      resolvedStart = 0;
    }

    // Keep ordering stable if client retries or buffering reorders segments.
    final minOrderedStart = _lastTranscriptEndMs - 1500;
    if (resolvedStart < minOrderedStart) {
      resolvedStart = minOrderedStart < 0 ? 0 : minOrderedStart;
    }
    return resolvedStart;
  }

  int _estimateTranscriptDurationMs(String text) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .length;
    if (words <= 0) {
      return 1200;
    }
    final estimated = words * 420; // ~143 words-per-minute speaking pace.
    if (estimated < 1200) {
      return 1200;
    }
    if (estimated > 9000) {
      return 9000;
    }
    return estimated;
  }

  bool get isInCall => _isInCall;
  String? get currentCallId => _currentCallId;
  Map<String, dynamic>? get meetingCredentials => _meetingCredentials;

  void setPatientSentimentSourceEnabled(bool enabled) {
    _isPatientSentimentSource = enabled;
  }

  /// Records a user ID known to be in (or invited to) the active conference.
  void trackParticipant(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return;
    }
    _participantUserIds.add(normalized);
  }

  @visibleForTesting
  Set<String> get participantUserIdsForTest => Set<String>.unmodifiable(_participantUserIds);

  void dispose() {
    _sentimentTimer?.cancel();
    _stopTranscriptFlushTimer();
    _wsSubscription?.cancel();
    _aggregatedSentiment.clear();
    _pendingTranscriptSegments.clear();
    _onCallDeclined = null;
    _isPatientSentimentSource = false;
    _isInitialized = false;
    _isInCall = false;
    _currentCallId = null;
    _otherPartyId = null;
    _participantUserIds.clear();
    _callContextMetadata = null;
    _callStartedAt = null;
    _lastTranscriptEndMs = 0;
  }

  // ================================================================
  // RECORDING
  // ================================================================

  /// Starts server-side recording of [callId] via AWS Chime Media Capture
  /// Pipeline. Returns the full response body or throws on error.
  Future<Map<String, dynamic>> startRecording(String callId) async {
    final response = await http.post(
      Uri.parse(
        '${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/recording/start',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwtToken',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'startRecording failed (${response.statusCode}): ${response.body}',
    );
  }

  /// Stops an active recording for [callId]. Returns the final recording info
  /// or throws on error.
  Future<Map<String, dynamic>> stopRecording(String callId) async {
    final response = await http.post(
      Uri.parse(
        '${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/recording/stop',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwtToken',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'stopRecording failed (${response.statusCode}): ${response.body}',
    );
  }

  /// Returns the current recording status for [callId], or null if none.
  Future<Map<String, dynamic>?> getRecordingStatus(String callId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/recording',
        ),
        headers: {'Authorization': 'Bearer $_jwtToken'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 404) return null;
    } catch (e) {
      debugPrint('⚠️ getRecordingStatus error: $e');
    }
    return null;
  }

  // ================================================================
  // CONFERENCE - invite participants to an active call
  // ================================================================

  /// Returns care-circle members who can be added to [callId].
  /// Each entry has: userId, name, role (CAREGIVER|FAMILY_MEMBER), relationship?.
  Future<List<Map<String, dynamic>>> getEligibleInvitees(String callId) async {
    try {
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/eligible-invitees'),
        headers: {'Authorization': 'Bearer $_jwtToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.cast<Map<String, dynamic>>();
      }
      debugPrint('getEligibleInvitees returned ${response.statusCode}');
    } catch (e) {
      debugPrint('getEligibleInvitees error: $e');
    }
    return [];
  }

  /// Invites [targetUserId] into the active [callId].
  /// Returns the backend invite status.
  Future<String> inviteParticipant(String callId, String targetUserId) async {
    try {
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/invite'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({'targetUserId': targetUserId}),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return (body['status'] as String?) ?? 'invited';
      }
      debugPrint('inviteParticipant returned ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('inviteParticipant error: $e');
    }
    return 'error';
  }

  /// Returns a time-limited presigned S3 URL for playback of [callId].
  Future<String?> getRecordingPlaybackUrl(String callId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${EnvironmentConfig.baseUrl}/api/v3/calls/$callId/recording/playback-url',
        ),
        headers: {'Authorization': 'Bearer $_jwtToken'},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['url'] as String?;
      }
    } catch (e) {
      debugPrint('⚠️ getRecordingPlaybackUrl error: $e');
    }
    return null;
  }

}

class _BufferedTranscriptSegment {
  final String callId;
  final String speakerLabel;
  final String text;
  final int? startMs;
  final int? endMs;
  final String source;

  const _BufferedTranscriptSegment({
    required this.callId,
    required this.speakerLabel,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.source,
  });
}

// ================================================================
// DATA CLASS — Chime call session credentials
// ================================================================

class ChimeCallSession {
  final String callId;
  final String meetingId;
  final String attendeeId;
  final String joinToken;
  final Map<String, dynamic> mediaPlacement;
  final String? mediaRegion;
  final String? externalUserId;
  final bool isVideoEnabled;
  final bool isAudioEnabled;

  const ChimeCallSession({
    required this.callId,
    required this.meetingId,
    required this.attendeeId,
    required this.joinToken,
    required this.mediaPlacement,
    this.mediaRegion,
    this.externalUserId,
    required this.isVideoEnabled,
    required this.isAudioEnabled,
  });
}
