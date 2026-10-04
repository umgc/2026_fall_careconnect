import 'package:flutter/material.dart';

import '../../models/help_article.dart';

/// Article presentation shared by the starter screen and future detail screens.
class HelpArticleContent extends StatelessWidget {
  const HelpArticleContent({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(article.title, style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(article.summary, style: textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text(article.body, style: textTheme.bodyLarge),
      ],
    );
  }
}
