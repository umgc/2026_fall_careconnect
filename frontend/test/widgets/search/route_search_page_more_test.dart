// More happy-path tests for RouteSearchPage
// (lib/widgets/search/route_search_page.dart): a path-based entry navigates
// to its route.
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/search/route_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../mock_user_provider.dart';

void main() {
  testWidgets('a path entry opens its route', (tester) async {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const RouteSearchPage()),
        GoRoute(
          path: '/wearables',
          builder: (_, __) => const Scaffold(body: Text('wearables page')),
        ),
      ],
    );
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT')),
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.enterText(find.byType(TextField), 'fitbit');
    await tester.pump();
    await tester.tap(find.text('Wearables'));
    await tester.pumpAndSettle();
    expect(find.text('wearables page'), findsOneWidget);
  });
}
