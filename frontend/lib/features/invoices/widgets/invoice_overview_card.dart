import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_tabbed_page.dart';
import 'package:flutter/material.dart';

/// Simple card that shows the count of unpaid invoices and links to the invoice dashboard.
/// Provide a Future<int> that returns the count, so you can plug any data source.
class InvoiceOverviewCard extends StatelessWidget {
  const InvoiceOverviewCard({
    super.key,
    required this.getUnpaidCount,
  });

  /// Fetch function for unpaid invoice count.
  final Future<int> Function() getUnpaidCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Invoice Assistant',
              builder: (context) => const InvoiceTabbedPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long,
                    size: 28, color: Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invoices',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<int>(
                      future: getUnpaidCount(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Text('Loading unpaid invoices...');
                        }
                        if (snapshot.hasError) {
                          return const Text(
                              'Unable to load unpaid invoice count');
                        }
                        final count = snapshot.data ?? 0;
                        final label = count == 1
                            ? 'invoice not paid'
                            : 'invoices not paid';
                        return Text(
                          '$count $label',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black54),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward_ios,
                  size: 16, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}
