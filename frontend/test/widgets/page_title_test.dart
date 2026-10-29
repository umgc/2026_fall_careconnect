import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final titles = <String>[];

  setUp(() {
    titles.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
        titles.add((call.arguments as Map)['label'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('sets route titles on direct load and route replacement',
      (tester) async {
    final router = GoRouter(initialLocation: '/settings', routes: [
      TitledGoRoute(
        title: 'Home',
        path: '/',
        builder: (_, __) => const Scaffold(),
      ),
      TitledGoRoute(
        title: 'Settings',
        path: '/settings',
        builder: (_, __) => const Scaffold(),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(titles.last, 'Settings | CareConnect');
    router.go('/');
    await tester.pumpAndSettle();
    expect(titles.last, 'Home | CareConnect');
  });

  testWidgets('restores title and preserves page state after push and pop',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const PageTitle(
        title: 'Settings',
        child: Scaffold(body: TextField()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this text');
    navigator.currentState!.push(TitledMaterialPageRoute<void>(
      title: 'Profile',
      builder: (_) => const Scaffold(),
    ));
    await tester.pumpAndSettle();
    expect(titles.last, 'Profile | CareConnect');
    titles.clear();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(titles.last, 'Settings | CareConnect');
    expect(find.text('Keep this text'), findsOneWidget);
  });

  testWidgets('only active tab updates title, including after returning',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (_, index, __) => Scaffold(
          body: IndexedStack(index: index, children: [
            for (var i = 0; i < 2; i++)
              PageTitleScope(
                active: i == index,
                child: PageTitle(
                  title: i == 0 ? 'Home' : 'Messages',
                  child: const SizedBox(),
                ),
              ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(titles.last, 'Home | CareConnect');
    selected.value = 1;
    await tester.pumpAndSettle();
    expect(titles.last, 'Messages | CareConnect');
    navigator.currentState!.push(TitledMaterialPageRoute<void>(
      title: 'Profile',
      builder: (_) => const Scaffold(),
    ));
    await tester.pumpAndSettle();
    expect(titles.last, 'Profile | CareConnect');
    titles.clear();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(titles, ['Messages | CareConnect']);
  });

  testWidgets('an inactive ancestor suppresses nested navigator titles',
      (tester) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (_, enabled, __) => PageTitleScope(
          active: enabled,
          child: PageTitleScope(
            active: true,
            child: Navigator(
              onGenerateRoute: (_) => TitledMaterialPageRoute<void>(
                title: 'Invoice List',
                builder: (_) => const Scaffold(),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(titles, isNot(contains('Invoice List | CareConnect')));
    active.value = true;
    await tester.pumpAndSettle();
    expect(titles.last, 'Invoice List | CareConnect');
  });

  testWidgets('restores the title after a dialog without changing page state',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      home: PageTitle(
        title: 'Settings',
        child: Builder(builder: (context) {
          pageContext = context;
          return const Scaffold(body: TextField());
        }),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this text');
    showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(content: Text('Confirm')),
    );
    await tester.pumpAndSettle();
    Navigator.of(pageContext).pop();
    await tester.pumpAndSettle();
    expect(titles.last, 'Settings | CareConnect');
    expect(find.text('Keep this text'), findsOneWidget);
  });
}
