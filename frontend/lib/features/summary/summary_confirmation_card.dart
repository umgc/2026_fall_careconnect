import 'package:flutter/material.dart';
import 'package:care_connect_app/providers/confirmation_provider.dart';

import 'summary_confirmation_payload.dart';

/// Renders one PENDING summary confirmation item and routes confirm/dismiss through
/// David's [ConfirmationProvider] (WBS 3.15.2). Items are `Map<String, dynamic>` per
/// David's provider API — this widget holds no domain state of its own beyond an
/// in-flight flag so the buttons disable during the network call.
class SummaryConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final ConfirmationProvider provider;

  const SummaryConfirmationCard({
    super.key,
    required this.item,
    required this.provider,
  });

  @override
  State<SummaryConfirmationCard> createState() => _SummaryConfirmationCardState();
}

class _SummaryConfirmationCardState extends State<SummaryConfirmationCard> {
  bool _busy = false;

  int get _itemId => widget.item['id'] as int;
  String get _payloadJson => (widget.item['payload'] as String?) ?? '';

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final ok = await widget.provider.confirmItem(_itemId);
      if (!ok && mounted) {
        _showError('Could not confirm item. Please try again.');
      }
      // On success the provider updates the item to CONFIRMED and notifies listeners;
      // the parent list rebuilds and this card drops out via the PENDING filter.
    } catch (e) {
      if (mounted) _showError('Could not confirm item: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    final reason = await _promptForReason();
    if (reason == null) return; // user cancelled
    setState(() => _busy = true);
    try {
      final ok = await widget.provider.dismissItem(_itemId, note: reason);
      if (!ok && mounted) {
        _showError('Could not dismiss item. Please try again.');
      }
    } catch (e) {
      if (mounted) _showError('Could not dismiss item: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _promptForReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss summary item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'e.g. Inaccurate side effect',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = SummaryConfirmationPayload.fromJson(_payloadJson);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(payload.headline, style: theme.textTheme.titleMedium),
                ),
                if (payload.typeLabel != null)
                  Chip(
                    label: Text(payload.typeLabel!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (payload.detail != null && payload.detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(payload.detail!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton(
                  onPressed: _busy ? null : _dismiss,
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
