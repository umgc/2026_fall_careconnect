import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PatientReportsScreen extends StatelessWidget {
  const PatientReportsScreen({super.key});

  String _getMonthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    // --- Fake data ---
    final double avgMood = 7.5; // out of 10

    // Generate last 7 days with actual dates
    final now = DateTime.now();
    final moodTrend = List.generate(7, (index) {
      final date = now
          .subtract(Duration(days: 6 - index)); // Last 7 days including today
      final moodValues = [6, 8, 7, 9, 6, 8, 7]; // Your mood values
      return {
        'date': date,
        'mood': moodValues[index],
        'displayDate':
            '${_getMonthAbbreviation(date.month)} ${date.day}', // Format: Oct 9
      };
    });

    final adherenceData = [
      {'day': 'Mon', 'taken': 3, 'missed': 1},
      {'day': 'Tue', 'taken': 2, 'missed': 2},
      {'day': 'Wed', 'taken': 4, 'missed': 0},
      {'day': 'Thu', 'taken': 1, 'missed': 3},
      {'day': 'Fri', 'taken': 3, 'missed': 1},
      {'day': 'Sat', 'taken': 4, 'missed': 0},
      {'day': 'Sun', 'taken': 2, 'missed': 2},
    ];

    // compute adherence percentage (taken / (taken + missed))
    final totalTaken =
        adherenceData.fold<int>(0, (s, d) => s + (d['taken'] as int));
    final totalMissed =
        adherenceData.fold<int>(0, (s, d) => s + (d['missed'] as int));
    final adherencePercent = (totalTaken + totalMissed) > 0
        ? (totalTaken / (totalTaken + totalMissed)) * 100
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('My Reports'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ---- Summary row: Average Mood (out of 10) + Adherence %
          Row(children: [
            Expanded(
              child: _SummaryCard(
                title: 'Average Mood',
                value: '${avgMood.toStringAsFixed(1)} / 10',
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Adherence',
                value: '${adherencePercent.toStringAsFixed(0)}%',
                color: adherencePercent >= 80 ? Colors.green : Colors.redAccent,
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ---- Mood Trend (line chart) ----
          const Text('Mood Trend (Last 7 Days)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: _panelDecoration(),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 2,
                  verticalInterval: 1,
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      getTitlesWidget: (value, meta) {
                        // show integers 0,2,4,6,8,10 only
                        if (value % 2 == 0) {
                          return Text(value.toInt().toString(),
                              style: const TextStyle(fontSize: 12));
                        }
                        return const SizedBox.shrink();
                      },
                      reservedSize: 28,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i >= 0 && i < moodTrend.length) {
                          final displayDate =
                              moodTrend[i]['displayDate'] as String;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(displayDate,
                                style: const TextStyle(fontSize: 12)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                    show: true, border: Border.all(color: Colors.black12)),
                minX: 0,
                maxX: (moodTrend.length - 1).toDouble(),
                minY: 0,
                maxY: 10,
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      moodTrend.length,
                      (i) => FlSpot(i.toDouble(),
                          (moodTrend[i]['mood'] as num).toDouble()),
                    ),
                    isCurved: true,
                    color: Colors.green,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                        show: true, color: Colors.green.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Medication Adherence grouped bar chart ----
          const Text('Medication Adherence (Last 7 Days)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            height: 260,
            padding: const EdgeInsets.all(12),
            decoration: _panelDecoration(),
            child: Column(children: [
              Expanded(
                child: BarChart(
                  BarChartData(
                    gridData: FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value % 1 == 0) {
                              // Show integer values only
                              return Text(value.toInt().toString(),
                                  style: const TextStyle(fontSize: 12));
                            }
                            return const SizedBox.shrink();
                          },
                          reservedSize: 28,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i >= 0 && i < adherenceData.length) {
                              final day = adherenceData[i]['day'] as String;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(day,
                                    style: const TextStyle(fontSize: 12)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    // create grouped bars (two rods per group)
                    barGroups: List.generate(adherenceData.length, (i) {
                      final taken =
                          (adherenceData[i]['taken'] as num).toDouble();
                      final missed =
                          (adherenceData[i]['missed'] as num).toDouble();
                      return BarChartGroupData(
                        x: i,
                        groupVertically: false,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: taken,
                            color: Colors.green,
                            width: 16,
                            borderRadius: BorderRadius.zero,
                          ),
                          BarChartRodData(
                            toY: missed,
                            color: Colors.redAccent,
                            width: 16,
                            borderRadius: BorderRadius.zero,
                          ),
                        ],
                      );
                    }),
                    maxY: 6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // legend
              Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                _LegendDot(color: Colors.green, label: 'Taken'),
                SizedBox(width: 12),
                _LegendDot(color: Colors.redAccent, label: 'Missed'),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static BoxDecoration _panelDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryCard(
      {required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 13)),
    ]);
  }
}
