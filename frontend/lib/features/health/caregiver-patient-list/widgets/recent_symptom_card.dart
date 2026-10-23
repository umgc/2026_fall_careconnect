import 'package:flutter/material.dart';

class SymptomEntry {
  final String id;
  final DateTime date;
  final String name; // comma-separated symptom names for the chip pill
  final String severity; // Mild | Moderate | Severe (any text supported)
  final String note; // description line under chips

  SymptomEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.severity,
    required this.note,
  });
}

/// Recent Symptoms section (single card).
/// Pass [extraTop] to render a widget directly under the section header
/// (use this to place PainLevelCard inside this card).
class RecentSymptomsSection extends StatelessWidget {
  const RecentSymptomsSection({
    super.key,
    required this.entries,
    this.extraTop,
  });

  final List<SymptomEntry> entries;
  final Widget? extraTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.medical_services_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Recent Symptoms',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary, // teal to match the app theme
                ),
              ),
            ],
          ),

          // Optional injected widget (e.g., PainLevelCard) directly under header
          if (extraTop != null) ...[const SizedBox(height: 12), extraTop!],

          // Each symptom entry
          for (int i = 0; i < entries.length; i++) ...[
            const SizedBox(height: 12),
            _SymptomTile(entry: entries[i]),
            if (i != entries.length - 1)
              Divider(color: cs.outlineVariant.withOpacity(.35)),
          ],
        ],
      ),
    );
  }
}

class _SymptomTile extends StatelessWidget {
  const _SymptomTile({required this.entry});
  final SymptomEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color chipColor() {
      final t = entry.severity.toLowerCase();
      if (t.contains('severe')) return const Color(0xFFE65757);
      if (t.contains('moderate')) return const Color(0xFFF29B1D);
      if (t.contains('mild')) return const Color(0xFF4CAF50);
      return cs.primary;
    }

    // ⬇️ Match PainLevelCard / CurrentMedications card styling
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + severity chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(entry.date),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface.withOpacity(.75),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: chipColor(),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.severity.toLowerCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Symptom name “pill”
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              entry.name,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Note line
          if (entry.note.isNotEmpty)
            Text(
              entry.note,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
