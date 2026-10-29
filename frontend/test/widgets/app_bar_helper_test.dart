// Tests for AppBarHelper from lib/widgets/app_bar_helper.dart.
// Static utility — creates an AppBar with consistent styling.
// Tested by using it inside a Scaffold within a MaterialApp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';

Widget _wrap({
  String title = 'Test Title',
  List<Widget>? additionalActions,
  Widget? leading,
  PreferredSizeWidget? bottom,
  bool centerTitle = false,
  bool automaticallyImplyLeading = true,
}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBarHelper.createAppBar(
            context,
            title: title,
            additionalActions: additionalActions,
            leading: leading,
            bottom: bottom,
            centerTitle: centerTitle,
            automaticallyImplyLeading: automaticallyImplyLeading,
          ),
          body: const SizedBox(),
        ),
      ),
    );

void main() {
  group('AppBarHelper.createAppBar', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows the given title', (tester) async {
      await tester.pumpWidget(_wrap(title: 'My Page'));
      expect(find.text('My Page'), findsOneWidget);
    });

    testWidgets('shows back button by default', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('uses custom leading widget when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        leading: const Icon(Icons.menu),
      ));
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('shows additional actions when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows bottom widget when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) => Scaffold(
                appBar: AppBarHelper.createAppBar(
                  context,
                  title: 'Tabs',
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: 'Tab1'),
                      Tab(text: 'Tab2'),
                    ],
                  ),
                ),
                body: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Tab1'), findsOneWidget);
      expect(find.text('Tab2'), findsOneWidget);
    });

    testWidgets('centerTitle is false by default', (tester) async {
      await tester.pumpWidget(_wrap());
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isFalse);
    });

    testWidgets('centerTitle can be set to true', (tester) async {
      await tester.pumpWidget(_wrap(centerTitle: true));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isTrue);
    });

    testWidgets('automaticallyImplyLeading defaults to true', (tester) async {
      await tester.pumpWidget(_wrap());
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isTrue);
    });

    testWidgets('automaticallyImplyLeading can be set to false',
        (tester) async {
      await tester.pumpWidget(_wrap(automaticallyImplyLeading: false));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isFalse);
    });
  });
  group('navigation history regression #316', () {
    Widget page(BuildContext context, String title) =>
        Scaffold(appBar: AppBarHelper.createAppBar(context, title: title));

    testWidgets('direct Calendar Back makes dashboard the root', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/calendar',
        routes: [
          GoRoute(path: '/calendar', builder: (c, s) => page(c, 'Calendar')),
          GoRoute(path: '/dashboard', builder: (c, s) => page(c, 'Home')),
          GoRoute(path: '/analytics', builder: (c, s) => page(c, 'Analytics')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Voice navigation uses go(), so Calendar has no page to pop.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(
        router.canPop(),
        isFalse,
        reason: 'Home must not retain Calendar underneath it',
      );

      // A subsequent detail page must return to Home.
      router.push('/analytics');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Calendar'), findsNothing);
    });

    testWidgets('pushed Calendar Back preserves its actual caller', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(path: '/dashboard', builder: (c, s) => page(c, 'Home')),
          GoRoute(path: '/calendar', builder: (c, s) => page(c, 'Calendar')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.push('/calendar');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });
  });
}
