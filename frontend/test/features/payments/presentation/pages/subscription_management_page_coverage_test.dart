// Coverage tests for SubscriptionManagementPage
// (lib/features/payments/presentation/pages/subscription_management_page.dart):
// the alternative subscription payload shapes (single Payment-format object,
// object without id, list without an active entry using customer /
// customerId keys), plan matching fallbacks, status colours, epoch-second
// dates and picking a different plan in the radio group.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/payments/presentation/pages/subscription_management_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

final List<Map<String, dynamic>> _threePlans = [
  {'id': '1', 'nickname': 'Free Plan', 'amount': 0, 'active': true},
  {'id': '2', 'nickname': 'Standard Plan', 'amount': 1999, 'active': true},
  {'id': '3', 'nickname': 'Premium Plan', 'amount': 2999, 'active': false},
];

class _Backend {
  _Backend(this.subscriptionBody, {this.plans});
  final Object subscriptionBody;
  final List<Map<String, dynamic>>? plans;

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.contains('/plans')) {
      return http.Response(jsonEncode(plans ?? _threePlans), 200);
    }
    return http.Response(jsonEncode(subscriptionBody), 200);
  }
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final client = MockClient(backend.handle);
  ApiService.debugSetHttpClient(client);
  final router = GoRouter(
    routes: [
      GoRoute(
          path: '/', builder: (_, __) => const SubscriptionManagementPage()),
    ],
  );
  addTearDown(router.dispose);
  await http.runWithClient(() async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(),
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => client);
}

Color? _badgeColor(WidgetTester tester) {
  for (final e in find.byType(Container).evaluate()) {
    final w = e.widget as Container;
    final d = w.decoration;
    if (d is BoxDecoration &&
        d.borderRadius == BorderRadius.circular(16) &&
        (d.color == AppTheme.error ||
            d.color == AppTheme.success ||
            d.color == AppTheme.warning)) {
      return d.color;
    }
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final session = jsonEncode({'id': 1, 'token': 'mock_token'});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && key == 'user_session') return session;
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  testWidgets('single Payment-format object matching a plan by id',
      (tester) async {
    await _pump(
      tester,
      _Backend({
        'id': 'sub_9',
        'customer': 'cus_9',
        'status': 'canceled',
        'current_period_start': '1234567',
        'current_period_end': 'not-a-date',
        'plan': {'id': '3', 'nickname': 'Premium Plan', 'amount': 2999},
      }),
    );
    expect(tester.takeException(), isNull);
    // Epoch seconds that DateTime.parse rejects are formatted from int.
    expect(find.textContaining('1970'), findsWidgets);
    // Unparseable dates are shown as-is.
    expect(find.textContaining('not-a-date'), findsWidgets);
    expect(_badgeColor(tester), AppTheme.error);
  });

  testWidgets('single object with an unknown plan falls back to the second',
      (tester) async {
    await _pump(
      tester,
      _Backend({
        'id': 'sub_10',
        'status': 'paused',
        'plan': {'id': 'zzz', 'nickname': 'Legacy', 'amount': 100},
      }),
    );
    expect(tester.takeException(), isNull);
    final group =
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first);
    expect(group.groupValue, '2');
  });

  testWidgets('an object without an id means no subscription', (tester) async {
    await _pump(tester, _Backend({'unexpected': true}));
    expect(tester.takeException(), isNull);
    final group =
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first);
    expect(group.groupValue, '1');
  });

  testWidgets('a list without an active subscription reads customerId',
      (tester) async {
    await _pump(
      tester,
      _Backend([
        {'id': 1, 'status': 'canceled', 'customerId': 'cus_A'},
      ]),
    );
    expect(tester.takeException(), isNull);
    final group =
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first);
    expect(group.groupValue, '1');
  });

  testWidgets('a list without an active subscription reads customer',
      (tester) async {
    await _pump(
      tester,
      _Backend([
        {'id': 1, 'status': 'past_due', 'customer': 'cus_B'},
      ]),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RadioGroup<String>), findsWidgets);
  });

  testWidgets('one plan only: an unmatched active subscription uses it',
      (tester) async {
    await _pump(
      tester,
      _Backend(
        [
          {
            'id': '1',
            'paymentSubscriptionId': 'sub_1',
            'paymentCustomerId': 'cus_1',
            'status': 'active',
            'planId': 'unknown',
            'planName': 'Mystery',
            'priceCents': 500,
          },
        ],
        plans: [
          {'id': 'only', 'nickname': 'Solo', 'amount': 500, 'active': true},
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    final group =
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first);
    expect(group.groupValue, 'only');
    expect(_badgeColor(tester), AppTheme.success);
  });

  testWidgets('choosing another plan in the radio group selects it',
      (tester) async {
    await _pump(tester, _Backend({'unexpected': true}));
    final finder = find.byType(RadioGroup<String>).first;
    tester.widget<RadioGroup<String>>(finder).onChanged('3');
    await tester.pumpAndSettle();
    expect(
        tester.widget<RadioGroup<String>>(
            find.byType(RadioGroup<String>).first),
        isA<RadioGroup<String>>()
            .having((g) => g.groupValue, 'groupValue', '3'));
  });
}
