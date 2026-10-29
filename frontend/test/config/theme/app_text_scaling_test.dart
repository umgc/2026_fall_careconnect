// Widget tests for lib/config/theme/app_text_scaling.dart: Help routes keep the
// platform's text size (SC 1.4.4); every other route stays within 0.8x-1.2x.
import 'package:care_connect_app/config/theme/app_text_scaling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Records the text scale each page sees.
class _ScaleProbe extends StatelessWidget {
  const _ScaleProbe(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Text('$name ${MediaQuery.textScalerOf(context).scale(16) / 16}'));
}

Future<GoRouter> _pump(WidgetTester tester, double platformScale,
    {String initial = '/dashboard'}) async {
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
        path: '/dashboard', builder: (_, __) => const _ScaleProbe('dashboard')),
    GoRoute(
      path: '/help',
      builder: (_, __) => const _ScaleProbe('help'),
      routes: [
        GoRoute(
            path: 'glossary',
            builder: (_, __) => const _ScaleProbe('glossary')),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(platformScale)),
      child: AppTextScaling(router: router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('outside Help, a large platform text size is capped at 1.2x',
      (tester) async {
    await _pump(tester, 2.0);
    expect(find.text('dashboard 1.2'), findsOneWidget);
  });

  testWidgets('outside Help, a small platform text size is raised to 0.8x',
      (tester) async {
    await _pump(tester, 0.5);
    expect(find.text('dashboard 0.8'), findsOneWidget);
  });

  testWidgets('Help and its sub-pages keep the full platform text size',
      (tester) async {
    final router = await _pump(tester, 2.0, initial: '/help');
    expect(find.text('help 2.0'), findsOneWidget);

    router.go('/help/glossary');
    await tester.pumpAndSettle();
    expect(find.text('glossary 2.0'), findsOneWidget);
  });

  testWidgets('leaving Help restores the cap', (tester) async {
    final router = await _pump(tester, 2.0, initial: '/help');
    router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('dashboard 1.2'), findsOneWidget);
  });
}
