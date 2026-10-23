import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme/sentiment_colors.dart';
import '../../providers/user_provider.dart';
import '../../features/dashboard/presentation/pages/caregiver_dashboard.dart';
import '../../features/profile/presentation/pages/profile_settings_page.dart';
import '../../features/social/presentation/pages/chat_inbox_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/post_call_telemetry_summary_screen.dart';

class CaregiverPatientsTab extends StatelessWidget {
  const CaregiverPatientsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final caregiverId = userProvider.user?.caregiverId ?? 1;

    return CaregiverDashboard(
      caregiverId: caregiverId,
      userRole: userProvider.user?.role ?? 'CAREGIVER',
    );
  }
}

class CaregiverTasksTab extends StatelessWidget {
  const CaregiverTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 80,
              color: Color(0xFF14366E),
            ),
            SizedBox(height: 16),
            Text(
              'Task Management',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14366E),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Manage and assign tasks to your patients.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaregiverAnalyticsTab extends StatefulWidget {
  const CaregiverAnalyticsTab({super.key});

  @override
  State<CaregiverAnalyticsTab> createState() => _CaregiverAnalyticsTabState();
}

class _CaregiverAnalyticsTabState extends State<CaregiverAnalyticsTab> {
  bool _loadingPatients = true;
  bool _loadingHistory = false;
  String? _error;
  List<_AnalyticsPatient> _patients = const [];
  int? _selectedPatientUserId;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _moodHistory = const [];
  String? _selectedCallId;
  final Map<int, GlobalKey> _historyRowKeys = <int, GlobalKey>{};
  final ScrollController _historyScrollController = ScrollController();
  final ScrollController _chartScrollController = ScrollController();
  _HistorySort _historySort = _HistorySort.newest;
  _HistoryLabelFilter _historyLabelFilter = _HistoryLabelFilter.all;
  _AnalyticsPlotFilter _plotFilter = _AnalyticsPlotFilter.all;
  _AnalyticsTimeframe _timeframe = _AnalyticsTimeframe.last7Days;
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _historyScrollController.dispose();
    _chartScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loadingPatients = true;
      _error = null;
    });
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiverId = userProvider.user?.caregiverId;
      if (caregiverId == null || caregiverId <= 0) {
        throw Exception('No caregiver profile is linked to this account.');
      }

      final response = await ApiService.getCaregiverPatients(caregiverId);
      if (response.statusCode != 200) {
        throw Exception(
            'Failed to load caregiver patients (${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('Unexpected caregiver patient payload.');
      }

      final patients = <_AnalyticsPatient>[];
      final seen = <int>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final link = item['link'];
        final patient = item['patient'];

        final linkMap =
            link is Map<String, dynamic> ? link : const <String, dynamic>{};
        final patientMap = patient is Map<String, dynamic>
            ? patient
            : const <String, dynamic>{};

        final patientUserId =
            _asInt(linkMap['patientUserId']) ?? _asInt(patientMap['userId']);
        if (patientUserId == null ||
            patientUserId <= 0 ||
            seen.contains(patientUserId)) {
          continue;
        }
        seen.add(patientUserId);

        final firstName = (patientMap['firstName'] ?? '').toString().trim();
        final lastName = (patientMap['lastName'] ?? '').toString().trim();
        final fallbackName = (linkMap['patientName'] ?? '').toString().trim();
        final displayName =
            [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim();

        patients.add(_AnalyticsPatient(
          userId: patientUserId,
          name: displayName.isNotEmpty
              ? displayName
              : (fallbackName.isNotEmpty
                  ? fallbackName
                  : 'Patient $patientUserId'),
        ));
      }

      if (!mounted) return;
      setState(() {
        _patients = patients;
        _selectedPatientUserId = null;
        _historyRowKeys.clear();
        _history = const [];
        _moodHistory = const [];
        _selectedCallId = null;
        _loadingPatients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingPatients = false;
      });
    }
  }

  Future<void> _loadHistory(int patientUserId) async {
    setState(() {
      _loadingHistory = true;
      _error = null;
    });

    try {
      final responses = await Future.wait([
        ApiService.getSentimentHistory(patientUserId),
        ApiService.getMoodHistory(patientUserId),
      ]);
      final history = responses[0] as List<Map<String, dynamic>>;
      final moodRaw = responses[1];
      final moods = moodRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _historyRowKeys.clear();
        _history = history;
        _moodHistory = moods;
        _selectedCallId = null;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyRowKeys.clear();
        _history = const [];
        _moodHistory = const [];
        _selectedCallId = null;
        _error = e.toString();
        _loadingHistory = false;
      });
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime _asDateTime(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _shortDateWithYear(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$month/$day/$year';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _axisLabelForDate(DateTime dt, double spanDays) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    if (spanDays > 365) {
      final year = dt.year.toString().substring(2);
      return '$month/$day/$year';
    }
    return '$month/$day';
  }

  Future<DateTimeRange?> _showCustomRangeModal() {
    final now = DateTime.now();
    final initial = _customDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    var start =
        DateTime(initial.start.year, initial.start.month, initial.start.day);
    var end = DateTime(initial.end.year, initial.end.month, initial.end.day);
    var editingStart = true;

    return showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final focused = editingStart ? start : end;
            return AlertDialog(
              title: const Text('Select Date Range'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text('Start: ${_shortDateWithYear(start)}'),
                            selected: editingStart,
                            onSelected: (_) {
                              setLocalState(() => editingStart = true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Text('End: ${_shortDateWithYear(end)}'),
                            selected: !editingStart,
                            onSelected: (_) {
                              setLocalState(() => editingStart = false);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CalendarDatePicker(
                      initialDate: focused,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: now.add(const Duration(days: 365)),
                      onDateChanged: (picked) {
                        setLocalState(() {
                          if (editingStart) {
                            start =
                                DateTime(picked.year, picked.month, picked.day);
                            if (start.isAfter(end)) {
                              end = start;
                            }
                          } else {
                            end =
                                DateTime(picked.year, picked.month, picked.day);
                            if (end.isBefore(start)) {
                              start = end;
                            }
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      DateTimeRange(start: start, end: end),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatCallTitle(String callId) {
    final normalized = callId.trim();
    if (normalized.isEmpty) return 'Telehealth call';
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

  Color _colorForScore(double score) {
    if (score >= SentimentColors.calmThreshold) {
      return Colors.green.shade600;
    }
    if (score >= SentimentColors.anxiousThreshold) {
      return Colors.orange.shade600;
    }
    return Colors.red.shade600;
  }

  String _labelForScore(double score) {
    if (score >= SentimentColors.calmThreshold) return 'CALM';
    if (score >= SentimentColors.anxiousThreshold) return 'ANXIOUS';
    return 'DISTRESSED';
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime _endOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, 23, 59, 59, 999);

  bool _isInSelectedTimeframe(DateTime date, DateTime latestDate) {
    if (_timeframe == _AnalyticsTimeframe.custom && _customDateRange != null) {
      final start = _startOfDay(_customDateRange!.start);
      final end = _endOfDay(_customDateRange!.end);
      return !date.isBefore(start) && !date.isAfter(end);
    }
    final start = _timeframe.startFrom(latestDate);
    if (start == null) return true;
    return !date.isBefore(start);
  }

  String _normalizedLabel(Map<String, dynamic> item) {
    return (item['overallLabel'] ?? '').toString().trim().toUpperCase();
  }

  List<_MetricPoint> _buildCallPoints(List<Map<String, dynamic>> history) {
    return history.map((item) {
      final dt = _asDateTime(item['callDate']);
      final score = _asDouble(item['overallScore']).clamp(0.0, 1.0);
      return _MetricPoint(
        date: dt,
        score: score,
        callId: (item['callId'] ?? '').toString(),
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<_MetricPoint> _buildMoodPoints() {
    final points = <_MetricPoint>[];
    for (final item in _moodHistory) {
      final dt = _asDateTime(
        item['createdAt'] ??
            item['timestamp'] ??
            item['date'] ??
            item['takenAt'],
      );
      final raw =
          _asDouble(item['score'] ?? item['moodValue'] ?? item['value'], -1);
      if (raw < 0) continue;
      final normalized =
          raw > 1.0 ? (raw / 10.0).clamp(0.0, 1.0) : raw.clamp(0.0, 1.0);
      points.add(_MetricPoint(date: dt, score: normalized));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  double _moodScoreFromItem(Map<String, dynamic> item) {
    final raw =
        _asDouble(item['score'] ?? item['moodValue'] ?? item['value'], -1);
    if (raw < 0) return 0.5;
    return raw > 1.0 ? (raw / 10.0).clamp(0.0, 1.0) : raw.clamp(0.0, 1.0);
  }

  GlobalKey _keyForHistoryRow(int index) {
    return _historyRowKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scrollToSelectedHistoryRow(List<Map<String, dynamic>> visibleHistory) {
    final selectedCallId = _selectedCallId;
    if (selectedCallId == null || visibleHistory.isEmpty) return;

    final idx = visibleHistory.indexWhere(
      (item) => (item['callId'] ?? '').toString() == selectedCallId,
    );
    if (idx < 0) return;

    if (_historyScrollController.hasClients) {
      const rowExtent = 74.0;
      final viewport = _historyScrollController.position.viewportDimension;
      final centered = (idx * rowExtent) - (viewport / 2) + (rowExtent / 2);
      final target = centered.clamp(
          0.0, _historyScrollController.position.maxScrollExtent);
      _historyScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }

    final rowContext = _historyRowKeys[idx]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyAnalyticsData = _history.isNotEmpty || _moodHistory.isNotEmpty;
    final visibleHistory = List<Map<String, dynamic>>.from(_history)
      ..removeWhere((item) {
        if (_historyLabelFilter == _HistoryLabelFilter.all) {
          return false;
        }
        final label = _normalizedLabel(item);
        return label != _historyLabelFilter.name.toUpperCase();
      });

    visibleHistory.sort((a, b) {
      switch (_historySort) {
        case _HistorySort.newest:
          return _asDateTime(b['callDate'])
              .compareTo(_asDateTime(a['callDate']));
        case _HistorySort.oldest:
          return _asDateTime(a['callDate'])
              .compareTo(_asDateTime(b['callDate']));
        case _HistorySort.highestScore:
          return _asDouble(b['overallScore'])
              .compareTo(_asDouble(a['overallScore']));
        case _HistorySort.lowestScore:
          return _asDouble(a['overallScore'])
              .compareTo(_asDouble(b['overallScore']));
      }
    });

    final latest = visibleHistory.isEmpty ? null : visibleHistory.first;
    final callPoints = _buildCallPoints(visibleHistory);
    final moodPoints = _buildMoodPoints();
    final allRawPoints = <_MetricPoint>[
      ...callPoints,
      ...moodPoints,
    ];
    final latestDataDate = allRawPoints.isEmpty
        ? DateTime.now()
        : allRawPoints
            .map((e) => e.date)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final renderedSeries = <_RenderedSeries>[];
    if (_plotFilter == _AnalyticsPlotFilter.all ||
        _plotFilter == _AnalyticsPlotFilter.calls) {
      renderedSeries.add(
        _RenderedSeries(
          kind: _SeriesKind.calls,
          points: callPoints
              .where((p) => _isInSelectedTimeframe(p.date, latestDataDate))
              .toList(),
          color: const Color(0xFF2E7D32),
        ),
      );
    }
    if (_plotFilter == _AnalyticsPlotFilter.all ||
        _plotFilter == _AnalyticsPlotFilter.mood) {
      renderedSeries.add(
        _RenderedSeries(
          kind: _SeriesKind.mood,
          points: moodPoints
              .where((p) => _isInSelectedTimeframe(p.date, latestDataDate))
              .toList(),
          color: const Color(0xFF7E57C2),
        ),
      );
    }
    final allPlotPoints = renderedSeries.expand((s) => s.points).toList();
    final sortedPlotPoints = List<_MetricPoint>.from(allPlotPoints)
      ..sort((a, b) => a.date.compareTo(b.date));
    final avgScore = sortedPlotPoints.isEmpty
        ? 0.0
        : sortedPlotPoints.map((p) => p.score).reduce((a, b) => a + b) /
            sortedPlotPoints.length;
    final trendDelta = sortedPlotPoints.length >= 2
        ? sortedPlotPoints.last.score - sortedPlotPoints.first.score
        : 0.0;
    final trendText = trendDelta > 0.03
        ? 'Improving'
        : trendDelta < -0.03
            ? 'Declining'
            : 'Stable';
    final recentLabel = sortedPlotPoints.isEmpty
        ? (latest?['overallLabel'] ?? 'N/A').toString()
        : _labelForScore(sortedPlotPoints.last.score);
    final minPointDate = allPlotPoints.isEmpty
        ? DateTime.now()
        : allPlotPoints
            .map((e) => e.date)
            .reduce((a, b) => a.isBefore(b) ? a : b);
    final maxPointDate = allPlotPoints.isEmpty
        ? DateTime.now().add(const Duration(days: 1))
        : allPlotPoints
            .map((e) => e.date)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final minX = minPointDate.millisecondsSinceEpoch.toDouble();
    final maxX = maxPointDate.millisecondsSinceEpoch.toDouble();
    final totalSpanDays = (maxPointDate.difference(minPointDate).inHours / 24.0)
        .abs()
        .clamp(1.0, 5000.0);
    final showCallsHistory = _plotFilter == _AnalyticsPlotFilter.all ||
        _plotFilter == _AnalyticsPlotFilter.calls;
    final showMoodHistory = _plotFilter == _AnalyticsPlotFilter.all ||
        _plotFilter == _AnalyticsPlotFilter.mood;
    final visibleMoodHistory = _moodHistory.where((item) {
      final dt = _asDateTime(
        item['createdAt'] ??
            item['timestamp'] ??
            item['date'] ??
            item['takenAt'],
      );
      return _isInSelectedTimeframe(dt, latestDataDate);
    }).toList()
      ..sort((a, b) {
        final ad = _asDateTime(
          a['createdAt'] ?? a['timestamp'] ?? a['date'] ?? a['takenAt'],
        );
        final bd = _asDateTime(
          b['createdAt'] ?? b['timestamp'] ?? b['date'] ?? b['takenAt'],
        );
        return bd.compareTo(ad);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadPatients,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingPatients
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load analytics: $_error'),
                  ),
                )
              : _patients.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'No linked patients found for this caregiver.'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPatients,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Patient',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<int>(
                                    initialValue: _selectedPatientUserId,
                                    items: _patients
                                        .map(
                                          (patient) => DropdownMenuItem<int>(
                                            value: patient.userId,
                                            child: Text(patient.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(
                                          () => _selectedPatientUserId = value);
                                      _loadHistory(value);
                                    },
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingHistory)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_selectedPatientUserId == null)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child:
                                    Text('Select a patient to load analytics.'),
                              ),
                            )
                          else if (!hasAnyAnalyticsData)
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No sentiment or mood history found for this patient yet.',
                                ),
                              ),
                            )
                          else ...[
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 180,
                                            child: DropdownButtonFormField<
                                                _HistorySort>(
                                              initialValue: _historySort,
                                              items: _HistorySort.values
                                                  .map(
                                                    (sort) => DropdownMenuItem<
                                                        _HistorySort>(
                                                      value: sort,
                                                      child: Text(sort.label),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value == null) return;
                                                setState(
                                                    () => _historySort = value);
                                              },
                                              decoration: const InputDecoration(
                                                labelText: 'Sort',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 160,
                                            child: DropdownButtonFormField<
                                                _HistoryLabelFilter>(
                                              initialValue: _historyLabelFilter,
                                              items: _HistoryLabelFilter.values
                                                  .map(
                                                    (filter) => DropdownMenuItem<
                                                        _HistoryLabelFilter>(
                                                      value: filter,
                                                      child: Text(filter.label),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value == null) return;
                                                setState(() =>
                                                    _historyLabelFilter =
                                                        value);
                                              },
                                              decoration: const InputDecoration(
                                                labelText: 'Label',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 150,
                                            child: DropdownButtonFormField<
                                                _AnalyticsPlotFilter>(
                                              initialValue: _plotFilter,
                                              items: _AnalyticsPlotFilter.values
                                                  .map(
                                                    (filter) => DropdownMenuItem<
                                                        _AnalyticsPlotFilter>(
                                                      value: filter,
                                                      child: Text(filter.label),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value == null) return;
                                                setState(
                                                    () => _plotFilter = value);
                                              },
                                              decoration: const InputDecoration(
                                                labelText: 'Plot',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 180,
                                            child: DropdownButtonFormField<
                                                _AnalyticsTimeframe>(
                                              initialValue: _timeframe,
                                              items: _AnalyticsTimeframe.values
                                                  .map(
                                                    (tf) => DropdownMenuItem<
                                                        _AnalyticsTimeframe>(
                                                      value: tf,
                                                      child: Text(tf.label),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value == null) return;
                                                if (value ==
                                                    _AnalyticsTimeframe
                                                        .custom) {
                                                  _showCustomRangeModal()
                                                      .then((picked) {
                                                    if (!mounted ||
                                                        picked == null) return;
                                                    setState(() {
                                                      _customDateRange = picked;
                                                      _timeframe =
                                                          _AnalyticsTimeframe
                                                              .custom;
                                                    });
                                                  });
                                                  return;
                                                }
                                                setState(() {
                                                  _timeframe = value;
                                                });
                                              },
                                              decoration: const InputDecoration(
                                                labelText: 'Timeframe',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Longitudinal Sentiment Trend',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_shortDateWithYear(minPointDate)} - ${_shortDateWithYear(maxPointDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: renderedSeries
                                          .map(
                                            (series) => Chip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              avatar: Icon(
                                                Icons.circle,
                                                size: 12,
                                                color: series.color,
                                              ),
                                              label: Text(series.kind.label),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                    const SizedBox(height: 12),
                                    if (renderedSeries.isEmpty)
                                      const SizedBox(
                                        height: 220,
                                        child: Center(
                                          child: Text(
                                              'No points available for selected plot filter.'),
                                        ),
                                      )
                                    else
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final maxPointCount = renderedSeries
                                              .map((s) => s.points.length)
                                              .fold<int>(
                                                  0, (a, b) => a > b ? a : b);
                                          final chartWidth =
                                              (maxPointCount * 24.0).clamp(
                                                  constraints.maxWidth,
                                                  12000.0);
                                          final xSpan = (maxX - minX).abs();
                                          final dayMs = const Duration(days: 1)
                                              .inMilliseconds
                                              .toDouble();
                                          final desiredDaysPerTick =
                                              totalSpanDays > 720
                                                  ? 120.0
                                                  : totalSpanDays > 365
                                                      ? 60.0
                                                      : totalSpanDays > 180
                                                          ? 30.0
                                                          : totalSpanDays > 90
                                                              ? 14.0
                                                              : totalSpanDays >
                                                                      45
                                                                  ? 7.0
                                                                  : totalSpanDays >
                                                                          14
                                                                      ? 3.0
                                                                      : 1.0;
                                          final xInterval = xSpan <= 0
                                              ? dayMs
                                              : dayMs * desiredDaysPerTick;

                                          return SizedBox(
                                            height: 220,
                                            child: Scrollbar(
                                              controller:
                                                  _chartScrollController,
                                              thumbVisibility: chartWidth >
                                                  constraints.maxWidth,
                                              child: SingleChildScrollView(
                                                controller:
                                                    _chartScrollController,
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: SizedBox(
                                                  width: chartWidth,
                                                  child: LineChart(
                                                    LineChartData(
                                                      minY: 0,
                                                      maxY: 1,
                                                      minX: minX,
                                                      maxX: maxX <= minX
                                                          ? minX + 1
                                                          : maxX,
                                                      gridData:
                                                          const FlGridData(
                                                              show: true),
                                                      borderData: FlBorderData(
                                                          show: true),
                                                      titlesData: FlTitlesData(
                                                        rightTitles:
                                                            const AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                                  showTitles:
                                                                      false),
                                                        ),
                                                        topTitles:
                                                            const AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                                  showTitles:
                                                                      false),
                                                        ),
                                                        leftTitles: AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: true,
                                                            reservedSize: 32,
                                                            interval: 0.25,
                                                            getTitlesWidget:
                                                                (value, meta) =>
                                                                    Text(
                                                              value
                                                                  .toStringAsFixed(
                                                                      2),
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          10),
                                                            ),
                                                          ),
                                                        ),
                                                        bottomTitles:
                                                            AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                            showTitles: true,
                                                            reservedSize: 30,
                                                            interval: xInterval,
                                                            getTitlesWidget:
                                                                (value, meta) {
                                                              final dt = DateTime
                                                                  .fromMillisecondsSinceEpoch(
                                                                value.round(),
                                                              );
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top: 6),
                                                                child: Text(
                                                                  _axisLabelForDate(
                                                                      dt,
                                                                      totalSpanDays),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          10),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      lineTouchData:
                                                          LineTouchData(
                                                        handleBuiltInTouches:
                                                            true,
                                                        touchCallback:
                                                            (event, response) {
                                                          if (event
                                                              is! FlTapUpEvent) {
                                                            return;
                                                          }
                                                          final spots = response
                                                              ?.lineBarSpots;
                                                          if (spots == null ||
                                                              spots.isEmpty) {
                                                            return;
                                                          }
                                                          final selected =
                                                              spots.first;
                                                          final barIndex =
                                                              selected.barIndex;
                                                          if (barIndex < 0 ||
                                                              barIndex >=
                                                                  renderedSeries
                                                                      .length) {
                                                            return;
                                                          }
                                                          final series =
                                                              renderedSeries[
                                                                  barIndex];
                                                          if (series.kind !=
                                                              _SeriesKind
                                                                  .calls) {
                                                            return;
                                                          }
                                                          final pointIdx =
                                                              selected
                                                                  .spotIndex;
                                                          if (pointIdx < 0 ||
                                                              pointIdx >=
                                                                  series.points
                                                                      .length) {
                                                            return;
                                                          }
                                                          final callId = series
                                                              .points[pointIdx]
                                                              .callId;
                                                          if (callId == null ||
                                                              callId.isEmpty) {
                                                            return;
                                                          }
                                                          setState(() {
                                                            _selectedCallId =
                                                                callId;
                                                          });
                                                          WidgetsBinding
                                                              .instance
                                                              .addPostFrameCallback(
                                                                  (_) {
                                                            _scrollToSelectedHistoryRow(
                                                                visibleHistory);
                                                          });
                                                        },
                                                      ),
                                                      lineBarsData:
                                                          renderedSeries
                                                              .map((series) {
                                                        return LineChartBarData(
                                                          isCurved: false,
                                                          color: series.color,
                                                          barWidth: 2.2,
                                                          dotData: FlDotData(
                                                            show: true,
                                                            getDotPainter:
                                                                (spot, _, __,
                                                                    ___) {
                                                              final dotColor =
                                                                  _colorForScore(
                                                                      spot.y);
                                                              return FlDotCirclePainter(
                                                                radius: 3.6,
                                                                color: dotColor,
                                                                strokeColor: dotColor
                                                                    .withValues(
                                                                        alpha:
                                                                            0.75),
                                                                strokeWidth: 1,
                                                              );
                                                            },
                                                          ),
                                                          spots: series.points
                                                              .map(
                                                                  (p) => FlSpot(
                                                                        p.date
                                                                            .millisecondsSinceEpoch
                                                                            .toDouble(),
                                                                        p.score,
                                                                      ))
                                                              .toList(),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                        'Average score: ${avgScore.toStringAsFixed(3)}'),
                                    Text('Trend: $trendText'),
                                    Text('Recent label: $recentLabel'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (showCallsHistory)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Call History',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${visibleHistory.length} calls recorded',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 260,
                                        child: Scrollbar(
                                          controller: _historyScrollController,
                                          thumbVisibility:
                                              visibleHistory.length > 5,
                                          child: ListView.separated(
                                            controller:
                                                _historyScrollController,
                                            itemCount: visibleHistory.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final item =
                                                  visibleHistory[index];
                                              final callId =
                                                  (item['callId'] ?? '')
                                                      .toString();
                                              final callDate =
                                                  _asDateTime(item['callDate']);
                                              final label =
                                                  (item['overallLabel'] ??
                                                          'N/A')
                                                      .toString();
                                              final score = _asDouble(
                                                  item['overallScore']);
                                              final durationMinutes = _asDouble(
                                                  item['durationMinutes']);
                                              final isSelected =
                                                  _selectedCallId == callId;
                                              final scoreColor =
                                                  _colorForScore(score);
                                              final colorScheme =
                                                  Theme.of(context).colorScheme;
                                              return Container(
                                                key: _keyForHistoryRow(index),
                                                height: 74,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? colorScheme.onSurface
                                                          .withValues(
                                                              alpha: 0.08)
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: isSelected
                                                      ? Border.all(
                                                          color: colorScheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.22),
                                                          width: 1,
                                                        )
                                                      : null,
                                                ),
                                                child: Row(
                                                  children: [
                                                    AnimatedContainer(
                                                      duration: const Duration(
                                                          milliseconds: 180),
                                                      curve: Curves.easeOut,
                                                      width: 3,
                                                      height: 58,
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? colorScheme
                                                                .onSurface
                                                                .withValues(
                                                                    alpha: 0.45)
                                                            : Colors
                                                                .transparent,
                                                        borderRadius:
                                                            const BorderRadius
                                                                .only(
                                                          topLeft:
                                                              Radius.circular(
                                                                  8),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                  8),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: ListTile(
                                                        dense: false,
                                                        contentPadding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8),
                                                        leading: Icon(
                                                            Icons.call,
                                                            color: colorScheme
                                                                .primary),
                                                        title: Text(
                                                          _formatCallTitle(
                                                              callId),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                        ),
                                                        subtitle: Text(
                                                          '${_formatDateTime(callDate)} - Ended - Duration ${durationMinutes.toStringAsFixed(1)} min',
                                                        ),
                                                        trailing: SizedBox(
                                                          width: 88,
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                              Text(
                                                                '${(score * 100).toStringAsFixed(1)}%',
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelSmall
                                                                    ?.copyWith(
                                                                      color:
                                                                          scoreColor,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                    ),
                                                              ),
                                                              Text(
                                                                label
                                                                    .toUpperCase(),
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelSmall
                                                                    ?.copyWith(
                                                                      color:
                                                                          scoreColor,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        onTap: callId.isEmpty
                                                            ? null
                                                            : () {
                                                                setState(() {
                                                                  _selectedCallId =
                                                                      callId;
                                                                });
                                                                WidgetsBinding
                                                                    .instance
                                                                    .addPostFrameCallback(
                                                                        (_) {
                                                                  _scrollToSelectedHistoryRow(
                                                                    visibleHistory,
                                                                  );
                                                                });
                                                                Navigator.of(
                                                                        context)
                                                                    .push(
                                                                  MaterialPageRoute(
                                                                    builder: (_) =>
                                                                        PostCallTelemetrySummaryScreen(
                                                                      callId:
                                                                          callId,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (showCallsHistory) const SizedBox(height: 12),
                            if (showMoodHistory)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Mood History',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${visibleMoodHistory.length} mood entries',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 220,
                                        child: ListView.separated(
                                          itemCount: visibleMoodHistory.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final item =
                                                visibleMoodHistory[index];
                                            final dt = _asDateTime(
                                              item['createdAt'] ??
                                                  item['timestamp'] ??
                                                  item['date'] ??
                                                  item['takenAt'],
                                            );
                                            final score =
                                                _moodScoreFromItem(item);
                                            final label = _labelForScore(score);
                                            final color = _colorForScore(score);
                                            return ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              leading: Icon(Icons.mood,
                                                  color: color),
                                              title: Text(
                                                  'Mood entry - ${_formatDateTime(dt)}'),
                                              subtitle: Text(
                                                (item['notes'] ??
                                                            item['note'] ??
                                                            item[
                                                                'description'] ??
                                                            '')
                                                        .toString()
                                                        .trim()
                                                        .isEmpty
                                                    ? 'No notes'
                                                    : (item['notes'] ??
                                                            item['note'] ??
                                                            item['description'])
                                                        .toString(),
                                              ),
                                              trailing: SizedBox(
                                                width: 88,
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      '${(score * 100).toStringAsFixed(1)}%',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: color,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                    Text(
                                                      label,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: color,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (showMoodHistory) const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }
}

class _AnalyticsPatient {
  final int userId;
  final String name;

  const _AnalyticsPatient({
    required this.userId,
    required this.name,
  });
}

enum _HistorySort {
  newest('Newest first'),
  oldest('Oldest first'),
  highestScore('Highest score'),
  lowestScore('Lowest score');

  final String label;
  const _HistorySort(this.label);
}

enum _HistoryLabelFilter {
  all('All labels'),
  calm('Calm'),
  anxious('Anxious'),
  distressed('Distressed');

  final String label;
  const _HistoryLabelFilter(this.label);
}

enum _AnalyticsPlotFilter {
  all('All metrics'),
  calls('Calls'),
  mood('Mood');

  final String label;
  const _AnalyticsPlotFilter(this.label);
}

enum _AnalyticsTimeframe {
  last24Hours('Last 24 hours', 1),
  last3Days('Last 3 days', 3),
  last7Days('Last 7 days', 7),
  last30Days('Last 30 days', 30),
  last90Days('Last 90 days', 90),
  last180Days('Last 180 days', 180),
  custom('Custom range', null);

  final String label;
  final int? days;
  const _AnalyticsTimeframe(this.label, this.days);

  DateTime? startFrom(DateTime latestDate) {
    if (days == null) return null;
    return latestDate.subtract(Duration(days: days!));
  }
}

enum _SeriesKind {
  calls('Calls'),
  mood('Mood');

  final String label;
  const _SeriesKind(this.label);
}

class _MetricPoint {
  final DateTime date;
  final double score;
  final String? callId;

  const _MetricPoint({
    required this.date,
    required this.score,
    this.callId,
  });
}

class _RenderedSeries {
  final _SeriesKind kind;
  final List<_MetricPoint> points;
  final Color color;

  const _RenderedSeries({
    required this.kind,
    required this.points,
    required this.color,
  });
}

class CaregiverMessagesTab extends StatelessWidget {
  const CaregiverMessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    if (user == null) {
      return Scaffold(
        body: const Center(
          child: Text('Please log in to view messages'),
        ),
      );
    }

    return Scaffold(
      body: const ChatInboxScreen(),
    );
  }
}

class CaregiverProfileTab extends StatelessWidget {
  const CaregiverProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProfileSettingsPage();
  }
}
