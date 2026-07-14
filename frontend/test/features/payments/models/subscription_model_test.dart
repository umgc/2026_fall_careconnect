// Tests for Subscription and SubscriptionPlan models
// (lib/features/payments/models/subscription_model.dart).
//
// Coverage strategy:
//   Both classes are pure Dart data models with no platform channels or I/O.
//
//   Branches tested:
//     Subscription.fromJson — new backend format (contains paymentSubscriptionId
//       key), including priceCents→planAmount conversion, customerId field
//       resolution order, and missing-field defaults.
//     Subscription.fromJson — Stripe direct format with plan object; items data
//       fallback path when plan key is absent; missing plan fields defaults.
//     Subscription computed getters — isActive (active, trialing, uppercase),
//       isCancelled (canceled status, cancelAtPeriodEnd flag),
//       formattedAmount (dollar string), formattedInterval (month, year, other),
//       statusDisplay (all six branches: cancelAtPeriodEnd, active, trialing,
//       canceled, unpaid, passthrough).
//     SubscriptionPlan — constructor, formattedAmount, formattedInterval
//       (month, year, custom).
//     availablePlans global constant — has three entries with expected names.

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/payments/models/subscription_model.dart';

// ─── Helper builder ───────────────────────────────────────────────────────────

Subscription buildSub(String status, {
  bool cancelAtPeriodEnd = false,
  String interval = 'month',
  double amount = 0.0,
}) {
  return Subscription(
    id: '1',
    paymentSubscriptionId: 's',
    customerId: 'c',
    status: status,
    currentPeriodStart: '',
    currentPeriodEnd: '',
    cancelAtPeriodEnd: cancelAtPeriodEnd,
    planId: 'p',
    planName: 'P',
    planAmount: amount,
    planInterval: interval,
  );
}

