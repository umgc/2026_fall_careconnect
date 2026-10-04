import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';
import '../../models/help_role.dart';
import '../widgets/help_app_bar.dart';
import '../widgets/help_article_tile.dart';
import '../widgets/help_glossary_entry.dart';

/// Eager entries let direct links reach variable-height definitions reliably.
class HelpGlossaryPage extends StatefulWidget {
  const HelpGlossaryPage({super.key, this.termId, this.repository});
  final String? termId;
  final HelpRepository? repository;
  @override
  State<HelpGlossaryPage> createState() => _HelpGlossaryPageState();
}

class _HelpGlossaryPageState extends State<HelpGlossaryPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  final _focusNodes = <String, FocusNode>{};
  late final _bundled = HelpRepository.bundled();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateScroll);
    _scheduleSelection();
  }

  @override
  void didUpdateWidget(covariant HelpGlossaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.termId != widget.termId ||
        oldWidget.repository != widget.repository) {
      _search.clear();
      _scheduleSelection();
    }
  }

  void _updateScroll() {
    final show = _scroll.offset >= 320;
    if (show != _showBackToTop) setState(() => _showBackToTop = show);
  }

  void _scheduleSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final id = widget.termId;
      final target = _keys[id]?.currentContext;
      if (target == null) return;
      await Scrollable.ensureVisible(target,
          alignment: 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300));
      if (mounted && widget.termId == id) _focusNodes[id]?.requestFocus();
    });
  }

  void _backToTop() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = widget.repository ?? _bundled;
    final terms = catalog.searchGlossary(_search.text);
    final unknown = widget.termId != null &&
        catalog.findGlossaryTerm(widget.termId!) == null;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Scaffold(
        appBar: helpAppBar(context, title: t.helpGlossary),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: _showBackToTop
            ? FloatingActionButton.extended(
                heroTag: null,
                onPressed: _backToTop,
                icon: const Icon(Icons.arrow_upward),
                label: Text(t.helpBackToTop))
            : null,
        body: SafeArea(
            child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.helpGlossaryDescription,
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: t.helpFindWord,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: t.helpClearSearch,
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(_search.clear))),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                      key: const ValueKey('help-glossary-status'),
                      liveRegion: true,
                      child: Text(t.helpGlossaryResultsCount(terms.length),
                          style: Theme.of(context).textTheme.bodyLarge)),
                  if (unknown) ...[
                    const SizedBox(height: 16),
                    Semantics(
                        liveRegion: true,
                        child: Text(t.helpWordNotFound,
                            style: Theme.of(context).textTheme.bodyLarge)),
                  ],
                  if (terms.isEmpty) ...[
                    const SizedBox(height: 16),
                    Text(t.helpNoGlossaryResults,
                        style: Theme.of(context).textTheme.bodyLarge),
                    Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                            onPressed: () => setState(_search.clear),
                            child: Text(t.helpShowAllWords))),
                  ],
                  for (final term in terms)
                    Focus(
                      key: _keys.putIfAbsent(term.id, GlobalKey.new),
                      focusNode: _focusNodes.putIfAbsent(
                          term.id,
                          () => FocusNode(
                              skipTraversal: true, debugLabel: term.term)),
                      child: HelpGlossaryEntry(
                        key: ValueKey('help-glossary-${term.id}'),
                        term: term,
                        selected: term.id == widget.termId,
                        guides: [
                          for (final article in catalog.articlesForGlossaryTerm(
                              term.id,
                              role: HelpRole.patient))
                            HelpArticleTile(
                                article: article,
                                onTap: () => context
                                    .push(HelpRoutes.article(article.id)))
                        ],
                      ),
                    ),
                ]),
          )),
        )),
      ),
    );
  }
}
