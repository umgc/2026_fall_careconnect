import 'package:care_connect_app/features/ui_preview/ui_preview_frame.dart';
import 'package:care_connect_app/features/ui_preview/ui_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders preview banner, stub frame and goes back',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/ui-preview',
      routes: [
        GoRoute(
          path: '/ui-preview',
          builder: (_, __) => const UiPreviewScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('Dashboard Screen')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('New CareConnect UI (preview)'), findsOneWidget);
    expect(find.textContaining('Prototype only'), findsOneWidget);
    expect(find.byType(UiPreviewFrame), findsOneWidget);
    expect(
      find.text('UI preview is available on the web build'),
      findsOneWidget,
    );
    expect(find.textContaining('/ui-preview/index.html'), findsOneWidget);
    expect(find.byIcon(Icons.web_asset), findsOneWidget);
    expect(find.text('Open fullscreen'), findsNothing);

    await tester.tap(find.byTooltip('Back to dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard Screen'), findsOneWidget);
  });
}
