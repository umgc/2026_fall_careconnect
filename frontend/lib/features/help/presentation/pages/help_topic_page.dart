import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../../models/help_role.dart';
import '../widgets/help_article_tile.dart';
import '../widgets/help_app_bar.dart';
import '../widgets/help_accessibility.dart';

/// A Browse Topics destination, resolved by permanent category ID.
class HelpTopicPage extends StatelessWidget {
  const HelpTopicPage({super.key, required this.categoryId, this.repository});

  final String categoryId;
  final HelpRepository? repository;

  @override
  Widget build(BuildContext context) => HelpAccessibility(
      pageTitle: (repository ?? HelpRepository.bundled())
              .findCategory(categoryId)
              ?.title ??
          AppLocalizations.of(context)!.helpTopicNotFound,
      builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = repository ?? HelpRepository.bundled();
    final category = catalog.findCategory(categoryId);
    final articles =
        catalog.articlesForCategory(categoryId, role: HelpRole.patient);

    return Scaffold(
      appBar:
          helpAppBar(context, title: category?.title ?? t.helpTopicNotFound),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                      key: const ValueKey('help-page-heading'),
                      header: true,
                      headingLevel: 1,
                      child: Text(category?.title ?? t.helpTopicNotFound,
                          style: Theme.of(context).textTheme.displayMedium)),
                  const SizedBox(height: 16),
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
