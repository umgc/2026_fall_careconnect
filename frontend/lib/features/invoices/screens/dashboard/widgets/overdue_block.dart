import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/utilis/format.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/widgets/activity_and_charts.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OverdueBlock extends StatelessWidget {
  const OverdueBlock(
      {super.key, required this.invoices, required this.loading});
  final List<Invoice> invoices;
  final bool loading;

  static const int _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    final overdue = invoices
        .where((i) =>
            i.paymentStatus != PaymentStatus.paid &&
            i.dates.dueDate.isBefore(now))
        .toList()
      ..sort(
          (a, b) => a.dates.dueDate.compareTo(b.dates.dueDate)); // oldest first

    final visible = overdue.take(_maxShown).toList();
    final hasMore = overdue.length > _maxShown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Text('Urgent Attention Required', style: theme.textTheme.titleMedium),
        ]),
        const SizedBox(height: 4),
        Text('Overdue and upcoming bills', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (loading)
          const BlockLoading(height: 160)
        else if (overdue.isEmpty)
          const Text('No invoices found.')
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasMore
                          ? 'Overdue Bills (${visible.length} of ${overdue.length})'
                          : 'Overdue Bills (${overdue.length})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (hasMore)
                    TextButton.icon(
                      onPressed: () {
                        context.pushNamed(
                          'invoiceListFiltered',
                          pathParameters: {'filter': 'overdue'},
                        );
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('View all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Show only the top 5
              ListView.separated(
                itemCount: visible.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => OverdueTile(invoice: visible[i]),
              ),
            ],
          ),
      ],
    );
  }
}

class OverdueTile extends StatelessWidget {
  const OverdueTile({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: theme.colorScheme.error..withValues(alpha: 0.15)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Due: ${fmt(invoice.dates.dueDate)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          AmountBadge(
              text: currency(
                  invoice.amounts.amountDue ?? invoice.amounts.total ?? 0)),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                TitledMaterialPageRoute(
                  title: 'Invoice Details',
                    builder: (_) => InvoiceDetailPage(invoice: invoice)),
              );
            },
            icon: const Icon(Icons.remove_red_eye, size: 16),
            label: const Text('View'),
          ),
        ],
      ),
    );
  }
}
