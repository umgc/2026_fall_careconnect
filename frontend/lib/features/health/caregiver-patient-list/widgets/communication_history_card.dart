import 'dart:convert';

import 'package:flutter/material.dart';

class CommunicationHistoryCard extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final void Function(String callId)? onCallTap;

  const CommunicationHistoryCard({
    super.key,
    required this.events,
    this.onCallTap,
  });

  @override
  State<CommunicationHistoryCard> createState() =>
      _CommunicationHistoryCardState();
}

class _CommunicationHistoryCardState extends State<CommunicationHistoryCard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summaries = _buildSummaries(widget.events);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.10),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: cs.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Telehealth Communication History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (summaries.isEmpty)
            Text(
              'No telehealth call records available for this patient.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              '${summaries.length} calls recorded',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: summaries.length > 5,
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  primary: false,
                  itemCount: summaries.length,
                  itemBuilder: (context, index) {
                    final summary = summaries[index];
                    final finalBadgeText = _buildFinalBadgeText(summary);
                    final isInteractive = widget.onCallTap != null;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.call, color: cs.primary),
                      onTap: widget.onCallTap == null
                          ? null
                          : () => widget.onCallTap!(summary.callId),
                      title: Text(
                        _formatCallTitle(summary.callId),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${_formatDate(summary.lastOccurredAt)} - '
                        '${summary.callOutcome} - '
                        '${summary.isCareTeamCall ? 'Care-team call' : '${summary.sentimentEvents} sentiment samples'}',
                      ),
                      trailing: isInteractive
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (finalBadgeText != null)
                                  Text(
                                    finalBadgeText,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: _colorForLabel(
                                        context,
                                        summary.finalSentimentLabel,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'View details',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : (finalBadgeText == null
                              ? null
                              : Text(
                                  finalBadgeText,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _colorForLabel(
                                      context,
                                      summary.finalSentimentLabel,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                )),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_CallSummary> _buildSummaries(List<Map<String, dynamic>> source) {
    final byCallId = <String, _CallSummary>{};

    for (final event in source) {
      final rawCallId = (event['callId'] ?? '').toString().trim();
      if (rawCallId.isEmpty) continue;

      final occurredAt = _parseDate(event['occurredAt']) ?? DateTime.now();
      final eventType = (event['eventType'] ?? '').toString().toUpperCase();
      final sentimentLabel = (event['sentimentLabel'] ?? '').toString().trim();
      final sentimentScore = (event['sentimentScore'] as num?)?.toDouble();
      final metadata = _extractJsonMap(event['metadataJson']);
      final callKind =
          (metadata['callKind'] ?? '').toString().trim().toUpperCase();
      final isCareTeamCall = callKind == 'CARE_TEAM';

      final existing = byCallId[rawCallId];
      if (existing == null) {
        byCallId[rawCallId] = _CallSummary(
          callId: rawCallId,
          lastOccurredAt: occurredAt,
          totalEvents: 1,
          sentimentEvents: eventType.startsWith('SENTIMENT_') ? 1 : 0,
          lastSentimentLabel: sentimentLabel.isEmpty ? null : sentimentLabel,
          finalSentimentLabel:
              eventType == 'SENTIMENT_FINAL' && sentimentLabel.isNotEmpty
                  ? sentimentLabel
                  : null,
          finalSentimentScore:
              eventType == 'SENTIMENT_FINAL' ? sentimentScore : null,
          callOutcome: _resolveCallOutcomeFromEvent(eventType, null),
          isCareTeamCall: isCareTeamCall,
        );
      } else {
        final hasFinal = existing.finalSentimentLabel != null ||
            existing.finalSentimentScore != null;
        byCallId[rawCallId] = _CallSummary(
          callId: existing.callId,
          lastOccurredAt: occurredAt.isAfter(existing.lastOccurredAt)
              ? occurredAt
              : existing.lastOccurredAt,
          totalEvents: existing.totalEvents + 1,
          sentimentEvents: existing.sentimentEvents +
              (eventType.startsWith('SENTIMENT_') ? 1 : 0),
          lastSentimentLabel: sentimentLabel.isNotEmpty
              ? sentimentLabel
              : existing.lastSentimentLabel,
          finalSentimentLabel: hasFinal
              ? existing.finalSentimentLabel
              : (eventType == 'SENTIMENT_FINAL' && sentimentLabel.isNotEmpty
                  ? sentimentLabel
                  : null),
          finalSentimentScore: hasFinal
              ? existing.finalSentimentScore
              : (eventType == 'SENTIMENT_FINAL' ? sentimentScore : null),
          callOutcome:
              _resolveCallOutcomeFromEvent(eventType, existing.callOutcome),
          isCareTeamCall: existing.isCareTeamCall || isCareTeamCall,
        );
      }
    }

    final summaries = byCallId.values.toList();
    summaries.sort((a, b) => b.lastOccurredAt.compareTo(a.lastOccurredAt));
    return summaries;
  }

  Map<String, dynamic> _extractJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map(
            (key, item) => MapEntry(key.toString(), item),
          );
        }
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  String? _buildFinalBadgeText(_CallSummary summary) {
    if (summary.isCareTeamCall) {
      return null;
    }
    if (summary.finalSentimentScore == null &&
        (summary.finalSentimentLabel == null ||
            summary.finalSentimentLabel!.isEmpty)) {
      return null;
    }

    final scoreText = summary.finalSentimentScore == null
        ? null
        : '${(summary.finalSentimentScore! * 100).toStringAsFixed(1)}%';
    final labelText = summary.finalSentimentLabel;

    if (scoreText != null && labelText != null && labelText.isNotEmpty) {
      return '$scoreText $labelText';
    }
    return scoreText ?? labelText;
  }

  String _resolveCallOutcomeFromEvent(
      String eventType, String? existingOutcome) {
    if (existingOutcome != null && existingOutcome != '--') {
      return existingOutcome;
    }
    switch (eventType) {
      case 'WS_DECLINE_CALL':
        return 'Rejected';
      case 'WS_ACCEPT_CALL':
      case 'CALL_JOIN':
        return 'Accepted';
      case 'WS_END_CALL':
      case 'CALL_END':
        return 'Ended';
      default:
        return '--';
    }
  }

  Color _colorForLabel(BuildContext context, String? label) {
    final l = (label ?? '').toUpperCase();
    if (l == 'POSITIVE' || l == 'CALM') {
      return Colors.green.shade700;
    }
    if (l == 'NEGATIVE' || l == 'DISTRESSED' || l == 'ANXIOUS') {
      return Colors.red.shade700;
    }
    if (l == 'NEUTRAL') {
      return Colors.amber.shade800;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _formatCallTitle(String callId) {
    final normalized = callId.trim();
    if (normalized.isEmpty) {
      return 'Telehealth call';
    }

    // Keep SDK/vendor-specific identifiers out of user-facing UI.
    final cleaned = normalized
        .replaceFirst(
          RegExp(
            r'^(chime|twilio|agora|vonage)[_-]call[_-]?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'^[a-z]+[_-]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

    if (cleaned.length >= 4) {
      return 'Telehealth call #${cleaned.substring(cleaned.length - 4)}';
    }
    return 'Telehealth call';
  }
}

class _CallSummary {
  final String callId;
  final DateTime lastOccurredAt;
  final int totalEvents;
  final int sentimentEvents;
  final String? lastSentimentLabel;
  final String? finalSentimentLabel;
  final double? finalSentimentScore;
  final String callOutcome;
  final bool isCareTeamCall;

  const _CallSummary({
    required this.callId,
    required this.lastOccurredAt,
    required this.totalEvents,
    required this.sentimentEvents,
    required this.lastSentimentLabel,
    required this.finalSentimentLabel,
    required this.finalSentimentScore,
    required this.callOutcome,
    required this.isCareTeamCall,
  });
}
