import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/help_repository.dart';
import '../../help_routes.dart';

/// Entry screen backed by the local, bundled Help catalog.
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key, this.repository});

  final HelpRepository? repository;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final catalog = repository ?? HelpRepository.bundled();

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
                  for (final article in catalog.articles)
                    Card(
                      child: ListTile(
                        title: Text(article.title),
                        subtitle: Text(article.summary),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push(HelpRoutes.article(article.id)),
                      ),
                    ),
                  const SizedBox(height: 24),
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
