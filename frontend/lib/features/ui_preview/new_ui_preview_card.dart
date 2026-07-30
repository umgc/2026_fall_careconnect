import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Dashboard entry point for the React UI preview (does not replace current UI).
class NewUiPreviewCard extends StatelessWidget {
  const NewUiPreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(
          Icons.auto_awesome,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Try the new CareConnect UI'),
        subtitle: const Text(
          'Preview only — does not replace your current dashboard yet',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/ui-preview'),
      ),
    );
  }
}
