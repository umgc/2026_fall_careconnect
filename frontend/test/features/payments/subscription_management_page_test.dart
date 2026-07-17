// Tests for SubscriptionManagementPage
// (lib/features/payments/presentation/pages/subscription_management_page.dart).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/features/payments/presentation/pages/subscription_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

// ---------------------------------------------------------------------------
// Global mutable mock handler
// ---------------------------------------------------------------------------

/// The current request handler. Tests swap this before pumping the widget.
late Future<http.Response> Function(http.Request) _currentHandler;

/// A single [MockClient] whose handler delegates to [_currentHandler].
/// Because ApiService._httpClient is a static final, the first Client()
/// instantiated in a runWithClient zone becomes the permanent instance.
/// We ensure that instance delegates every call to our mutable handler.
final MockClient _globalMockClient = MockClient((request) => _currentHandler(request));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap({MockUserProvider? userProvider}) {
  final provider = userProvider ?? MockUserProvider();
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: SubscriptionManagementPage()),
  );
}

Future<void> _pumpN(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _setupPlatformChannels() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      if (call.method == 'read') return null;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    },
  );
}

void _setupPlatformChannelsWithSession() {
  SharedPreferences.setMockInitialValues({});
  final sessionJson = jsonEncode({'id': 1, 'token': 'mock_token'});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') {
        return <String, String>{
          'user_session': sessionJson,
          'jwt_token': 'mock_token',
        };
      }
      if (call.method == 'containsKey') return true;
      if (call.method == 'read') {
        final key = call.arguments['key'];
        if (key == 'user_session') return sessionJson;
        if (key == 'jwt_token') return 'mock_token';
        return null;
      }
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    },
  );
}

// ---------------------------------------------------------------------------
// Default mock data
// ---------------------------------------------------------------------------

final _defaultPlans = [
  {
    'id': 'price_basic',
    'priceId': 'price_basic',
    'nickname': 'Basic Plan',
    'amount': 999,
    'interval': 'month',
    'active': true,
  },
  {
    'id': 'price_standard',
    'priceId': 'price_standard',
    'nickname': 'Standard Plan',
    'amount': 1999,
    'interval': 'month',
    'active': true,
  },
  {
    'id': 'price_premium',
    'priceId': 'price_premium',
    'nickname': 'Premium Plan',
    'amount': 2999,
    'interval': 'month',
    'active': true,
  },
];

final _defaultActiveSubscription = [
  {
    'id': '1',
    'stripeSubscriptionId': 'sub_123',
    'stripeCustomerId': 'cus_123',
    'status': 'active',
    'startedAt': '1700000000',
    'currentPeriodEnd': '1702592000',
    'planId': 'price_standard',
    'planName': 'Standard Plan',
    'priceCents': 1999,
  },
];

/// Sentinel to distinguish "not provided" from explicit null.
const _notProvided = '__NOT_PROVIDED__';

/// Sets [_currentHandler] to return configurable responses.
void _setMockResponses({
  int subscriptionStatus = 200,
  dynamic subscriptionBody = _notProvided,
  int plansStatus = 200,
  dynamic plansBody = _notProvided,
  int cancelStatus = 200,
  dynamic cancelBody,
}) {
  final subBody =
      subscriptionBody == _notProvided ? _defaultActiveSubscription : subscriptionBody;
  final pBody = plansBody == _notProvided ? _defaultPlans : plansBody;

  _currentHandler = (request) async {
    final path = request.url.path;
    if (path.contains('/plans')) {
      return http.Response(jsonEncode(pBody), plansStatus);
    }
    if (path.contains('/cancel')) {
      return http.Response(
        jsonEncode(cancelBody ?? {'message': 'Cancelled'}),
        cancelStatus,
      );
    }
    return http.Response(jsonEncode(subBody), subscriptionStatus);
  };
}

/// Pump widget inside runWithClient to ensure the static _httpClient
/// initializes with our global mock (only needed for the very first test).
Future<void> _pumpInZone(WidgetTester tester, Widget widget) async {
  await http.runWithClient(() async {
    await tester.pumpWidget(widget);
  }, () => _globalMockClient);
}

