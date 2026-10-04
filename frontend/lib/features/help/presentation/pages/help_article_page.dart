import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../widgets/help_article_content.dart';
import '../widgets/help_app_bar.dart';

/// One screen renders any catalog article using its permanent ID.
class HelpArticlePage extends StatefulWidget {
  const HelpArticlePage({super.key, required this.articleId, this.repository});

  final String articleId;
  final HelpRepository? repository;

  @override
  State<HelpArticlePage> createState() => _HelpArticlePageState();
}

class _HelpArticlePageState extends State<HelpArticlePage> {
  final _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateBackToTop);
  }

  void _updateBackToTop() {
    final show = _scrollController.offset >= 320;
    if (show != _showBackToTop) setState(() => _showBackToTop = show);
  }

  void _backToTop() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(0);
    } else {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = widget.repository ?? HelpRepository.bundled();
    final article = catalog.findArticle(widget.articleId);

    return Scaffold(
      appBar: helpAppBar(context,
          title: article?.title ?? t.helpArticleNotFoundTitle),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _showBackToTop && article != null
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _backToTop,
              icon: const Icon(Icons.arrow_upward),
              label: Text(t.helpBackToTop),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: article == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(t.helpArticleNotFoundDescription,
                            style: Theme.of(context).textTheme.bodyLarge),
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
