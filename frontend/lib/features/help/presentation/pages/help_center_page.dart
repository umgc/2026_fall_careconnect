import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../../models/help_role.dart';
import '../widgets/help_article_tile.dart';
import '../widgets/help_app_bar.dart';
import '../widgets/help_topic_tile.dart';
import '../widgets/help_glossary_entry.dart';

/// Patient-focused home with bundled guides and local search.
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key, this.repository});

  final HelpRepository? repository;

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final _searchController = TextEditingController();
  final _topicsHeadingKey = GlobalKey();
  final _firstTopicFocusNode = FocusNode(debugLabel: 'First Help topic');
  late final _bundledCatalog = HelpRepository.bundled();

  @override
  void dispose() {
    _searchController.dispose();
    _firstTopicFocusNode.dispose();
    super.dispose();
  }

  void _browseTopics() {
    setState(_searchController.clear);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _firstTopicFocusNode.requestFocus();
      final headingContext = _topicsHeadingKey.currentContext;
      if (headingContext != null) Scrollable.ensureVisible(headingContext);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = widget.repository ?? _bundledCatalog;
    final searching = _searchController.text.trim().isNotEmpty;
    final articles = searching
        ? catalog.searchArticles(_searchController.text, role: HelpRole.patient)
        : catalog.popularArticlesForRole(HelpRole.patient);
    final categories = catalog.categoriesForRole(HelpRole.patient);
    final terms =
        searching ? catalog.searchGlossary(_searchController.text) : const [];

    return FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Scaffold(
          appBar: helpAppBar(context, title: t.helpCenterTitle),
          body: SafeArea(
            child: SingleChildScrollView(
              key: const PageStorageKey('help-center-home'),
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        style: Theme.of(context).textTheme.bodyLarge,
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: t.helpSearchArticles,
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: t.helpClearSearch,
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(_searchController.clear),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!searching) ...[
                        Card(
                            child: MergeSemantics(
                                child: Semantics(
                                    button: true,
                                    child: ListTile(
                                      key: const ValueKey('help-open-glossary'),
                                      contentPadding: const EdgeInsets.all(16),
                                      title: Text(t.helpGlossary,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      subtitle: Text(t.helpGlossaryDescription,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          context.push(HelpRoutes.glossary),
                                    )))),
                        const SizedBox(height: 24),
                      ],
                      Semantics(
                          key: const ValueKey('help-search-status'),
                          header: true,
                          liveRegion: searching,
                          label: searching
                              ? t.helpCombinedResultsCount(
                                  t.helpSearchResultsCount(articles.length),
                                  t.helpGlossaryResultsCount(terms.length))
                              : null,
                          child: ExcludeSemantics(
                              excluding: searching,
                              child: Text(
                                searching
                                    ? t.helpSearchResults
                                    : t.helpPopularHelp,
                                style: Theme.of(context).textTheme.displaySmall,
                              ))),
                      const SizedBox(height: 12),
                      if (searching && articles.isEmpty && terms.isEmpty) ...[
                        Text(t.helpNoSearchResults,
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 12),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: _browseTopics,
                            icon: const Icon(Icons.topic_outlined),
                            label: Text(t.helpBrowseTopics),
                          ),
                        ),
                      ] else if (!searching && articles.isEmpty)
                        Text(t.helpNoArticles,
                            style: Theme.of(context).textTheme.bodyLarge),
                      if (searching && articles.isNotEmpty)
                        Semantics(
                            header: true,
                            child: Text(t.helpArticles,
                                style: Theme.of(context).textTheme.titleLarge)),
                      for (final article in articles)
                        HelpArticleTile(
                          key: ValueKey(article.id),
                          article: article,
                          onTap: () =>
                              context.push(HelpRoutes.article(article.id)),
                        ),
                      if (searching && terms.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Semantics(
                            header: true,
                            child: Text(t.helpWordsAndMeanings,
                                style: Theme.of(context).textTheme.titleLarge)),
                        for (final term in terms)
                          HelpGlossaryResultTile(
                              key: ValueKey('help-word-result-${term.id}'),
                              term: term,
                              onTap: () => context
                                  .push(HelpRoutes.glossaryTerm(term.id))),
                      ],
                      if (!searching) ...[
                        const SizedBox(height: 24),
                        Semantics(
                            key: _topicsHeadingKey,
                            header: true,
                            child: Text(t.helpBrowseTopics,
                                style:
                                    Theme.of(context).textTheme.displaySmall)),
                        const SizedBox(height: 12),
                        for (var i = 0; i < categories.length; i++)
                          HelpTopicTile(
                            category: categories[i],
                            focusNode: i == 0 ? _firstTopicFocusNode : null,
                            onTap: () => context
                                .push(HelpRoutes.topic(categories[i].id)),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}
