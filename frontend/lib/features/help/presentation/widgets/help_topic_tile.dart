import 'package:flutter/material.dart';

import '../../models/help_category.dart';

/// Topic navigation with one accessible title/description/button node.
class HelpTopicTile extends StatelessWidget {
  const HelpTopicTile(
      {super.key, required this.category, required this.onTap, this.focusNode});

  final HelpCategory category;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
            button: true,
            child: Card(
              child: ListTile(
                focusNode: focusNode,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(category.title,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(category.description,
                    style: Theme.of(context).textTheme.bodyLarge),
                trailing: const Icon(Icons.chevron_right),
                onTap: onTap,
              ),
            )),
      );
}
