import 'package:flutter/material.dart';

class AllergyCard extends StatelessWidget {
  final String drug;
  final String severity;
  final String reaction;
  final String note;

  const AllergyCard({
    super.key,
    required this.drug,
    required this.severity,
    required this.reaction,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    Color severityColor = _getSeverityColor(severity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: severityColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  drug,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  severity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  // Handle remove allergy
                },
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reaction,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'severe':
        return Colors.red;
      case 'moderate':
        return Colors.orange;
      case 'mild':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
