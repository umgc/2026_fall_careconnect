import 'package:flutter/material.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/invoice_dashboard_page.dart';
import 'package:care_connect_app/features/invoices/screens/upload_invoice.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_list_page.dart';

class InvoiceTabbedPage extends StatefulWidget {
  const InvoiceTabbedPage({
    super.key,
    this.initialTabIndex = 0,
    this.quickFilter,
  });

  final int initialTabIndex;
  final String? quickFilter;

  @override
  State<InvoiceTabbedPage> createState() => _InvoiceTabbedPageState();
}

class _InvoiceTabbedPageState extends State<InvoiceTabbedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBack = widget.quickFilter != null; // filtered route
    final appBarTheme = Theme.of(context).appBarTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Assistant'),
        leading: showBack
            ? BackButton(onPressed: () => Navigator.of(context).maybePop())
            : null,
        bottom: TabBar(
          // Let the theme determine the selected color for full compatibility
          // Set unselected color to be a slightly transparent version of the foreground color
          unselectedLabelColor: appBarTheme.foregroundColor?.withOpacity(0.7),
          controller: _tabController,
          tabs: const [
            // Removed hardcoded colors from icons to allow the theme to control them
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            Tab(icon: Icon(Icons.upload_file_outlined), text: 'Upload Invoice'),
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Invoice List'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _DashboardTab(key: ValueKey('dashboard')),
          const _UploadInvoiceTab(key: ValueKey('upload')),
          _InvoiceListTab(
            key: const ValueKey('list'),
            quickFilter: widget.quickFilter, // <— pass it in
          ),
        ],
      ),
    );
  }
}

/// Wrapper that renders InvoiceDashboardPage without its Scaffold/AppBar/Drawer
class _DashboardTab extends StatelessWidget {
  const _DashboardTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
            builder: (context) => const InvoiceDashboardPage());
      },
    );
  }
}

/// Wrapper that renders UploadInvoicePage without its Scaffold/AppBar/Drawer
class _UploadInvoiceTab extends StatelessWidget {
  const _UploadInvoiceTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
            builder: (context) => const UploadInvoicePage());
      },
    );
  }
}

/// Wrapper that renders InvoiceListPage without its Scaffold/AppBar/Drawer
class _InvoiceListTab extends StatelessWidget {
  const _InvoiceListTab({super.key, this.quickFilter});
  final String? quickFilter;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => InvoiceListPage(quickFilter: quickFilter),
        );
      },
    );
  }
}
