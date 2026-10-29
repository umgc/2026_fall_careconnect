// Shared harness for single-widget Help tests: the app theme, English
// localizations, and a router whose Help and Settings destinations are stubs,
// so a test can check where a control navigates without building those pages.
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Text shown by a stub destination, e.g. `stub:/settings`.
String helpStubText(String path) => 'stub:$path';

Widget _stub(GoRouterState state) =>
    Scaffold(body: Text(helpStubText(state.uri.toString())));

/// Pumps [builder] at `/under-test`, inside the app theme and localizations.
Future<GoRouter> pumpHelpWidget(
  WidgetTester tester,
  WidgetBuilder builder, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = GoRouter(
    initialLocation: '/under-test',
    routes: [
      GoRoute(path: '/under-test', builder: (context, _) => builder(context)),
      GoRoute(path: '/settings', builder: (_, state) => _stub(state)),
      GoRoute(
        path: HelpRoutes.home,
        builder: (_, state) => _stub(state),
        routes: [
          GoRoute(
              path: HelpRoutes.articlePattern,
              builder: (_, state) => _stub(state)),
          GoRoute(
              path: HelpRoutes.topicPattern,
              builder: (_, state) => _stub(state)),
          GoRoute(
              path: HelpRoutes.glossaryPattern,
              builder: (_, state) => _stub(state)),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
    theme: AppTheme.lightTheme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}
