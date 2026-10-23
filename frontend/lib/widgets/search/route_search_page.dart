// lib/features/search/pages/route_search_page.dart
// Search UI that lists pages by role, supports routes and direct widget pushes.

import 'package:care_connect_app/widgets/search/route_registry.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../providers/user_provider.dart';

class RouteSearchPage extends StatefulWidget {
  const RouteSearchPage({super.key});

  @override
  State<RouteSearchPage> createState() => _RouteSearchPageState();
}

class _RouteSearchPageState extends State<RouteSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _query = _controller.text.trim());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Iterable<RouteMeta> _filterByRole(Iterable<RouteMeta> items, AppRole? role) {
    if (role == null) return const [];
    return items.where((m) => m.roles.contains(role));
  }

  int _score(RouteMeta m, String q) {
    if (q.isEmpty) return 1;
    final lcq = q.toLowerCase();
    int score = 0;
    if (m.title.toLowerCase().contains(lcq)) score += 5;
    if ((m.path ?? '').toLowerCase().contains(lcq)) score += 3;
    if (m.description.toLowerCase().contains(lcq)) score += 2;
    for (final k in m.keywords) {
      if (k.toLowerCase().contains(lcq)) {
        score += 2;
        break;
      }
    }
    return score;
  }

  Future<void> _navigate(BuildContext context, RouteMeta m) async {
    if (!m.launchable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'This page needs context and cannot be opened directly from search')),
      );
      return;
    }

    // Collect parameters if needed
    Map<String, String> query = {};
    Map<String, String> pathVars = {};
    if (m.params.isNotEmpty) {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _ParamDialog(meta: m),
      );
      if (values == null) return;
      for (final p in m.params) {
        final v = values[p.key]?.trim();
        if (v == null || v.isEmpty) return;
        if (p.isPathParam) {
          pathVars[p.key] = v;
        } else {
          query[p.key] = v;
        }
      }
    }

    switch (m.kind) {
      case NavKind.routeName:
        context.goNamed(m.routeName!,
            queryParameters: query, pathParameters: pathVars);
        break;

      case NavKind.routePath:
        var p = m.path!;
        pathVars.forEach((k, v) => p = p.replaceFirst(':$k', v));
        final uri = Uri.parse(p);
        final merged = Uri(
          path: uri.path,
          queryParameters: {
            ...uri.queryParameters,
            ...query,
          },
        );
        context.go(merged.toString());
        break;

      case NavKind.widgetBuilder:
        final builderArgs = {...pathVars, ...query};
        final widget = m.builder!(builderArgs);
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => widget),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final role = user != null ? toAppRole(user.role) : null;

    final candidates = _filterByRole(routeCatalog, role).toList();
    candidates.sort((a, b) => _score(b, _query).compareTo(_score(a, _query)));
    final results = candidates.where((m) => _score(m, _query) > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search pages'),
        backgroundColor: const Color(0xFF14366E),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search by page name or keyword',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (role == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('You are not logged in'),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = results[i];
                return ListTile(
                  leading: Icon(m.icon),
                  title: Text(m.title),
                  subtitle: Text(m.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!m.launchable)
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Chip(label: Text('Context')),
                        ),
                      if (m.params.isNotEmpty)
                        const Chip(label: Text('Params')),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _navigate(context, m),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamDialog extends StatefulWidget {
  final RouteMeta meta;
  const _ParamDialog({required this.meta});

  @override
  State<_ParamDialog> createState() => _ParamDialogState();
}

class _ParamDialogState extends State<_ParamDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final p in widget.meta.params) {
      _controllers[p.key] = TextEditingController(text: p.defaultValue ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter parameters'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.meta.params.map((p) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(
                controller: _controllers[p.key],
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: p.label,
                  helperText:
                      p.isPathParam ? 'Path parameter' : 'Query parameter',
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final values = <String, String>{};
            _controllers.forEach((k, c) => values[k] = c.text);
            Navigator.pop(context, values);
          },
          child: const Text('Go'),
        ),
      ],
    );
  }
}
