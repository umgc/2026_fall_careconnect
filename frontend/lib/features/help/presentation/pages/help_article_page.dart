import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../widgets/help_article_content.dart';

/// One screen renders any catalog article using its permanent ID.
class HelpArticlePage extends StatelessWidget {
  const HelpArticlePage({super.key, required this.articleId, this.repository});

  final String articleId;
  final HelpRepository? repository;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = repository ?? HelpRepository.bundled();
    final article = catalog.findArticle(articleId);

    return Scaffold(
      appBar: AppBar(title: Text(article?.title ?? t.helpArticleNotFoundTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: article == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(t.helpArticleNotFoundDescription),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => context.go(HelpRoutes.home),
                          child: Text(t.helpBackToCenter),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          catalog.findCategory(article.categoryId)!.title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 16),
                        HelpArticleContent(
                          article: article,
                          repository: catalog,
                          onArticleSelected: (id) =>
                              context.push(HelpRoutes.article(id)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
