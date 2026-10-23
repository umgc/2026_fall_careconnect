import 'package:care_connect_app/features/invoices/models/filter_result.dart';
import 'package:flutter/material.dart';
import '../models/invoice_models.dart';

class SearchFilterSheetContent extends StatefulWidget {
  const SearchFilterSheetContent({
    super.key,
    required this.invoices,
    required this.initialSort,
    required this.initialSearch,
    required this.initialStatus,
    this.initialProvider,
    this.initialPatient,
    this.initialServiceRange,
    this.initialDueRange,
    this.initialAmountRange,
    required this.onSubmit,
  });

  final List<Invoice> invoices;
  final String initialSort;
  final String initialSearch;
  final Set<PaymentStatus> initialStatus;
  final String? initialProvider;
  final String? initialPatient;
  final DateTimeRange? initialServiceRange;
  final DateTimeRange? initialDueRange;
  final RangeValues? initialAmountRange;
  final void Function(FilterResult) onSubmit;

  @override
  State<SearchFilterSheetContent> createState() =>
      _SearchFilterSheetContentState();
}

class _SearchFilterSheetContentState extends State<SearchFilterSheetContent> {
  late String sort;
  late String search;
  late Set<PaymentStatus> status;
  String? provider;
  String? patient;
  DateTimeRange? serviceRange;
  DateTimeRange? dueRange;
  RangeValues amountRange = const RangeValues(0, 2000);

  @override
  void initState() {
    super.initState();
    sort = widget.initialSort;
    search = widget.initialSearch;
    status = {...widget.initialStatus};
    provider = widget.initialProvider;
    patient = widget.initialPatient;
    serviceRange = widget.initialServiceRange;
    dueRange = widget.initialDueRange;
    amountRange = widget.initialAmountRange ?? const RangeValues(0, 2000);
  }

