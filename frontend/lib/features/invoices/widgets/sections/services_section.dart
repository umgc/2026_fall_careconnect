// sections/services_section.dart
import 'package:flutter/material.dart';
import '../components/key_value_row.dart';
import '../../models/invoice_models.dart';

class ServicesSection extends StatelessWidget {
  const ServicesSection({
    super.key,
    required this.value,
    required this.isEditing,
    required this.onChanged,
  });

  final Invoice value;
  final bool isEditing;
  final ValueChanged<Invoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = value.services;
    final a = value.amounts;
    String money(double? v) => v == null ? '-' : '\$${v.toStringAsFixed(2)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Services & Charges',
                style: Theme.of(context).textTheme.titleMedium,
                softWrap: true,
              ),
            ),
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Service',
                onPressed: () async {
                  final newLine =
                      await _showEditDialog(context, const ServiceLine());
                  if (newLine != null) {
                    final updated = [...s, newLine];
                    _applyServices(updated);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 8),

        // List of services with swipe-to-delete when editing
        ...List.generate(s.length, (index) {
          final line = s[index];

          Widget tile = Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with title and actions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          line.description ?? 'Service',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          softWrap: true,
                        ),
                      ),
                      if (isEditing) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final edited = await _showEditDialog(context, line);
                            if (edited != null) {
                              final updated =
                                  List<ServiceLine>.from(value.services);
                              final at = updated.indexOf(line);
                              if (at >= 0) {
                                updated[at] = edited;
                                _applyServices(updated);
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Delete',
                          onPressed: () async {
                            final ok = await _confirmDelete(context);
                            if (ok) _removeLine(line);
                          },
                        ),
                      ],
                    ],
                  ),

                  Text(
                    'Service Code: ${line.serviceCode ?? '-'}',
                    style: Theme.of(context).textTheme.bodySmall,
                    softWrap: true,
                  ),
                  if (line.serviceDate != null)
                    Text(
                      'Service Date: ${_fmt(line.serviceDate!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      softWrap: true,
                    ),

                  const SizedBox(height: 8),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: KeyValueRow(
                          'Total Charge',
                          money(line.charge),
                          allowWrap: true,
                        ),
                      ),
                      if (line.insuranceAdjustments != null)
                        const SizedBox(width: 12),
                      if (line.insuranceAdjustments != null)
                        Expanded(
                          child: KeyValueRow(
                            'Insurance Paid',
                            money(line.insuranceAdjustments),
                            success: true,
                            allowWrap: true,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );

          if (!isEditing) return tile;

          // Wrap with Dismissible only in editing mode
          return Dismissible(
            key: ValueKey<Object>(line.hashCode ^ index),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(context),
            onDismissed: (_) => _removeLine(line),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red.withOpacity(0.12),
              child: const Icon(Icons.delete, color: Colors.red),
            ),
            child: tile,
          );
        }),

        const SizedBox(height: 8),

        // Totals
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                        child: Text('Total Charges', softWrap: true)),
                    Expanded(
                      child: Text(
                        money(a.totalCharges),
                        softWrap: true,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                if ((a.totalAdjustments ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                          child: Text('Insurance Adjustments', softWrap: true)),
                      Expanded(
                        child: Text(
                          '-${money(a.totalAdjustments)}',
                          softWrap: true,
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Color(0xFF059669)),
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Total Due',
                        softWrap: true,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        money(a.total ?? a.amountDue),
                        softWrap: true,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Recalculate amounts and push a new Invoice via onChanged
  void _applyServices(List<ServiceLine> updated) {
    final totals = _recomputeAmounts(updated);
    onChanged(
      value.copyWith(
        services: updated,
        amounts: totals,
      ),
    );
  }

  void _removeLine(ServiceLine line) {
    final updated = List<ServiceLine>.from(value.services)..remove(line);
    _applyServices(updated);
  }

  Amounts _recomputeAmounts(List<ServiceLine> lines) {
    double sumCharges = 0;
    double sumInsurance = 0;
    for (final l in lines) {
      sumCharges += l.charge ?? 0;
      sumInsurance += l.insuranceAdjustments ?? 0;
    }
    final due = sumCharges - sumInsurance;
    return Amounts(
      totalCharges: sumCharges,
      totalAdjustments: sumInsurance,
      total: due,
      amountDue: due,
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove service'),
        content:
            const Text('Are you sure you want to delete this service line?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    return res ?? false;
  }

  String _fmt(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<ServiceLine?> _showEditDialog(
      BuildContext context, ServiceLine line) async {
    final descCtrl = TextEditingController(text: line.description);
    final codeCtrl = TextEditingController(text: line.serviceCode);
    final chargeCtrl =
        TextEditingController(text: line.charge?.toStringAsFixed(2));
    final insCtrl = TextEditingController(
        text: line.insuranceAdjustments?.toStringAsFixed(2));

    final fnDesc = FocusNode();
    final fnCode = FocusNode();
    final fnCharge = FocusNode();
    final fnIns = FocusNode();

    return showDialog<ServiceLine>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Service'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: descCtrl,
                  focusNode: fnDesc,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnCode),
                  decoration: _fieldDecoration(ctx, 'Description'),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  focusNode: fnCode,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnCharge),
                  decoration: _fieldDecoration(ctx, 'Service Code'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: chargeCtrl,
                  focusNode: fnCharge,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnIns),
                  decoration: _fieldDecoration(ctx, 'Charge'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: insCtrl,
                  focusNode: fnIns,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: _fieldDecoration(ctx, 'Insurance Paid'),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                ctx,
                line.copyWith(
                  description: descCtrl.text.trim(),
                  serviceCode: codeCtrl.text.trim(),
                  charge: double.tryParse(chargeCtrl.text.trim()),
                  insuranceAdjustments: double.tryParse(insCtrl.text.trim()),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
