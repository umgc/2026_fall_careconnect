import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/format.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/invoice_models.dart';
import '../../services/invoice_service.dart';

import 'widgets/overdue_block.dart';
import 'widgets/kpi_card.dart';
import 'widgets/activity_and_charts.dart';

class InvoiceDashboardPage extends StatefulWidget {
  const InvoiceDashboardPage({super.key});

  @override
  State<InvoiceDashboardPage> createState() => _InvoiceDashboardPageState();
}

class _InvoiceDashboardPageState extends State<InvoiceDashboardPage> {
  late final Future<List<Invoice>> _invoicesFuture =
      InvoiceService.instance.fetchInvoices();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Invoice>>(
        future: _invoicesFuture,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final invoices = snap.data ?? const <Invoice>[];
          final metrics = computeMetrics(invoices);

          return LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final isDesktop = w >= 900;
              final cols = w >= 1400 ? 12 : (w >= 900 ? 8 : 1);
              const gutter = 12.0;
              const maxContentWidth = 1600.0;
              final leftRailWidth = isDesktop ? 360.0 : w;

              int span(int desktop, int tablet) {
                if (cols >= 12) return desktop;
                if (cols >= 6) return tablet;
                return 1;
              }

              Widget overdueRail() => ConstrainedBox(
                    constraints: BoxConstraints.tightFor(width: leftRailWidth),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: OverdueBlock(
                              invoices: invoices, loading: loading),
                        ),
                      ),
                    ),
                  );

              Widget gridBody() => _grid(
                    cols: cols,
                    gutter: gutter,
                    invoices: invoices,
                    metrics: metrics,
                    loading: loading,
                    span: span,
                  );

              Widget rightGrid({bool scrollable = true}) => Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: maxContentWidth),
                      child: scrollable
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: gridBody(),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: gridBody(),
                            ),
                    ),
                  );

              if (!isDesktop) {
                // Single scroll view on mobile to avoid nested scroll issues
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      overdueRail(),
                      rightGrid(scrollable: false),
                    ],
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: leftRailWidth,
                    child: SingleChildScrollView(child: overdueRail()),
                  ),
                  Expanded(child: rightGrid()),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _grid({
    required int cols,
    required double gutter,
    required List<Invoice> invoices,
    required Metrics metrics,
    required bool loading,
    required int Function(int desktop, int tablet) span,
  }) {
    return StaggeredGrid.count(
      crossAxisCount: cols,
      mainAxisSpacing: gutter,
      crossAxisSpacing: gutter,
      children: [
        StaggeredGridTile.fit(
          crossAxisCellCount: span(3, 3),
          child: KpiCard(
            icon: Icons.receipt_long,
            title: 'Total Invoices',
            subtitle: 'Active medical invoices',
            value: '${metrics.totalCount}',
            loading: loading,
          ),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(3, 3),
          child: KpiCard(
            icon: Icons.attach_money,
            title: 'Total Amount',
            subtitle: 'Across all invoices',
            value: currency(metrics.totalAmount),
            loading: loading,
          ),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(3, 3),
          child: KpiCard(
            icon: Icons.schedule,
            title: 'Pending Payments',
            subtitle: 'Requires attention',
            value: currency(metrics.pendingAmount),
            loading: loading,
          ),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(3, 3),
          child: KpiCard(
            icon: Icons.report_gmailerrorred_outlined,
            title: 'Overdue Bills',
            subtitle: 'Past due date',
            value: '${metrics.overdueCount}',
            loading: loading,
          ),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(6, 6),
          child: RecentActivityCard(invoices: invoices, loading: loading),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(4, 6),
          child: PaymentProgressCard(metrics: metrics, loading: loading),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(8, 6),
          child: PaymentStatusChartCard(invoices: invoices, loading: loading),
        ),
        StaggeredGridTile.fit(
          crossAxisCellCount: span(12, 6),
          child: MonthlyInvoiceTrendsCard(invoices: invoices, loading: loading),
        ),
      ],
    );
  }
}
