import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/confirmation_provider.dart';

import 'summary_confirmation_card.dart';

/// The 3.11.8 surface: pending SUMMARY confirmation items for review.
///
/// Reads David's [ConfirmationProvider] — no parallel state. Shows cached items
/// instantly on mount, then syncs from the backend with sourceType SUMMARY. Filters to
/// sourceType SUMMARY client-side so this surface stays scoped even if the provider
/// holds items of other source types.
///
/// Assumes a [ConfirmationProvider] is available above this widget in the tree
/// (e.g. `ChangeNotifierProvider` at app root, per David's frontend setup).
class SummaryConfirmationList extends StatefulWidget {
  const SummaryConfirmationList({super.key});

  @override
  State<SummaryConfirmationList> createState() => _SummaryConfirmationListState();
}

class _SummaryConfirmationListState extends State<SummaryConfirmationList> {
  @override
  void initState() {
    super.initState();
    // Defer provider access until after the first frame so context.read is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ConfirmationProvider>();
      provider.loadFromCache();
      provider.fetchFromBackend(sourceType: 'SUMMARY');
    });
  }

  Future<void> _refresh() =>
      context.read<ConfirmationProvider>().fetchFromBackend(sourceType: 'SUMMARY');

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfirmationProvider>(
      builder: (context, provider, _) {
        final items = provider.pendingItems
            .where((i) => i['sourceType'] == 'SUMMARY')
            .toList();

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              // ListView (not Column) so pull-to-refresh works on an empty surface.
              children: const [
                SizedBox(height: 120),
                _SummaryEmptyState(),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => SummaryConfirmationCard(
              item: items[index],
              provider: provider,
            ),
          ),
        );
      },
    );
  }
}

/// Minimal empty state — the hook for 3.11.9. Swap in the finished empty-state design
/// when that ticket lands.
class _SummaryEmptyState extends StatelessWidget {
  const _SummaryEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('No summary items to review',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Confirmed and dismissed items won\'t appear here.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
