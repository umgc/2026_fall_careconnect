import 'package:care_connect_app/pages/epic_linked_return_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router(String? status) => GoRouter(
      initialLocation: '/epic-linked',
      routes: [
        GoRoute(
          path: '/epic-linked',
          builder: (_, __) => EpicLinkedReturnPage(status: status),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Settings Screen')),
        ),
      ],
    );

void main() {
  testWidgets('ok status shows connected copy and auto-redirects',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router('ok')));
    await tester.pump();
    expect(find.text('Epic connected'), findsOneWidget);
    expect(
      find.text(
        'Your clinical records are importing in the background and will help answer Ask AI.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text('Return to Settings'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Settings Screen'), findsOneWidget);
  });

  testWidgets('error status shows retry copy and button navigates',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: _router('error')),
    );
    await tester.pump();
    expect(find.text('Epic connection was not completed'), findsOneWidget);
    expect(
      find.text('You can try connecting again from Settings.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.tap(find.text('Return to Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings Screen'), findsOneWidget);
  });

  testWidgets('null status renders error state', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router(null)));
    await tester.pump();
    expect(find.text('Epic connection was not completed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