  @override
  Widget build(BuildContext context) {
    final providers =
        widget.invoices.map((e) => e.provider.name).toSet().toList()..sort();
    final patients = widget.invoices.map((e) => e.patient.name).toSet().toList()
      ..sort();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Search & Filter Invoices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 8),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  children: [
                    // Sort and Search (responsive)
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked =
                            constraints.maxWidth < 480; // stack on phones

                        final sortField = DropdownButtonFormField<String>(
                          initialValue: sort,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Sort by'),
                          items: const [
                            DropdownMenuItem(
                                value: 'recently_added',
                                child: Text('Recently Added')),
                            DropdownMenuItem(
                                value: 'service_date_desc',
                                child: Text('Service Date (Newest)')),
                            DropdownMenuItem(
                                value: 'service_date_asc',
                                child: Text('Service Date (Oldest)')),
                            DropdownMenuItem(
                                value: 'due_date_desc',
                                child: Text('Due Date (Latest)')),
                            DropdownMenuItem(
                                value: 'due_date_asc',
                                child: Text('Due Date (Earliest)')),
                            DropdownMenuItem(
                                value: 'amount_desc',
                                child: Text('Amount (High to Low)')),
                            DropdownMenuItem(
                                value: 'amount_asc',
                                child: Text('Amount (Low to High)')),
                          ],
                          onChanged: (v) =>
                              setState(() => sort = v ?? 'recently_added'),
                        );

                        final searchField = TextFormField(
                          initialValue: search,
                          decoration: const InputDecoration(
                            labelText: 'Search',
                            prefixIcon: Icon(Icons.search),
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => search = v),
                        );

                        if (stacked) {
                          return Column(
                            children: [
                              sortField,
                              const SizedBox(height: 12),
                              searchField,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: sortField),
                            const SizedBox(width: 12),
                            Expanded(child: searchField),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Status
                    _Section(
                      title: 'Payment Status',
                      child: Wrap(
                        spacing: 8,
                        children: PaymentStatus.values.map((s) {
                          final selected = status.contains(s);
                          return FilterChip(
                            label: Text(_label(s)),
                            selected: selected,
                            onSelected: (on) => setState(() {
                              if (on) {
                                status.add(s);
                              } else {
                                status.remove(s);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),

                    // Provider & Patient
                    _Section(
                      title: 'Provider & Patient',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: provider,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Provider'),
                            items: providers
                                .map((p) =>
                                    DropdownMenuItem(value: p, child: Text(p)))
                                .toList(),
                            onChanged: (v) => setState(() => provider = v),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: patient,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Patient'),
                            items: patients
                                .map((p) =>
                                    DropdownMenuItem(value: p, child: Text(p)))
                                .toList(),
                            onChanged: (v) => setState(() => patient = v),
                          ),
                        ],
                      ),
                    ),

                    // Dates
                    _Section(
                      title: 'Date Range',
                      child: Column(
                        children: [
                          _RangePickerRow(
                            label: 'Service Date',
                            current: serviceRange,
                            onPick: (r) => setState(() => serviceRange = r),
                          ),
                          const SizedBox(height: 8),
                          _RangePickerRow(
                            label: 'Due Date',
                            current: dueRange,
                            onPick: (r) => setState(() => dueRange = r),
                          ),
                        ],
                      ),
                    ),

                    // Amount
                    _Section(
                      title: 'Amount Range',
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('\$${amountRange.start.round()}'),
                              Text('\$${amountRange.end.round()}'),
                            ],
                          ),
                          RangeSlider(
                            values: amountRange,
                            min: 0,
                            max: 5000,
                            divisions: 100,
                            onChanged: (v) => setState(() => amountRange = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Pinned action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Clear All Filters'),
                    onPressed: () => setState(() {
                      sort = 'recently_added';
                      search = '';
                      status.clear();
                      provider = null;
                      patient = null;
                      serviceRange = null;
                      dueRange = null;
                      amountRange = const RangeValues(0, 2000);
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Apply'),
                    onPressed: () {
                      widget.onSubmit(
                        FilterResult(
                          sort: sort,
                          search: search,
                          status: status,
                          provider: provider,
                          patient: patient,
                          serviceRange: serviceRange,
                          dueRange: dueRange,
                          amountRange: amountRange,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _label(PaymentStatus s) {
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
        return 'Rejected Insurance';
      case PaymentStatus.overdue:
        return 'Overdue';
      case PaymentStatus.pendingInsurance:
        return 'Pending Insurance';
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}

class _RangePickerRow extends StatelessWidget {
  const _RangePickerRow(
      {required this.label, required this.current, required this.onPick});
  final String label;
  final DateTimeRange? current;
  final void Function(DateTimeRange?) onPick;

  @override
  Widget build(BuildContext context) {
    String fmt(DateTime d) => d.toIso8601String().split('T').first;
    return Row(children: [
      Expanded(
        child: TextFormField(
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: current == null
                ? 'Select range'
                : '${fmt(current!.start)} to ${fmt(current!.end)}',
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 3),
              lastDate: DateTime(now.year + 3),
              initialDateRange: current,
            );
            onPick(picked);
          },
        ),
      ),
    ]);
  }
}

// --- Wrapper and helper for easier use from InvoiceListPage ---
class SearchFilterSheet extends StatelessWidget {
  const SearchFilterSheet({
    super.key,
    required this.invoices,
    required this.initialSort,
    required this.initialSearch,
    required this.initialStatus,
    this.initialProvider,
    this.initialPatient,
    this.initialServiceRange,
    this.initialDueRange,
    this.initialAmountRange,
  });

  final List<Invoice> invoices;
  final String initialSort;
  final String initialSearch;
  final Set<PaymentStatus> initialStatus;
  final String? initialProvider;
  final String? initialPatient;
  final DateTimeRange? initialServiceRange;
  final DateTimeRange? initialDueRange;
  final RangeValues? initialAmountRange;

  @override
  Widget build(BuildContext context) {
    return SearchFilterSheetContent(
      invoices: invoices,
      initialSort: initialSort,
      initialSearch: initialSearch,
      initialStatus: initialStatus,
      initialProvider: initialProvider,
      initialPatient: initialPatient,
      initialServiceRange: initialServiceRange,
      initialDueRange: initialDueRange,
      initialAmountRange: initialAmountRange,
      onSubmit: (res) => Navigator.pop(context, res),
    );
  }
}

Future<FilterResult?> showSearchFilterSheet({
  required BuildContext context,
  required List<Invoice> invoices,
  required String initialSort,
  required String initialSearch,
  required Set<PaymentStatus> initialStatus,
  String? initialProvider,
  String? initialPatient,
  DateTimeRange? initialServiceRange,
  DateTimeRange? initialDueRange,
  RangeValues? initialAmountRange,
}) {
  return showModalBottomSheet<FilterResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SearchFilterSheet(
      invoices: invoices,
      initialSort: initialSort,
      initialSearch: initialSearch,
      initialStatus: initialStatus,
      initialProvider: initialProvider,
      initialPatient: initialPatient,
      initialServiceRange: initialServiceRange,
      initialDueRange: initialDueRange,
      initialAmountRange: initialAmountRange,
    ),
  );
}
