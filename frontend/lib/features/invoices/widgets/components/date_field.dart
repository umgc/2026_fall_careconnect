// components/date_field.dart
import 'package:flutter/material.dart';

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.optional = false,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(
      text: value == null ? '' : _fmt(value!),
    );

    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: true, // keep true to allow tap, use enabled flag to gate picker
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        hintText: optional ? 'Not set' : null,
      ),
      onTap: !enabled
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: DateTime(now.year + 3),
                initialDate: value ?? now,
              );
              if (picked != null)
                onChanged(DateTime(picked.year, picked.month, picked.day));
            },
    );
  }

  String _fmt(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
