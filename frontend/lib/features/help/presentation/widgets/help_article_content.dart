import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../models/help_article.dart';
import '../../models/help_section.dart';
import 'help_section_heading.dart';

/// Article presentation shared by the starter screen and future detail screens.
class HelpArticleContent extends StatefulWidget {
  const HelpArticleContent({
    super.key,
    required this.article,
    required this.repository,
    required this.onArticleSelected,
  });

  final HelpArticle article;
  final HelpRepository repository;
  final ValueChanged<String> onArticleSelected;

  @override
  State<HelpArticleContent> createState() => _HelpArticleContentState();
}

class _SectionTarget {
  final key = GlobalKey();
  final focusNode = FocusNode(skipTraversal: true);

  void dispose() => focusNode.dispose();
}

class _HelpArticleContentState extends State<HelpArticleContent> {
  late List<_SectionTarget> _targets;
  bool _contentsExpanded = true;

  @override
  void initState() {
    super.initState();
    _createTargets();
  }

  void _createTargets() {
    _targets = [for (final _ in widget.article.sections) _SectionTarget()];
  }

  @override
  void didUpdateWidget(covariant HelpArticleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.id != widget.article.id ||
        !identical(oldWidget.article.sections, widget.article.sections)) {
      for (final target in _targets) {
        target.dispose();
      }
      _createTargets();
      _contentsExpanded = true;
    }
  }

  Future<void> _jumpToSection(int index) async {
    final target = _targets[index];
    final targetContext = target.key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(targetContext,
        alignment: 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOut);
    if (mounted && target.key.currentContext != null) {
      target.focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    for (final target in _targets) {
      target.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final t = AppLocalizations.of(context)!;
    final headings = [
      for (final section in widget.article.sections)
        helpSectionHeading(section, t),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.article.title, style: textTheme.displayMedium),
        const SizedBox(height: 8),
        Text(widget.article.summary, style: textTheme.bodyLarge),
        const SizedBox(height: 16),
        if (headings.whereType<String>().length >= 2) ...[
          Card(
            key: const ValueKey('help-article-contents'),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MergeSemantics(
                    key: const ValueKey('help-contents-toggle-semantics'),
                    child: Semantics(
                      header: true,
                      expanded: _contentsExpanded,
                      child: TextButton(
                        key: const ValueKey('help-contents-toggle'),
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48)),
                        onPressed: () => setState(
                            () => _contentsExpanded = !_contentsExpanded),
                        child: Row(children: [
                          Expanded(
                              child: Text(t.helpOnThisPage,
                                  style: textTheme.displaySmall)),
                          Icon(_contentsExpanded
                              ? Icons.expand_less
                              : Icons.expand_more),
                        ]),
                      ),
                    ),
                  ),
                  if (_contentsExpanded)
                    for (var i = 0; i < headings.length; i++)
                      if (headings[i] != null)
                        TextButton(
                          key: ValueKey('help-contents-entry-$i'),
                          style: TextButton.styleFrom(
                              alignment: AlignmentDirectional.centerStart,
                              minimumSize: const Size(0, 48)),
                          onPressed: () => _jumpToSection(i),
                          child: Text(headings[i]!, style: textTheme.bodyLarge),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < widget.article.sections.length; i++) ...[
          _buildSection(context, widget.article.sections[i], i, headings[i]),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildSection(
      BuildContext context, HelpSection section, int index, String? heading) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null) ...[
          Focus(
            key: _targets[index].key,
            focusNode: _targets[index].focusNode,
            child: Semantics(
              key: ValueKey('help-section-heading-$index'),
              header: true,
              child: Text(heading, style: textTheme.displaySmall),
            ),
          ),
          const SizedBox(height: 8),
        ],
        switch (section) {
          HelpParagraph(:final text) => Text(text, style: textTheme.bodyLarge),
          HelpSteps(:final steps) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${i + 1}. ${steps[i]}',
                        style: textTheme.bodyLarge),
                  ),
              ],
            ),
          HelpTroubleshooting(:final tips) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tip in tips)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tip.problem, style: textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(tip.solution, style: textTheme.bodyLarge),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          HelpRelatedArticles(:final articleIds) => Column(
              children: [
                for (final id in articleIds)
                  MergeSemantics(
                      child: Semantics(
                          button: true,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                widget.repository.findArticle(id)!.title,
                                style: textTheme.titleMedium),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onArticleSelected(id),
                          ))),
              ],
            ),
        },
      ],
    );
  }
}
