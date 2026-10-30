// RouteSearchPage navigation: a context-only page explains it cannot be
// opened from search, and a named-route entry navigates by name.

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/search/route_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../mock_user_provider.dart';

Widget _app() {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (_, __) => const RouteSearchPage()),
      GoRoute(
        path: '/invoices',
        name: 'invoiceDashboard',
        builder: (_, __) => const Scaffold(body: Text('invoice page')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER')),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('context-only pages cannot be opened from search',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'chime');
    await tester.pump();
    expect(find.text('Context'), findsOneWidget);
    await tester.tap(find.text('Video Call'));
    await tester.pump();
    expect(
      find.text(
        'This page needs context and cannot be opened directly from search',
      ),
      findsOneWidget,
    );
  });

  testWidgets('named routes are opened by name', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pump();
    await tester.tap(find.text('Invoice Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('invoice page'), findsOneWidget);
  });
}
