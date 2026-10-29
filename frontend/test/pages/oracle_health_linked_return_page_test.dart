import 'package:care_connect_app/pages/oracle_health_linked_return_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late GoRouter router;

  Widget buildTestApp(String? status) {
    router = GoRouter(
      initialLocation: '/oracle-health-linked',
      routes: [
        GoRoute(
          path: '/oracle-health-linked',
          builder: (context, state) =>
              OracleHealthLinkedReturnPage(status: status),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('Test Settings Page')),
        ),
      ],
    );

    return MaterialApp.router(routerConfig: router);
  }

  tearDown(() {
    router.dispose();
  });

  testWidgets('displays success after successful authorization', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp('ok'));

    expect(find.text('Oracle Health connected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text('Return to Settings'), findsOneWidget);
  });

  testWidgets('displays failure after unsuccessful authorization', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp('error'));

    expect(
      find.text('Oracle Health connection was not completed'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('missing authorization status is not treated as success', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp(null));

    expect(
      find.text('Oracle Health connection was not completed'),
      findsOneWidget,
    );
  });

  testWidgets('Return to Settings button navigates immediately', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp('ok'));

    await tester.tap(find.text('Return to Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Test Settings Page'), findsOneWidget);
    expect(find.text('Oracle Health connected'), findsNothing);
  });

  testWidgets('automatically returns to Settings after three seconds', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp('ok'));

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Test Settings Page'), findsOneWidget);
    expect(find.text('Oracle Health connected'), findsNothing);
  });
}
