import 'package:care_connect_app/widgets/page_title.dart';
// invoice_list_page.dart
import 'package:care_connect_app/features/invoices/models/filter_result.dart';
import 'package:care_connect_app/features/invoices/services/invoice_service.dart';
import 'package:care_connect_app/features/invoices/widgets/search_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'invoice_detail_page.dart';

import 'package:care_connect_app/features/invoices/services/excel/excel_service.dart';

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key, this.quickFilter});
  final String? quickFilter; // 'all' | 'pending' | 'overdue' | 'rejected'

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  List<Invoice> _invoices = [];
  bool _loading = true;

  String _searchQuery = '';
  String _sort = 'recently_added';
  Set<PaymentStatus> _statusFilter = {};
  String? _providerFilter;
  String? _patientFilter;
  DateTimeRange? _statementRange;
  DateTimeRange? _dueRange;
  RangeValues? _amountRange;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);

    final results = await InvoiceService.instance.fetchInvoices(
      search: _searchQuery,
      status: _statusFilter,
      providerName: _providerFilter,
      patientName: _patientFilter,
      dueRange: _dueRange,
      amountRange: _amountRange,
      sort: _mapSort(_sort),
    );

    // apply quick filter locally
    List<Invoice> filtered = results;
    final now = DateTime.now();
    switch (widget.quickFilter) {
      case 'pending':
        filtered = filtered
            .where((i) => i.paymentStatus == PaymentStatus.pending)
            .toList();
        break;
      case 'rejected':
        filtered = filtered
            .where((i) => i.paymentStatus == PaymentStatus.rejectedInsurance)
            .toList();
        break;
      case 'overdue':
        filtered = filtered.where((i) {
          final due = i.dates.dueDate;
          return i.paymentStatus != PaymentStatus.paid && due.isBefore(now);
        }).toList();
        break;
      default:
        break;
    }

    setState(() {
      _invoices = filtered;
      _loading = false;
    });
  }

  // Map UI sort -> service sort. (Returns null for default.)
  String? _mapSort(String uiSort) {
    switch (uiSort) {
      case 'service_date_desc':
        return 'service_desc';
      case 'service_date_asc':
        return 'service_asc';
      case 'due_date_desc':
        return 'due_desc';
      case 'due_date_asc':
        return 'due_asc';
      case 'amount_desc':
        return 'amount_desc';
      case 'amount_asc':
        return 'amount_asc';
      case 'recently_added':
      default:
        return null;
    }
  }

  Future<void> _openSearchSheet() async {
    final cfg = await showSearchFilterSheet(
      context: context,
      invoices: _invoices,
      initialSort: _sort,
      initialSearch: _searchQuery,
      initialStatus: _statusFilter,
      initialProvider: _providerFilter,
      initialPatient: _patientFilter,
      initialServiceRange: _statementRange,
      initialDueRange: _dueRange,
      initialAmountRange: _amountRange,
    );

    if (cfg != null) {
      setState(() {
        _sort = cfg.sort;
        _searchQuery = cfg.search;
        _statusFilter = cfg.status;
        _providerFilter = cfg.provider;
        _patientFilter = cfg.patient;
        _statementRange = cfg.serviceRange;
        _dueRange = cfg.dueRange;
        _amountRange = cfg.amountRange;
      });
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _invoices.fold<double>(
      0,
      (sum, i) => sum + (i.amounts.amountDue ?? i.amounts.total ?? 0),
    );

    final pendingCount =
        _invoices.where((i) => i.paymentStatus == PaymentStatus.pending).length;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top filter bar like the mock
                _FilterBar(
                  sort: _sort,
                  onChangeSort: (v) {
                    setState(() => _sort = v);
                    _fetch();
                  },
                  onOpenSearchSheet: _openSearchSheet,
                ),

                // Results header card styled like the mock
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.description, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text(
                                    'Invoice Results',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  if (_invoices.isNotEmpty)
                                    Chip(
                                      label: Text('${_invoices.length} found'),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Amount: \$${total.toStringAsFixed(2)}'
                                '${pendingCount > 0 ? ' • $pendingCount pending' : ''}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Export'),
                          onPressed: () {
                            // THIS IS THE UPDATED CODE
                            ExcelService.instance
                                .exportInvoices(_invoices, context);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Desktop or mobile layouts
                LayoutBuilder(
                  builder: (context, c) {
                    final isWide = c.maxWidth >= 720;
                    if (isWide) {
                      return DesktopTable(
                        invoices: _invoices,
                        onView: _openDetail,
                        onPay: _openDetailPaymentTab,
                      );
                    }
                    return Column(
                      children: _invoices
                          .map(
                            (i) => MobileCard(
                              invoice: i,
                              onView: () => _openDetail(i),
                              onPay: () => _openDetailPaymentTab(i),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }

  void _openDetail(Invoice invoice) async {
    // Push onto the app-level (root) navigator
    final updated =
        await Navigator.of(context, rootNavigator: true).push<Invoice>(
      TitledMaterialPageRoute(
        title: 'Invoice Details',
        builder: (_) => InvoiceDetailPage(invoice: invoice)),
    );
    if (updated != null) {
      await InvoiceService.instance.upsert(updated);
      _fetch();
    }
  }

  void _openDetailPaymentTab(Invoice invoice) {
    // Same idea, but start on the Payment tab
    Navigator.of(context, rootNavigator: true).push(
      TitledMaterialPageRoute(
        title: 'Invoice Details',
        builder: (_) => InvoiceDetailPage(
          invoice: invoice,
          initialTabIndex: 2,
        ),
      ),
    );
  }
}

/// Compact, Material 3 styled filter bar that matches the mock:
/// left is the sort dropdown, right is a compact search button.
/// Stacks on small screens to avoid overflow and give the search more room.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sort,
    required this.onChangeSort,
    required this.onOpenSearchSheet,
  });

  final String sort;
  final ValueChanged<String> onChangeSort;
  final VoidCallback onOpenSearchSheet;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 520;

            final sortField = DropdownButtonFormField<String>(
              initialValue: sort,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sort By'),
              items: const [
                DropdownMenuItem(
                    value: 'recently_added', child: Text('Recently Added')),
                DropdownMenuItem(
                    value: 'service_date_desc',
                    child: Text('Service Date (Newest)')),
                DropdownMenuItem(
                    value: 'service_date_asc',
                    child: Text('Service Date (Oldest)')),
                DropdownMenuItem(
                    value: 'due_date_desc', child: Text('Due Date (Latest)')),
                DropdownMenuItem(
                    value: 'due_date_asc', child: Text('Due Date (Earliest)')),
                DropdownMenuItem(
                    value: 'amount_desc', child: Text('Amount (High to Low)')),
                DropdownMenuItem(
                    value: 'amount_asc', child: Text('Amount (Low to High)')),
              ],
              onChanged: (v) => onChangeSort(v ?? 'recently_added'),
            );

            final searchBtn = IconButton.filledTonal(
              tooltip: 'Search & Filter',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onOpenSearchSheet,
              icon: const Icon(Icons.search),
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sortField,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: searchBtn),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: sortField),
                const SizedBox(width: 12),
                searchBtn,
              ],
            );
          },
        ),
      ),
    );
  }
}
