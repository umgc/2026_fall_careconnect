import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme/sentiment_colors.dart';
import '../services/api_service.dart';
import '../utils/sentiment_clip_recording_status.dart';
import '../utils/sentiment_clip_window.dart';
import 'sentiment_clip_player_widget.dart';

class PostCallTelemetrySummaryScreen extends StatefulWidget {
  final String callId;
  final String? recipientName;

  /// Optional: called when the user taps "Call Again".
  final VoidCallback? onCallAgain;

  /// Optional: called when the user taps "Send Message".
  final VoidCallback? onSendMessage;

  /// When true the screen auto-dismisses after [autoDismissSeconds] seconds.
  /// Any interaction cancels the countdown.
  final bool autoDismiss;
  final int autoDismissSeconds;

  const PostCallTelemetrySummaryScreen({
    super.key,
    required this.callId,
    this.recipientName,
    this.onCallAgain,
    this.onSendMessage,
    this.autoDismiss = false,
    this.autoDismissSeconds = 5,
  });

  @override
  State<PostCallTelemetrySummaryScreen> createState() =>
      _PostCallTelemetrySummaryScreenState();
}

class _PostCallTelemetrySummaryScreenState
    extends State<PostCallTelemetrySummaryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _callTelemetry = const [];
  Map<String, dynamic>? _callSummary;
  List<Map<String, dynamic>> _transcriptSegments = const [];
  Map<String, dynamic>? _recording;
  bool _loadingPlaybackUrl = false;
  bool _loadingClip = false;
  String? _clipPlaybackUrl;
  double? _clipStartSec;
  double? _clipEndSec;
  DateTime? _clipRecordingStartedAtUtc;
  int _clipLoadGeneration = 0;
  _TimelineChannel _selectedChannel = _TimelineChannel.all;
  DateTime? _selectedSentimentAt;
  double? _selectedSentimentMinute;
  double? _selectedSentimentScore;
  bool _transcriptExpanded = false;
  final GlobalKey _transcriptCardKey = GlobalKey();
  final GlobalKey _clipPanelKey = GlobalKey();
  final Map<int, GlobalKey> _transcriptRowKeys = <int, GlobalKey>{};
  final ScrollController _timelineScrollController = ScrollController();
  _CallTimelineWindow _timelineWindow = _CallTimelineWindow.fullCall;
  RangeValues? _customTimelineRange;

  Timer? _dismissTimer;
  int _dismissSecondsLeft = 0;

  final Set<String> _confirmingItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadTelemetry();
    if (widget.autoDismiss) {
      _dismissSecondsLeft = widget.autoDismissSeconds;
      _startDismissTimer();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _timelineScrollController.dispose();
    super.dispose();
  }

  void _startDismissTimer() {
    _dismissTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _dismissSecondsLeft--);
      if (_dismissSecondsLeft <= 0) {
        t.cancel();
        if (mounted) Navigator.of(context).maybePop();
      }
    });
  }

  void _cancelDismiss() {
    if (_dismissTimer?.isActive == true) {
      _dismissTimer!.cancel();
      setState(() => _dismissSecondsLeft = 0);
    }
  }

  Future<void> _loadClipForSelectedSentiment() async {
    final rec = _recording;
    final selectedAt = _selectedSentimentAt;
    if (rec == null ||
        selectedAt == null ||
        !shouldLoadSentimentClipOnDotTap(rec)) {
      return;
    }

    if (_clipPlaybackUrl != null && _clipRecordingStartedAtUtc != null) {
      _updateClipWindowForSelection();
      return;
    }

    setState(() {
      _loadingClip = true;
      _clipPlaybackUrl = null;
      _clipStartSec = null;
      _clipEndSec = null;
      _clipRecordingStartedAtUtc = null;
    });
    _scrollClipPanelIntoView();

    final generation = ++_clipLoadGeneration;
    final data = await ApiService.getCallRecordingPlaybackData(widget.callId);
    if (!mounted || generation != _clipLoadGeneration) {
      return;
    }

    if (data == null) {
      setState(() => _loadingClip = false);
      _showClipLoadFailedSnackBar();
      return;
    }

    final playbackUrl = data['playbackUrl']?.toString().trim();
    final recordingStartedAtRaw = data['recordingStartedAt']?.toString();
    if (playbackUrl == null ||
        playbackUrl.isEmpty ||
        recordingStartedAtRaw == null ||
        recordingStartedAtRaw.isEmpty) {
      setState(() => _loadingClip = false);
      _showClipLoadFailedSnackBar();
      return;
    }

    final recordingStartedAt = DateTime.parse(recordingStartedAtRaw).toUtc();
    final clipWindow = computeSentimentClipWindow(
      sentimentOccurredAt: selectedAt.toUtc(),
      recordingStartedAt: recordingStartedAt,
    );

    setState(() {
      _clipPlaybackUrl = playbackUrl;
      _clipRecordingStartedAtUtc = recordingStartedAt;
      _clipStartSec = clipWindow.clipStartSec;
      _clipEndSec = clipWindow.clipEndSec;
      _loadingClip = false;
    });
    _scrollClipPanelIntoView();
  }

  void _updateClipWindowForSelection() {
    final selectedAt = _selectedSentimentAt;
    final recordingStartedAt = _clipRecordingStartedAtUtc;
    if (selectedAt == null || recordingStartedAt == null) {
      return;
    }

    final clipWindow = computeSentimentClipWindow(
      sentimentOccurredAt: selectedAt.toUtc(),
      recordingStartedAt: recordingStartedAt,
    );

    setState(() {
      _clipStartSec = clipWindow.clipStartSec;
      _clipEndSec = clipWindow.clipEndSec;
    });
    _scrollClipPanelIntoView();
  }

  void _scrollClipPanelIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final clipCtx = _clipPanelKey.currentContext;
      if (clipCtx == null || !mounted) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          clipCtx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        ),
      );
    });
  }

  void _showRecordingProcessingSnackBar() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(kSentimentClipRecordingProcessingSnackBar),
      ),
    );
  }

  void _showClipLoadFailedSnackBar() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(kSentimentClipLoadFailedSnackBar),
      ),
    );
  }

  void _clearClipPlayback() {
    _clipPlaybackUrl = null;
    _clipStartSec = null;
    _clipEndSec = null;
    _clipRecordingStartedAtUtc = null;
    _loadingClip = false;
  }

  void _clearSentimentSelectionState() {
    _selectedSentimentAt = null;
    _selectedSentimentMinute = null;
    _selectedSentimentScore = null;
    _clearClipPlayback();
  }

  void _dismissSentimentSelection() {
    setState(_clearSentimentSelectionState);
  }

  void _dismissClipPanel() {
    _dismissSentimentSelection();
  }

  Future<void> _loadPlaybackUrl() async {
    if (_loadingPlaybackUrl) return;
    setState(() => _loadingPlaybackUrl = true);
    final url = await ApiService.getCallRecordingPlaybackUrl(widget.callId);
    if (!mounted) return;
    setState(() => _loadingPlaybackUrl = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording not ready yet — try again in a moment.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open recording URL.')),
      );
    }
  }

  Future<void> _loadTelemetry() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.getCallTelemetry(widget.callId),
      ApiService.getCallSummary(widget.callId),
      ApiService.getCallTranscriptSegments(widget.callId),
      ApiService.getCallRecording(widget.callId),
    ]);
    final callEvents = (results[0] as List<Map<String, dynamic>>);
    final callSummary = results[1] as Map<String, dynamic>?;
    final transcriptSegments = (results[2] as List<Map<String, dynamic>>);
    final recording = results[3] as Map<String, dynamic>?;
    final sorted = _sortByOccurredAtAsc(callEvents);
    if (!mounted) return;
    setState(() {
      _callTelemetry = sorted;
      _callSummary = callSummary;
      _transcriptSegments = transcriptSegments;
      _recording = recording;
      _clearSentimentSelectionState();
      _customTimelineRange = null;
      _loading = false;
    });
  }

  // ── Sorting ───────────────────────────────────────────────────────

  List<Map<String, dynamic>> _sortByOccurredAtAsc(
    List<Map<String, dynamic>> events,
  ) {
    final sorted = List<Map<String, dynamic>>.from(events);
    sorted.sort(
      (a, b) =>
          _safeDate(a['occurredAt']).compareTo(_safeDate(b['occurredAt'])),
    );
    return sorted;
  }

  DateTime _safeDate(dynamic input) {
    if (input is String) {
      return DateTime.tryParse(input) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, dynamic>? get _summaryPayload {
    final root = _callSummary;
    if (root == null) return null;
    final raw = root['summary'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String? _summaryText(dynamic value, {int max = 220}) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  List<String> _summaryList(dynamic value, {int maxItems = 3}) {
    if (value is! List) return const [];
    return value
        .map((e) => _summaryText(e, max: 140))
        .whereType<String>()
        .take(maxItems)
        .toList();
  }

  // ── Per-item summary confirmation (FR-SUM-4) ────────────────────────

  List<_PendingSummaryItem> get _pendingSummaryItems {
    final summary = _summaryPayload;
    if (summary == null) return const [];
    final items = <_PendingSummaryItem>[];

    void collect(
      String category,
      String Function(Map<String, dynamic>) describe,
    ) {
      final raw = summary[category];
      if (raw is! List) return;
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = entry as Map<String, dynamic>;
        final needsConfirmationRaw = map['needsConfirmation'];
        final needsConfirmation = needsConfirmationRaw == true ||
            (needsConfirmationRaw is String &&
                needsConfirmationRaw.toLowerCase() == 'true');
        if (!needsConfirmation) continue;
        final itemId = map['itemId']?.toString();
        if (itemId == null || itemId.isEmpty) continue;
        items.add(
          _PendingSummaryItem(
            category: category,
            itemId: itemId,
            description: describe(map),
            raw: map,
          ),
        );
      }
    }

    collect('actionItems', _describeActionItem);
    collect('appointments', _describeAppointment);
    collect('careInstructions', _describeCareInstruction);
    return items;
  }

  String _describeActionItem(Map<String, dynamic> item) {
    final text = (item['text'] ?? '').toString().trim();
    final dueHint = (item['dueHint'] ?? '').toString().trim();
    if (dueHint.isEmpty) return text;
    return '$text ($dueHint)';
  }

  String _describeAppointment(Map<String, dynamic> item) {
    final date = (item['date'] ?? '').toString().trim();
    final time = (item['time'] ?? '').toString().trim();
    final withWhom = (item['with'] ?? '').toString().trim();
    final purpose = (item['purpose'] ?? '').toString().trim();
    final parts = <String>[
      if (date.isNotEmpty) date,
      if (time.isNotEmpty) time,
      if (withWhom.isNotEmpty) 'with $withWhom',
      if (purpose.isNotEmpty) purpose,
    ];
    return parts.isEmpty ? 'Appointment' : parts.join(' · ');
  }

  String _describeCareInstruction(Map<String, dynamic> item) {
    final text = (item['text'] ?? '').toString().trim();
    final type = (item['type'] ?? '').toString().trim();
    if (type.isEmpty) return text;
    return '[$type] $text';
  }

  IconData _iconForSummaryCategory(String category) {
    switch (category) {
      case 'actionItems':
        return Icons.checklist_rtl;
      case 'appointments':
        return Icons.event_outlined;
      case 'careInstructions':
        return Icons.medical_information_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _labelForSummaryCategory(String category) {
    switch (category) {
      case 'actionItems':
        return 'ACTION ITEM';
      case 'appointments':
        return 'APPOINTMENT';
      case 'careInstructions':
        return 'CARE INSTRUCTION';
      default:
        return category.toUpperCase();
    }
  }

  Future<void> _decideSummaryItem(
    _PendingSummaryItem item,
    String decision,
  ) async {
    setState(() => _confirmingItemIds.add(item.itemId));
    try {
      final response = await ApiService.confirmCallSummaryItem(
        widget.callId,
        item.itemId,
        decision: decision,
      );
      if (!mounted) return;
      final held = response['held'] == true;
      if (held) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sent for clinician review before it can be confirmed.',
            ),
          ),
        );
      } else {
        item.raw['needsConfirmation'] = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approve' ? 'Item approved.' : 'Item declined.',
            ),
          ),
        );
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update item: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _confirmingItemIds.remove(item.itemId));
      }
    }
  }

  Widget _buildPendingConfirmationsCard(bool isDark) {
    final pending = _pendingSummaryItems;
    if (pending.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items to confirm', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Review these items extracted from your call.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            ...pending.map((item) => _buildPendingItemTile(item, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingItemTile(_PendingSummaryItem item, bool isDark) {
    final busy = _confirmingItemIds.contains(item.itemId);
    return Container(
      key: ValueKey('pending-summary-item-${item.itemId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForSummaryCategory(item.category), size: 16),
              const SizedBox(width: 6),
              Text(
                _labelForSummaryCategory(item.category),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.description,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      busy ? null : () => _decideSummaryItem(item, 'approve'),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  onPressed:
                      busy ? null : () => _decideSummaryItem(item, 'decline'),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Sentiment sample selection ────────────────────────────────────
  // Prefer COMBINED / FINAL events; fall back to any event with a score.

  List<Map<String, dynamic>> get _sentimentSampleEvents {
    // Prefer ≥2 COMBINED/FINAL events — unambiguous aggregated scores across
    // the call timeline.  A single final event is not enough for a meaningful
    // distribution, so we fall through to per-channel streams in that case.
    final combined = _callTelemetry.where((e) {
      final type = (e['eventType'] as String?)?.trim().toUpperCase() ?? '';
      return (type == 'SENTIMENT_COMBINED' || type == 'SENTIMENT_FINAL') &&
          e['sentimentScore'] != null;
    }).toList();
    if (combined.length >= 2) return combined;

    // Fall back to a single-channel stream to avoid double-counting parallel
    // voice/video/text events that share timestamps.
    for (final preferred in [
      'SENTIMENT_VOICE',
      'SENTIMENT_VIDEO',
      'SENTIMENT_TEXT',
    ]) {
      final channel = _callTelemetry.where((e) {
        final type = (e['eventType'] as String?)?.trim().toUpperCase() ?? '';
        return type == preferred && e['sentimentScore'] != null;
      }).toList();
      if (channel.length >= 2) return channel;
    }

    // Last resort: return whatever SENTIMENT_* events we have (may be ≤1).
    final all = _callTelemetry.where((e) {
      final type = (e['eventType'] as String?)?.trim().toUpperCase() ?? '';
      return type.startsWith('SENTIMENT_') && e['sentimentScore'] != null;
    }).toList();
    return all.isNotEmpty ? all : combined;
  }

  // ── Time-in-state breakdown ───────────────────────────────────────

  Map<String, double> get _timeInStatePct {
    final samples = _sentimentSampleEvents;
    if (samples.isEmpty) return {'CALM': 0, 'ANXIOUS': 0, 'DISTRESSED': 0};

    double calmMs = 0, anxiousMs = 0, distressedMs = 0;

    for (var i = 0; i < samples.length; i++) {
      final score =
          (samples[i]['sentimentScore'] as num?)?.toDouble() ?? 0.5;
      final from = _safeDate(samples[i]['occurredAt']);
      final to = i + 1 < samples.length
          ? _safeDate(samples[i + 1]['occurredAt'])
          : (_callEnd ?? from);

      final durationMs =
          to.difference(from).inMilliseconds.toDouble();
      if (durationMs <= 0) continue;

      if (score >= SentimentColors.calmThreshold) {
        calmMs += durationMs;
      } else if (score >= SentimentColors.anxiousThreshold) {
        anxiousMs += durationMs;
      } else {
        distressedMs += durationMs;
      }
    }

    final total = calmMs + anxiousMs + distressedMs;
    if (total <= 0) return {'CALM': 0, 'ANXIOUS': 0, 'DISTRESSED': 0};

    return {
      'CALM': calmMs / total,
      'ANXIOUS': anxiousMs / total,
      'DISTRESSED': distressedMs / total,
    };
  }

  // ── Stability score (1 − normalised std-dev) ─────────────────────

  /// Returns null when there are fewer than 2 samples — stability cannot be
  /// computed from a single data point and should be displayed as "N/A".
  double? get _stabilityScore {
    final samples = _sentimentSampleEvents;
    if (samples.length < 2) return null;

    final scores = samples
        .map((e) => (e['sentimentScore'] as num?)?.toDouble() ?? 0.5)
        .toList();
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    final variance = scores
            .map((s) => (s - mean) * (s - mean))
            .reduce((a, b) => a + b) /
        scores.length;
    final stdDev = math.sqrt(variance);
    // Typical max std-dev for a 0–1 variable is 0.5; normalise against that.
    return (1.0 - (stdDev / 0.5)).clamp(0.0, 1.0);
  }

  // ── Final overall sentiment ───────────────────────────────────────

  int get _sentimentEventCount => _callTelemetry
      .where((e) =>
          (e['eventType'] as String?)?.toUpperCase().startsWith('SENTIMENT_') ==
          true)
      .length;

  Map<String, dynamic>? get _finalOverallEvent {
    for (final event in _callTelemetry.reversed) {
      final eventType =
          (event['eventType'] as String?)?.trim().toUpperCase();
      if (eventType == 'SENTIMENT_FINAL') return event;
    }
    for (final event in _callTelemetry.reversed) {
      final channel = (event['channel'] as String?)?.trim().toUpperCase();
      final eventType =
          (event['eventType'] as String?)?.trim().toUpperCase();
      if (channel == 'COMBINED' || eventType == 'SENTIMENT_COMBINED') {
        return event;
      }
    }
    return null;
  }

  double? get _finalOverallScore =>
      (_finalOverallEvent?['sentimentScore'] as num?)?.toDouble();

  String get _finalOverallScoreText {
    final score = _finalOverallScore;
    if (score == null) return '--';
    return '${(score * 100).toStringAsFixed(1)}%';
  }

  String get _finalOverallLabel {
    final event = _finalOverallEvent;
    if (event == null) return '--';
    final label = (event['sentimentLabel'] as String?)?.trim();
    if (label == null || label.isEmpty) return '--';
    return _toClinicalLabel(label);
  }

  String get _finalOverallNotes {
    final event = _finalOverallEvent;
    if (event == null) return '--';
    final notes = (event['sentimentNotes'] as String?)?.trim();
    if (notes == null || notes.isEmpty) return '--';
    return notes;
  }

  String _toClinicalLabel(String raw) {
    final n = raw.trim().toUpperCase();
    if (n == 'CALM' || n == 'ANXIOUS' || n == 'DISTRESSED') return n;
    if (n == 'POSITIVE') return 'CALM';
    if (n == 'NEGATIVE') return 'DISTRESSED';
    return 'ANXIOUS';
  }

  String get _caregiverRecommendation {
    final score = _finalOverallScore;
    if (score == null) return 'Final assessment not yet available.';
    if (score < 0.30) {
      return 'High concern — check in immediately and assess acute distress signs.';
    }
    if (score < 0.45) return 'Elevated concern — increase monitoring and follow up soon.';
    if (score < 0.65) return 'Moderate concern — continue routine monitoring.';
    return 'Stable — maintain normal follow-up cadence.';
  }

  // ── Call metadata ─────────────────────────────────────────────────

  String get _finalCallStatus {
    for (final event in _callTelemetry.reversed) {
      final eventType =
          (event['eventType'] as String?)?.trim().toUpperCase() ?? '';
      final status =
          (event['status'] as String?)?.trim().toUpperCase() ?? '';
      if (status == 'ERROR') return 'Failed';
      switch (eventType) {
        case 'WS_DECLINE_CALL':
          return 'Rejected';
        case 'WS_ACCEPT_CALL':
          return 'Accepted';
        case 'WS_END_CALL':
        case 'CALL_END':
          return 'Ended';
        case 'WS_SEND_VIDEO_CALL_INVITATION':
          return 'Invited';
        case 'CALL_JOIN':
          return 'Joined';
      }
    }
    return '--';
  }

  String get _finalCallWhy {
    final finalEvent = _resolveFinalOutcomeEvent();
    if (finalEvent == null) return '--';

    final eventType =
        (finalEvent['eventType'] as String?)?.trim().toUpperCase() ?? '';
    final status =
        (finalEvent['status'] as String?)?.trim().toUpperCase() ?? '';
    final errorMessage = (finalEvent['errorMessage'] as String?)?.trim();
    if (errorMessage != null && errorMessage.isNotEmpty) return errorMessage;

    final payloadReason =
        _extractReasonFromJsonBlob(finalEvent['payloadJson']);
    if (payloadReason != null) return payloadReason;

    if (status == 'ERROR') return 'The call action failed to complete.';

    switch (eventType) {
      case 'WS_DECLINE_CALL':
        return 'The recipient declined the invitation.';
      case 'WS_ACCEPT_CALL':
        return 'The recipient accepted and joined the call.';
      case 'WS_END_CALL':
      case 'CALL_END':
        return 'A participant ended the call.';
      case 'WS_SEND_VIDEO_CALL_INVITATION':
        return 'Invitation was sent to the recipient.';
      case 'CALL_JOIN':
        return 'Participant joined the call session.';
      default:
        return '--';
    }
  }

  String get _finalCallStatusWithReason {
    final status = _finalCallStatus;
    final why = _finalCallWhy;
    if (status == '--') return status;
    if (why == '--') return status;
    return '$status — $why';
  }

  Map<String, dynamic>? _resolveFinalOutcomeEvent() {
    for (final event in _callTelemetry.reversed) {
      final eventType =
          (event['eventType'] as String?)?.trim().toUpperCase() ?? '';
      final status =
          (event['status'] as String?)?.trim().toUpperCase() ?? '';
      if (status == 'ERROR') return event;
      if (eventType == 'WS_DECLINE_CALL' ||
          eventType == 'WS_ACCEPT_CALL' ||
          eventType == 'WS_END_CALL' ||
          eventType == 'CALL_END' ||
          eventType == 'WS_SEND_VIDEO_CALL_INVITATION' ||
          eventType == 'CALL_JOIN') {
        return event;
      }
    }
    return null;
  }

  String? _extractReasonFromJsonBlob(dynamic jsonBlob) {
    if (jsonBlob is! String || jsonBlob.trim().isEmpty) return null;
    try {
      final decoded = Map<String, dynamic>.from(
        (jsonDecode(jsonBlob) as Map).cast<String, dynamic>(),
      );
      final reason = (decoded['reason'] as String?)?.trim();
      if (reason != null && reason.isNotEmpty) return reason;
      final message = (decoded['message'] as String?)?.trim();
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    return null;
  }

  // ── Duration ──────────────────────────────────────────────────────

  // Anchor to CALL_JOIN / CALL_END events so pre-call and post-call telemetry
  // (sentiment samples, summaries) don't inflate the displayed duration.
  // Falls back to first/last event if the typed anchors are missing.
  DateTime? get _callStart {
    if (_callTelemetry.isEmpty) return null;
    final joinEvent = _callTelemetry.firstWhere(
      (e) {
        final t = ((e['eventType'] ?? '') as String).toUpperCase();
        return t == 'CALL_JOIN' || t == 'CALL_STARTED';
      },
      orElse: () => _callTelemetry.first,
    );
    return _safeDate(joinEvent['occurredAt']);
  }

  DateTime? get _callEnd {
    if (_callTelemetry.isEmpty) return null;
    final endEvent = _callTelemetry.lastWhere(
      (e) {
        final t = ((e['eventType'] ?? '') as String).toUpperCase();
        return t == 'CALL_END' || t == 'CALL_ENDED';
      },
      orElse: () => _callTelemetry.last,
    );
    return _safeDate(endEvent['occurredAt']);
  }

  double get _callDurationMinutes {
    final start = _callStart;
    final end = _callEnd;
    if (start == null || end == null) return 0;
    final seconds = end.difference(start).inSeconds;
    return seconds <= 0 ? 1 : seconds / 60.0;
  }

  String get _callDurationText {
    final start = _callStart;
    final end = _callEnd;
    if (start == null || end == null) return '--';
    final diff = end.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${diff.inMinutes}:$seconds';
  }

  // ── Timeline series ───────────────────────────────────────────────

  _TimelineChannel? _resolveEventChannel(Map<String, dynamic> event) {
    final channelRaw =
        (event['channel'] as String?)?.trim().toUpperCase() ?? '';
    if (channelRaw == 'VOICE' || channelRaw == 'AUDIO') {
      return _TimelineChannel.voice;
    }
    if (channelRaw == 'COMBINED') return null;
    final eventType =
        (event['eventType'] as String?)?.trim().toUpperCase() ?? '';
    if (eventType.contains('VOICE') || eventType.contains('AUDIO')) {
      return _TimelineChannel.voice;
    }
    if (eventType.contains('COMBINED') || eventType.contains('FINAL')) {
      return null;
    }
    return _TimelineChannel.video;
  }

  Map<_TimelineChannel, List<_ScoreSample>> get _allChannelSeries {
    final start = _callStart;
    if (start == null) {
      return {
        _TimelineChannel.voice: const <_ScoreSample>[],
        _TimelineChannel.video: const <_ScoreSample>[],
      };
    }
    final byChannel = <_TimelineChannel, List<_ScoreSample>>{
      _TimelineChannel.voice: <_ScoreSample>[],
      _TimelineChannel.video: <_ScoreSample>[],
    };
    for (final event in _callTelemetry) {
      final eventType =
          (event['eventType'] as String?)?.toUpperCase() ?? '';
      if (!eventType.startsWith('SENTIMENT_')) continue;
      final channel = _resolveEventChannel(event);
      if (channel == null || !byChannel.containsKey(channel)) continue;
      final score = (event['sentimentScore'] as num?)?.toDouble();
      if (score == null) continue;
      final at = _safeDate(event['occurredAt']);
      final minuteOffset =
          at.difference(start).inMilliseconds / 60000.0;
      byChannel[channel]!.add(
        _ScoreSample(
          minuteOffset: minuteOffset.clamp(0.0, _callDurationMinutes),
          score: score.clamp(0.0, 1.0),
          occurredAt: at,
        ),
      );
    }
    for (final points in byChannel.values) {
      points.sort((a, b) => a.minuteOffset.compareTo(b.minuteOffset));
    }
    return byChannel;
  }

  Map<_TimelineChannel, List<_ScoreSample>> get _visibleSeries {
    final all = _allChannelSeries;
    if (_selectedChannel == _TimelineChannel.all) return all;
    return {
      _selectedChannel: all[_selectedChannel] ?? const <_ScoreSample>[]
    };
  }

  void _handleTimelineTap({
    required Offset localPosition,
    required Size canvasSize,
    required Map<_TimelineChannel, List<_ScoreSample>> visibleSeries,
    required double durationMinutes,
    required double minuteOffsetBase,
  }) {
    if (durationMinutes <= 0) return;
    const leftPad = 72.0;
    const rightPad = 20.0;
    const topPad = 20.0;
    const bottomPad = 44.0;

    final plotWidth = math.max(1.0, canvasSize.width - leftPad - rightPad);
    final plotHeight = math.max(1.0, canvasSize.height - topPad - bottomPad);
    final plotRect = Rect.fromLTWH(leftPad, topPad, plotWidth, plotHeight);
    if (!plotRect.contains(localPosition)) return;

    double yForScore(double s) =>
        plotRect.bottom - s.clamp(0.0, 1.0) * plotRect.height;

    _ScoreSample? nearest;
    double nearestDist2 = double.infinity;
    for (final points in visibleSeries.values) {
      for (final sample in points) {
        final x = leftPad + (sample.minuteOffset / durationMinutes) * plotWidth;
        final y = yForScore(sample.score);
        final dx = x - localPosition.dx;
        final dy = y - localPosition.dy;
        final dist2 = dx * dx + dy * dy;
        if (dist2 < nearestDist2) {
          nearestDist2 = dist2;
          nearest = sample;
        }
      }
    }
    if (nearest == null) return;

    setState(() {
      _selectedSentimentAt = nearest!.occurredAt;
      _selectedSentimentMinute = nearest.minuteOffset + minuteOffsetBase;
      _selectedSentimentScore = nearest.score;
    });

    final rec = _recording;
    final loadClip = shouldLoadSentimentClipOnDotTap(rec);

    if (loadClip) {
      unawaited(_loadClipForSelectedSentiment());
    } else {
      if (_clipPlaybackUrl != null || _loadingClip) {
        setState(_clearClipPlayback);
      }
      if (shouldShowSentimentClipProcessingSnackBar(rec)) {
        _showRecordingProcessingSnackBar();
      }
    }

    final transcriptCtx = _transcriptCardKey.currentContext;
    if (!loadClip && transcriptCtx != null) {
      unawaited(
        Scrollable.ensureVisible(
          transcriptCtx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.1,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollTranscriptToSelectedSegment();
    });
  }

  _TimelineWindowSpan _resolveTimelineWindow(double fullDurationMinutes) {
    final safeDuration = fullDurationMinutes <= 0 ? 1.0 : fullDurationMinutes;
    switch (_timelineWindow) {
      case _CallTimelineWindow.first5:
        return _TimelineWindowSpan(
          startMinute: 0.0,
          endMinute: math.min(5.0, safeDuration),
        );
      case _CallTimelineWindow.first15:
        return _TimelineWindowSpan(
          startMinute: 0.0,
          endMinute: math.min(15.0, safeDuration),
        );
      case _CallTimelineWindow.last5:
        return _TimelineWindowSpan(
          startMinute: math.max(0.0, safeDuration - 5.0),
          endMinute: safeDuration,
        );
      case _CallTimelineWindow.last15:
        return _TimelineWindowSpan(
          startMinute: math.max(0.0, safeDuration - 15.0),
          endMinute: safeDuration,
        );
      case _CallTimelineWindow.custom:
        final rv = _customTimelineRange ??
            RangeValues(
              0.0,
              math.max(1.0, safeDuration),
            );
        final start = rv.start.clamp(0.0, safeDuration);
        final end = rv.end.clamp(0.0, safeDuration);
        final normalizedStart = math.min(start, end - 0.1);
        final normalizedEnd = math.max(end, normalizedStart + 0.1);
        return _TimelineWindowSpan(
          startMinute: normalizedStart,
          endMinute: normalizedEnd,
        );
      case _CallTimelineWindow.fullCall:
        return _TimelineWindowSpan(startMinute: 0.0, endMinute: safeDuration);
    }
  }

  Map<_TimelineChannel, List<_ScoreSample>> _sliceSeriesToWindow({
    required Map<_TimelineChannel, List<_ScoreSample>> source,
    required double windowStartMinute,
    required double windowEndMinute,
  }) {
    final span = math.max(0.001, windowEndMinute - windowStartMinute);
    final sliced = <_TimelineChannel, List<_ScoreSample>>{};
    source.forEach((channel, samples) {
      final points = samples
          .where((s) =>
              s.minuteOffset >= windowStartMinute &&
              s.minuteOffset <= windowEndMinute)
          .map(
            (s) => _ScoreSample(
              minuteOffset:
                  (s.minuteOffset - windowStartMinute).clamp(0.0, span),
              score: s.score,
              occurredAt: s.occurredAt,
            ),
          )
          .toList();
      sliced[channel] = points;
    });
    return sliced;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    final bool showCountdown =
        widget.autoDismiss && _dismissSecondsLeft > 0;

    return GestureDetector(
      onTap: _cancelDismiss,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Call Summary'),
          actions: [
            if (showCountdown)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'Closing in $_dismissSecondsLeft s',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ),
            IconButton(
              onPressed: _loadTelemetry,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  _cancelDismiss();
                  await _loadTelemetry();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (widget.recipientName != null &&
                        widget.recipientName!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Call with ${widget.recipientName}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    _SummarySection(
                      isDark: isDark,
                      finalOverallScore: _finalOverallScoreText,
                      finalOverallLabel: _finalOverallLabel,
                      finalOverallNotes: _finalOverallNotes,
                      caregiverRecommendation: _caregiverRecommendation,
                      callSummaryHeadline:
                          _summaryText(_summaryPayload?['headline'], max: 100),
                      callSummaryAssessment: _summaryText(
                        _summaryPayload?['overallAssessment'],
                        max: 240,
                      ),
                      callSummaryConcerns: _summaryList(
                        _summaryPayload?['keyConcerns'],
                      ),
                      callSummaryActions: _summaryList(
                        _summaryPayload?['recommendedActions'],
                      ),
                      finalCallStatus: _finalCallStatusWithReason,
                      callDuration: _callDurationText,
                      timeInStatePct: _timeInStatePct,
                      sampleCount: _sentimentSampleEvents.length,
                      stabilityScore: _stabilityScore,
                      onCallAgain: widget.onCallAgain,
                      onSendMessage: widget.onSendMessage,
                    ),
                    const SizedBox(height: 16),
                    _buildPendingConfirmationsCard(isDark),
                    if (_pendingSummaryItems.isNotEmpty)
                      const SizedBox(height: 16),
                    if (_recording != null) ...[
                      _buildRecordingCard(isDark),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Sentiment Trend',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (sentimentClipRecordingStatusMessage(_recording) !=
                        null) ...[
                      const SizedBox(height: 6),
                      Text(
                        sentimentClipRecordingStatusMessage(_recording)!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      sentimentChartDotTapHint(_recording),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTimelineCard(isDark),
                    const SizedBox(height: 12),
                    _buildTranscriptCard(isDark),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Recording card ────────────────────────────────────────────────

  Widget _buildRecordingCard(bool isDark) {
    final rec = _recording!;
    final status = (rec['status'] as String? ?? '').toUpperCase();
    final concatenationStatus =
        (rec['concatenationStatus'] as String? ?? '').toUpperCase();
    final startedAt = rec['startedAt'] as String?;
    final playbackReady = rec['playbackReady'] == true;
    final errorMessage = (rec['errorMessage'] as String?)?.trim();
    final transcriptionStatus =
        (rec['transcriptionStatus'] as String? ?? '').toUpperCase();


    // A system-initiated recording (initiatedByUserId == null) is for transcription only —
    // the S3 file is deleted after transcription so playback is never available for it.
    final isSystemRecording = !isUserInitiatedCallRecording(rec);

    String startedText = '—';
    if (!isSystemRecording && startedAt != null) {
      final dt = DateTime.tryParse(startedAt)?.toLocal();
      if (dt != null) {
        startedText =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    final hasNoRecording =
        status == 'NO_RECORDING' ||
        status == 'NOT_FOUND' ||
        status.isEmpty ||
        isSystemRecording;
    final isCapturing = status == 'STARTED' || status == 'CAPTURING';
    final isReady = status == 'STOPPED';
    final statusColor = hasNoRecording
        ? Colors.blueGrey.shade600
        : isReady
            ? Colors.green.shade700
            : isCapturing
                ? Colors.orange.shade700
                : Colors.grey;
    final availabilityLabel = switch (concatenationStatus) {
      _ when hasNoRecording => 'NOT RECORDED',
      'READY' => 'VIDEO READY',
      'FAILED' => 'STITCH FAILED',
      'PROCESSING' => 'STITCHING',
      _ when playbackReady => 'VIDEO READY',
      _ when isReady => 'PROCESSING',
      _ when isCapturing => 'CAPTURING',
      _ => 'UNAVAILABLE',
    };
    final availabilityColor = switch (availabilityLabel) {
      'VIDEO READY' => Colors.green.shade700,
      'STITCH FAILED' => Colors.red.shade700,
      'STITCHING' || 'PROCESSING' => Colors.orange.shade700,
      'NOT RECORDED' || 'UNAVAILABLE' => Colors.blueGrey.shade600,
      _ => Colors.blueGrey.shade600,
    };
    final availabilityMessage = switch (availabilityLabel) {
      'VIDEO READY' => 'The stitched call video is ready to play.',
      'STITCH FAILED' => errorMessage?.isNotEmpty == true
          ? errorMessage!
          : 'Video stitching did not complete successfully.',
      'STITCHING' || 'PROCESSING' =>
        'The final video is still processing. Pull to refresh in about 1-2 minutes.',
      'NOT RECORDED' => isSystemRecording
        ? 'The Record button was not pressed during this call. Toggle recording next time to enable playback.'
        : 'Recording was not started for this call, so no playback is available.',
      'UNAVAILABLE' =>
        'Recording is not available for this call.',
      _ => 'Recording is still in progress.',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Call Recording',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: availabilityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: availabilityColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    availabilityLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: availabilityColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isSystemRecording)
              Row(
                children: [
                  _RecordingMetaChip(
                    icon: Icons.calendar_today,
                    label: 'Recorded',
                    value: startedText,
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: availabilityColor.withValues(alpha: isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: availabilityColor.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: availabilityColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      availabilityMessage,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (transcriptionStatus == 'FAILED') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Automatic transcript generation did not complete for this call.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (!playbackReady || _loadingPlaybackUrl)
                    ? null
                    : _loadPlaybackUrl,
                icon: _loadingPlaybackUrl
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline, size: 18),
                label: Text(
                  _loadingPlaybackUrl ? 'Loading...' : 'Play Recording',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Timeline card ─────────────────────────────────────────────────

  Widget _buildTimelineCard(bool isDark) {
    final theme = Theme.of(context);
    final duration = _callDurationMinutes;
    final allSeries = _allChannelSeries;
    final hasAnySamples = allSeries.values.any((p) => p.isNotEmpty);

    if (_callTelemetry.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No telemetry saved for this call yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final channelColors = <_TimelineChannel, Color>{
      _TimelineChannel.voice: SentimentColors.forChannel('VOICE', isDark: isDark),
      _TimelineChannel.video: SentimentColors.forChannel('VIDEO', isDark: isDark),
    };
    final window = _resolveTimelineWindow(duration);
    final windowDuration = math.max(0.1, window.endMinute - window.startMinute);
    final visibleSeries = _sliceSeriesToWindow(
      source: _visibleSeries,
      windowStartMinute: window.startMinute,
      windowEndMinute: window.endMinute,
    );
    final hasSelectedSamples = visibleSeries.values.any((p) => p.isNotEmpty);
    final selectedMinuteInWindow = _selectedSentimentMinute == null
        ? null
        : ((_selectedSentimentMinute! >= window.startMinute &&
                _selectedSentimentMinute! <= window.endMinute)
            ? (_selectedSentimentMinute! - window.startMinute)
            : null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = math.max(320.0, constraints.maxWidth);
            final baseTimelineWidth =
                math.max(viewportWidth, windowDuration * 120.0);
            final contentWidth =
                math.min(24000.0, baseTimelineWidth).toDouble();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice and Video channels shown.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _TimelineChannel.values.map((ch) {
                    return ChoiceChip(
                      label: Text(ch.label),
                      selected: _selectedChannel == ch,
                      onSelected: (_) {
                        if (_selectedChannel == ch) {
                          return;
                        }
                        setState(() {
                          _selectedChannel = ch;
                          _clearSentimentSelectionState();
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<_CallTimelineWindow>(
                        initialValue: _timelineWindow,
                        items: _CallTimelineWindow.values
                            .map(
                              (w) => DropdownMenuItem<_CallTimelineWindow>(
                                value: w,
                                child: Text(w.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _timelineWindow = value;
                            if (value != _CallTimelineWindow.custom) return;
                            _customTimelineRange ??= RangeValues(
                              0.0,
                              math.max(1.0, duration),
                            );
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Window',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_timelineWindow == _CallTimelineWindow.custom) ...[
                  RangeSlider(
                    min: 0.0,
                    max: math.max(1.0, duration),
                    values: _customTimelineRange ??
                        RangeValues(0.0, math.max(1.0, duration)),
                    labels: RangeLabels(
                      _formatElapsed(window.startMinute),
                      _formatElapsed(window.endMinute),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _customTimelineRange = RangeValues(
                          values.start.clamp(0.0, duration),
                          values.end.clamp(0.0, duration),
                        );
                      });
                    },
                  ),
                ],
                Text(
                  'Window: ${_formatElapsed(window.startMinute)} - ${_formatElapsed(window.endMinute)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (_selectedSentimentAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Selected sample: ${_formatAbsoluteTime(_selectedSentimentAt!)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          key: const Key('dismiss_sentiment_selection'),
                          onPressed: _dismissSentimentSelection,
                          tooltip: 'Clear selection',
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!hasAnySamples)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No score-based sentiment samples captured for this call.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else if (!hasSelectedSamples)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No samples for ${_selectedChannel.label}. Select another channel.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300,
                  child: Scrollbar(
                    controller: _timelineScrollController,
                    thumbVisibility: contentWidth > viewportWidth,
                    child: SingleChildScrollView(
                      controller: _timelineScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: GestureDetector(
                          key: const Key('sentiment_timeline_canvas'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _handleTimelineTap(
                            localPosition: details.localPosition,
                            canvasSize: Size(contentWidth, 300),
                            visibleSeries: visibleSeries,
                            durationMinutes: windowDuration,
                            minuteOffsetBase: window.startMinute,
                          ),
                          child: CustomPaint(
                            painter: _SentimentTimelinePainter(
                              durationMinutes: windowDuration,
                              series: visibleSeries,
                              channelColors: channelColors,
                              isDark: isDark,
                              selectedMinute: selectedMinuteInWindow,
                              selectedScore: _selectedSentimentScore,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _TimelineLegend(
                  channelColors: channelColors,
                  isDark: isDark,
                ),
                if (_loadingClip ||
                    (_clipPlaybackUrl != null &&
                        _clipStartSec != null &&
                        _clipEndSec != null))
                  KeyedSubtree(
                    key: _clipPanelKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_loadingClip) ...[
                          const SizedBox(height: 12),
                          const AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Sentiment clip',
                                style: theme.textTheme.titleSmall,
                              ),
                              const Spacer(),
                              IconButton(
                                key: const Key('dismiss_sentiment_clip'),
                                onPressed: _dismissClipPanel,
                                tooltip: 'Dismiss clip',
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          SentimentClipPlayerWidget(
                            key: ValueKey(_clipPlaybackUrl!),
                            playbackUrl: _clipPlaybackUrl!,
                            clipStartSec: _clipStartSec!,
                            clipEndSec: _clipEndSec!,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatElapsed(double minute) {
    final totalSeconds = (minute * 60).round().clamp(0, 24 * 3600 * 30);
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildTranscriptCard(bool isDark) {
    final segments = _transcriptSegments;
    if (segments.isEmpty) {
      final rec = _recording ?? const <String, dynamic>{};
      final transcriptionStatus =
          (rec['transcriptionStatus'] as String? ?? '').toUpperCase();
      final concatenationStatus =
          (rec['concatenationStatus'] as String? ?? '').toUpperCase();
      final recordingStatus = (rec['status'] as String? ?? '').toUpperCase();
      final waitingForTranscript = transcriptionStatus == 'PROCESSING' ||
          transcriptionStatus == 'READY' ||
          // User recording finished but transcript job not marked yet (concat still
          // stitching, or status not refreshed to READY/PROCESSING).
          (isUserInitiatedCallRecording(rec) &&
              recordingStatus != 'NO_RECORDING' &&
              recordingStatus.isNotEmpty &&
              transcriptionStatus != 'FAILED' &&
              transcriptionStatus != 'COMPLETE' &&
              concatenationStatus != 'FAILED');
      if (waitingForTranscript) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generating Transcript…',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'The call transcript is being processed. Check back in a few minutes.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final anchorOccurredAt = _safeDate(segments.first['occurredAt']);
    final callStart = _resolveTranscriptCallStart(
      segments: segments,
      anchorOccurredAt: anchorOccurredAt,
      fallbackCallStart: _callStart,
    );
    final selectedAt = _selectedSentimentAt;
    final selectedSegmentIndex = _resolveSelectedSegmentIndex(
      segments: segments,
      selectedAt: selectedAt,
      callStart: callStart,
      anchorOccurredAt: anchorOccurredAt,
    );

    final preview = segments;
    return Card(
      key: _transcriptCardKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Call Transcript',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _transcriptExpanded ? 'Collapse' : 'Expand',
                  onPressed: () {
                    setState(() => _transcriptExpanded = !_transcriptExpanded);
                  },
                  icon: Icon(
                    _transcriptExpanded
                        ? Icons.unfold_less
                        : Icons.unfold_more,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              _selectedSentimentAt == null
                  ? 'Select a plot sample to show matching sentiment badges.'
                  : 'Badges show the selected sample context.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _transcriptExpanded ? 460 : 260,
              child: ListView(
                children: preview.asMap().entries.map((entry) {
                  final index = entry.key;
                  final segment = entry.value;
                  final speaker = (segment['speakerLabel'] ?? 'PARTICIPANT')
                      .toString()
                      .trim();
                  final text = (segment['text'] ?? '').toString().trim();
                  final matchingSentiment = _sentimentHitsForSegment(
                    segment,
                    callStart: callStart,
                    anchorOccurredAt: anchorOccurredAt,
                    isDark: isDark,
                  );
                  final rangeObj = _segmentAbsoluteRange(
                    segment,
                    callStart: callStart,
                    anchorOccurredAt: anchorOccurredAt,
                  );
                  final range = _formatSegmentRange(
                    segment['startMs'],
                    segment['endMs'],
                    occurredAt: segment['occurredAt'],
                    anchorOccurredAt: anchorOccurredAt,
                  );
                  final isSelectedRange = selectedAt != null &&
                      rangeObj != null &&
                      !selectedAt.isBefore(rangeObj.start) &&
                      !selectedAt.isAfter(rangeObj.end);
                  final isNearestSelected =
                      selectedSegmentIndex != null && selectedSegmentIndex == index;
                  final showBadges = selectedAt != null &&
                      (isSelectedRange || isNearestSelected);
                  if (text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    key: _keyForTranscriptRow(index),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelectedRange
                            ? SentimentColors.forScore(
                                _selectedSentimentScore ?? 0.5,
                                isDark: isDark,
                              ).withValues(alpha: isDark ? 0.18 : 0.12)
                            : (isNearestSelected
                                ? (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05))
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      // selected match gets stronger border, nearest fallback gets soft border
                      foregroundDecoration: (isSelectedRange || isNearestSelected)
                          ? BoxDecoration(
                              border: Border.all(
                                color: isSelectedRange
                                    ? SentimentColors.forScore(
                                        _selectedSentimentScore ?? 0.5,
                                        isDark: isDark,
                                      ).withValues(alpha: 0.7)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.35)
                                        : Colors.black.withValues(alpha: 0.28)),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$range [$speaker] $text',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: (isSelectedRange || isNearestSelected)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          if (showBadges && matchingSentiment.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: matchingSentiment.take(4).map((hit) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hit.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: hit.color.withValues(alpha: 0.55),
                                    ),
                                  ),
                                  child: Text(
                                    '${hit.timeText}  ${hit.channel} ${hit.label}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: hit.color,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _resolveTranscriptCallStart({
    required List<Map<String, dynamic>> segments,
    required DateTime anchorOccurredAt,
    required DateTime? fallbackCallStart,
  }) {
    for (final segment in segments) {
      final startMs = _asInt(segment['startMs']);
      final occurredAt = _safeDate(segment['occurredAt']);
      if (startMs == null) continue;
      if (occurredAt.millisecondsSinceEpoch <= 0) continue;
      final offsetMs = startMs < 0 ? 0 : startMs;
      return occurredAt.subtract(Duration(milliseconds: offsetMs));
    }
    if (anchorOccurredAt.millisecondsSinceEpoch > 0) {
      return anchorOccurredAt;
    }
    return fallbackCallStart;
  }

  int? _resolveSelectedSegmentIndex({
    required List<Map<String, dynamic>> segments,
    required DateTime? selectedAt,
    required DateTime? callStart,
    required DateTime anchorOccurredAt,
  }) {
    if (selectedAt == null) return null;

    int? containingIndex;
    int? nearestIndex;
    var nearestDistanceMs = 1 << 30;

    for (var i = 0; i < segments.length; i++) {
      final range = _segmentAbsoluteRange(
        segments[i],
        callStart: callStart,
        anchorOccurredAt: anchorOccurredAt,
      );
      if (range == null) continue;

      if (!selectedAt.isBefore(range.start) && !selectedAt.isAfter(range.end)) {
        containingIndex = i;
        break;
      }

      final distanceMs = selectedAt.isBefore(range.start)
          ? range.start.difference(selectedAt).inMilliseconds
          : selectedAt.difference(range.end).inMilliseconds;
      if (distanceMs < nearestDistanceMs) {
        nearestDistanceMs = distanceMs;
        nearestIndex = i;
      }
    }

    if (containingIndex != null) return containingIndex;
    // Accept nearest fallback up to 12 seconds away to absorb clock drift/jitter.
    if (nearestIndex != null && nearestDistanceMs <= 12000) return nearestIndex;
    return null;
  }

  GlobalKey _keyForTranscriptRow(int index) {
    return _transcriptRowKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scrollTranscriptToSelectedSegment() {
    final selectedAt = _selectedSentimentAt;
    final segments = _transcriptSegments;
    if (selectedAt == null || segments.isEmpty) return;

    final anchorOccurredAt = _safeDate(segments.first['occurredAt']);
    final callStart = _resolveTranscriptCallStart(
      segments: segments,
      anchorOccurredAt: anchorOccurredAt,
      fallbackCallStart: _callStart,
    );
    final selectedIndex = _resolveSelectedSegmentIndex(
      segments: segments,
      selectedAt: selectedAt,
      callStart: callStart,
      anchorOccurredAt: anchorOccurredAt,
    );
    if (selectedIndex == null) return;

    final rowContext = _transcriptRowKeys[selectedIndex]?.currentContext;
    if (rowContext == null) return;

    unawaited(
      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.25,
      ),
    );
  }

  List<_SegmentSentimentHit> _sentimentHitsForSegment(
    Map<String, dynamic> segment, {
    required DateTime? callStart,
    required DateTime anchorOccurredAt,
    required bool isDark,
  }) {
    final range = _segmentAbsoluteRange(
      segment,
      callStart: callStart,
      anchorOccurredAt: anchorOccurredAt,
    );
    if (range == null) return const [];

    final hits = <_SegmentSentimentHit>[];
    for (final event in _callTelemetry) {
      final eventType = (event['eventType'] as String?)?.toUpperCase() ?? '';
      if (!eventType.startsWith('SENTIMENT_')) continue;
      final resolvedChannel = _resolveEventChannel(event);
      if (resolvedChannel == null) continue;

      final score = (event['sentimentScore'] as num?)?.toDouble();
      if (score == null) continue;

      final at = _safeDate(event['occurredAt']);
      if (at.isBefore(range.start) || at.isAfter(range.end)) continue;

      final channel =
          resolvedChannel == _TimelineChannel.voice ? 'VOICE' : 'VIDEO';
      final color = SentimentColors.forChannel(channel, isDark: isDark);
      final rawLabel = (event['sentimentLabel'] as String?)?.trim();
      final label = (rawLabel == null || rawLabel.isEmpty)
          ? _toClinicalLabelFromScore(score)
          : _toClinicalLabel(rawLabel);

      hits.add(
        _SegmentSentimentHit(
          timeText: _formatAbsoluteTime(at),
          channel: channel,
          label: label,
          color: color,
          occurredAt: at,
        ),
      );
    }

    hits.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return hits;
  }

  _SegmentAbsoluteRange? _segmentAbsoluteRange(
    Map<String, dynamic> segment, {
    required DateTime? callStart,
    required DateTime anchorOccurredAt,
  }) {
    final startMs = _asInt(segment['startMs']);
    final endMs = _asInt(segment['endMs']);

    DateTime? start;
    DateTime? end;

    if (callStart != null && startMs != null) {
      start = callStart.add(Duration(milliseconds: startMs));
    }
    if (callStart != null && endMs != null) {
      end = callStart.add(Duration(milliseconds: endMs));
    }

    if (start == null) {
      final fallbackStart = _fallbackStartMs(
        segment['occurredAt'],
        anchorOccurredAt,
      );
      if (fallbackStart != null) {
        start = anchorOccurredAt.add(Duration(milliseconds: fallbackStart));
      }
    }

    if (end == null && start != null) {
      if (endMs != null && startMs != null && endMs >= startMs) {
        end = start.add(Duration(milliseconds: endMs - startMs));
      } else {
        end = start.add(const Duration(seconds: 2));
      }
    }

    if (start == null || end == null) return null;
    if (end.isBefore(start)) end = start;
    return _SegmentAbsoluteRange(start: start, end: end);
  }

  String _toClinicalLabelFromScore(double score) {
    if (score >= SentimentColors.calmThreshold) return 'CALM';
    if (score >= SentimentColors.anxiousThreshold) return 'ANXIOUS';
    return 'DISTRESSED';
  }

  String _formatAbsoluteTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatSegmentRange(
    dynamic startMs,
    dynamic endMs, {
    dynamic occurredAt,
    DateTime? anchorOccurredAt,
  }) {
    final start = _asInt(startMs);
    final end = _asInt(endMs);
    if (start == null && end == null) {
      final fallbackStart = _fallbackStartMs(occurredAt, anchorOccurredAt);
      if (fallbackStart != null) {
        return '[${_formatMs(fallbackStart)}]';
      }
      return '[--:--]';
    }
    if (start != null && end != null) {
      return '[${_formatMs(start)}-${_formatMs(end)}]';
    }
    if (start != null) {
      return '[${_formatMs(start)}-..:..]';
    }
    return '[..:..-${_formatMs(end!)}]';
  }

  int? _fallbackStartMs(dynamic occurredAt, DateTime? anchorOccurredAt) {
    if (anchorOccurredAt == null) {
      return null;
    }
    final at = _safeDate(occurredAt);
    if (at.millisecondsSinceEpoch <= 0 ||
        anchorOccurredAt.millisecondsSinceEpoch <= 0) {
      return null;
    }
    final delta = at.difference(anchorOccurredAt).inMilliseconds;
    return delta < 0 ? 0 : delta;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _formatMs(int ms) {
    final clamped = ms < 0 ? 0 : ms;
    final totalSeconds = clamped ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PendingSummaryItem {
  final String category;
  final String itemId;
  final String description;
  final Map<String, dynamic> raw;

  const _PendingSummaryItem({
    required this.category,
    required this.itemId,
    required this.description,
    required this.raw,
  });
}

// ── Summary section ───────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final bool isDark;
  final String finalOverallScore;
  final String finalOverallLabel;
  final String finalOverallNotes;
  final String caregiverRecommendation;
  final String? callSummaryHeadline;
  final String? callSummaryAssessment;
  final List<String> callSummaryConcerns;
  final List<String> callSummaryActions;
  final String finalCallStatus;
  final String callDuration;
  final Map<String, double> timeInStatePct;
  final int sampleCount;
  final double? stabilityScore;
  final VoidCallback? onCallAgain;
  final VoidCallback? onSendMessage;

  const _SummarySection({
    required this.isDark,
    required this.finalOverallScore,
    required this.finalOverallLabel,
    required this.finalOverallNotes,
    required this.caregiverRecommendation,
    required this.callSummaryHeadline,
    required this.callSummaryAssessment,
    required this.callSummaryConcerns,
    required this.callSummaryActions,
    required this.finalCallStatus,
    required this.callDuration,
    required this.timeInStatePct,
    required this.sampleCount,
    required this.stabilityScore,
    this.onCallAgain,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overallColor = SentimentColors.forLabel(
      finalOverallLabel,
      isDark: isDark,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: duration + status ──────────────────────
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  callDuration,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.06)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    finalCallStatus,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Time-in-state distribution ─────────────────────────
            Text(
              'EMOTIONAL STATE DISTRIBUTION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 8),
            _StateDistributionRow(
              timeInStatePct: timeInStatePct,
              sampleCount: sampleCount,
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // ── Stability bar ──────────────────────────────────────
            _StabilityBar(score: stabilityScore, isDark: isDark),
            const SizedBox(height: 16),

            // ── Overall assessment ─────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  finalOverallLabel == '--' ? '' : finalOverallLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: overallColor,
                  ),
                ),
                if (finalOverallScore != '--') ...[
                  const SizedBox(width: 8),
                  Text(
                    finalOverallScore,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: overallColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
            if (finalOverallNotes != '--') ...[
              const SizedBox(height: 4),
              Text(
                finalOverallNotes,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              caregiverRecommendation,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            if (callSummaryHeadline != null ||
                callSummaryAssessment != null ||
                callSummaryConcerns.isNotEmpty ||
                callSummaryActions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Call summary',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              if (callSummaryHeadline != null) ...[
                const SizedBox(height: 6),
                Text(
                  callSummaryHeadline!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
              if (callSummaryAssessment != null) ...[
                const SizedBox(height: 6),
                Text(
                  callSummaryAssessment!,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
              if (callSummaryConcerns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Key concerns: ${callSummaryConcerns.join(' | ')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
              if (callSummaryActions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Actions: ${callSummaryActions.join(' | ')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ],
            // ── Action buttons ─────────────────────────────────────
            if (onCallAgain != null || onSendMessage != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  if (onCallAgain != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCallAgain,
                        icon: const Icon(Icons.videocam_outlined, size: 18),
                        label: const Text('Call Again'),
                      ),
                    ),
                  if (onCallAgain != null && onSendMessage != null)
                    const SizedBox(width: 12),
                  if (onSendMessage != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSendMessage,
                        icon: const Icon(Icons.message_outlined, size: 18),
                        label: const Text('Send Message'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── State distribution row ────────────────────────────────────────────────────

class _StateDistributionRow extends StatelessWidget {
  final Map<String, double> timeInStatePct;
  final int sampleCount;
  final bool isDark;

  const _StateDistributionRow({
    required this.timeInStatePct,
    required this.sampleCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final calm = timeInStatePct['CALM'] ?? 0.0;
    final anxious = timeInStatePct['ANXIOUS'] ?? 0.0;
    final distressed = timeInStatePct['DISTRESSED'] ?? 0.0;
    final hasData = (calm + anxious + distressed) > 0;

    if (!hasData) {
      return Text(
        'No sentiment data available for this call.',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stacked proportional bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              if (calm > 0)
                Flexible(
                  flex: (calm * 1000).round(),
                  child: Container(
                    height: 10,
                    color: SentimentColors.forScore(0.8, isDark: isDark),
                  ),
                ),
              if (anxious > 0)
                Flexible(
                  flex: (anxious * 1000).round(),
                  child: Container(
                    height: 10,
                    color: SentimentColors.forScore(0.5, isDark: isDark),
                  ),
                ),
              if (distressed > 0)
                Flexible(
                  flex: (distressed * 1000).round(),
                  child: Container(
                    height: 10,
                    color: SentimentColors.forScore(0.1, isDark: isDark),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Label chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (calm > 0)
              _StatChip(
                label: 'CALM',
                value: '${(calm * 100).round()}%',
                color: SentimentColors.forScore(0.8, isDark: isDark),
                isDark: isDark,
              ),
            if (anxious > 0)
              _StatChip(
                label: 'ANXIOUS',
                value: '${(anxious * 100).round()}%',
                color: SentimentColors.forScore(0.5, isDark: isDark),
                isDark: isDark,
              ),
            if (distressed > 0)
              _StatChip(
                label: 'DISTRESSED',
                value: '${(distressed * 100).round()}%',
                color: SentimentColors.forScore(0.1, isDark: isDark),
                isDark: isDark,
              ),
          ],
        ),
        if (sampleCount <= 1) ...[
          const SizedBox(height: 6),
          Text(
            'Based on final assessment only — not enough readings for a full timeline.',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label  $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stability bar ─────────────────────────────────────────────────────────────

class _StabilityBar extends StatelessWidget {
  final double? score; // null = insufficient data
  final bool isDark;

  const _StabilityBar({required this.score, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasData = score != null;
    final color = hasData
        ? SentimentColors.forScore(score!, isDark: isDark)
        : (isDark ? Colors.white38 : Colors.black45);
    final pct = hasData ? '${(score! * 100).round()}%' : 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'EMOTIONAL STABILITY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const Spacer(),
            Text(
              pct,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                height: 8,
                color: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.08),
              ),
              FractionallySizedBox(
                widthFactor: hasData ? score!.clamp(0.0, 1.0) : 0.0,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.7), color],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Painters & helpers ────────────────────────────────────────────────────────

enum _TimelineChannel {
  all('All'),
  voice('Voice'),
  video('Video');

  final String label;
  const _TimelineChannel(this.label);
}

enum _CallTimelineWindow {
  fullCall('Full call'),
  first5('First 5 min'),
  first15('First 15 min'),
  last5('Last 5 min'),
  last15('Last 15 min'),
  custom('Custom range');

  final String label;
  const _CallTimelineWindow(this.label);
}

class _TimelineWindowSpan {
  final double startMinute;
  final double endMinute;

  const _TimelineWindowSpan({
    required this.startMinute,
    required this.endMinute,
  });
}

class _ScoreSample {
  final double minuteOffset;
  final double score;
  final DateTime occurredAt;
  const _ScoreSample({
    required this.minuteOffset,
    required this.score,
    required this.occurredAt,
  });
}

class _SegmentAbsoluteRange {
  final DateTime start;
  final DateTime end;

  const _SegmentAbsoluteRange({required this.start, required this.end});
}

class _SegmentSentimentHit {
  final String timeText;
  final String channel;
  final String label;
  final Color color;
  final DateTime occurredAt;

  const _SegmentSentimentHit({
    required this.timeText,
    required this.channel,
    required this.label,
    required this.color,
    required this.occurredAt,
  });
}

class _SentimentTimelinePainter extends CustomPainter {
  final double durationMinutes;
  final Map<_TimelineChannel, List<_ScoreSample>> series;
  final Map<_TimelineChannel, Color> channelColors;
  final bool isDark;
  final double? selectedMinute;
  final double? selectedScore;

  const _SentimentTimelinePainter({
    required this.durationMinutes,
    required this.series,
    required this.channelColors,
    required this.isDark,
    required this.selectedMinute,
    required this.selectedScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (durationMinutes <= 0) return;
    const leftPad   = 72.0;
    const rightPad  = 20.0;
    const topPad    = 20.0;
    const bottomPad = 44.0;

    final plotWidth  = math.max(1.0, size.width  - leftPad - rightPad);
    final plotHeight = math.max(1.0, size.height - topPad  - bottomPad);
    final plotRect   = Rect.fromLTWH(leftPad, topPad, plotWidth, plotHeight);

    // Frame
    canvas.drawRect(
      plotRect,
      Paint()
        ..color = (isDark ? Colors.white24 : Colors.grey.shade400)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);
    double yForScore(double s) =>
        plotRect.bottom - s.clamp(0.0, 1.0) * plotRect.height;

    // Band fills
    final bands = <(double lo, double hi, double midScore)>[
      (0.60, 1.00, 0.80), // calm
      (0.35, 0.60, 0.50), // anxious
      (0.00, 0.35, 0.10), // distressed
    ];
    for (final (lo, hi, mid) in bands) {
      canvas.drawRect(
        Rect.fromLTRB(
          plotRect.left, yForScore(hi), plotRect.right, yForScore(lo),
        ),
        Paint()
          ..color = SentimentColors.forScore(mid, isDark: isDark)
                    .withValues(alpha: isDark ? 0.14 : 0.10),
      );
    }

    // Band mid-line guidelines
    for (final (lo, hi, mid) in bands) {
      final y = (yForScore(lo) + yForScore(hi)) / 2;
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        Paint()
          ..color = SentimentColors.forScore(mid, isDark: isDark)
                    .withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // Y-axis ticks + labels
    final axisColor = isDark ? Colors.white38 : Colors.grey.shade600;
    for (final tick in [1.0, 0.8, 0.6, 0.4, 0.2, 0.0]) {
      final y = yForScore(tick);
      canvas.drawLine(
        Offset(leftPad - 6, y), Offset(leftPad, y),
        Paint()..color = axisColor,
      );
      tp.text = TextSpan(
        text: tick.toStringAsFixed(1),
        style: TextStyle(color: axisColor, fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas,
          Offset(leftPad - tp.width - 10, y - tp.height / 2));
    }

    // Y-axis title
    tp.text = TextSpan(
      text: 'Sentiment score (0–1)',
      style: TextStyle(color: axisColor, fontSize: 11),
    );
    tp.layout();
    canvas.save();
    canvas.translate(14, topPad + plotHeight / 2 + tp.width / 2);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset.zero);
    canvas.restore();

    // Data lines
    for (final entry in series.entries) {
      final points = entry.value;
      if (points.isEmpty) continue;
      final color = channelColors[entry.key] ??
          SentimentColors.forChannel(
            entry.key.name.toUpperCase(), isDark: isDark,
          );

      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x = leftPad +
            (points[i].minuteOffset / durationMinutes) * plotWidth;
        final y = yForScore(points[i].score);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke,
      );
    }

    if (selectedMinute != null && selectedScore != null) {
      final sx =
          leftPad + (selectedMinute!.clamp(0.0, durationMinutes) / durationMinutes) * plotWidth;
      final sy = yForScore(selectedScore!.clamp(0.0, 1.0));
      final marker = SentimentColors.forScore(selectedScore!, isDark: isDark);
      canvas.drawLine(
        Offset(sx, plotRect.top),
        Offset(sx, plotRect.bottom),
        Paint()
          ..color = marker.withValues(alpha: 0.7)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        Offset(sx, sy),
        7,
        Paint()
          ..color = marker.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(sx, sy),
        4,
        Paint()..color = marker,
      );
    }

    // X-axis ticks + labels
    const tickCount = 5;
    for (var i = 0; i < tickCount; i++) {
      final ratio     = i / (tickCount - 1);
      final x         = leftPad + ratio * plotWidth;
      final tickMinute = durationMinutes * ratio;
      canvas.drawLine(
        Offset(x, plotRect.bottom), Offset(x, plotRect.bottom + 6),
        Paint()..color = axisColor,
      );
      tp.text = TextSpan(
        text: _formatMinuteTick(tickMinute),
        style: TextStyle(color: axisColor, fontSize: 11),
      );
      tp.layout();
      tp.paint(canvas,
          Offset(x - tp.width / 2, plotRect.bottom + 10));
    }

    // X-axis title
    tp.text = TextSpan(
      text: 'Elapsed Time',
      style: TextStyle(color: axisColor, fontSize: 12),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(leftPad + plotWidth / 2 - tp.width / 2,
             size.height - tp.height),
    );
  }

  String _formatMinuteTick(double minute) {
    final totalSeconds = (minute * 60).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  bool shouldRepaint(covariant _SentimentTimelinePainter old) =>
      old.durationMinutes != durationMinutes ||
      old.series != series ||
      old.channelColors != channelColors ||
      old.isDark != isDark ||
      old.selectedMinute != selectedMinute ||
      old.selectedScore != selectedScore;
}

class _TimelineLegend extends StatelessWidget {
  final Map<_TimelineChannel, Color> channelColors;
  final bool isDark;

  const _TimelineLegend({
    required this.channelColors,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _LegendChip(
          label: 'Calm',
          color: SentimentColors.forScore(0.8, isDark: isDark),
        ),
        _LegendChip(
          label: 'Anxious',
          color: SentimentColors.forScore(0.5, isDark: isDark),
        ),
        _LegendChip(
          label: 'Distressed',
          color: SentimentColors.forScore(0.1, isDark: isDark),
        ),
        _LegendChip(
          label: 'Voice',
          color: channelColors[_TimelineChannel.voice] ??
              SentimentColors.forChannel('VOICE', isDark: isDark),
        ),
        _LegendChip(
          label: 'Video',
          color: channelColors[_TimelineChannel.video] ??
              SentimentColors.forChannel('VIDEO', isDark: isDark),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _RecordingMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RecordingMetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isDark ? Colors.white54 : Colors.black45),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

