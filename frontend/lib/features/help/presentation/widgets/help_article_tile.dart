import 'package:flutter/material.dart';

import '../../models/help_article.dart';

/// Shared article entry used by popular articles, search, and topic screens.
class HelpArticleTile extends StatelessWidget {
  const HelpArticleTile(
      {super.key, required this.article, required this.onTap});

  final HelpArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
            button: true,
            child: Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(article.title,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(article.summary,
                    style: Theme.of(context).textTheme.bodyLarge),
                trailing: const Icon(Icons.chevron_right),
                onTap: onTap,
              ),
            )),
      );
}
