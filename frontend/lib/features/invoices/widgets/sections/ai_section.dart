// sections/ai_section.dart
import 'package:flutter/material.dart';
import '../../models/invoice_models.dart';

class AiSection extends StatelessWidget {
  const AiSection({super.key, required this.value});
  final Invoice value;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('AI Summary'),
            subtitle: Text(value.aiSummary ?? 'No AI summary available.'),
          ),
        ),
        const SizedBox(height: 12),
        if (value.recommendedActions?.isNotEmpty == true)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recommended Actions',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...value.recommendedActions!.map(
                    (a) => ListTile(
                        leading: const Icon(Icons.check), title: Text(a)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
