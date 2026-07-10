import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Current Mood Widget
class CurrentMoodWidget extends StatefulWidget {
  final int moodScore;
  final String moodLabel;
  final List<String> moodTags;
  final DateTime? date;
  final ValueChanged<double>? onAverageMoodChanged;

  const CurrentMoodWidget({
    super.key,
    required this.moodScore,
    required this.moodLabel,
    required this.moodTags,
    this.date,
    this.onAverageMoodChanged,
  });

  @override
  State<CurrentMoodWidget> createState() => _CurrentMoodWidgetState();
}

class _CurrentMoodWidgetState extends State<CurrentMoodWidget> {
  late int currentMoodScore;
  late String currentMoodLabel;
  List<Map<String, dynamic>> moodHistory = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    currentMoodScore = widget.moodScore;
    currentMoodLabel = widget.moodLabel;
    _loadMoodHistory();
  }

  /// Gets a mood icon based on score.
  String _getMoodEmoji(int score) {
    if (score == 10) return '\u{1F60A}';
    if (score == 9) return '\u{1F601}';
    if (score == 8) return '\u{1F604}';
    if (score == 7) return '\u{1F60A}';
    if (score == 6) return '\u{1F642}';
    if (score == 5) return '\u{1F610}';
    if (score == 4) return '\u{1F615}';
    if (score == 3) return '\u{1F641}';
    if (score == 2) return '\u{2639}\u{FE0F}';
    if (score == 1) return '\u{1F61E}';
    return '\u{1F614}';
  }

  String _getMoodLabel(int score) {
    if (score == 10) return 'Excellent';
    if (score >= 9) return 'Great';
    if (score >= 7) return 'Happy';
    if (score >= 5) return 'Okay';
    if (score >= 3) return 'Down';
    return 'Sad';
  }

  String _translateMood(String mood, AppLocalizations t){
    switch(mood){
      case('Sad'):
        return t.recentcheckinwidget_moodSad;
      case('Down'):
        return t.recentcheckinwidget_moodDown;
      case('Okay'):
        return t.recentcheckinwidget_moodOkay;
      case('Happy'):
        return t.recentcheckinwidget_moodHappy;
      case('Great'):
        return t.recentcheckinwidget_moodGreat;
      case('Excellent'):
        return t.recentcheckinwidget_moodExcellent;
      default:
        return mood;
    }
  }

  String _translateMoodTags(String tag, AppLocalizations t){
    switch(tag){
      case('happy'):
        return t.currentmoodwidget_moodTagHappy;
      case('calm'):
        return t.currentmoodwidget_moodTagCalm;
      case('positive'):
        return t.currentmoodwidget_moodTagPositive;
      case('comfortable'):
        return t.currentmoodwidget_moodTagComfortable;
      case('stable'):
        return t.currentmoodwidget_moodTagStable;
      case('neutral'):
        return t.currentmoodwidget_moodTagNeutral;
      case('watchful'):
        return t.currentmoodwidget_moodTagWatchful;
      case('low'):
        return t.currentmoodwidget_moodTagLow;
      case('monitoring'):
        return t.currentmoodwidget_moodTagMonitoring;
      case('no recent mood data'):
        return t.currentmoodwidget_noMoodTags;
      default:
        return tag;
    }
  }

  void _checkForAlerts() {
    // Placeholder for alert logic.
  }

  String _formatDate(DateTime date) {
    final t = AppLocalizations.of(context)!;
    final now = DateTime.now().toUtc();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return t.medicationreminderwidget_today;
    } else if (difference.inDays == 1) {
      return t.currentmoodwidget_yesterday;
    } else {
      return '${date.month}/${date.day}';
    }
  }

  Future<void> _loadMoodHistory() async {
    final t = AppLocalizations.of(context)!;
    final user = Provider.of<UserProvider>(context, listen: false).user;

    try {
      final response = await ApiService.getMoodHistory(user?.id ?? 0);
      setState(() {
        moodHistory = response
            .map<Map<String, dynamic>>(
              (entry) => {
                'score': entry['score'],
                'label': _translateMood(entry['label'], t),
                'date': DateTime.parse(entry['createdAt']),
              },
            )
            .toList();
      });
      _notifyAverageMoodChanged();
    } catch (e) {
      print('Error loading mood history: $e');
    }
  }

  void _notifyAverageMoodChanged() {
    final callback = widget.onAverageMoodChanged;
    if (callback == null) {
      return;
    }
    callback(_averageMoodScore());
  }

  int _safeScore(dynamic value) {
    if (value is int) {
      return value.clamp(1, 10);
    }
    if (value is num) {
      return value.round().clamp(1, 10);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed.clamp(1, 10);
      }
    }
    return 5;
  }

  DateTime _safeDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now().toUtc();
  }

  List<Map<String, dynamic>> _latestMoodEntries() {
    final rows = moodHistory
        .map((entry) => {
              'score': _safeScore(entry['score']),
              'label': (entry['label'] ?? '').toString(),
              'date': _safeDate(entry['date']),
            })
        .toList();

    rows.sort((a, b) {
      final left = a['date'] as DateTime;
      final right = b['date'] as DateTime;
      return right.compareTo(left);
    });
    return rows.take(4).toList();
  }

  double _averageMoodScore() {
    final nowUtc = DateTime.now().toUtc();
    final cutoffUtc = nowUtc.subtract(const Duration(days: 7));
    final recentEntries = moodHistory.where((entry) {
      final date = _safeDate(entry['date']).toUtc();
      return date.isAfter(cutoffUtc) || date.isAtSameMomentAs(cutoffUtc);
    }).toList();

    if (recentEntries.isEmpty) {
      return 5.0;
    }
    final total = recentEntries.fold<int>(0, (sum, entry) {
      return sum + _safeScore(entry['score']);
    });
    return total / recentEntries.length;
  }

  List<double> _dailyMoodTrendForLast7Days(double fallbackAverage) {
    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final buckets = List<List<int>>.generate(7, (_) => <int>[]);

    for (final entry in moodHistory) {
      final score = _safeScore(entry['score']);
      final dateUtc = _safeDate(entry['date']).toUtc();
      final entryDay = DateTime.utc(dateUtc.year, dateUtc.month, dateUtc.day);
      final dayDiff = todayUtc.difference(entryDay).inDays;

      if (dayDiff >= 0 && dayDiff < 7) {
        final bucketIndex = 6 - dayDiff;
        buckets[bucketIndex].add(score);
      }
    }

    final safeFallback = fallbackAverage.clamp(1.0, 10.0);
    return buckets.map((scores) {
      if (scores.isEmpty) {
        return safeFallback;
      }
      final total = scores.fold<int>(0, (sum, value) => sum + value);
      return (total / scores.length).clamp(1.0, 10.0);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dateLabel = widget.date == null ? t.medicationreminderwidget_today : _formatDate(widget.date!);
    final latestMoods = _latestMoodEntries();
    final averageMood = _averageMoodScore();
    final trendPoints = _dailyMoodTrendForLast7Days(averageMood);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.1),
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
              Icon(
                Icons.favorite_outline,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                t.currentmoodwidget_title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                _getMoodEmoji(currentMoodScore),
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$currentMoodScore/10',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    _translateMood(currentMoodLabel, t),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.currentmoodwidget_rateCurrentMood,
                  style: theme.textTheme.titleMedium,
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbColor: Colors.white,
                    overlayColor: theme.colorScheme.primary.withOpacity(0.2),
                    trackShape: const GradientRectSliderTrackShape(
                      gradient: LinearGradient(colors: [Colors.blue, Colors.yellow]),
                    ),
                  ),
                  child: Slider(
                    value: currentMoodScore.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '$currentMoodScore',
                    onChanged: (double newValue) {
                      setState(() {
                        currentMoodScore = newValue.round();
                        currentMoodLabel = _getMoodLabel(currentMoodScore);
                      });
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: Text(t.currentmoodwidget_saveMood),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                    onPressed: () async {
                      final userProvider = Provider.of<UserProvider>(
                        context,
                        listen: false,
                      );
                      final messenger = ScaffoldMessenger.of(context);
                      final errorColor = theme.colorScheme.error;

                      try {
                        final user = userProvider.user;
                        final response = await ApiService.saveMoodScore(
                          userId: user?.id ?? 0,
                          score: currentMoodScore,
                          label: currentMoodLabel,
                        );

                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          moodHistory.insert(0, {
                            'score': currentMoodScore,
                            'label': currentMoodLabel,
                            'date': DateTime.now().toUtc(),
                          });
                        });
                        _notifyAverageMoodChanged();

                        _checkForAlerts();

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              response.headers['x-offline-queued'] == 'true'
                                  ? t.currentmoodwidget_saveMoodOnSync
                                  : userProvider.isDeviceOnline
                                      ? t.currentmoodwidget_moodSaved
                                      : t.currentmoodwidget_moodSavedLocal,
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('${t.currentmoodwidget_errorSavingMood}: $e'),
                            backgroundColor: errorColor,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (moodHistory.isNotEmpty) ...[
            const SizedBox(height: 20),
            _MoodSummaryCard(
              averageScore: averageMood,
              trendPoints: trendPoints,
            ),
            const SizedBox(height: 14),
            Text(t.currentmoodwidget_lastFourMoods, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: latestMoods.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.1,
              ),
              itemBuilder: (context, index) {
                final entry = latestMoods[index];
                final score = entry['score'] as int;
                final label = (entry['label'] as String).isEmpty
                    ? _translateMood(_getMoodLabel(score), t)
                    : entry['label'] as String;
                final date = entry['date'] as DateTime;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _getMoodEmoji(score),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$score/10 - $label',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(date),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.moodTags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _translateMoodTags(tag, t),
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MoodSummaryCard extends StatelessWidget {
  const _MoodSummaryCard({
    required this.averageScore,
    required this.trendPoints,
  });

  final double averageScore;
  final List<double> trendPoints;

  String _statusText(double score, AppLocalizations t) {
    if (score <= 5.0) {
      return t.currentmoodwidget_lowMoodTrend;
    }
    if (score < 7.0) {
      return t.currentmoodwidget_stableMoodTrend;
    }
    return t.currentmoodwidget_positiveMoodTrend;
  }

  Color _statusColor(double score, ThemeData theme) {
    if (score <= 5.0) {
      return theme.colorScheme.error;
    }
    if (score < 7.0) {
      return Colors.orange.shade700;
    }
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final clamped = averageScore.clamp(1.0, 10.0);
    final normalized = (clamped / 10.0).clamp(0.0, 1.0);
    final statusColor = _statusColor(clamped, theme);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: normalized,
                        strokeWidth: 8,
                        backgroundColor: theme.colorScheme.outline.withValues(
                          alpha: 0.2,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          clamped.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '/10',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.currentmoodwidget_sevenDaySummary,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusText(clamped, t),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.currentmoodwidget_summaryDescription,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: CustomPaint(
              painter: _MoodSparklinePainter(
                points: trendPoints,
                lineColor: statusColor,
                fillColor: statusColor.withValues(alpha: 0.18),
                gridColor: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.currentmoodwidget_sevenDaysAgo,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              Text(
                t.medicationreminderwidget_today,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodSparklinePainter extends CustomPainter {
  _MoodSparklinePainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<double> points;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    const horizontalPadding = 4.0;
    const verticalPadding = 6.0;
    final chartWidth = size.width - (horizontalPadding * 2);
    final chartHeight = size.height - (verticalPadding * 2);
    if (chartWidth <= 0 || chartHeight <= 0) {
      return;
    }

    final baselinePaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final midY = verticalPadding + (chartHeight / 2);
    canvas.drawLine(
      Offset(horizontalPadding, midY),
      Offset(size.width - horizontalPadding, midY),
      baselinePaint,
    );

    final strokePath = Path();
    final fillPath = Path();
    final step = points.length == 1 ? 0.0 : chartWidth / (points.length - 1);

    for (var i = 0; i < points.length; i++) {
      final x = horizontalPadding + (i * step);
      final normalized = ((points[i].clamp(1.0, 10.0) - 1.0) / 9.0);
      final y = verticalPadding + ((1 - normalized) * chartHeight);

      if (i == 0) {
        strokePath.moveTo(x, y);
        fillPath.moveTo(x, size.height - verticalPadding);
        fillPath.lineTo(x, y);
      } else {
        strokePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    final endX = horizontalPadding + ((points.length - 1) * step);
    fillPath.lineTo(endX, size.height - verticalPadding);
    fillPath.close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(strokePath, linePaint);

    final lastNormalized = ((points.last.clamp(1.0, 10.0) - 1.0) / 9.0);
    final lastX = horizontalPadding + ((points.length - 1) * step);
    final lastY = verticalPadding + ((1 - lastNormalized) * chartHeight);

    final markerFill = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 3.5, markerFill);

    final markerStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(lastX, lastY), 3.5, markerStroke);
  }

  @override
  bool shouldRepaint(covariant _MoodSparklinePainter oldDelegate) {
    if (oldDelegate.points.length != points.length) {
      return true;
    }
    for (var i = 0; i < points.length; i++) {
      if (oldDelegate.points[i] != points[i]) {
        return true;
      }
    }
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class GradientRectSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const GradientRectSliderTrackShape({required this.gradient});
  final LinearGradient gradient;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackRight = trackLeft + parentBox.size.width;
    final double trackBottom = trackTop + trackHeight;
    final Rect trackRect = Rect.fromLTRB(trackLeft, trackTop, trackRight, trackBottom);

    final Paint paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;

    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(3)),
      paint,
    );
  }
}
