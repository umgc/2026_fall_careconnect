import 'package:flutter/material.dart';

enum AdminKpiTone { info, warning, error, neutral }

class AdminKpiSpec {
  const AdminKpiSpec({
    required this.title,
    required this.value,
    required this.icon,
    this.tone = AdminKpiTone.neutral,
  });

  final String title;
  final String value;
  final IconData icon;
  final AdminKpiTone tone;
}

class AdminAnalyticsKpiRow extends StatelessWidget {
  const AdminAnalyticsKpiRow({super.key, required this.items});

  final List<AdminKpiSpec> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Overview',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final itemWidth = isWide
                    ? (constraints.maxWidth - 12 * (items.length - 1)) /
                        items.length
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items
                      .map(
                        (spec) => SizedBox(
                          width: itemWidth,
                          child: _AdminKpiCard(spec: spec, scheme: scheme),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminKpiCard extends StatelessWidget {
  const _AdminKpiCard({required this.spec, required this.scheme});

  final AdminKpiSpec spec;
  final ColorScheme scheme;

  Color _foreground(AdminKpiTone tone) {
    switch (tone) {
      case AdminKpiTone.info:
        return scheme.onPrimaryContainer;
      case AdminKpiTone.warning:
        return scheme.onTertiaryContainer;
      case AdminKpiTone.error:
        return scheme.onErrorContainer;
      case AdminKpiTone.neutral:
        return scheme.onSecondaryContainer;
    }
  }

  Color _background(AdminKpiTone tone) {
    switch (tone) {
      case AdminKpiTone.info:
        return scheme.primaryContainer;
      case AdminKpiTone.warning:
        return scheme.tertiaryContainer;
      case AdminKpiTone.error:
        return scheme.errorContainer;
      case AdminKpiTone.neutral:
        return scheme.secondaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _foreground(spec.tone);
    final background = _background(spec.tone);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background.withOpacity(0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, color: foreground),
          const SizedBox(height: 8),
          Text(
            spec.value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            spec.title,
            style: TextStyle(
              fontSize: 12,
              color: foreground.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
