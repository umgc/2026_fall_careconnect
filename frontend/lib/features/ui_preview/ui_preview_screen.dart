import 'package:care_connect_app/features/ui_preview/ui_preview_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Embeds the React Care Circle preview without replacing the existing Flutter UI.
class UiPreviewScreen extends StatelessWidget {
  const UiPreviewScreen({super.key});

  Future<void> _openFullscreen() async {
    final uri = Uri.base.resolve('/ui-preview/index.html');
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New CareConnect UI (preview)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          if (kIsWeb)
            TextButton.icon(
              onPressed: _openFullscreen,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open fullscreen'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Prototype only — this preview will eventually replace the '
                'current UI. Your existing dashboard is unchanged.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
          const Expanded(child: UiPreviewFrame()),
        ],
      ),
    );
  }
}
