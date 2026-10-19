import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/providers/shortcut_provider.dart';

class ShortcutSearchDelegate extends SearchDelegate<void> {
  final String roleUpper;
  final String userId;
  final bool allowPinToggle;

  ShortcutSearchDelegate({
    required this.roleUpper,
    required this.userId,
    this.allowPinToggle = true,
  }) : super(searchFieldLabel: 'Search features');

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final sp = context.read<ShortcutProvider>();
    final all = sp.visibleCatalogForRole(roleUpper);

    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? all
        : all.where((d) {
            final haystack = '${d.label} ${d.routeTemplate}'.toLowerCase();
            return haystack.contains(q);
          }).toList();

    if (results.isEmpty) {
      return const Center(child: Text('No matches'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final d = results[i];
        final resolved = d.resolveRoute({'userId': userId});
        final isActive = sp.isActive(d.key);

        return ListTile(
          leading: Icon(d.icon),
          title: Text(d.label),
          // subtitle: Text(resolved, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: allowPinToggle && !isActive
              ? const Icon(Icons.push_pin_outlined, size: 18)
              : null,
          onTap: () {
            close(ctx, null);
            // push so the back button returns to Menu
            ctx.push(resolved);
          },
          onLongPress: allowPinToggle
              ? () async {
                  await sp.toggle(d.key);
                }
              : null,
        );
      },
    );
  }
}
