import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../../models/help_role.dart';
import '../widgets/help_article_tile.dart';

/// Patient-focused home with bundled guides and local search.
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key, this.repository});

  final HelpRepository? repository;

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final _searchController = TextEditingController();
  late final _bundledCatalog = HelpRepository.bundled();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = widget.repository ?? _bundledCatalog;
    final searching = _searchController.text.trim().isNotEmpty;
    final articles = searching
        ? catalog.searchArticles(_searchController.text, role: HelpRole.patient)
        : catalog.popularArticlesForRole(HelpRole.patient);

    return Scaffold(
      appBar: AppBar(title: Text(t.helpCenterTitle)),
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
                  Semantics(
                      header: true,
                      child: Text(
                        searching ? t.helpSearchResults : t.helpPopularHelp,
                        style: Theme.of(context).textTheme.titleLarge,
                      )),
                  const SizedBox(height: 12),
                  if (articles.isEmpty)
                    Text(searching ? t.helpNoSearchResults : t.helpNoArticles),
                  for (final article in articles)
                    HelpArticleTile(
                      key: ValueKey(article.id),
                      article: article,
                      onTap: () => context.push(HelpRoutes.article(article.id)),
                    ),
                  if (!searching) ...[
                    const SizedBox(height: 24),
                    Semantics(
                        header: true,
                        child: Text(t.helpBrowseTopics,
                            style: Theme.of(context).textTheme.titleLarge)),
                    const SizedBox(height: 12),
                    for (final category
                        in catalog.categoriesForRole(HelpRole.patient))
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          title: Text(category.title),
                          subtitle: Text(category.description),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push(HelpRoutes.topic(category.id)),
                        ),
                      ),
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
