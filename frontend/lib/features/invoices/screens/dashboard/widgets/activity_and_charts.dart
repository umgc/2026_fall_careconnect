import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/format.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/metrics.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_detail_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard(
      {super.key, required this.invoices, required this.loading});
  final List<Invoice> invoices;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = invoices.toList()
      ..sort((a, b) => b.dates.statementDate.compareTo(a.dates.statementDate));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.update, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Recent Invoice Activity',
                  style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text('Latest updates and submissions',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (loading)
              const BlockLoading(height: 160)
            else if (data.isEmpty)
              const Text('No recent activity.')
            else
              Column(
                children: data.take(5).map((i) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      title: Text(i.provider.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(labelForStatus(i.paymentStatus),
                              style: theme.textTheme.bodySmall),
                          Text(fmt(i.dates.statementDate),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                      trailing: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AmountBadge(
                                text: currency(i.amounts.amountDue ??
                                    i.amounts.total ??
                                    0)),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          InvoiceDetailPage(invoice: i)),
                                );
                              },
                              icon: const Icon(Icons.remove_red_eye, size: 16),
                              label: const Text('View'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class PaymentProgressCard extends StatelessWidget {
  const PaymentProgressCard(
      {super.key, required this.metrics, required this.loading});
  final Metrics metrics;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: BlockLoading(height: 160),
        ),
      );
    }

    final total = metrics.totalAmount;
    final paid = metrics.paidAmount;
    final remaining = (total - paid).clamp(0, double.infinity);
    final pct = total > 0 ? (paid / total) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.trending_up, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Payment Progress', style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text('Your payment completion rate',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Paid Invoices', style: theme.textTheme.bodySmall),
              Text('${(pct * 100).round()}%'),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct, minHeight: 10),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Paid',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.green)),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(currency(paid),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Remaining',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                  FittedBox(
                    alignment: Alignment.centerRight,
                    fit: BoxFit.scaleDown,
                    child: Text(currency(remaining),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            Text('Recent Invoice Insights',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Insight(text: 'Contact insurance for claim status'),
            const Insight(text: 'Explore financial assistance programs'),
            const Insight(text: 'Set up payment plans for large bills'),
          ],
        ),
      ),
    );
  }
}

class PaymentStatusChartCard extends StatelessWidget {
  const PaymentStatusChartCard(
      {super.key, required this.invoices, required this.loading});
  final List<Invoice> invoices;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: BlockLoading(height: 240),
        ),
      );
    }

    final paid =
        invoices.where((i) => i.paymentStatus == PaymentStatus.paid).length;
    final pending =
        invoices.where((i) => i.paymentStatus == PaymentStatus.pending).length;
    final rejected = invoices
        .where((i) => i.paymentStatus == PaymentStatus.rejectedInsurance)
        .length;
    final total = (paid + pending + rejected).clamp(1, 1 << 30);

    PieChartSectionData section({required double value, required Color color}) {
      return PieChartSectionData(
        value: value <= 0 ? 0.001 : value,
        color: color,
        title: '',
        radius: 56,
        titleStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.pie_chart, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Payment Status Distribution',
                  style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text('Overview of invoice payment statuses',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: kIsWeb ? 1.8 : 1.5,
              child: PieChart(
                PieChartData(
                  sections: [
                    section(value: paid.toDouble(), color: Colors.green),
                    section(value: pending.toDouble(), color: Colors.orange),
                    section(
                        value: rejected.toDouble(), color: Colors.red.shade600),
                  ],
                  centerSpaceRadius: 46,
                  sectionsSpace: 4,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(enabled: true),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                LegendDot(color: Colors.green, label: 'Paid ($paid)'),
                LegendDot(color: Colors.orange, label: 'Pending ($pending)'),
                LegendDot(
                    color: Colors.red.shade600, label: 'Rejected ($rejected)'),
              ],
            ),
            const SizedBox(height: 4),
            Text('Total: $total', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class MonthlyInvoiceTrendsCard extends StatelessWidget {
  const MonthlyInvoiceTrendsCard(
      {super.key, required this.invoices, required this.loading});
  final List<Invoice> invoices;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: BlockLoading(height: 260),
        ),
      );
    }

    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - (5 - i), 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final label = monthShort(d.month);
      return _MonthBucket(key: key, label: label, date: d);
    });

    final counts =
        Map<String, int>.fromEntries(months.map((m) => MapEntry(m.key, 0)));
    for (final inv in invoices) {
      final d = inv.dates.statementDate;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
    }

    final bars = months
        .map((m) => BarChartGroupData(
              x: months.indexOf(m),
              barRods: [
                BarChartRodData(
                  toY: (counts[m.key] ?? 0).toDouble(),
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ))
        .toList();

    final maxY = (counts.values.isEmpty
            ? 0
            : counts.values.reduce((a, b) => a > b ? a : b))
        .toDouble();
    final yMax = (maxY <= 5) ? 6.0 : maxY + 2.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bar_chart, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Monthly Invoice Trends',
                  style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text('Invoice volume and amounts over time',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 2),
                  borderData: FlBorderData(show: false),
                  barGroups: bars,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true, interval: 2, reservedSize: 28),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= months.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(months[idx].label,
                                style: const TextStyle(fontSize: 12)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  barTouchData: BarTouchData(enabled: true),
                  maxY: yMax,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* Shared tiny widgets */

class Insight extends StatelessWidget {
  const Insight({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.check_circle_outline, size: 18),
      const SizedBox(width: 6),
      Expanded(child: Text(text)),
    ]);
  }
}

class AmountBadge extends StatelessWidget {
  const AmountBadge({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(.4)),
      ),
      child: Text(
        text,
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label),
    ]);
  }
}

class BlockLoading extends StatelessWidget {
  const BlockLoading({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(child: LinearProgressIndicator(minHeight: 4)),
    );
  }
}

class _MonthBucket {
  _MonthBucket({required this.key, required this.label, required this.date});
  final String key;
  final String label;
  final DateTime date;
}
