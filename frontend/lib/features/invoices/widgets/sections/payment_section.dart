import 'package:care_connect_app/features/invoices/services/invoice_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/invoice_models.dart';

/// Supported method keys stored in PaymentReferences.supportedMethods
const String kMethodCheck = 'check';
const String kMethodCard = 'credit_card';
const String kMethodOnline = 'online';
const String kMethodTelephone = 'telephone';

class PaymentSection extends StatelessWidget {
  const PaymentSection({
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
    final refs = value.paymentReferences;
    final methodsSet = refs.supportedMethods.toSet();
    final isPaid = value.paymentStatus == PaymentStatus.paid;

    // Flags for online card and QR behavior
    final hasQrDataPreferred = (refs.qrCodeUrl?.trim().isNotEmpty ??
        false); // use this first if present
    final hasPaymentLink =
        (refs.paymentLink?.trim().isNotEmpty ?? false); // fallback for QR
    final canOpenPaymentLink = _isHttpUrl(
      refs.paymentLink,
    ); // only show button for http(s)
    final showOnlineCard = methodsSet.contains(kMethodOnline) ||
        hasQrDataPreferred ||
        hasPaymentLink;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Payment Options', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        // Status + Record Payment
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButtonFormField<PaymentStatus>(
                  initialValue: value.paymentStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment Status',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  onChanged: isEditing
                      ? (s) => onChanged(value.copyWith(paymentStatus: s))
                      : null,
                  items: PaymentStatus.values
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e, child: Text(_label(e))),
                      )
                      .toList(),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.attach_money),
                  label: const Text('Record Payment'),
                  onPressed: isPaid
                      ? null
                      : () async {
                          final enabled = methodsSet.isNotEmpty
                              ? methodsSet
                              : {
                                  kMethodCheck,
                                  kMethodCard,
                                  kMethodOnline,
                                  kMethodTelephone,
                                };
                          final result = await showDialog<_PaymentEntry>(
                            context: context,
                            builder: (_) => _RecordPaymentDialog(
                              invoice: value,
                              supported: enabled,
                            ),
                          );
                          if (result != null) {
                            // Convert to a PaymentRecord for the API
                            final rec = PaymentRecord(
                              id: 'local-${DateTime.now().millisecondsSinceEpoch}',
                              confirmationNumber: result.confirmationNumber,
                              date: result.date,
                              methodKey: result.methodKey,
                              amountPaid: result.amountPaid,
                              planEnabled: result.planEnabled,
                              planDurationMonths: result.planDurationMonths,
                            );
                            final updated =
                                await InvoiceService.instance.recordPayment(
                              invoiceId: value.id,
                              record: rec,
                            );

                            if (updated != null) {
                              onChanged(updated);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Payment recorded'),
                                ),
                              );
                            } else {
                              // optimistic fallback if the API fails
                              final newList = [...?value.payments, rec];
                              final newAmounts = _applyPayment(value, result);
                              final dueLeft = (newAmounts.amountDue ??
                                      newAmounts.total ??
                                      0)
                                  .toDouble();
                              final newStatus = dueLeft <= 0
                                  ? PaymentStatus.paid
                                  : PaymentStatus.partialPayment;
                              onChanged(
                                value.copyWith(
                                  payments: newList,
                                  amounts: newAmounts,
                                  paymentStatus: newStatus,
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Payment recorded locally'),
                                ),
                              );
                            }
                          }
                        },
                ),
                Chip(
                  label: Text(_label(value.paymentStatus)),
                  backgroundColor: _statusColor(context, value.paymentStatus),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Supported methods editor
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supported Payment Methods',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in [
                      kMethodCheck,
                      kMethodCard,
                      kMethodOnline,
                      kMethodTelephone,
                    ])
                      FilterChip(
                        label: Text(_methodLabel(m)),
                        selected: methodsSet.contains(m),
                        onSelected: isEditing
                            ? (on) {
                                final next = {...methodsSet};
                                on ? next.add(m) : next.remove(m);
                                onChanged(
                                  value.copyWith(
                                    paymentReferences: refs.copyWith(
                                      supportedMethods: next.toList(),
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Online details, including QR display
        if (showOnlineCard)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Online Payment',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue: refs.paymentLink ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Payment Link (URL or deeplink)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: (v) => onChanged(
                      value.copyWith(
                        paymentReferences: refs.copyWith(paymentLink: v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue: refs.qrCodeUrl ?? '',
                    decoration: const InputDecoration(
                      labelText: 'QR Code Destination URL (encoded in QR)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: (v) => onChanged(
                      value.copyWith(
                        paymentReferences: refs.copyWith(qrCodeUrl: v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Prefer QR from qrCodeUrl; else QR from paymentLink
                  if (hasQrDataPreferred) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: refs.qrCodeUrl!.trim(),
                            version: QrVersions.auto,
                            size: 140,
                            gapless: true,
                            backgroundColor: Colors.white,
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Scan this QR code to open the destination URL.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (canOpenPaymentLink)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open Payment Page'),
                        onPressed: () => _openUrl(refs.paymentLink!.trim()),
                      ),
                  ] else if (hasPaymentLink) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: refs.qrCodeUrl!.trim(),
                            version: QrVersions.auto,
                            size: 140,
                            gapless: true,
                            backgroundColor: Colors.white,
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 10,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canOpenPaymentLink)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open Payment Page'),
                                  onPressed: () =>
                                      _openUrl(refs.paymentLink!.trim()),
                                ),
                              const SizedBox(height: 20),
                              Text(
                                canOpenPaymentLink
                                    ? 'Scan the QR or tap the button to open the payment page.'
                                    : 'Scan the QR to open the payment destination.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Telephone details
        if (methodsSet.contains(kMethodTelephone))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Telephone Payment',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue: refs.notes ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Phone Number or Instructions',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (v) => onChanged(
                      value.copyWith(
                        paymentReferences: refs.copyWith(notes: v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // General notes for payer
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes for Payer',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  enabled: isEditing,
                  initialValue: refs.notes ?? '',
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (appears on statement or instructions)',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  onChanged: (v) => onChanged(
                    value.copyWith(paymentReferences: refs.copyWith(notes: v)),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Check details, only when check is an accepted method
        if (methodsSet.contains(kMethodCheck))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Check Payment Instructions',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue: value.checkPayableTo?.name ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Payable To',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: (v) {
                      final dst = (value.checkPayableTo ??
                              CheckPayableTo(
                                name: '',
                                address: '',
                                reference: value.invoiceNumber,
                              ))
                          .copyWith(name: v);
                      onChanged(value.copyWith(checkPayableTo: dst));
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue: value.checkPayableTo?.address ?? '',
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Mailing Address',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: (v) {
                      final dst = (value.checkPayableTo ??
                              CheckPayableTo(
                                name: '',
                                address: '',
                                reference: value.invoiceNumber,
                              ))
                          .copyWith(address: v);
                      onChanged(value.copyWith(checkPayableTo: dst));
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: isEditing,
                    initialValue:
                        value.checkPayableTo?.reference ?? value.invoiceNumber,
                    decoration: const InputDecoration(
                      labelText: 'Reference (include invoice number)',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onChanged: (v) {
                      final dst = (value.checkPayableTo ??
                              CheckPayableTo(
                                name: '',
                                address: '',
                                reference: value.invoiceNumber,
                              ))
                          .copyWith(reference: v);
                      onChanged(value.copyWith(checkPayableTo: dst));
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Amounts _applyPayment(Invoice inv, _PaymentEntry entry) {
    final a = inv.amounts;
    final double due = (a.amountDue ?? a.total ?? 0).toDouble();
    final double paid = entry.amountPaid.clamp(0, double.infinity).toDouble();
    final double newDue = (due - paid).clamp(0, double.infinity).toDouble();
    final double newTotal = (a.total ?? due).toDouble();
    return a.copyWith(amountDue: newDue, total: newTotal);
  }

  static Color _statusColor(BuildContext context, PaymentStatus s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case PaymentStatus.paid:
        return const Color(0xFF059669);
      case PaymentStatus.rejectedInsurance:
        return cs.error;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.pendingInsurance:
      case PaymentStatus.pending:
      case PaymentStatus.partialPayment:
      case PaymentStatus.sent:
        return cs.secondary;
    }
  }

  static String _label(PaymentStatus s) {
    switch (s) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.overdue:
        return 'Overdue';
      case PaymentStatus.pendingInsurance:
        return 'Pending Insurance';
      case PaymentStatus.sent:
        return 'Sent';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.partialPayment:
        return 'Partial Payment';
      case PaymentStatus.rejectedInsurance:
        return 'Rejected by Insurance';
    }
  }

  static String _methodLabel(String key) {
    switch (key) {
      case kMethodCheck:
        return 'Check';
      case kMethodCard:
        return 'Credit Card';
      case kMethodOnline:
        return 'Online Payment';
      case kMethodTelephone:
        return 'Telephone';
      default:
        return key;
    }
  }

  static bool _isHttpUrl(String? s) {
    if (s == null) return false;
    final t = s.trim();
    if (t.isEmpty) return false;
    final uri = Uri.tryParse(t);
    return uri != null; // && (uri.isScheme('http') || uri.isScheme('https'));
  }

  static Future<void> _openUrl(String url) async {
    final link = url.trim();
    final normalized = link.startsWith('http') ? link : 'https://$link';
    if (await canLaunchUrlString(normalized)) {
      await launchUrlString(normalized, mode: LaunchMode.externalApplication);
    }
  }
}

/* ------------ Record Payment Dialog ------------- */

class _PaymentEntry {
  _PaymentEntry({
    required this.confirmationNumber,
    required this.date,
    required this.methodKey,
    required this.amountPaid,
    this.planEnabled = false,
    this.planDurationMonths,
  });

  final String confirmationNumber;
  final DateTime date;
  final String methodKey;
  final double amountPaid;
  final bool planEnabled;
  final int? planDurationMonths;
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.invoice, required this.supported});

  final Invoice invoice;
  final Set<String> supported;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _confCtrl;
  late final TextEditingController _amountCtrl;
  DateTime? _date;
  String? _methodKey;
  bool _full = true;
  bool _plan = false;
  int _months = 6;

  @override
  void initState() {
    super.initState();
    _confCtrl = TextEditingController(
      text: 'PAY-${DateTime.now().millisecondsSinceEpoch % 1000000}',
    );
    final due =
        (widget.invoice.amounts.amountDue ?? widget.invoice.amounts.total ?? 0)
            .toDouble();
    _amountCtrl = TextEditingController(text: due.toStringAsFixed(2));
    _date = DateTime.now();
    _methodKey = widget.supported.isNotEmpty ? widget.supported.first : null;
  }

  @override
  void dispose() {
    _confCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due =
        (widget.invoice.amounts.amountDue ?? widget.invoice.amounts.total ?? 0)
            .toDouble();

    return AlertDialog(
      title: const Text('Record Payment'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _confCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Confirmation Number',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Payment Date',
                    value: _date,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _methodKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              items: widget.supported
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(_methodLabel(k)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _methodKey = v),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _full,
              onChanged: (v) {
                setState(() {
                  _full = v ?? false;
                  if (_full) _amountCtrl.text = due.toStringAsFixed(2);
                });
              },
              dense: true,
              title: Text('Payment in full (\$${due.toStringAsFixed(2)})'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            TextFormField(
              controller: _amountCtrl,
              enabled: !_full,
              decoration: const InputDecoration(
                labelText: 'Partial Payment Amount',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _plan,
              onChanged: (v) => setState(() => _plan = (v ?? false)),
              dense: true,
              title: const Text('Set up payment plan for remaining balance'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_plan)
              DropdownButtonFormField<int>(
                initialValue: _months,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Payment Plan Frequency',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                items: const [1, 3, 6, 9, 12, 24, 36]
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m, child: Text('$m months')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _months = v ?? 6),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: (_methodKey != null && _date != null)
              ? () {
                  final paid = double.tryParse(_amountCtrl.text) ?? 0;
                  final entry = _PaymentEntry(
                    confirmationNumber: _confCtrl.text.trim(),
                    date: _date!,
                    methodKey: _methodKey!,
                    amountPaid: _full ? due : paid,
                    planEnabled: _plan,
                    planDurationMonths: _plan ? _months : null,
                  );
                  Navigator.of(context).pop(entry);
                }
              : null,
          child: const Text('Record Payment'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  static String _methodLabel(String key) {
    switch (key) {
      case kMethodCheck:
        return 'Check';
      case kMethodCard:
        return 'Credit Card';
      case kMethodOnline:
        return 'Online Payment';
      case kMethodTelephone:
        return 'Telephone';
      default:
        return key;
    }
  }
}

/* Simple inline date field to keep this file self-contained */
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(
      text: value == null ? '' : _fmt(value!),
    );
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: const Icon(Icons.calendar_today),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 3),
          initialDate: value ?? now,
        );
        onChanged(picked);
      },
    );
  }

  static String _fmt(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$m/$day/${d.year}';
  }
}

/* ----------------- copyWith helpers for your models ------------------ */

extension PaymentReferencesCopy on PaymentReferences {
  PaymentReferences copyWith({
    String? paymentLink,
    String? qrCodeUrl,
    String? notes,
    List<String>? supportedMethods,
  }) {
    return PaymentReferences(
      paymentLink: paymentLink ?? this.paymentLink,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      notes: notes ?? this.notes,
      supportedMethods: supportedMethods ?? this.supportedMethods.toList(),
    );
  }
}

extension CheckPayableToCopy on CheckPayableTo {
  CheckPayableTo copyWith({String? name, String? address, String? reference}) {
    return CheckPayableTo(
      name: name ?? this.name,
      address: address ?? this.address,
      reference: reference ?? this.reference,
    );
  }
}

extension AmountsCopy on Amounts {
  Amounts copyWith({
    double? totalCharges,
    double? totalAdjustments,
    double? total,
    double? amountDue,
  }) {
    return Amounts(
      totalCharges: totalCharges ?? this.totalCharges,
      totalAdjustments: totalAdjustments ?? this.totalAdjustments,
      total: total ?? this.total,
      amountDue: amountDue ?? this.amountDue,
    );
  }
}
