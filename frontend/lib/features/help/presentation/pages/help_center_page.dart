import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_content_ids.dart';
import '../../data/help_repository.dart';
import '../widgets/help_article_content.dart';

/// Entry screen backed by the local, bundled Help catalog.
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key, this.repository});

  final HelpRepository? repository;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = repository ?? HelpRepository.bundled();
    final introduction = catalog.findArticle(HelpArticleIds.openingHelp);

    return Scaffold(
      appBar: AppBar(title: Text(t.helpCenterTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (introduction != null) ...[
                    HelpArticleContent(article: introduction),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    t.helpCenterPlaceholder,
                    style: Theme.of(context).textTheme.bodyLarge,
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
