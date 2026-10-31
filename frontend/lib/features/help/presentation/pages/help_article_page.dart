import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../widgets/help_article_content.dart';
import '../widgets/help_app_bar.dart';
import '../widgets/help_accessibility.dart';
import '../widgets/help_back_to_top.dart';

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
  final _titleFocus =
      FocusNode(skipTraversal: true, debugLabel: 'Help article title');
  late final _bundledCatalog = HelpRepository.bundled();
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
    _titleFocus.requestFocus();
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
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HelpAccessibility(
      pageTitle: (widget.repository ?? _bundledCatalog)
              .findArticle(widget.articleId)
              ?.title ??
          AppLocalizations.of(context)!.helpArticleNotFoundTitle,
      builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = widget.repository ?? _bundledCatalog;
    final article = catalog.findArticle(widget.articleId);

    return Scaffold(
      appBar: helpAppBar(context,
          title: article?.title ?? t.helpArticleNotFoundTitle),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _showBackToTop && article != null
          ? HelpBackToTop(onPressed: _backToTop)
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('help-page-scroll'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: article == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                            key: const ValueKey('help-page-heading'),
                            header: true,
                            headingLevel: 1,
                            child: Text(t.helpArticleNotFoundTitle,
                                style:
                                    Theme.of(context).textTheme.displayMedium)),
                        const SizedBox(height: 16),
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
                          titleFocusNode: _titleFocus,
                          article: article,
                          repository: catalog,
                          onGlossarySelected: (id) =>
                              context.push(HelpRoutes.glossaryTerm(id)),
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
