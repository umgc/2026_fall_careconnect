import 'package:flutter/material.dart';

import '../../models/help_article.dart';
import '../../../../l10n/app_localizations.dart';
import 'help_link_tile.dart';

/// Shared article entry used by popular articles, search, and topic screens.
class HelpArticleTile extends StatelessWidget {
  const HelpArticleTile(
      {super.key, required this.article, required this.onTap});

  final HelpArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
          child: Card(
        child: HelpLinkTile(
          title: article.title,
          summary: article.summary,
          hint: AppLocalizations.of(context)!.helpOpenArticleHint,
          onTap: onTap,
        ),
      ));
}