void main() {
  // ─── Subscription.fromJson — new backend format ──────────────────────────────

  group('Subscription.fromJson (new backend format)', () {
    test('parses new format with paymentSubscriptionId key', () {
      // Verifies field mapping from the custom backend response shape.
      final json = {
        'id': 'db-123',
        'paymentSubscriptionId': 'sub_ABC',
        'paymentCustomerId': 'cus_XYZ',
        'status': 'active',
        'startedAt': '2025-01-01',
        'currentPeriodEnd': '2025-02-01',
        'planId': 'plan_standard',
        'planName': 'Standard Plan',
        'priceCents': 1999,
      };
      final sub = Subscription.fromJson(json);
      expect(sub.id, 'db-123');
      expect(sub.paymentSubscriptionId, 'sub_ABC');
      expect(sub.customerId, 'cus_XYZ');
      expect(sub.status, 'active');
      expect(sub.planId, 'plan_standard');
      expect(sub.planName, 'Standard Plan');
      expect(sub.planAmount, closeTo(19.99, 0.001));
      expect(sub.planInterval, 'month'); // default
      expect(sub.cancelAtPeriodEnd, isFalse); // default
    });

    test('priceCents = 0 → planAmount = 0.0', () {
      // Verifies that zero cents converts to 0.0 without rounding issues.
      final json = {'paymentSubscriptionId': 'sub_FREE', 'status': 'trialing', 'priceCents': 0};
      expect(Subscription.fromJson(json).planAmount, 0.0);
    });

    test('missing priceCents defaults planAmount to 0.0', () {
      // Verifies the fallback when priceCents key is absent.
      final json = {'paymentSubscriptionId': 'sub_X', 'status': 'active'};
      expect(Subscription.fromJson(json).planAmount, 0.0);
    });

    test('customerId resolved from stripeCustomerId first', () {
      // Verifies primary customerId field resolution in new format.
      final json = {
        'paymentSubscriptionId': 's',
        'paymentCustomerId': 'cus_A',
        'status': '',
      };
      expect(Subscription.fromJson(json).customerId, 'cus_A');
    });

    test('customerId falls back to customer then customerId fields', () {
      // Verifies secondary and tertiary fallback for customerId.
      final json1 = {'paymentSubscriptionId': 's', 'customer': 'cus_A', 'status': ''};
      expect(Subscription.fromJson(json1).customerId, 'cus_A');

      final json2 = {'paymentSubscriptionId': 's', 'customerId': 'cus_B', 'status': ''};
      expect(Subscription.fromJson(json2).customerId, 'cus_B');
    });

    test('planCode fallback used when planId is absent', () {
      // Verifies the planCode field is used when planId key is missing.
      final json = {
        'paymentSubscriptionId': 's',
        'status': 'active',
        'planCode': 'PLAN_CODE',
      };
      expect(Subscription.fromJson(json).planId, 'PLAN_CODE');
    });
  });

  // ─── Subscription.fromJson — Stripe direct format ─────────────────────────────

  group('Subscription.fromJson (Stripe direct format)', () {
    test('parses Stripe format with top-level plan object', () {
      // Verifies field mapping from the Stripe API response shape.
      final json = {
        'id': 'sub_STRIPE',
        'customer': 'cus_STRIPE',
        'status': 'active',
        'current_period_start': '1700000000',
        'current_period_end': '1702678400',
        'cancel_at_period_end': false,
        'plan': {
          'id': 'price_monthly',
          'nickname': 'Monthly Pro',
          'amount': 2999,
          'interval': 'month',
        },
      };
      final sub = Subscription.fromJson(json);
      expect(sub.id, 'sub_STRIPE');
      expect(sub.paymentSubscriptionId, 'sub_STRIPE');
      expect(sub.customerId, 'cus_STRIPE');
      expect(sub.planId, 'price_monthly');
      expect(sub.planName, 'Monthly Pro');
      expect(sub.planAmount, closeTo(29.99, 0.001));
      expect(sub.planInterval, 'month');
      expect(sub.cancelAtPeriodEnd, isFalse);
    });

    test('parses plan from items.data[0].plan fallback path', () {
      // Verifies the deeply-nested Stripe plan fallback.
      final json = {
        'id': 'sub_ITEMS',
        'customer': 'cus_Z',
        'status': 'active',
        'current_period_start': '1700000000',
        'current_period_end': '1702678400',
        'cancel_at_period_end': true,
        'items': {
          'data': [
            {
              'plan': {
                'id': 'price_yearly',
                'nickname': 'Yearly',
                'amount': 9999,
                'interval': 'year',
              }
            }
          ]
        },
      };
      final sub = Subscription.fromJson(json);
      expect(sub.planId, 'price_yearly');
      expect(sub.planAmount, closeTo(99.99, 0.001));
      expect(sub.cancelAtPeriodEnd, isTrue);
    });

    test('missing plan fields fall back to defaults', () {
      // Verifies safe defaults when the plan sub-object is absent entirely.
      final json = {
        'id': 'sub_EMPTY',
        'customer': '',
        'status': 'active',
        'current_period_start': '',
        'current_period_end': '',
      };
      final sub = Subscription.fromJson(json);
      expect(sub.planName, '');
      expect(sub.planAmount, 0.0);
      expect(sub.planInterval, 'month');
    });
  });

  // ─── Subscription.isActive ────────────────────────────────────────────────────

  group('Subscription.isActive', () {
    test('"active" status → isActive = true', () {
      expect(buildSub('active').isActive, isTrue);
    });

    test('"trialing" status → isActive = true', () {
      expect(buildSub('trialing').isActive, isTrue);
    });

    test('"canceled" status → isActive = false', () {
      expect(buildSub('canceled').isActive, isFalse);
    });

    test('uppercase "ACTIVE" → isActive = true (case insensitive)', () {
      // Verifies the toLowerCase() comparison.
      expect(buildSub('ACTIVE').isActive, isTrue);
    });
  });

  // ─── Subscription.isCancelled ─────────────────────────────────────────────────

  group('Subscription.isCancelled', () {
    test('"canceled" status → isCancelled = true', () {
      expect(buildSub('canceled').isCancelled, isTrue);
    });

    test('cancelAtPeriodEnd = true → isCancelled = true regardless of status', () {
      expect(buildSub('active', cancelAtPeriodEnd: true).isCancelled, isTrue);
    });

    test('"active" with no cancelAtPeriodEnd → isCancelled = false', () {
      expect(buildSub('active').isCancelled, isFalse);
    });
  });

  // ─── Subscription.formattedAmount ─────────────────────────────────────────────

  group('Subscription.formattedAmount', () {
    test('formats planAmount as dollar string with 2 decimal places', () {
      // Verifies the currency-formatted output includes $ sign.
      expect(buildSub('active', amount: 19.99).formattedAmount, '\$19.99');
    });
  });

  // ─── Subscription.formattedInterval ──────────────────────────────────────────

  group('Subscription.formattedInterval', () {
    test('"month" → "Monthly"', () {
      expect(buildSub('active', interval: 'month').formattedInterval, 'Monthly');
    });

    test('"year" → "Yearly"', () {
      expect(buildSub('active', interval: 'year').formattedInterval, 'Yearly');
    });

    test('custom interval value → passthrough', () {
      // Verifies that unrecognized intervals are returned as-is.
      expect(buildSub('active', interval: 'week').formattedInterval, 'week');
    });
  });

  // ─── Subscription.statusDisplay ──────────────────────────────────────────────

  group('Subscription.statusDisplay', () {
    test('"active" → "Active"', () {
      expect(buildSub('active').statusDisplay, 'Active');
    });

    test('"trialing" → "Trial"', () {
      expect(buildSub('trialing').statusDisplay, 'Trial');
    });

    test('"canceled" → "Cancelled"', () {
      expect(buildSub('canceled').statusDisplay, 'Cancelled');
    });

    test('"unpaid" → "Unpaid"', () {
      expect(buildSub('unpaid').statusDisplay, 'Unpaid');
    });

    test('cancelAtPeriodEnd = true → "Canceling at period end"', () {
      // Verifies this branch takes priority over the status string.
      expect(
        buildSub('active', cancelAtPeriodEnd: true).statusDisplay,
        'Canceling at period end',
      );
    });

    test('unknown status → passthrough of original status string', () {
      // Verifies the default branch returns the raw status value.
      expect(buildSub('pending').statusDisplay, 'pending');
    });
  });

  // ─── SubscriptionPlan ─────────────────────────────────────────────────────────

  group('SubscriptionPlan', () {
    test('constructor stores all fields including features list', () {
      // Verifies every field including the list of feature strings is stored.
      final plan = SubscriptionPlan(
        id: 'price_basic',
        name: 'Basic',
        description: 'Basic plan',
        amount: 9.99,
        interval: 'month',
        features: ['Feature A', 'Feature B'],
      );
      expect(plan.id, 'price_basic');
      expect(plan.name, 'Basic');
      expect(plan.description, 'Basic plan');
      expect(plan.amount, 9.99);
      expect(plan.features, ['Feature A', 'Feature B']);
    });

    test('formattedAmount formats as dollar string with 2 decimal places', () {
      final plan = SubscriptionPlan(
        id: 'p', name: 'P', description: 'D',
        amount: 29.99, interval: 'month', features: [],
      );
      expect(plan.formattedAmount, '\$29.99');
    });

    test('formattedInterval for "month" → "/month"', () {
      final plan = SubscriptionPlan(
        id: 'p', name: 'P', description: 'D',
        amount: 9.99, interval: 'month', features: [],
      );
      expect(plan.formattedInterval, '/month');
    });

    test('formattedInterval for "year" → "/year"', () {
      final plan = SubscriptionPlan(
        id: 'p', name: 'P', description: 'D',
        amount: 99.99, interval: 'year', features: [],
      );
      expect(plan.formattedInterval, '/year');
    });

    test('formattedInterval for custom → "/custom"', () {
      // Verifies the fallback for non-standard intervals.
      final plan = SubscriptionPlan(
        id: 'p', name: 'P', description: 'D',
        amount: 5.0, interval: 'week', features: [],
      );
      expect(plan.formattedInterval, '/week');
    });

    test('availablePlans has three entries with expected names', () {
      // Verifies the pre-built global plan list is complete.
      expect(availablePlans.length, 3);
      final names = availablePlans.map((p) => p.name).toList();
      expect(names, containsAll(['Basic Plan', 'Standard Plan (Legacy)', 'Premium Plan']));
    });
  });
}
