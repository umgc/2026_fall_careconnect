import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../../models/help_role.dart';
import '../widgets/help_article_tile.dart';

/// A Browse Topics destination, resolved by permanent category ID.
class HelpTopicPage extends StatelessWidget {
  const HelpTopicPage({super.key, required this.categoryId, this.repository});

  final String categoryId;
  final HelpRepository? repository;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = repository ?? HelpRepository.bundled();
    final category = catalog.findCategory(categoryId);
    final articles =
        catalog.articlesForCategory(categoryId, role: HelpRole.patient);

    return Scaffold(
      appBar: AppBar(title: Text(category?.title ?? t.helpTopicNotFound)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (category == null) ...[
                    Text(t.helpTopicNotFoundDescription,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: () => context.go(HelpRoutes.home),
                        child: Text(t.helpBackToCenter)),
                  ] else ...[
                    Text(category.description,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    if (articles.isEmpty)
                      Text(t.helpNoArticles,
                          style: Theme.of(context).textTheme.bodyLarge),
                    for (final article in articles)
                      HelpArticleTile(
                          article: article,
                          onTap: () =>
                              context.push(HelpRoutes.article(article.id))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