/// Pump frames inside runWithClient zone.
Future<void> _pumpNInZone(WidgetTester tester, int n) async {
  await http.runWithClient(() async {
    await _pumpN(tester, n);
  }, () => _globalMockClient);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  // =========================================================================
  // Group 1: Initial render / loading state
  // =========================================================================
  group('SubscriptionManagementPage - initial render', () {
    setUp(() {
      _setupPlatformChannels();
      _setMockResponses();
    });

    testWidgets('renders without crashing', (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.byType(SubscriptionManagementPage), findsOneWidget);
    });

    testWidgets('shows Subscription Management in AppBar', (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.text('Subscription Management'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold and AppBar', (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows Center widget while loading', (tester) async {
      await _pumpInZone(tester, _wrap());
      expect(find.byType(Center), findsWidgets);
    });
  });

  // =========================================================================
  // Group 2: Error state (no session -> API throws)
  // =========================================================================
  group('SubscriptionManagementPage - error state', () {
    setUp(() {
      _setupPlatformChannels(); // no session -> getCurrentSubscription throws
      _setMockResponses();
    });

    testWidgets('shows error state after API failure', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Error Loading Subscription'), findsOneWidget);
    });

    testWidgets('shows error icon in error state', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error message text', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(
        find.text(
          'Error loading subscription data. Please check your connection and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Try Again button in error state', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('Try Again button can be tapped', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final tryAgainButton = find.text('Try Again');
      expect(tryAgainButton, findsOneWidget);

      // Tap the button - it calls _loadSubscriptionData again
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Try Again')).onPressed!();
      // After pumping, error state re-appears (still no session)
      await _pumpNInZone(tester, 20);
      expect(find.text('Error Loading Subscription'), findsOneWidget);
    });

    testWidgets('no loading indicator after error state resolves',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // =========================================================================
  // Group 3: Content state - No subscription (404)
  // =========================================================================
  group('SubscriptionManagementPage - no subscription (404)', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses(subscriptionStatus: 404);
    });

    testWidgets('shows No Active Subscription when 404', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('No Active Subscription'), findsOneWidget);
    });

    testWidgets('shows prompt to choose plan when no subscription',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(
        find.text('Choose a plan below to get started with CareConnect'),
        findsOneWidget,
      );
    });

    testWidgets('shows Available Plans heading', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Available Plans'), findsOneWidget);
    });

    testWidgets('shows plan cards with Subscribe Now button', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Subscribe Now'), findsWidgets);
    });

    testWidgets('shows Current Subscription header', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Current Subscription'), findsOneWidget);
    });

    testWidgets('shows credit card icon', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.credit_card), findsOneWidget);
    });

    testWidgets('shows info icon when no subscription', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.info_outline), findsWidgets);
    });
  });

  // =========================================================================
  // Group 4: Active subscription with plans
  // =========================================================================
  group('SubscriptionManagementPage - active subscription', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses();
    });

    testWidgets('shows current subscription plan name', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Standard Plan'), findsWidgets);
    });

    testWidgets('shows subscription status badge', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('shows Amount Paid label', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Amount Paid'), findsOneWidget);
    });

    testWidgets('shows Next Billing label', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Next Billing'), findsOneWidget);
    });

    testWidgets('shows Current Period info row', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Current Period:'), findsOneWidget);
    });

    testWidgets('shows Cancel Subscription button for active sub',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Cancel Subscription'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('shows star icon for current plan name', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('shows Available Plans section', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Available Plans'), findsOneWidget);
    });

    testWidgets('shows plan names from API', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Basic Plan'), findsWidgets);
      expect(find.text('Premium Plan'), findsWidgets);
    });

    testWidgets('shows Current Active Plan button for matched plan',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Current Active Plan'), findsOneWidget);
    });

    testWidgets('shows Switch to This Plan for non-current plans',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Switch to This Plan'), findsWidgets);
    });

    testWidgets('shows check_circle_outline for plan features',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    });

    testWidgets('shows Radio buttons for plans', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byType(Radio<String>), findsWidgets);
    });

    testWidgets('shows plan features for basic plan', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Core monitoring features'), findsWidgets);
      expect(find.text('Email support'), findsWidgets);
    });

    testWidgets('shows premium plan features', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Unlimited patients'), findsOneWidget);
      expect(
        find.text('AI-powered insights and recommendations'),
        findsOneWidget,
      );
    });

    testWidgets('shows formatted price for plans', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('\$9.99'), findsWidgets);
      expect(find.text('\$19.99'), findsWidgets);
      expect(find.text('\$29.99'), findsWidgets);
    });

    testWidgets('shows /month interval for plans', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('/month'), findsWidgets);
    });

    testWidgets('shows event icon for period info', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.event), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 5: Single Map subscription response
  // =========================================================================
  group('SubscriptionManagementPage - single object subscription', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_single',
          'status': 'active',
          'customer': 'cus_single',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_standard',
            'nickname': 'Standard Plan',
            'amount': 1999,
            'interval': 'month',
          },
        },
      );
    });

    testWidgets('handles subscription as single Map with id',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Standard Plan'), findsWidgets);
      expect(find.text('ACTIVE'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 6: Null/empty subscription data
  // =========================================================================
  group('SubscriptionManagementPage - null/empty subscription body', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('shows no subscription when data is null', (tester) async {
      _setMockResponses(subscriptionBody: null);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('No Active Subscription'), findsOneWidget);
    });

    testWidgets('shows no subscription when list has no active sub',
        (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_1',
            'stripeCustomerId': 'cus_1',
            'status': 'canceled',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('No Active Subscription'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 7: Plans API fallback
  // =========================================================================
  group('SubscriptionManagementPage - plans API fallback', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('falls back to default plans when plans API returns 500',
        (tester) async {
      _setMockResponses(
        plansStatus: 500,
        plansBody: {'error': 'Server error'},
        subscriptionStatus: 404,
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Available Plans'), findsOneWidget);
      expect(find.text('Basic Plan'), findsWidgets);
    });

    testWidgets(
        'falls back to default plans when plans response is not a list',
        (tester) async {
      _setMockResponses(
        plansBody: {'not': 'a list'},
        subscriptionStatus: 404,
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Available Plans'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 8: Subscription error status codes
  // =========================================================================
  group('SubscriptionManagementPage - non-200/404 subscription status', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('shows error for 500 subscription response', (tester) async {
      _setMockResponses(subscriptionStatus: 500);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Error Loading Subscription'), findsOneWidget);
      expect(
        find.textContaining('Failed to load subscription: 500'),
        findsOneWidget,
      );
    });

    testWidgets('shows error for 403 subscription response', (tester) async {
      _setMockResponses(subscriptionStatus: 403);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Error Loading Subscription'), findsOneWidget);
      expect(
        find.textContaining('Failed to load subscription: 403'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // Group 9: Cancel subscription dialog flow
  // =========================================================================
  group('SubscriptionManagementPage - cancel subscription dialog', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses();
    });

    testWidgets('tapping Cancel Subscription shows first dialog',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel Subscription')).onPressed!();
      await tester.pump();

      expect(find.text('Cancel Subscription'), findsWidgets);
      expect(
        find.textContaining('Warning: Cancelling your subscription'),
        findsOneWidget,
      );
      expect(find.text('NO, KEEP MY PLAN'), findsOneWidget);
      expect(find.text('YES, CANCEL'), findsOneWidget);
    });

    testWidgets('dismissing first cancel dialog keeps subscription',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel Subscription')).onPressed!();
      await tester.pump();

      tester.widget<TextButton>(find.widgetWithText(TextButton, 'NO, KEEP MY PLAN')).onPressed!();
      await tester.pump();

      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets(
        'confirming first cancel dialog shows second confirmation dialog',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel Subscription')).onPressed!();
      await tester.pump();

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'YES, CANCEL')).onPressed!();
      await tester.pump();

      expect(find.text('Final Confirmation'), findsOneWidget);
      expect(
        find.textContaining('This action cannot be undone'),
        findsOneWidget,
      );
      expect(find.text('NO, GO BACK'), findsOneWidget);
      expect(find.text('YES, CANCEL MY SUBSCRIPTION'), findsOneWidget);
    });

    testWidgets('dismissing second cancel dialog does not cancel',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel Subscription')).onPressed!();
      await tester.pump();

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'YES, CANCEL')).onPressed!();
      await tester.pump();

      tester.widget<TextButton>(find.widgetWithText(TextButton, 'NO, GO BACK')).onPressed!();
      await tester.pump();

      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('first dialog shows warning about effects', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cancel Subscription')).onPressed!();
      await tester.pump();

      expect(
        find.textContaining('You will be automatically logged out'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Your access to the application will be immediately removed',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('You will not receive a refund'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // Group 10: Change plan dialog
  // =========================================================================
  group('SubscriptionManagementPage - change plan dialog', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses();
    });

    testWidgets('tapping Switch to This Plan shows confirmation dialog',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final switchButtons = find.text('Switch to This Plan');
      expect(switchButtons, findsWidgets);
      // Scroll the first Switch button into view before tapping
      await tester.ensureVisible(switchButtons.first);
      await tester.pump();
      tester.widget<ElevatedButton>(switchButtons.first).onPressed!();
      await _pumpN(tester, 5);

      expect(find.text('Confirm Plan Change'), findsOneWidget);
      expect(
        find.textContaining(
          'You are about to change your subscription plan',
        ),
        findsOneWidget,
      );
      expect(find.text('Current Plan (to be cancelled)'), findsOneWidget);
      expect(find.text('New Plan (to be activated)'), findsOneWidget);
      expect(find.text('What happens next:'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('CONFIRM CHANGE'), findsOneWidget);
    });

    testWidgets('cancelling change plan dialog keeps current plan',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final switchButtons = find.text('Switch to This Plan');
      await tester.ensureVisible(switchButtons.first);
      await tester.pump();
      tester.widget<ElevatedButton>(switchButtons.first).onPressed!();
      await _pumpN(tester, 5);

      tester.widget<TextButton>(find.widgetWithText(TextButton, 'CANCEL')).onPressed!();
      await tester.pump();

      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('change plan dialog shows swap icon', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final switchButtons = find.text('Switch to This Plan');
      await tester.ensureVisible(switchButtons.first);
      await tester.pump();
      tester.widget<ElevatedButton>(switchButtons.first).onPressed!();
      await _pumpN(tester, 5);

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('change plan dialog shows info about steps', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final switchButtons = find.text('Switch to This Plan');
      await tester.ensureVisible(switchButtons.first);
      await tester.pump();
      tester.widget<ElevatedButton>(switchButtons.first).onPressed!();
      await _pumpN(tester, 5);

      expect(
        find.textContaining('Your current subscription will be cancelled'),
        findsOneWidget,
      );
      expect(
        find.textContaining('New plan starts immediately after payment'),
        findsOneWidget,
      );
    });

    testWidgets('change plan dialog shows add and remove circle icons',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final switchButtons = find.text('Switch to This Plan');
      await tester.ensureVisible(switchButtons.first);
      await tester.pump();
      tester.widget<ElevatedButton>(switchButtons.first).onPressed!();
      await _pumpN(tester, 5);

      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 11: Plan selection
  // =========================================================================
  group('SubscriptionManagementPage - plan selection', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses(subscriptionStatus: 404);
    });

    testWidgets('tapping plan card selects it', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);

      final premiumPlan = find.text('Premium Plan');
      expect(premiumPlan, findsWidgets);
      tester.widget<ElevatedButton>(premiumPlan.last).onPressed!();
      await tester.pump();

      expect(find.byType(Radio<String>), findsWidgets);
    });

    testWidgets('Subscribe Now shown instead of Switch when no active sub',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Subscribe Now'), findsWidgets);
      expect(find.text('Switch to This Plan'), findsNothing);
    });
  });

  // =========================================================================
  // Group 12: cancelAtPeriodEnd
  // =========================================================================
  group('SubscriptionManagementPage - cancelAtPeriodEnd', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_cancel',
          'status': 'active',
          'customer': 'cus_123',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': true,
          'plan': {
            'id': 'price_basic',
            'nickname': 'Basic Plan',
            'amount': 999,
            'interval': 'month',
          },
        },
      );
    });

    testWidgets('shows cancellation warning', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(
        find.text(
          'Subscription will be cancelled at the end of current period',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_outlined), findsOneWidget);
    });

    testWidgets('does not show Cancel Subscription button', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    });

    testWidgets('shows CANCELING AT PERIOD END status', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('CANCELING AT PERIOD END'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 13: Trialing status
  // =========================================================================
  group('SubscriptionManagementPage - trialing status', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      // Use Map format (not List) so the source code does not filter by
      // status == 'active'. The Map path at line 190 creates the subscription
      // directly regardless of status.
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_trial',
          'status': 'trialing',
          'customer': 'cus_trial',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_standard',
            'nickname': 'Standard Plan',
            'amount': 1999,
            'interval': 'month',
          },
        },
      );
    });

    testWidgets('shows TRIAL status', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('TRIAL'), findsOneWidget);
    });

    testWidgets('trialing subscription shows Cancel button', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Cancel Subscription'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 14: Empty plans
  // =========================================================================
  group('SubscriptionManagementPage - empty plans', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses(plansBody: [], subscriptionStatus: 404);
    });

    testWidgets('shows no plans available message', (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(
        find.text('No subscription plans are currently available'),
        findsOneWidget,
      );
      expect(
        find.text('Please check back later or contact support'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // Group 15: Date formatting
  // =========================================================================
  group('SubscriptionManagementPage - date formatting', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('shows N/A for empty timestamps', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_empty',
            'stripeCustomerId': 'cus_123',
            'status': 'active',
            'startedAt': '',
            'currentPeriodEnd': '',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('N/A'), findsWidgets);
    });

    testWidgets('handles non-numeric timestamp gracefully', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_bad',
            'stripeCustomerId': 'cus_123',
            'status': 'active',
            'startedAt': 'not_a_number',
            'currentPeriodEnd': 'also_not_a_number',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.textContaining('not_a_number'), findsWidgets);
    });

    testWidgets('formats valid Unix timestamps', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_date',
            'stripeCustomerId': 'cus_123',
            'status': 'active',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      // Valid timestamps should not show raw numbers
      expect(find.text('1700000000'), findsNothing);
      expect(find.text('1702592000'), findsNothing);
    });
  });

  // =========================================================================
  // Group 16: Customer ID extraction
  // =========================================================================
  group('SubscriptionManagementPage - customer ID extraction', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('extracts from stripeCustomerId', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_s',
            'stripeCustomerId': 'cus_stripe',
            'status': 'active',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('extracts from customer field', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_c',
            'customer': 'cus_from_customer',
            'status': 'active',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('extracts from customerId field', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_ci',
            'customerId': 'cus_from_customerId',
            'status': 'active',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('extracts from first element if no active sub',
        (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_inactive',
            'stripeCustomerId': 'cus_first',
            'status': 'canceled',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_basic',
            'planName': 'Basic Plan',
            'priceCents': 999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('No Active Subscription'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 17: Plan matching
  // =========================================================================
  group('SubscriptionManagementPage - plan matching', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('matches plan by ID', (tester) async {
      _setMockResponses();
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Current Active Plan'), findsOneWidget);
    });

    testWidgets('matches plan by price as fallback', (tester) async {
      _setMockResponses(
        subscriptionBody: [
          {
            'id': '1',
            'stripeSubscriptionId': 'sub_pm',
            'stripeCustomerId': 'cus_123',
            'status': 'active',
            'startedAt': '1700000000',
            'currentPeriodEnd': '1702592000',
            'planId': 'price_xyz',
            'planName': 'Some Unknown Plan',
            'priceCents': 2999,
          }
        ],
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Current Active Plan'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 18: Plan nickname features
  // =========================================================================
  group('SubscriptionManagementPage - plan nickname features', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('standard plan shows standard features', (tester) async {
      _setMockResponses(subscriptionStatus: 404);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Up to 10 patients'), findsOneWidget);
      expect(find.text('Advanced monitoring'), findsOneWidget);
      expect(find.text('Full analytics dashboard'), findsOneWidget);
      expect(find.text('Priority email support'), findsOneWidget);
    });

    testWidgets('basic plan shows basic features', (tester) async {
      _setMockResponses(subscriptionStatus: 404);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Up to 3 patients'), findsOneWidget);
      expect(find.text('Basic analytics'), findsOneWidget);
    });

    testWidgets('premium plan shows premium features', (tester) async {
      _setMockResponses(subscriptionStatus: 404);
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Unlimited patients'), findsOneWidget);
      expect(find.text('Premium monitoring features'), findsOneWidget);
      expect(find.text('Advanced analytics with exports'), findsOneWidget);
      expect(find.text('24/7 priority support'), findsOneWidget);
      expect(
        find.text('AI-powered insights and recommendations'),
        findsOneWidget,
      );
    });

    testWidgets('plan with active true shows Active Plan description',
        (tester) async {
      _setMockResponses(
        plansBody: [
          {
            'id': 'p1',
            'priceId': 'p1',
            'nickname': 'Active Plan Name',
            'amount': 999,
            'interval': 'month',
            'active': true,
          },
        ],
        subscriptionStatus: 404,
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Active Plan'), findsOneWidget);
    });

    testWidgets('plan with active false shows Inactive Plan description',
        (tester) async {
      _setMockResponses(
        plansBody: [
          {
            'id': 'p2',
            'priceId': 'p2',
            'nickname': 'Old Plan',
            'amount': 999,
            'interval': 'month',
            'active': false,
          },
        ],
        subscriptionStatus: 404,
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('Inactive Plan'), findsOneWidget);
    });

    testWidgets('yearly plan shows /year interval', (tester) async {
      _setMockResponses(
        plansBody: [
          {
            'id': 'p3',
            'priceId': 'p3',
            'nickname': 'Annual Plan',
            'amount': 9999,
            'interval': 'year',
            'active': true,
          },
        ],
        subscriptionStatus: 404,
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('/year'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 19: Drawer
  // =========================================================================
  group('SubscriptionManagementPage - drawer', () {
    setUp(() {
      _setupPlatformChannels();
      _setMockResponses();
    });

    testWidgets('has a drawer', (tester) async {
      await _pumpInZone(tester, _wrap());
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.drawer, isNotNull);
    });
  });

  // =========================================================================
  // Group 20: Status color branches
  // =========================================================================
  group('SubscriptionManagementPage - status color branches', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
    });

    testWidgets('canceled status renders correctly', (tester) async {
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_canceled',
          'status': 'canceled',
          'customer': 'cus_123',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_basic',
            'nickname': 'Basic Plan',
            'amount': 999,
            'interval': 'month',
          },
        },
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('CANCELLED'), findsOneWidget);
    });

    testWidgets('unpaid status renders correctly', (tester) async {
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_unpaid',
          'status': 'unpaid',
          'customer': 'cus_123',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_basic',
            'nickname': 'Basic Plan',
            'amount': 999,
            'interval': 'month',
          },
        },
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('UNPAID'), findsOneWidget);
    });

    testWidgets('past_due status renders', (tester) async {
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_pastdue',
          'status': 'past_due',
          'customer': 'cus_123',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_basic',
            'nickname': 'Basic Plan',
            'amount': 999,
            'interval': 'month',
          },
        },
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('PAST_DUE'), findsOneWidget);
    });

    testWidgets('incomplete status renders', (tester) async {
      _setMockResponses(
        subscriptionBody: {
          'id': 'sub_incomplete',
          'status': 'incomplete',
          'customer': 'cus_123',
          'current_period_start': '1700000000',
          'current_period_end': '1702592000',
          'cancel_at_period_end': false,
          'plan': {
            'id': 'price_basic',
            'nickname': 'Basic Plan',
            'amount': 999,
            'interval': 'month',
          },
        },
      );
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.text('INCOMPLETE'), findsOneWidget);
    });
  });

  // =========================================================================
  // Group 21: Monthly interval display
  // =========================================================================
  group('SubscriptionManagementPage - interval display', () {
    setUp(() {
      _setupPlatformChannelsWithSession();
      _setMockResponses();
    });

    testWidgets('shows Monthly for month interval subscription',
        (tester) async {
      await _pumpInZone(tester, _wrap());
      await _pumpNInZone(tester, 20);
      expect(find.textContaining('Monthly'), findsWidgets);
    });
  });
}
