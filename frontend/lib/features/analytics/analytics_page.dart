import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/config/theme/color_utils.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/widgets/responsive_container.dart';
import 'models/vital_model.dart';
import 'models/dashboard_analytics_model.dart';
import 'web_utils.dart' if (dart.library.html) 'web_utils_web.dart'
    as web_utils;
import '../../../widgets/ai_chat_improved.dart';

class AnalyticsPage extends StatefulWidget {
  final int patientId;
  const AnalyticsPage({super.key, required this.patientId});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

List<FlSpot> _getSafeSpots(List<double?> values, {double defaultValue = 0.0}) {
  List<FlSpot> spots = [];
  for (int i = 0; i < values.length; i++) {
    spots.add(FlSpot(i.toDouble(), values[i] ?? defaultValue));
  }
  return spots.isEmpty ? [FlSpot(0, defaultValue)] : spots;
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<Vital> vitals = [];
  DashboardAnalytics? dashboard;
  bool loading = true;
  String? error;
  int selectedDays = 7; // Default to 7 days

  final Map<int, String> moodEmojis = {
    1: '🙁',
    2: '😔',
    3: '😕',
    4: '😐',
    5: '🙂',
  };

  // Add pain emoji mapping
  final Map<int, String> painEmojis = {
    1: '😀',
    2: '🙂',
    3: '😐',
    4: '😕',
    5: '🙁',
    6: '😞',
    7: '😢',
    8: '😥',
    9: '😭',
    10: '😱',
  };

  @override
  void initState() {
    super.initState();
    // Add a small delay to ensure the widget is fully mounted before fetching data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchAnalytics();
    });
  }

  Future<void> fetchAnalytics() async {
    setState(() {
      loading = true;
      error = null;
    });

    // Validate patient ID before making API call
    if (widget.patientId <= 0) {
      setState(() {
        error = 'Invalid patient ID: ${widget.patientId}';
        loading = false;
      });
      print('⚠️ Analytics Error: Invalid patient ID: ${widget.patientId}');
      return;
    }

    try {
      print(
        '🔍 Fetching analytics for patientId: ${widget.patientId}, days: $selectedDays',
      );
      final authHeaders = await ApiService.getAuthHeaders();
      final vitalsUrl = Uri.parse(
        '${ApiConstants.baseUrl}analytics/vitals?patientId=${widget.patientId}&days=$selectedDays',
      );

      print('🔍 Making API call to: $vitalsUrl');
      final vitalsResp = await http
          .get(vitalsUrl, headers: authHeaders)
          .timeout(
            const Duration(seconds: 180),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );
      final dashboardUrl = Uri.parse(
        '${ApiConstants.baseUrl}analytics/dashboard?patientId=${widget.patientId}&days=$selectedDays',
      );

      print('🔍 Making API call to: $dashboardUrl');
      final dashboardResp = await http
          .get(dashboardUrl, headers: authHeaders)
          .timeout(
            const Duration(seconds: 180),
            onTimeout: () => http.Response('{"error": "Request timeout"}', 408),
          );

      // Log response statuses for debugging
      print('🔍 Vitals API response status: ${vitalsResp.statusCode}');
      print('🔍 Dashboard API response status: ${dashboardResp.statusCode}');

      if (vitalsResp.statusCode == 200 && dashboardResp.statusCode == 200) {
        try {
          final Map<String, dynamic> vitalsJsonMap = json.decode(
            vitalsResp.body,
          );
          print(
            '🔍 Vitals API response body: ${vitalsResp.body.substring(0, min(100, vitalsResp.body.length))}...',
          );

          if (!vitalsJsonMap.containsKey('data')) {
            throw const FormatException('Vitals response missing "data" key');
          }

          final List<dynamic> vitalsDataList = vitalsJsonMap['data'] as List;
          final dashboardJson = json.decode(dashboardResp.body);

          // Debug log the dashboard response
          print('🔍 Dashboard API response: ${dashboardResp.body}');
          print('🔍 Dashboard JSON parsed: $dashboardJson');

          setState(() {
            vitals = vitalsDataList.map((e) => Vital.fromJson(e)).toList();
            dashboard = DashboardAnalytics.fromJson(dashboardJson);
            loading = false;
          });

          // Debug log the parsed dashboard
          print(
            '✅ Dashboard parsed - avgMood: ${dashboard?.avgMoodValue}, avgPain: ${dashboard?.avgPainValue}',
          );
          print(
            '✅ Successfully loaded ${vitals.length} vitals and dashboard data',
          );
        } catch (e) {
          print('❌ Error parsing API response: $e');
          setState(() {
            error = 'Error parsing data: $e';
            loading = false;
          });
        }
      } else {
        String vitalsErrorMessage = 'Failed to fetch vitals data';
        if (vitalsResp.body.isNotEmpty) {
          try {
            final Map<String, dynamic> errorBody = json.decode(vitalsResp.body);
            vitalsErrorMessage = errorBody['error'] ?? vitalsErrorMessage;
            print('❌ Vitals API error: $vitalsErrorMessage');
          } catch (e) {
            print('❌ Could not parse vitals error response: $e');
          }
        }
        // Handle non-200 status codes for dashboardResp
        String dashboardErrorMessage = 'Failed to fetch dashboard data';
        if (dashboardResp.body.isNotEmpty) {
          try {
            final Map<String, dynamic> errorBody = json.decode(
              dashboardResp.body,
            );
            dashboardErrorMessage = errorBody['error'] ?? dashboardErrorMessage;
          } catch (e) {
            // ignore: avoid_print
            print("Failed to parse dashboard error response: $e");
          }
        }

        setState(() {
          error =
              'Vitals Error: $vitalsErrorMessage\nDashboard Error: $dashboardErrorMessage';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        loading = false;
      });
    }
  }

  Future<void> exportFile(String type) async {
    try {
      if (type == 'csv') {
        await _exportToCsv();
      } else if (type == 'pdf') {
        await _exportToPdf();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$type export completed successfully!'),
          backgroundColor: AppTheme.success,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${e.toString()}'),
          backgroundColor: Colors.red.shade600,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _exportToCsv() async {
    await _downloadExportFromApi('csv');
  }

  Future<void> _exportToPdf() async {
    await _downloadExportFromApi('pdf');
  }

  Future<void> _downloadExportFromApi(String type) async {
    final authHeaders = await ApiService.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}analytics/export/vitals/$type?patientId=${widget.patientId}&days=$selectedDays',
      ),
      headers: authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Export failed with status ${response.statusCode}');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fallbackFileName =
        'patient_${widget.patientId}_analytics_${selectedDays}days_$timestamp.$type';
    final contentDisposition = response.headers['content-disposition'];
    final fileName = _extractFileName(contentDisposition) ?? fallbackFileName;

    if (!kIsWeb) {
      throw Exception('Export download is currently supported on web builds.');
    }

    web_utils.downloadFile(fileName, response.bodyBytes);
  }

  String? _extractFileName(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.isEmpty) {
      return null;
    }
    final fileNameRegex = RegExp(r'filename="?([^";]+)"?');
    final match = fileNameRegex.firstMatch(contentDisposition);
    return match?.group(1);
  }

  /*
  // COMMENTED OUT API-BASED EXPORT
  Future<void> exportFileFromAPI(String type) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final from = vitals.isNotEmpty ? vitals.first.timestamp : DateTime.now();
      final to = vitals.isNotEmpty ? vitals.last.timestamp : DateTime.now();
      final fromStr = Uri.encodeComponent(from.toIso8601String());
      final toStr = Uri.encodeComponent(to.toIso8601String());
      
      final url = '${ApiConstants.baseUrl}analytics/export/$type?patientId=${widget.patientId}&from=$fromStr&to=$toStr';
      
      final response = await http.get(
        Uri.parse(url),
        headers: authHeaders,
      );
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'patient_${widget.patientId}_analytics_${DateTime.now().millisecondsSinceEpoch}.$type';
        
        if (kIsWeb) {
          web_utils.downloadFile(fileName, bytes);
        }
      }
    } catch (e) {
      // Error handling
    }
  }
  */

  void _onFilterChanged(int days) {
    setState(() {
      selectedDays = days;
    });
    fetchAnalytics();
  }

  DashboardAnalytics _getDefaultDashboard() {
    print(
      '🔍 _getDefaultDashboard called - vitals.length: ${vitals.length}, dashboard: ${dashboard != null ? "exists" : "null"}',
    );

    // Priority 1: Return existing dashboard if available
    if (dashboard != null) {
      print('✅ Using existing dashboard data');
      return dashboard!;
    }

    // Priority 2: If we have vitals data, calculate averages from it
    if (vitals.isNotEmpty) {
      print(
        '📊 Calculating dashboard data from ${vitals.length} vitals records',
      );

      // Calculate averages from vitals data
      double avgHeartRate =
          vitals.map((v) => v.heartRate).reduce((a, b) => a + b) /
              vitals.length;
      double avgSpo2 =
          vitals.map((v) => v.spo2).reduce((a, b) => a + b) / vitals.length;
      double avgSystolic =
          vitals.map((v) => v.systolic.toDouble()).reduce((a, b) => a + b) /
              vitals.length;
      double avgDiastolic =
          vitals.map((v) => v.diastolic.toDouble()).reduce((a, b) => a + b) /
              vitals.length;
      double avgWeight =
          vitals.map((v) => v.weight).reduce((a, b) => a + b) / vitals.length;

      // Calculate mood average (only from non-null values)
      List<double> moodValues = vitals
          .where((v) => v.moodValue != null)
          .map((v) => v.moodValue!.toDouble())
          .toList();
      double? avgMoodValue = moodValues.isNotEmpty
          ? moodValues.reduce((a, b) => a + b) / moodValues.length
          : null;

      // Calculate pain average (only from non-null values)
      List<double> painValues = vitals
          .where((v) => v.painValue != null)
          .map((v) => v.painValue!.toDouble())
          .toList();
      double? avgPainValue = painValues.isNotEmpty
          ? painValues.reduce((a, b) => a + b) / painValues.length
          : null;

      // Calculate adherence rate (assume reasonable value if we have data)
      double adherenceRate =
          85.0; // Default reasonable value when dashboard API fails

      print(
        '✅ Calculated averages - HR: $avgHeartRate, SpO2: $avgSpo2, Mood: $avgMoodValue, Pain: $avgPainValue',
      );

      return DashboardAnalytics(
        adherenceRate: adherenceRate,
        avgHeartRate: avgHeartRate,
        avgSpo2: avgSpo2,
        avgSystolic: avgSystolic,
        avgDiastolic: avgDiastolic,
        avgWeight: avgWeight,
        avgMoodValue: avgMoodValue,
        avgPainValue: avgPainValue,
        moodValues: moodValues,
        painValues: painValues,
        periodStart: vitals.isNotEmpty
            ? vitals.last.timestamp
            : DateTime.now().subtract(Duration(days: selectedDays)),
        periodEnd: vitals.isNotEmpty ? vitals.first.timestamp : DateTime.now(),
      );
    }

    print('⚠️ No vitals data available - returning null dashboard');
    // Priority 3: If no vitals data, return null values (will show "N/A" in UI)
    return DashboardAnalytics(
      adherenceRate: null,
      avgHeartRate: null,
      avgSpo2: null,
      avgSystolic: null,
      avgDiastolic: null,
      avgWeight: null,
      avgMoodValue: null,
      avgPainValue: null,
      moodValues: [],
      painValues: [],
      periodStart: DateTime.now().subtract(Duration(days: selectedDays)),
      periodEnd: DateTime.now(),
    );
  }

  String _getShortTitle(String title) {
    // Create shortened titles for mobile view to save space
    switch (title) {
      case 'Adherence Rate':
        return 'Adherence';
      case 'Avg Heart Rate':
        return 'HR';
      case 'Avg SpO₂':
        return 'SpO₂';
      case 'Avg Systolic':
        return 'Systolic';
      case 'Avg Diastolic':
        return 'Diastolic';
      case 'Avg Weight':
        return 'Weight';
      case 'Avg Mood':
        return 'Mood';
      case 'Avg Pain Level':
        return 'Pain';
      default:
        return title.length > 8 ? title.substring(0, 8) : title;
    }
  }

  String _getHealthDataContext() {
    if (vitals.isEmpty && dashboard == null) {
      return "No health data available for this patient in the selected period.";
    } else {
      StringBuffer context = StringBuffer();
      context.writeln("PATIENT HEALTH DATA SUMMARY (Last $selectedDays days):");
      context.writeln(
        "Note: Personal identifiers have been removed for privacy.",
      );
      context.writeln("");

      // Add dashboard summary if available
      if (dashboard != null) {
        context.writeln("OVERVIEW METRICS:");
        context.writeln(
          "• Adherence Rate: ${dashboard!.adherenceRate?.toStringAsFixed(1) ?? 'N/A'}%",
        );
        context.writeln(
          "• Average Heart Rate: ${dashboard!.avgHeartRate?.toStringAsFixed(1) ?? 'N/A'} bpm",
        );
        context.writeln(
          "• Average SpO₂: ${dashboard!.avgSpo2?.toStringAsFixed(1) ?? 'N/A'}%",
        );
        context.writeln(
          "• Average Blood Pressure: ${dashboard!.avgSystolic?.toStringAsFixed(1) ?? 'N/A'}/${dashboard!.avgDiastolic?.toStringAsFixed(1) ?? 'N/A'} mmHg",
        );
        context.writeln(
          "• Average Weight: ${dashboard!.avgWeight?.toStringAsFixed(1) ?? 'N/A'} lbs",
        );
        // ADD THESE LINES:
        context.writeln(
          "• Average Mood: ${dashboard!.avgMoodValue?.toStringAsFixed(1) ?? 'N/A'}/10",
        );
        context.writeln(
          "• Average Pain Level: ${dashboard!.avgPainValue?.toStringAsFixed(1) ?? 'N/A'}/10",
        );
        context.writeln("");
      }

      // Add recent vitals data including mood and pain
      if (vitals.isNotEmpty) {
        context.writeln("RECENT VITAL SIGNS:");
        final recentVitals = vitals.take(10).toList();
        for (var vital in recentVitals) {
          String moodStr = vital.moodValue != null
              ? 'Mood ${vital.moodValue}/10'
              : 'Mood N/A';
          String painStr = vital.painValue != null
              ? 'Pain ${vital.painValue}/10'
              : 'Pain N/A';
          context.writeln(
            "• ${vital.timestamp.toString().substring(0, 10)}: HR ${vital.heartRate}bpm, SpO₂ ${vital.spo2}%, BP ${vital.systolic}/${vital.diastolic}mmHg, Weight ${vital.weight}lbs, $moodStr, $painStr",
          );
        }
        if (vitals.length > 10) {
          context.writeln("... and ${vitals.length - 10} more entries");
        }
        context.writeln("");
      }

      // Add trends including mood and pain
      if (vitals.length > 1) {
        final firstVital = vitals.last; // oldest
        final lastVital = vitals.first; // newest

        context.writeln("TRENDS OVER PERIOD:");
        context.writeln(
          "• Heart Rate: ${firstVital.heartRate}bpm → ${lastVital.heartRate}bpm (${lastVital.heartRate - firstVital.heartRate > 0 ? '+' : ''}${lastVital.heartRate - firstVital.heartRate})",
        );
        context.writeln(
          "• SpO₂: ${firstVital.spo2}% → ${lastVital.spo2}% (${lastVital.spo2 - firstVital.spo2 > 0 ? '+' : ''}${lastVital.spo2 - firstVital.spo2})",
        );
        context.writeln(
          "• Weight: ${firstVital.weight}lbs → ${lastVital.weight}lbs (${lastVital.weight - firstVital.weight > 0 ? '+' : ''}${(lastVital.weight - firstVital.weight).toStringAsFixed(1)})",
        );

        // ADD MOOD AND PAIN TRENDS:
        if (firstVital.moodValue != null && lastVital.moodValue != null) {
          context.writeln(
            "• Mood: ${firstVital.moodValue}/10 → ${lastVital.moodValue}/10 (${lastVital.moodValue! - firstVital.moodValue! > 0 ? '+' : ''}${lastVital.moodValue! - firstVital.moodValue!})",
          );
        }
        if (firstVital.painValue != null && lastVital.painValue != null) {
          context.writeln(
            "• Pain Level: ${firstVital.painValue}/10 → ${lastVital.painValue}/10 (${lastVital.painValue! - firstVital.painValue! > 0 ? '+' : ''}${lastVital.painValue! - firstVital.painValue!})",
          );
        }
        context.writeln("");
      }

      context.writeln("You can ask questions about:");
      context.writeln("• Health trends and patterns");
      context.writeln("• Normal ranges and what values mean");
      context.writeln("• Potential health concerns or improvements");
      context.writeln("• Medication adherence insights");
      context.writeln("• Lifestyle recommendations");
      context.writeln("• Data interpretation and analysis");
      context.writeln("• Mood and pain level correlations"); // ADD THIS

      return context.toString();
    }
  }

  // Ensures a non-nullable String is always returned for health data context.
  // If no data, returns a default message; otherwise, returns the summary.
  // This prevents null errors and avoids throwing exceptions.
  // Always returns a valid String for display.
  Widget _buildAIAssistantCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use direct MediaQuery for production-ready responsive design
        final screenWidth = MediaQuery.of(context).size.width;

        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  AppTheme.success.withOpacity(0.05),
                  AppTheme.success.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(screenWidth < 400 ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ColorUtils.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.psychology,
                          color: ColorUtils.textLight,
                          size: screenWidth < 400 ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AI Health Assistant',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: screenWidth < 400 ? 14 : 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ask questions about this patient\'s health data and get AI-powered insights:',
                    style: TextStyle(
                      fontSize: screenWidth < 400 ? 12 : 14,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(screenWidth < 400 ? 8 : 12),
                    decoration: BoxDecoration(
                      color: ColorUtils.getInfoLight(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ColorUtils.getPrimaryLighter()),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You can ask about:',
                          style: TextStyle(
                            fontSize: screenWidth < 400 ? 11 : 13,
                            fontWeight: FontWeight.w600,
                            color: ColorUtils.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '• Health trends and patterns interpretation\n'
                          '• Whether values are within normal ranges\n'
                          '• Potential health concerns or improvements\n'
                          '• Medication adherence insights\n'
                          '• Lifestyle and care recommendations\n'
                          '• Overall health progress assessment',
                          style: TextStyle(
                            fontSize: screenWidth < 400 ? 10 : 12,
                            color: Colors.grey.shade700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (screenWidth >= 400) ...[
                    Text(
                      'Sample questions:',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildSuggestionChip('Interpret trends'),
                        _buildSuggestionChip('Normal ranges'),
                        _buildSuggestionChip('Health concerns'),
                        _buildSuggestionChip('Recommendations'),
                        _buildSuggestionChip('Adherence analysis'),
                        _buildSuggestionChip('Progress summary'),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(screenWidth < 400 ? 6 : 8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: screenWidth < 400 ? 14 : 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Click "Ask AI" to start a conversation about the patient\'s health data',
                            style: TextStyle(
                              fontSize: screenWidth < 400 ? 10 : 11,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.privacy_tip,
                        size: screenWidth < 400 ? 14 : 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Personal identifiers are excluded for privacy',
                          style: TextStyle(
                            fontSize: screenWidth < 400 ? 10 : 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionChip(String label) {
    // Use direct MediaQuery for production-ready responsive design
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth < 400 ? 8 : 10,
        vertical: screenWidth < 400 ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: ColorUtils.getInfoLight(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ColorUtils.getInfoLighter()),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: screenWidth < 400 ? 11 : 14,
          color: ColorUtils.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use direct MediaQuery for production-ready responsive design
        final screenWidth = MediaQuery.of(context).size.width;

        return Wrap(
          spacing: screenWidth < 400 ? 6 : 8,
          runSpacing: 6,
          children: [7, 14, 21, 30].map((days) {
            final isSelected = selectedDays == days;
            return FilterChip(
              label: Text(
                screenWidth < 400 ? '${days}d' : '$days days',
                style: TextStyle(fontSize: screenWidth < 400 ? 12 : 14),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _onFilterChanged(days);
                }
              },
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.15),
              checkmarkColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: screenWidth < 400 ? 12 : 14,
              ),
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth < 400 ? 8 : 12,
                vertical: screenWidth < 400 ? 4 : 8,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget buildChart(
    String title,
    List<FlSpot> spots, {
    double minY = 0,
    double maxY = 200,
    Color? primaryColor,
    String? unit,
  }) {
    final bool hasData = spots.isNotEmpty;
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLighter = Theme.of(
      context,
    ).colorScheme.primary.withOpacity(0.08);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(
        bottom: 16,
      ), // Fixed spacing to prevent overlap
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.white, themePrimaryLighter],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.of(context).size.width < 400 ? 16 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryColor ?? themePrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:
                            MediaQuery.of(context).size.width < 400 ? 14 : 16,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  if (unit != null)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            MediaQuery.of(context).size.width < 400 ? 6 : 8,
                        vertical:
                            MediaQuery.of(context).size.width < 400 ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: themePrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unit,
                        style: TextStyle(
                          fontSize:
                              MediaQuery.of(context).size.width < 400 ? 12 : 14,
                          color: primaryColor ?? themePrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!hasData)
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Use direct MediaQuery for production-ready responsive design
                    final screenWidth = MediaQuery.of(context).size.width;

                    return Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth < 400 ? 30 : 40,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.show_chart,
                              size: screenWidth < 400 ? 36 : 48,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: screenWidth < 400 ? 12 : 16),
                            Text(
                              'No data available for this period',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: screenWidth < 400 ? 12 : 14,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
              else
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots.isNotEmpty ? spots : [FlSpot(0, minY)],
                          isCurved: true,
                          color: primaryColor ?? themePrimary,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: spots.length <= 10,
                            getDotPainter: (spot, percent, barData, index) =>
                                FlDotCirclePainter(
                              radius: 4,
                              color: primaryColor ?? themePrimary,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: (primaryColor ?? themePrimary).withOpacity(
                              0.1,
                            ),
                          ),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: hasData,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (!hasData || idx < 0 || idx >= vitals.length) {
                                return const SizedBox();
                              }
                              final date = vitals[idx].timestamp;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${date.month}/${date.day}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              );
                            },
                            reservedSize: 32,
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade300,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final dashData = dashboard ?? _getDefaultDashboard();
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;

        // Mobile-first design: Use horizontal scrolling cards for narrow screens
        if (screenWidth < 500) {
          return _buildMobileSummaryCards(dashData);
        } else {
          return _buildDesktopSummaryGrid(dashData);
        }
      },
    );
  }

  Widget _buildMobileSummaryCards(DashboardAnalytics dashData) {
    // Get latest vital for current readings
    final latestVital = vitals.isNotEmpty ? vitals.first : null;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Debug: Print dashboard data to check what we have
    print('🔍 Mobile Summary - Dashboard data:');
    print('  - avgMood: ${dashData.avgMoodValue}');
    print('  - avgPain: ${dashData.avgPainValue}');
    print('  - avgHeartRate: ${dashData.avgHeartRate}');
    print('  - avgSpo2: ${dashData.avgSpo2}');

    // If no data at all, show a helpful message
    if (latestVital == null && dashData.avgHeartRate == null) {
      return Container(
        padding: const EdgeInsets.all(16), // Reduced padding
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.health_and_safety,
              color: isDarkMode
                  ? Colors.white.withOpacity(0.6)
                  : Colors.white.withOpacity(0.7),
              size: 28, // Reduced size
            ),
            const SizedBox(height: 8), // Reduced spacing
            Text(
              'No Health Data Available',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.white,
                fontSize: 14, // Reduced font size
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6), // Reduced spacing
            Text(
              'No vitals recorded in the last $selectedDays days.\nPlease sync your health devices or add manual entries.',
              style: TextStyle(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.8),
                fontSize: 11, // Reduced font size
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4, // Prevent overflow
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Prevent overflow
        children: [
          // Show dashboard averages prominently since they are available
          Row(
            children: [
              Text(
                'Health Summary',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.white,
                  fontSize: 15, // Reduced font size
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6), // Reduced spacing
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ), // Reduced padding
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(isDarkMode ? 0.3 : 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.blue.withOpacity(isDarkMode ? 0.4 : 0.3),
                  ),
                ),
                child: Text(
                  '$selectedDays days avg',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.white,
                    fontSize: 9, // Reduced font size
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // Reduced spacing
          // Main health metrics in compact horizontal scroll
          SizedBox(
            height: 85, // Further reduced height to prevent overflow
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (dashData.avgHeartRate != null)
                  _buildCompactCard(
                    'HR',
                    dashData.avgHeartRate!.toStringAsFixed(0),
                    'bpm',
                    Icons.favorite,
                    Colors.red.shade300,
                  ),
                if (dashData.avgSpo2 != null)
                  _buildCompactCard(
                    'SpO₂',
                    dashData.avgSpo2!.toStringAsFixed(1),
                    '%',
                    Icons.bloodtype,
                    Colors.blue.shade300,
                  ),
                if (dashData.avgSystolic != null &&
                    dashData.avgDiastolic != null)
                  _buildCompactCard(
                    'BP',
                    '${dashData.avgSystolic!.toStringAsFixed(0)}/${dashData.avgDiastolic!.toStringAsFixed(0)}',
                    'mmHg',
                    Icons.monitor_heart,
                    Colors.purple.shade300,
                  ),
                if (dashData.avgWeight != null)
                  _buildCompactCard(
                    'Weight',
                    dashData.avgWeight!.toStringAsFixed(1),
                    'lbs',
                    Icons.monitor_weight,
                    Colors.green.shade300,
                  ),
                if (dashData.avgMoodValue != null)
                  _buildCompactCard(
                    'Mood',
                    dashData.avgMoodValue!.toStringAsFixed(1),
                    '/10',
                    Icons.mood,
                    Colors.amber.shade300,
                  ),
                if (dashData.avgPainValue != null)
                  _buildCompactCard(
                    'Pain',
                    dashData.avgPainValue!.toStringAsFixed(1),
                    '/10',
                    Icons.healing,
                    Colors.orange.shade300,
                  ),
                if (dashData.adherenceRate != null)
                  _buildCompactCard(
                    'Adherence',
                    dashData.adherenceRate!.toStringAsFixed(0),
                    '%',
                    Icons.check_circle,
                    Colors.indigo.shade300,
                  ),
              ],
            ),
          ),

          // Latest readings section if available
          if (latestVital != null) ...[
            const SizedBox(height: 10), // Reduced spacing
            Row(
              children: [
                Text(
                  'Latest Reading',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.white70,
                    fontSize: 13, // Reduced font size
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6), // Reduced spacing
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ), // Reduced padding
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(isDarkMode ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green.withOpacity(isDarkMode ? 0.4 : 0.3),
                    ),
                  ),
                  child: Text(
                    _formatDateTimeAgo(latestVital.timestamp),
                    style: TextStyle(
                      color: isDarkMode ? Colors.white60 : Colors.white70,
                      fontSize: 8, // Reduced font size
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4), // Reduced spacing
            SizedBox(
              height: 70, // Further reduced height to prevent overflow
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCompactCard(
                    'HR',
                    '${latestVital.heartRate}',
                    'bpm',
                    Icons.favorite,
                    Colors.red.shade200,
                  ),
                  _buildCompactCard(
                    'SpO₂',
                    '${latestVital.spo2}',
                    '%',
                    Icons.bloodtype,
                    Colors.blue.shade200,
                  ),
                  _buildCompactCard(
                    'BP',
                    '${latestVital.systolic}/${latestVital.diastolic}',
                    'mmHg',
                    Icons.monitor_heart,
                    Colors.purple.shade200,
                  ),
                  _buildCompactCard(
                    'Weight',
                    latestVital.weight.toStringAsFixed(1),
                    'lbs',
                    Icons.monitor_weight,
                    Colors.green.shade200,
                  ),
                  // Find latest mood value from any available reading
                  if (_getLatestValue((v) => v.moodValue) != null)
                    _buildCompactCard(
                      'Mood',
                      '${_getLatestValue((v) => v.moodValue)}',
                      '/10',
                      Icons.mood,
                      Colors.amber.shade200,
                    ),
                  // Find latest pain value from any available reading
                  if (_getLatestValue((v) => v.painValue) != null)
                    _buildCompactCard(
                      'Pain',
                      '${_getLatestValue((v) => v.painValue)}',
                      '/10',
                      Icons.healing,
                      Colors.orange.shade200,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Helper method to get the latest available value for a metric
  // Falls back to next latest reading if current doesn't have the value
  T? _getLatestValue<T>(T? Function(Vital) getValue) {
    if (vitals.isEmpty) return null;

    // Check each vital from newest to oldest until we find a non-null value
    for (final vital in vitals) {
      final value = getValue(vital);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Widget _buildCompactCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDarkMode ? color.withOpacity(0.25) : color.withOpacity(0.15);
    final borderColor =
        isDarkMode ? color.withOpacity(0.4) : color.withOpacity(0.3);
    final textColor = isDarkMode ? Colors.white : Colors.white;
    final unitTextColor = isDarkMode
        ? Colors.white.withOpacity(0.7)
        : Colors.white.withOpacity(0.8);

    return Container(
      width: 80, // Further reduced to fit more cards and prevent overflow
      margin: const EdgeInsets.only(right: 6), // Reduced margin
      padding: const EdgeInsets.all(6), // Further reduced padding
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16), // Further reduced icon size
          const SizedBox(height: 2), // Reduced spacing
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 8, // Further reduced font size
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 12, // Reduced font size
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            unit,
            style: TextStyle(
              color: unitTextColor,
              fontSize: 7, // Further reduced unit text
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSummaryGrid(DashboardAnalytics dashData) {
    final screenWidth = MediaQuery.of(context).size.width;

    double aspectRatio;
    int crossAxisCount;

    // Production-ready responsive breakpoints for AWS Amplify
    if (screenWidth < 600) {
      aspectRatio = 2.2; // Reduced to prevent overflow
      crossAxisCount = 2;
    } else if (screenWidth < 900) {
      aspectRatio = 2.5; // Reduced to prevent overflow
      crossAxisCount = 3;
    } else if (screenWidth < 1200) {
      aspectRatio = 2.8; // Reduced to prevent overflow
      crossAxisCount = 4;
    } else {
      aspectRatio = 3.0; // Reduced to prevent overflow
      crossAxisCount = 4;
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6, // Prevent overflow
      ),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 8, // Reduced spacing
        mainAxisSpacing: 8, // Reduced spacing
        children: [
          _buildDesktopSummaryItem(
            'Adherence Rate',
            dashData.adherenceRate != null
                ? '${dashData.adherenceRate!.toStringAsFixed(1)}%'
                : 'N/A',
            Icons.check_circle,
            Colors.indigo.shade300,
            hasData: dashData.adherenceRate != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Heart Rate',
            dashData.avgHeartRate != null
                ? '${dashData.avgHeartRate!.toStringAsFixed(0)} bpm'
                : 'N/A',
            Icons.favorite,
            Colors.red.shade300,
            hasData: dashData.avgHeartRate != null,
          ),
          _buildDesktopSummaryItem(
            'Avg SpO₂',
            dashData.avgSpo2 != null
                ? '${dashData.avgSpo2!.toStringAsFixed(1)}%'
                : 'N/A',
            Icons.bloodtype,
            Colors.blue.shade300,
            hasData: dashData.avgSpo2 != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Systolic',
            dashData.avgSystolic != null
                ? '${dashData.avgSystolic!.toStringAsFixed(0)} mmHg'
                : 'N/A',
            Icons.monitor_heart,
            Colors.purple.shade300,
            hasData: dashData.avgSystolic != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Diastolic',
            dashData.avgDiastolic != null
                ? '${dashData.avgDiastolic!.toStringAsFixed(0)} mmHg'
                : 'N/A',
            Icons.health_and_safety,
            Colors.purple.shade200,
            hasData: dashData.avgDiastolic != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Weight',
            dashData.avgWeight != null
                ? '${dashData.avgWeight!.toStringAsFixed(1)} lbs'
                : 'N/A',
            Icons.monitor_weight,
            Colors.green.shade300,
            hasData: dashData.avgWeight != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Mood',
            dashData.avgMoodValue != null
                ? '${dashData.avgMoodValue!.toStringAsFixed(1)}/10'
                : 'N/A',
            Icons.mood,
            Colors.amber.shade300,
            hasData: dashData.avgMoodValue != null,
          ),
          _buildDesktopSummaryItem(
            'Avg Pain Level',
            dashData.avgPainValue != null
                ? '${dashData.avgPainValue!.toStringAsFixed(1)}/10'
                : 'N/A',
            Icons.healing,
            Colors.orange.shade300,
            hasData: dashData.avgPainValue != null,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSummaryItem(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool hasData = true,
  }) {
    // Dark mode support
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDarkMode ? color.withOpacity(0.2) : color.withOpacity(0.15);
    final borderColor =
        isDarkMode ? color.withOpacity(0.4) : color.withOpacity(0.3);
    final textColor = isDarkMode
        ? (hasData ? Colors.white : Colors.white60)
        : (hasData ? Colors.grey.shade900 : Colors.grey.shade600);
    final titleColor = isDarkMode ? Colors.white70 : Colors.grey.shade800;

    return Container(
      padding: const EdgeInsets.all(12), // Reduced from 16 to prevent overflow
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20), // Reduced icon size
              const SizedBox(width: 6), // Reduced spacing
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 12, // Reduced font size
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6), // Reduced spacing
          Text(
            hasData ? value : 'No data',
            style: TextStyle(
              color: textColor,
              fontSize: 16, // Reduced font size
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (!hasData)
            Text(
              'No records yet',
              style: TextStyle(
                color: isDarkMode ? Colors.white38 : Colors.grey.shade500,
                fontSize: 10, // Reduced font size
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBarHelper.createAppBar(context, title: 'Patient Analytics'),
        drawer: const CommonDrawer(currentRoute: '/analytics'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBarHelper.createAppBar(context, title: 'Patient Analytics'),
        drawer: const CommonDrawer(currentRoute: '/analytics'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: fetchAnalytics,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          onPressed: () {
            final double sheetHeight =
                MediaQuery.of(context).size.height * 0.75;
            showModalBottomSheet(
              isScrollControlled: true,
              context: context,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width,
              ),
              builder: (context) => SizedBox(
                height: sheetHeight,
                child: AIChat(
                  key: ValueKey(
                    'ai-chat-${AiChatMode.groundedRecords.name}-${widget.patientId}',
                  ),
                  role: 'caregiver',
                  healthDataContext: _getHealthDataContext(),
                  isModal: true,
                  patientId: widget.patientId,
                  mode: AiChatMode.groundedRecords,
                ),
              ),
            );
          },
          tooltip: 'Ask AI about analytics',
          child: const Icon(Icons.chat_bubble_outline),
        ),
      );
    }

    // Prepare chart data with different colors for each chart - with null safety
    List<FlSpot> heartRateSpots = [];
    List<FlSpot> spo2Spots = [];
    List<FlSpot> systolicSpots = [];
    List<FlSpot> diastolicSpots = [];
    List<FlSpot> weightSpots = [];

    // Only process data if vitals list is not empty and properly loaded
    if (vitals.isNotEmpty) {
      try {
        heartRateSpots = [
          for (int i = 0; i < vitals.length; i++)
            FlSpot(i.toDouble(), vitals[i].heartRate),
        ];
        spo2Spots = [
          for (int i = 0; i < vitals.length; i++)
            FlSpot(i.toDouble(), vitals[i].spo2),
        ];
        systolicSpots = [
          for (int i = 0; i < vitals.length; i++)
            FlSpot(i.toDouble(), vitals[i].systolic.toDouble()),
        ];
        diastolicSpots = [
          for (int i = 0; i < vitals.length; i++)
            FlSpot(i.toDouble(), vitals[i].diastolic.toDouble()),
        ];
        weightSpots = [
          for (int i = 0; i < vitals.length; i++)
            FlSpot(i.toDouble(), vitals[i].weight),
        ];
      } catch (e) {
        print('Error preparing chart data: $e');
        // Reset to empty lists if there's an error
        heartRateSpots = [];
        spo2Spots = [];
        systolicSpots = [];
        diastolicSpots = [];
        weightSpots = [];
      }
    }
    List<FlSpot> moodSpots = _getSafeSpots(
      vitals.map((v) => v.moodValue?.toDouble()).toList(),
      defaultValue: 0.0,
    );

    List<FlSpot> painSpots = _getSafeSpots(
      vitals.map((v) => v.painValue?.toDouble()).toList(),
      defaultValue: 0.0,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CommonDrawer(currentRoute: '/analytics'),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        title: Text(
          'Patient Analytics',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Always show visible colorful export buttons (no dropdown even on mobile)
          Container(
            margin: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: 'Download CSV',
              child: ElevatedButton.icon(
                onPressed: () => exportFile('csv'),
                icon: const Icon(Icons.download, size: 18),
                label: MediaQuery.of(context).size.width > 500
                    ? const Text('CSV')
                    : const SizedBox.shrink(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).size.width > 500 ? 12 : 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(
                    44,
                    40,
                  ), // Increased minimum size for mobile
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Download PDF',
              child: ElevatedButton.icon(
                onPressed: () => exportFile('pdf'),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: MediaQuery.of(context).size.width > 500
                    ? const Text('PDF')
                    : const SizedBox.shrink(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).size.width > 500 ? 12 : 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(
                    44,
                    40,
                  ), // Increased minimum size for mobile
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: ResponsiveContainer(
                    padding: EdgeInsets.all(
                      MediaQuery.of(context).size.width < 400 ? 12 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome header
                        Text(
                          'Analytics Overview',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Patient health metrics and trends',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Filter chips
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final screenWidth = MediaQuery.of(
                              context,
                            ).size.width;

                            if (screenWidth < 500) {
                              // Stack vertically on small screens
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Time Range:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildFilterChips(),
                                ],
                              );
                            } else {
                              // Horizontal layout for larger screens
                              return Row(
                                children: [
                                  Text(
                                    'Time Range:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildFilterChips()),
                                ],
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 24),

                        // AI Assistant Card
                        _buildAIAssistantCard(),

                        const SizedBox(height: 24),

                        // Summary Card - Always show, even when no data
                        Card(
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.85),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.analytics,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Health Summary',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: MediaQuery.of(
                                                          context,
                                                        ).size.width <
                                                        400
                                                    ? 16
                                                    : 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            LayoutBuilder(
                                              builder: (context, constraints) {
                                                // Use shorter format for narrow screens
                                                if (constraints.maxWidth <
                                                    200) {
                                                  return Text(
                                                    'Last ${selectedDays}d',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  );
                                                } else {
                                                  return Text(
                                                    'Last $selectedDays days overview',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: MediaQuery.of(
                                                                context,
                                                              ).size.width <
                                                              400
                                                          ? 12
                                                          : 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.width < 400
                                            ? 16
                                            : 20,
                                  ),
                                  // Use constrained height to prevent overflow
                                  Container(
                                    constraints: BoxConstraints(
                                      maxHeight: MediaQuery.of(context)
                                              .size
                                              .height *
                                          0.4, // Maximum 40% of screen height
                                    ),
                                    child: SingleChildScrollView(
                                      child: _buildSummaryGrid(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Charts Section
                        Text(
                          'Detailed Charts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        buildChart(
                          'Mood Level',
                          moodSpots,
                          minY: 1,
                          maxY: 10,
                          primaryColor: Colors.amber.shade600,
                          unit: '/10',
                        ),

                        buildChart(
                          'Pain Level',
                          painSpots,
                          minY: 1,
                          maxY: 10,
                          primaryColor: Colors.red.shade800,
                          unit: '/10',
                        ),
                        buildChart(
                          'Heart Rate',
                          heartRateSpots,
                          minY: 50,
                          maxY: 120,
                          primaryColor: Colors.red.shade600,
                          unit: 'bpm',
                        ),
                        buildChart(
                          'SpO₂',
                          spo2Spots,
                          minY: 90,
                          maxY: 100,
                          primaryColor: Colors.blue.shade600,
                          unit: '%',
                        ),
                        buildChart(
                          'Systolic Blood Pressure',
                          systolicSpots,
                          minY: 100,
                          maxY: 140,
                          primaryColor: Colors.orange.shade600,
                          unit: 'mmHg',
                        ),
                        buildChart(
                          'Diastolic Blood Pressure',
                          diastolicSpots,
                          minY: 60,
                          maxY: 100,
                          primaryColor: Colors.purple.shade600,
                          unit: 'mmHg',
                        ),
                        buildChart(
                          'Weight',
                          weightSpots,
                          minY: 100,
                          maxY: 250,
                          primaryColor: AppTheme.success,
                          unit: 'lbs',
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Loading overlay for filter changes
                if (loading)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Loading analytics data...',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // AI Chat FloatingActionButton commented out
      /*
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.chat_bubble_outline),
        onPressed: () {
          final double sheetHeight = MediaQuery.of(context).size.height * 0.75;
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width,
            ),
            builder: (context) => SizedBox(
              height: sheetHeight,
              child: AIChat(
                role: 'caregiver',
                healthDataContext: _getHealthDataContext(),
                isModal: true,
                patientId: widget.patientId,
                mode: AiChatMode.groundedRecords,
              ),
            ),
          );
        },
        tooltip: 'Ask AI about analytics',
      ),
      */
    );
  }
}
