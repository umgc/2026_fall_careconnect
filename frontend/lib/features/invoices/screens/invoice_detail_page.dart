import 'package:care_connect_app/features/invoices/services/pdf/invoice_file_service.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/toolbar/invoice_toolbar.dart';
import 'package:care_connect_app/features/invoices/widgets/components/prev_next_bar.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/details_section.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/services_section.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/payment_section.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/ai_section.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/history_section.dart';
import 'package:care_connect_app/features/invoices/services/invoice_service.dart';

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({
    super.key,
    required this.invoice,
    this.initialTabIndex = 0,
    this.isNew = false,
  });

  final Invoice invoice;
  final int initialTabIndex;
  final bool isNew;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage>
    with TickerProviderStateMixin {
  late Invoice _edited;
  late TabController _tab;
  bool _editing = false;
  bool _busy = false;

  bool get _showAiTab => (_edited.aiSummary?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _edited = widget.invoice;
    _editing = widget.isNew;

    final tabsLen = _buildTabs(widget.isNew).length;
    final safeIndex = widget.initialTabIndex.clamp(0, tabsLen - 1);
    _tab = TabController(length: tabsLen, vsync: this, initialIndex: safeIndex)
      ..addListener(() => setState(() {}));
  }

  // If _edited changes such that the number of tabs should change,
  // rebuild the TabController to match the new length while preserving index.
  void _ensureTabControllerSynced() {
    final needed = _buildTabs(widget.isNew).length;
    if (needed != _tab.length) {
      final newIndex = _tab.index.clamp(0, needed - 1);
      _tab.dispose();
      _tab = TabController(length: needed, vsync: this, initialIndex: newIndex)
        ..addListener(() => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureTabControllerSynced();

    final cs = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;
    final isNew = widget.isNew;
    final hasNumber = _edited.invoiceNumber.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
                isNew && !hasNumber
                    ? 'New Invoice'
                    : 'Invoice ${_edited.invoiceNumber}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            const SizedBox(width: 8),
            if (!isNew || hasNumber)
              _statusIcon(_edited.paymentStatus, context),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              IgnorePointer(
                ignoring: _busy,
                child: InvoiceToolbar(
                  isEditing: _editing,
                  isNew: isNew,
                  showPdf: !isNew,
                  onEdit: () => setState(() => _editing = true),
                  onCancel: _cancel,
                  onSave: _save,
                  onPdf: () {
                    final link = _edited.documentLink;
                    if (link != null && link.isNotEmpty) {
                      InvoiceFileService.openInvoicePdf(link);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'PDF is not available for this invoice yet')),
                      );
                    }
                  },
                  onClose: () => Navigator.pop(context),
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),

              // Tabs on light surface with classic underline indicator
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: dividerColor)),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    tabBarTheme: Theme.of(context).tabBarTheme.copyWith(
                          labelColor: cs.primary,
                          unselectedLabelColor: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.7),
                          labelStyle:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                  ),
                  child: TabBar(
                    controller: _tab,
                    isScrollable: true,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3, color: cs.primary),
                      insets: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    tabs: _buildTabs(isNew),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // drawer: const CommonDrawer(currentRoute: '/invoice-assistant/detail'),
      body: AbsorbPointer(
        absorbing: _busy,
        child: TabBarView(
          controller: _tab,
          children: _buildViews(isNew),
        ),
      ),
      bottomNavigationBar: PrevNextBar(
        canPrev: _tab.index > 0,
        isLast: _tab.index == _tab.length - 1,
        onPrev: () => _tab.animateTo(_tab.index - 1),
        onNextOrSave: () {
          if (_tab.index < _tab.length - 1) {
            _tab.animateTo(_tab.index + 1);
          } else {
            _save();
          }
        },
      ),
    );
  }

  // Tabs:
  // - Always show Details, Services, Payment
  // - If not new, also show AI Insights and History
  // - If new but aiSummary exists, include AI Insights
  List<Widget> _buildTabs(bool isNew) {
    final tabs = <Widget>[
      const Tab(text: 'Details'),
      const Tab(text: 'Services'),
      const Tab(text: 'Payment'),
    ];
    if (!isNew) {
      tabs.addAll(const [
        Tab(text: 'AI Insights'),
        Tab(text: 'History'),
      ]);
    } else if (_showAiTab) {
      tabs.add(const Tab(text: 'AI Insights'));
    }
    return tabs;
  }

  List<Widget> _buildViews(bool isNew) {
    final base = [
      DetailsSection(
        value: _edited,
        isEditing: _editing,
        onChanged: (v) => setState(() => _edited = v),
      ),
      ServicesSection(
        value: _edited,
        isEditing: _editing,
        onChanged: (v) => setState(() => _edited = v),
      ),
      PaymentSection(
        value: _edited,
        isEditing: _editing,
        onChanged: (v) => setState(() => _edited = v),
      ),
    ];

    if (!isNew) {
      return [
        ...base,
        AiSection(value: _edited),
        HistorySection(value: _edited),
      ];
    } else if (_showAiTab) {
      return [
        ...base,
        AiSection(value: _edited),
      ];
    }
    return base;
  }

  void _cancel() {
    if (widget.isNew) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _edited = widget.invoice;
      _editing = false;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final bool isCreate =
          widget.isNew || _edited.id.startsWith('local-') || _edited.id.isEmpty;

      final Invoice? saved = isCreate
          ? await InvoiceService.instance.create(_edited)
          : await InvoiceService.instance.update(_edited);

      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save failed. Please try again.')),
        );
        setState(() {
          _editing = true;
        });
        return;
      }

      setState(() {
        _edited = saved;
        _editing = false;
      });

      // Tabs might need to change if AI summary was populated on save
      _ensureTabControllerSynced();

      if (isCreate) {
        Navigator.pop(context, saved);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice saved')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
      setState(() {
        _editing = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _statusIcon(PaymentStatus s, BuildContext context) {
    switch (s) {
      case PaymentStatus.paid:
        return const Icon(Icons.check_circle,
            color: Color(0xFF059669), size: 18);
      case PaymentStatus.partialPayment:
        return const Icon(Icons.info, color: Color(0xFFF59E0B), size: 18);
      case PaymentStatus.rejectedInsurance:
        return Icon(Icons.error,
            color: Theme.of(context).colorScheme.error, size: 18);
      case PaymentStatus.overdue:
        return const Icon(Icons.warning, color: Color(0xFFF59E0B), size: 18);
      case PaymentStatus.pendingInsurance:
        return const Icon(Icons.schedule, color: Color(0xFF3B82F6), size: 18);
      case PaymentStatus.pending:
        return const Icon(Icons.schedule, color: Color(0xFFF59E0B), size: 18);
      case PaymentStatus.sent:
        return const Icon(Icons.outgoing_mail,
            color: Color(0xFF3B82F6), size: 18);
    }
  }
}
