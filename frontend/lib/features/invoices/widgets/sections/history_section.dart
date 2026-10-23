// sections/history_section.dart
import 'package:flutter/material.dart';
import '../../models/invoice_models.dart';

class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.value});
  final Invoice value;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: value.history
          .map(
            (h) => Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                    'Version ${h.version} • ${DateTime.parse(h.timestamp).toLocal()}'),
                subtitle: Text(h.changes),
              ),
            ),
          )
          .toList(),
    );
  }
}
