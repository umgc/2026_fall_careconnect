import 'package:flutter/material.dart';
import 'invoice_models.dart';

class FilterResult {
  final String sort;
  final String search;
  final Set<PaymentStatus> status;
  final String? provider;
  final String? patient;
  final DateTimeRange? serviceRange;
  final DateTimeRange? dueRange;
  final RangeValues? amountRange;

  const FilterResult({
    required this.sort,
    required this.search,
    required this.status,
    this.provider,
    this.patient,
    this.serviceRange,
    this.dueRange,
    this.amountRange,
  });
}

class DesktopTable extends StatelessWidget {
  final List<Invoice> invoices;
  final void Function(Invoice) onView;
  final void Function(Invoice) onPay;

  const DesktopTable({
    super.key,
    required this.invoices,
    required this.onView,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Invoice #')),
        DataColumn(label: Text('Provider')),
        DataColumn(label: Text('Patient')),
        DataColumn(label: Text('Amount')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Actions')),
      ],
      rows: invoices.map((i) {
        return DataRow(cells: [
          DataCell(Text(i.invoiceNumber)),
          DataCell(Text(i.provider.name)),
          DataCell(Text(i.patient.name)),
          DataCell(Text('\$${i.amounts.amountDue?.toStringAsFixed(2) ?? "-"}')),
          DataCell(Text(i.paymentStatus.name)),
          DataCell(Row(
            children: [
              IconButton(
                icon: const Icon(Icons.visibility),
                onPressed: () => onView(i),
              ),
              IconButton(
                icon: const Icon(Icons.payment),
                onPressed: () => onPay(i),
              ),
            ],
          )),
        ]);
      }).toList(),
    );
  }
}

class MobileCard extends StatelessWidget {
  const MobileCard({
    super.key,
    required this.invoice,
    required this.onView,
    required this.onPay,
    this.onPdf,
    this.onInsurance,
    this.onLinks,
  });

  final Invoice invoice;
  final VoidCallback onView;
  final VoidCallback onPay;
  final VoidCallback? onPdf;
  final VoidCallback? onInsurance;
  final VoidCallback? onLinks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOverdue = invoice.paymentStatus != PaymentStatus.paid &&
        invoice.dates.dueDate.isBefore(DateTime.now());
    final isRejected = invoice.paymentStatus == PaymentStatus.rejectedInsurance;

    final bg = switch (true) {
      _ when isRejected => cs.error.withOpacity(0.06),
      _ when isOverdue => cs.error.withOpacity(0.04),
      _ => cs.surface,
    };

    final amount = invoice.amounts.amountDue ?? invoice.amounts.total ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Title row: number, status pill(s), amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        invoice.id, // e.g., PT-2025-027
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (isOverdue)
                        _pill(context, 'Overdue',
                            bg: Colors.red.shade100, fg: Colors.red.shade800),
                      if (isRejected)
                        _pill(context, 'Rejected',
                            bg: cs.errorContainer, fg: cs.onErrorContainer),
                      // Secondary line under number
                      SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            invoice.provider.name, // adjust if needed
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(amount),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    _statusChip(context, invoice.paymentStatus),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Details grid (2 columns)
            _DetailsGrid(
              rows: [
                _kv(
                  'Patient',
                  invoice.patient.name, // adjust if needed
                  strong: true,
                ),
                _kv(
                  'Due Date',
                  _date(invoice.dates.dueDate),
                  color: isOverdue ? Colors.red.shade700 : null,
                  strong: isOverdue,
                ),
                _kv('Statement Date', _date(invoice.dates.statementDate)),
                _kv('Services',
                    '${invoice.services.length} ${invoice.services.length == 1 ? 'item' : 'items'}'),
                _kv('Provider Phone', invoice.provider.phone),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 16),

            // Actions
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onInsurance != null)
                    OutlinedButton(
                      onPressed: onInsurance,
                      child: const Text('Insurance'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('View'),
                  ),
                  if (onPdf != null)
                    IconButton.outlined(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      tooltip: 'PDF',
                    ),
                  if (onLinks != null)
                    IconButton.outlined(
                      onPressed: onLinks,
                      icon: const Icon(Icons.link_outlined),
                      tooltip: 'Links',
                    ),
                  FilledButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.attach_money),
                    label: const Text('Pay'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helpers

  static String _money(num v) => '\$${v.toStringAsFixed(2)}';

  static String _date(DateTime d) {
    // Format MM/DD/YYYY; replace with intl if you prefer
    return '${d.month}/${d.day}/${d.year}';
  }

  static Widget _pill(BuildContext context, String text,
      {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  static Widget _statusChip(BuildContext context, PaymentStatus s) {
    final cs = Theme.of(context).colorScheme;
    late Color bg;
    late Color fg;

    switch (s) {
      case PaymentStatus.paid:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case PaymentStatus.pending:
      case PaymentStatus.pendingInsurance:
        bg = Colors.amber.shade100;
        fg = Colors.brown.shade800;
        break;
      case PaymentStatus.overdue:
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        break;
      case PaymentStatus.rejectedInsurance:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case PaymentStatus.sent:
      case PaymentStatus.partialPayment:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        break;
    }

    return Chip(
      label: Text(_label(s)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  static String _label(PaymentStatus s) {
    switch (s) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.sent:
        return 'Sent';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.partialPayment:
        return 'Partial';
      case PaymentStatus.rejectedInsurance:
        return 'Rejected';
      case PaymentStatus.overdue:
        return 'Overdue';
      case PaymentStatus.pendingInsurance:
        return 'Pending Insurance';
    }
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.rows});

  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 380;
    final colCount = isNarrow ? 1 : 2;

    return LayoutBuilder(
      builder: (context, c) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colCount,
            mainAxisExtent: 48,
            crossAxisSpacing: 12,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (_, i) => rows[i],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value,
      {this.color, this.strong = false, this.icon});

  final String label;
  final String value;
  final Color? color;
  final bool strong;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: strong
                    ? Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: color)
                    : Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

_DetailRow _kv(String label, String value,
    {Color? color, bool strong = false, IconData? icon}) {
  return _DetailRow(label, value, color: color, strong: strong, icon: icon);
}
