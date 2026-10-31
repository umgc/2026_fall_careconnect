// Shared harness for the STML page tests. Not a test file itself.

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

/// Mocks secure storage and shared preferences so auth headers resolve
/// without a platform plugin.
void installStmlPlatformMocks() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    },
  );
}

/// Pumps [page] at `/` inside a GoRouter with stub routes for anything the
/// page may push or go to. Each stub renders `route:<path>`.
Future<void> pumpStmlPage(
  WidgetTester tester,
  Widget page, {
  UserProvider? provider,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => page),
      GoRoute(
        path: '/:a',
        builder: (_, s) => Text('route:${s.uri.path}'),
        routes: [
          GoRoute(
            path: ':b',
            builder: (_, s) => Text('route:${s.uri.path}'),
            routes: [
              GoRoute(
                path: ':c',
                builder: (_, s) => Text('route:${s.uri.path}'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: provider ?? MockUserProvider(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

/// Drops only the debug report that a ListTile sits in a coloured
/// DecoratedBox (the patient-selection list rows do this). Restored on
/// teardown.
void ignoreListTileInk() {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.toString().contains(
        'ListTile background color or ink splashes may be invisible')) {
      return;
    }
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}
