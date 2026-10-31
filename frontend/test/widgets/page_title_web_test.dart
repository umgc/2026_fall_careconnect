@TestOn('browser')
library;

// Browser-only verification of the title exposed to assistive technology.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('document.title follows navigation and restores after Back',
      (tester) async {
    // Let this channel reach the web engine instead of the test binding's mock.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    final router = GoRouter(routes: [
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
    expect(html.document.title, 'Home | CareConnect');
    router.push<void>('/settings');
    await tester.pumpAndSettle();
    expect(html.document.title, 'Settings | CareConnect');
    router.pop();
    await tester.pumpAndSettle();
    expect(html.document.title, 'Home | CareConnect');
  });
}
