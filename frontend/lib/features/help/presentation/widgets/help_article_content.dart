import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../models/help_article.dart';
import '../../models/help_section.dart';

/// Article presentation shared by the starter screen and future detail screens.
class HelpArticleContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(article.title, style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(article.summary, style: textTheme.bodyLarge),
        const SizedBox(height: 16),
        for (final section in article.sections) ...[
          _buildSection(context, section),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildSection(BuildContext context, HelpSection section) {
    final t = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final defaultHeading = switch (section) {
      HelpTroubleshooting() => t.helpTroubleshooting,
      HelpRelatedArticles() => t.helpRelatedArticles,
      _ => null,
    };
    final heading = section.heading ?? defaultHeading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null) ...[
          Semantics(
            header: true,
            child: Text(heading, style: textTheme.titleMedium),
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
                          Text(tip.problem, style: textTheme.titleSmall),
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
                            title: Text(repository.findArticle(id)!.title),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => onArticleSelected(id),
                          ))),
              ],
            ),
        },
      ],
    );
  }
}
