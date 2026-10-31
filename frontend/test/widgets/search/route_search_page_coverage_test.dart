// Coverage tests for RouteSearchPage
// (lib/widgets/search/route_search_page.dart): entries that need
// parameters (the parameter dialog: cancel, blank value, path + query
// values) and widget-builder entries pushed with a MaterialPageRoute.
// Temporary catalog entries are added for the test and removed afterwards.

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/search/route_registry.dart';
import 'package:care_connect_app/widgets/search/route_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../mock_user_provider.dart';

const _pathEntry = RouteMeta(
  title: 'Zzqx Path Params',
  description: 'Test entry with a path and a query param',
  keywords: ['zzqx'],
  kind: NavKind.routePath,
  path: '/zzqx/:itemId?tab=one',
  roles: {AppRole.CAREGIVER},
  params: [
    RouteParam(key: 'itemId', label: 'Item id', isPathParam: true),
    RouteParam(key: 'filter', label: 'Filter', defaultValue: 'all'),
  ],
);

final _builderEntry = RouteMeta(
  title: 'Zzqx Builder Page',
  description: 'Test entry built from a widget builder',
  keywords: const ['zzqx'],
  kind: NavKind.widgetBuilder,
  builder: (args) => Scaffold(body: Text('built ${args['note']}')),
  roles: const {AppRole.CAREGIVER},
  params: const [RouteParam(key: 'note', label: 'Note')],
);

Widget _app() {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (_, __) => const RouteSearchPage()),
      GoRoute(
        path: '/zzqx/:itemId',
        builder: (_, s) => Scaffold(
          body: Text(
              'item ${s.pathParameters['itemId']} ${s.uri.queryParameters['tab']} ${s.uri.queryParameters['filter']}'),
        ),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER')),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    routeCatalog.add(_pathEntry);
    routeCatalog.add(_builderEntry);
  });

  tearDown(() {
    routeCatalog.remove(_pathEntry);
    routeCatalog.remove(_builderEntry);
  });

  Future<void> search(WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'zzqx');
    await tester.pump();
  }

  testWidgets('entries with params show a Params chip', (tester) async {
    await search(tester);
    expect(find.text('Zzqx Path Params'), findsOneWidget);
    expect(find.text('Zzqx Builder Page'), findsOneWidget);
    expect(find.text('Params'), findsNWidgets(2));
  });

  testWidgets('cancelling the parameter dialog stays on search',
      (tester) async {
    await search(tester);
    await tester.tap(find.text('Zzqx Path Params'));
    await tester.pumpAndSettle();
    expect(find.text('Enter parameters'), findsOneWidget);
    expect(find.text('Path parameter'), findsOneWidget);
    expect(find.text('Query parameter'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Enter parameters'), findsNothing);
    expect(find.text('Search pages'), findsOneWidget);
  });

  testWidgets('a blank parameter value aborts navigation', (tester) async {
    await search(tester);
    await tester.tap(find.text('Zzqx Path Params'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Search pages'), findsOneWidget);
  });

  testWidgets('path and query values are merged into the route',
      (tester) async {
    await search(tester);
    await tester.tap(find.text('Zzqx Path Params'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Item id'), ' 42 ');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('item 42 one all'), findsOneWidget);
  });

  testWidgets('widget-builder entries are pushed with their arguments',
      (tester) async {
    await search(tester);
    await tester.tap(find.text('Zzqx Builder Page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Note'), 'hello');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('built hello'), findsOneWidget);
  });
}
