import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme/sentiment_colors.dart';

/// SentimentDashboardWidget — live emotional analysis panel during video calls.
///
/// Summary view: horizontal bar graphs for voice and video channels.
/// Each bar is tappable and navigates to a detailed drill-down view showing
/// the full history of that channel's scores as a line graph.
///
/// Color coding:
///   0.0 - 0.35 → red   (DISTRESSED)
///   0.35 - 0.60 → amber (ANXIOUS)
///   0.60 - 1.0 → green (CALM)
class SentimentDashboardWidget extends StatefulWidget {
  final Map<String, dynamic> sentimentData;
  final String callId;
  final Future<void> Function(String text)? onTextSend;

  const SentimentDashboardWidget({
    super.key,
    required this.sentimentData,
    required this.callId,
    this.onTextSend,
  });

  @override
  State<SentimentDashboardWidget> createState() =>
      _SentimentDashboardWidgetState();
}

class _SentimentDashboardWidgetState extends State<SentimentDashboardWidget>
    with SingleTickerProviderStateMixin {
  static const int _displayAverageWindow = 4;

  // History for the detail charts — up to 30 data points per channel
  final List<_SentimentPoint> _textHistory = [];
  final List<_SentimentPoint> _voiceHistory = [];
  final List<_SentimentPoint> _videoHistory = [];

  late AnimationController _animController;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didUpdateWidget(SentimentDashboardWidget old) {
    super.didUpdateWidget(old);
    // When new sentiment data arrives, record it in history
    if (widget.sentimentData != old.sentimentData &&
        widget.sentimentData.isNotEmpty) {
      _recordHistory();
      _animController.forward(from: 0);
    }
  }

  void _recordHistory() {
    final now = DateTime.now();
    final text = widget.sentimentData['text'];
    final voice = widget.sentimentData['voice'];
    final video = widget.sentimentData['video'];

    bool isCompleted(dynamic section) {
      if (section is! Map<String, dynamic>) return false;
      return ((section['status'] as String?) ?? 'COMPLETED').toUpperCase() ==
          'COMPLETED';
    }

    if (isCompleted(text)) {
      _textHistory.add(
        _SentimentPoint(
          now,
          ((text as Map<String, dynamic>)['score'] as num).toDouble(),
          ((text)['label'] as String?) ?? 'ANXIOUS',
        ),
      );
    }
    if (isCompleted(voice)) {
      _voiceHistory.add(
        _SentimentPoint(
          now,
          ((voice as Map<String, dynamic>)['score'] as num).toDouble(),
          ((voice)['label'] as String?) ?? 'ANXIOUS',
        ),
      );
    }
    if (isCompleted(video)) {
      _videoHistory.add(
        _SentimentPoint(
          now,
          ((video as Map<String, dynamic>)['score'] as num).toDouble(),
          ((video)['label'] as String?) ?? 'ANXIOUS',
        ),
      );
    }

    // Keep last 30 points
    if (_textHistory.length > 30) _textHistory.removeAt(0);
    if (_voiceHistory.length > 30) _voiceHistory.removeAt(0);
    if (_videoHistory.length > 30) _videoHistory.removeAt(0);
  }

  @override
  void dispose() {
    _animController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  // ================================================================
  // EXTRACT SCORES from sentiment data payload
  // ================================================================

  double _score(String channel) {
    final data = widget.sentimentData[channel.toLowerCase()];
    if (data == null) return 0.5;
    return (data['score'] as num?)?.toDouble() ?? 0.5;
  }

  String _status(String channel) {
    final data = widget.sentimentData[channel.toLowerCase()];
    if (data == null) return 'AWAITING';
    return ((data['status'] as String?) ?? 'COMPLETED').toUpperCase();
  }

  String _notes(String channel) {
    final data = widget.sentimentData[channel.toLowerCase()];
    if (data == null) return '—';

    final rawNotes = (data['notes'] as String?) ?? '—';
    if (channel.toUpperCase() != 'VOICE') {
      return rawNotes;
    }

    final normalized = rawNotes.trim();
    final metricMatch = RegExp(
      r'level=([0-9]*\.?[0-9]+)\s+speech=([0-9]*\.?[0-9]+)\s+var=([0-9]*\.?[0-9]+)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (metricMatch == null) {
      return 'Voice activity from raw Chime metrics.';
    }

    final level = double.tryParse(metricMatch.group(1) ?? '');
    final speech = double.tryParse(metricMatch.group(2) ?? '');
    final variability = double.tryParse(metricMatch.group(3) ?? '');

    if (level == null || speech == null || variability == null) {
      return 'Voice activity from raw Chime metrics.';
    }

    final levelPct = (level * 100).round();
    final speechPct = (speech * 100).round();
    final varPct = (variability * 100).round();

    return 'Speech activity $speechPct%, mic level $levelPct%, variability $varPct%.';
  }

  List<_SentimentPoint> _historyForChannel(String channel) {
    switch (channel.toUpperCase()) {
      case 'TEXT':
        return _textHistory;
      case 'VOICE':
        return _voiceHistory;
      case 'VIDEO':
        return _videoHistory;
      default:
        return const <_SentimentPoint>[];
    }
  }

  double _smoothedChannelScore(String channel) {
    if (channel.toUpperCase() == 'VOICE') {
      // Voice is intentionally shown raw to match direct Chime metric plotting.
      return _score(channel);
    }

    final history = _historyForChannel(channel);
    if (history.isEmpty) {
      return _score(channel);
    }

    final take = math.min(_displayAverageWindow, history.length);
    var sum = 0.0;
    for (var i = history.length - take; i < history.length; i++) {
      sum += history[i].score;
    }
    return sum / take;
  }

  double _smoothedOverallScore() {
    var sum = 0.0;
    var count = 0;
    for (final channel in const ['VOICE', 'VIDEO']) {
      if (_status(channel) == 'COMPLETED') {
        sum += _smoothedChannelScore(channel);
        count += 1;
      }
    }

    if (count == 0) {
      return _overallScore();
    }
    return sum / count;
  }

  double _overallScore() {
    final overall = widget.sentimentData['overall'];
    if (overall == null) return 0.5;
    return (overall['score'] as num?)?.toDouble() ?? 0.5;
  }

  String _labelFromScore(double score) {
    if (score >= 0.60) return 'CALM';
    if (score >= 0.35) return 'ANXIOUS';
    return 'DISTRESSED';
  }

  String _overallStatus() {
    final overall = widget.sentimentData['overall'];
    if (overall == null) return 'AWAITING';
    return ((overall['status'] as String?) ?? 'COMPLETED').toUpperCase();
  }

  List<String> _mutedChannels() {
    final muted = <String>[];
    for (final channel in const ['voice', 'video']) {
      final status = _status(channel);
      if (status == 'MUTED') {
        muted.add(channel);
      }
    }
    return muted;
  }

  Widget _buildChannelMutedBanner(bool isDark) {
    final mutedChannels = _mutedChannels();
    if (mutedChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final bgColor = isDark ? Colors.orange.shade900 : Colors.orange.shade100;
    final textColor = isDark ? Colors.orange.shade100 : Colors.orange.shade900;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: mutedChannels
            .map(
              (channel) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${channel[0].toUpperCase()}${channel.substring(1)}: Channel Muted',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F7FA);
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPanelHeader(isDark),
          _buildChannelMutedBanner(isDark),
          _buildBarGraphRow(isDark),
          _buildOverallScore(isDark),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  // ================================================================
  // PANEL HEADER — title + last updated timestamp
  // ================================================================

  Widget _buildPanelHeader(bool isDark) {
    final hasData = widget.sentimentData.isNotEmpty;
    final overallStatus = _overallStatus();
    final overallDisplayScore = _smoothedOverallScore();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.monitor_heart,
            size: 16,
            color: isDark ? Colors.tealAccent : Colors.teal.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            'Live Emotional Analysis',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const Spacer(),
          if (hasData)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(
                  overallStatus,
                  overallDisplayScore,
                  isDark: isDark,
                ).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _statusColor(
                    overallStatus,
                    overallDisplayScore,
                    isDark: isDark,
                  ).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                overallStatus == 'COMPLETED'
                    ? _labelFromScore(overallDisplayScore)
                    : overallStatus,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _statusColor(overallStatus, overallDisplayScore,
                      isDark: isDark),
                ),
              ),
            )
          else
            Text(
              'Awaiting data...',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }

  // ================================================================
  // THREE BAR GRAPHS — side by side, each tappable
  // ================================================================

  Widget _buildBarGraphRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _buildChannelBar(
              channel: 'VOICE',
              icon: Icons.mic_none,
              history: _voiceHistory,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildChannelBar(
              channel: 'VIDEO',
              icon: Icons.videocam_outlined,
              history: _videoHistory,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBar({
    required String channel,
    required IconData icon,
    required List<_SentimentPoint> history,
    required bool isDark,
  }) {
    final score = _smoothedChannelScore(channel);
    final status = _status(channel);
    final hasUsableSample = status == 'COMPLETED';
    final label = hasUsableSample ? _labelFromScore(score) : status;
    final notes = hasUsableSample
        ? _notes(channel)
        : (status == 'DEGRADED'
            ? 'Insights are briefly paused. Your call is still running normally.'
            : (status == 'QUIET'
                ? 'No speech detected in this window.'
                : 'Listening for a stable signal...'));
    final color = _statusColor(status, score, isDark: isDark);
    final cardBg = isDark ? const Color(0xFF252540) : Colors.white;

    return GestureDetector(
      onTap: () => _openDetailView(channel, history, icon),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) => child!,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Channel label + icon
              Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Text(
                    channel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 12,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Horizontal bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    // Background track
                    Container(
                      height: 8,
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                    // Filled bar
                    FractionallySizedBox(
                      widthFactor:
                          hasUsableSample ? score.clamp(0.0, 1.0) : 0.0,
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
              const SizedBox(height: 6),

              // Score percentage
              Text(
                hasUsableSample ? '${(score * 100).toStringAsFixed(0)}%' : '—',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),

              // Label
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),

              // Clinical notes
              Text(
                notes,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // OVERALL SCORE BAR
  // ================================================================

  Widget _buildOverallScore(bool isDark) {
    final score = _smoothedOverallScore();
    final status = _overallStatus();
    final hasUsableSample = status == 'COMPLETED' || status == 'DEGRADED';
    final color = _statusColor(status, score, isDark: isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            'OVERALL',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                  FractionallySizedBox(
                    widthFactor: hasUsableSample ? score.clamp(0.0, 1.0) : 0.0,
                    child: Container(height: 6, color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hasUsableSample ? '${(score * 100).toStringAsFixed(0)}%' : '—',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // INLINE CHAT INPUT — sends text for sentiment analysis
  // ================================================================

  // ================================================================
  // DETAIL VIEW — full screen chart for one channel
  // Navigated to when user taps a bar
  // ================================================================

  void _openDetailView(
    String channel,
    List<_SentimentPoint> history,
    IconData icon,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SentimentDetailScreen(
          channel: channel,
          icon: icon,
          history: List.from(history),
          callId: widget.callId,
          currentScore: _smoothedChannelScore(channel),
          currentLabel: _labelFromScore(_smoothedChannelScore(channel)),
          currentNotes: _notes(channel),
        ),
      ),
    );
  }

  // ================================================================
  // COLOR HELPER
  // ================================================================

  static Color _statusColor(String status, double score,
          {bool isDark = false}) =>
      SentimentColors.forStatus(status, score, isDark: isDark);
}

// ================================================================
// DETAIL SCREEN — line graph history for a single channel
// ================================================================

class _SentimentDetailScreen extends StatelessWidget {
  final String channel;
  final IconData icon;
  final List<_SentimentPoint> history;
  final String callId;
  final double currentScore;
  final String currentLabel;
  final String currentNotes;

  const _SentimentDetailScreen({
    required this.channel,
    required this.icon,
    required this.history,
    required this.callId,
    required this.currentScore,
    required this.currentLabel,
    required this.currentNotes,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = SentimentColors.forChannel(channel, isDark: isDark);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        title: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              '$channel Sentiment',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current snapshot card
            _buildSnapshotCard(isDark, color),
            const SizedBox(height: 24),

            // History chart header
            Text(
              'Score History',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),

            // Line chart
            Expanded(
              child: history.isEmpty
                  ? _buildNoData(isDark)
                  : _SentimentLineChart(
                      history: history,
                      color: color,
                      isDark: isDark,
                    ),
            ),

            // Legend
            const SizedBox(height: 16),
            _buildLegend(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotCard(bool isDark, Color color) {
    final cardBg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Score ring
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: currentScore,
                  strokeWidth: 6,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '${(currentScore * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentLabel,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentNotes,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 40,
            color: isDark ? Colors.white30 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            'No history yet.\nData points appear every 15 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(bool isDark) {
    final items = [
      (SentimentColors.forScore(0.8, isDark: isDark), 'Calm (>=60%)'),
      (SentimentColors.forScore(0.5, isDark: isDark), 'Anxious (35-60%)'),
      (SentimentColors.forScore(0.2, isDark: isDark), 'Distressed (<35%)'),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: item.$1, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              item.$2,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ================================================================
// LINE CHART — custom painter for sentiment history
// ================================================================

class _SentimentLineChart extends StatelessWidget {
  final List<_SentimentPoint> history;
  final Color color;
  final bool isDark;

  const _SentimentLineChart({
    required this.history,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: _LineChartPainter(
          points: history,
          lineColor: color,
          gridColor:
              isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
          labelColor: isDark ? Colors.white38 : Colors.black38,
          isDark: isDark,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_SentimentPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final bool isDark;

  _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const paddingLeft = 32.0;
    const paddingBottom = 24.0;
    const paddingTop = 8.0;
    const paddingRight = 8.0;

    final chartW = size.width - paddingLeft - paddingRight;
    final chartH = size.height - paddingTop - paddingBottom;

    // Grid lines at 0, 25, 50, 75, 100%
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(color: labelColor, fontSize: 9);

    for (final pct in [0, 25, 50, 75, 100]) {
      final y = paddingTop + chartH * (1 - pct / 100);
      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(paddingLeft + chartW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '$pct', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 4, y - tp.height / 2));
    }

    // Color zone fills
    void fillZone(double y0, double y1, Color c) {
      canvas.drawRect(
        Rect.fromLTRB(
          paddingLeft,
          paddingTop + chartH * y0,
          paddingLeft + chartW,
          paddingTop + chartH * y1,
        ),
        Paint()..color = c.withValues(alpha: 0.04),
      );
    }

    // Zones: y=0 is top (score=1.0), calm threshold=0.60→y=0.40, anxious=0.35→y=0.65
    fillZone(0.0, 0.40, SentimentColors.forScore(0.8, isDark: isDark));
    fillZone(0.40, 0.65, SentimentColors.forScore(0.5, isDark: isDark));
    fillZone(0.65, 1.0, SentimentColors.forScore(0.2, isDark: isDark));

    // Data line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = paddingLeft + chartW * i / math.max(points.length - 1, 1);
      final y = paddingTop + chartH * (1 - points[i].score.clamp(0.0, 1.0));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);

    // Data points
    final dotPaint = Paint()..color = lineColor;
    final dotBorder = Paint()
      ..color = isDark ? const Color(0xFF1A1A2E) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < points.length; i++) {
      final x = paddingLeft + chartW * i / math.max(points.length - 1, 1);
      final y = paddingTop + chartH * (1 - points[i].score.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
      canvas.drawCircle(Offset(x, y), 3.5, dotBorder);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points || old.isDark != isDark;
}

// ================================================================
// DATA CLASS
// ================================================================

class _SentimentPoint {
  final DateTime time;
  final double score;
  final String label;

  const _SentimentPoint(this.time, this.score, this.label);
}
