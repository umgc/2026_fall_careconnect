// Tests for payment subscription models:
// Subscription, SubscriptionPlan (subscription_model.dart)
// SubscriptionPlan (subscription_plan_model.dart)

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/payments/models/subscription_model.dart' as sm;
import 'package:care_connect_app/features/payments/models/subscription_plan_model.dart' as spm;

void main() {
  group('Subscription (subscription_model.dart)', () {
    sm.Subscription sub0({
      String status = 'active',
      bool cancelAtPeriodEnd = false,
      double planAmount = 19.99,
      String planInterval = 'month',
    }) =>
        sm.Subscription(
          id: 'sub-1',
          paymentSubscriptionId: 'sub_stripe_1',
          customerId: 'cus_123',
          status: status,
          currentPeriodStart: '2024-01-01',
          currentPeriodEnd: '2024-02-01',
          cancelAtPeriodEnd: cancelAtPeriodEnd,
          planId: 'plan_1',
          planName: 'Standard',
          planAmount: planAmount,
          planInterval: planInterval,
        );

    test('isActive true for active status', () {
      expect(sub0(status: 'active').isActive, isTrue);
    });

    test('isActive true for trialing status', () {
      expect(sub0(status: 'trialing').isActive, isTrue);
    });

    test('isActive false for canceled status', () {
      expect(sub0(status: 'canceled').isActive, isFalse);
    });

    test('isCancelled true for canceled status', () {
      expect(sub0(status: 'canceled').isCancelled, isTrue);
    });

    test('isCancelled true when cancelAtPeriodEnd is true', () {
      expect(sub0(cancelAtPeriodEnd: true).isCancelled, isTrue);
    });

    test('formattedAmount formats correctly', () {
      expect(sub0(planAmount: 19.99).formattedAmount, '\$19.99');
    });

    test('formattedInterval returns Monthly for month', () {
      expect(sub0(planInterval: 'month').formattedInterval, 'Monthly');
    });

    test('formattedInterval returns Yearly for year', () {
      expect(sub0(planInterval: 'year').formattedInterval, 'Yearly');
    });

    test('statusDisplay for active', () {
      expect(sub0(status: 'active').statusDisplay, 'Active');
    });

    test('statusDisplay for trialing', () {
      expect(sub0(status: 'trialing').statusDisplay, 'Trial');
    });

    test('statusDisplay for canceled', () {
      expect(sub0(status: 'canceled').statusDisplay, 'Cancelled');
    });

    test('statusDisplay for cancelAtPeriodEnd', () {
      expect(sub0(cancelAtPeriodEnd: true).statusDisplay, 'Canceling at period end');
    });

    test('fromJson with backend format', () {
      final json = {
        'id': '42',
        'paymentSubscriptionId': 'sub_abc',
        'paymentCustomerId': 'cus_xyz',
        'status': 'active',
        'startedAt': '2024-01-01',
        'currentPeriodEnd': '2024-02-01',
        'planId': 'plan_std',
        'planName': 'Standard',
        'priceCents': 1999,
      };
      final sub = sm.Subscription.fromJson(json);
      expect(sub.id, '42');
      expect(sub.paymentSubscriptionId, 'sub_abc');
      expect(sub.customerId, 'cus_xyz');
      expect(sub.status, 'active');
      expect(sub.planAmount, closeTo(19.99, 0.01));
    });

    test('fromJson with stripe direct format', () {
      final json = {
        'id': 'sub_direct',
        'customer': 'cus_direct',
        'status': 'active',
        'current_period_start': '1700000000',
        'current_period_end': '1702592000',
        'cancel_at_period_end': false,
        'plan': {
          'id': 'plan_x',
          'nickname': 'Premium',
          'amount': 2999,
          'interval': 'month',
        },
      };
      final sub = sm.Subscription.fromJson(json);
      expect(sub.id, 'sub_direct');
      expect(sub.planAmount, closeTo(29.99, 0.01));
    });
  });

  group('SubscriptionPlan (subscription_model.dart)', () {
    test('formattedAmount returns dollar string', () {
      final plan = sm.SubscriptionPlan(
        id: 'p1',
        name: 'Basic',
        description: 'Desc',
        amount: 9.99,
        interval: 'month',
        features: [],
      );
      expect(plan.formattedAmount, '\$9.99');
    });

    test('formattedInterval for month', () {
      final plan = sm.SubscriptionPlan(
        id: 'p1', name: 'B', description: 'D', amount: 9.99, interval: 'month', features: [],
      );
      expect(plan.formattedInterval, '/month');
    });

    test('formattedInterval for year', () {
      final plan = sm.SubscriptionPlan(
        id: 'p1', name: 'B', description: 'D', amount: 9.99, interval: 'year', features: [],
      );
      expect(plan.formattedInterval, '/year');
    });
  });

  group('SubscriptionPlan (subscription_plan_model.dart)', () {
    test('constructor stores all fields', () {
      final plan = spm.SubscriptionPlan(
        id: 'price_123',
        active: true,
        amount: 1999,
        currency: 'usd',
        interval: 'month',
        intervalCount: 1,
        product: 'prod_abc',
        nickname: 'Standard',
        features: ['Feature A', 'Feature B'],
      );
      expect(plan.id, 'price_123');
      expect(plan.active, isTrue);
      expect(plan.amount, 1999);
      expect(plan.currency, 'usd');
      expect(plan.interval, 'month');
      expect(plan.nickname, 'Standard');
    });

    test('formattedPrice converts cents to dollars', () {
      final plan = spm.SubscriptionPlan(
        id: 'p1', active: true, amount: 2999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'prod_x', nickname: 'Premium',
      );
      expect(plan.formattedPrice, '\$29.99');
    });

    test('formattedInterval returns monthly for month', () {
      final plan = spm.SubscriptionPlan(
        id: 'p1', active: true, amount: 999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'prod_x', nickname: 'Basic',
      );
      expect(plan.formattedInterval, 'monthly');
    });

    test('formattedInterval returns yearly for year', () {
      final plan = spm.SubscriptionPlan(
        id: 'p1', active: true, amount: 999, currency: 'usd',
        interval: 'year', intervalCount: 1, product: 'prod_x', nickname: 'Basic',
      );
      expect(plan.formattedInterval, 'yearly');
    });

    test('description uses customDescription when provided', () {
      final plan = spm.SubscriptionPlan(
        id: 'p1', active: true, amount: 999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'prod_x', nickname: 'Basic',
        customDescription: 'My custom desc',
      );
      expect(plan.description, 'My custom desc');
    });

    test('description returns standard message for standard nickname', () {
      final plan = spm.SubscriptionPlan(
        id: 'p1', active: true, amount: 999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'prod_x', nickname: 'Standard Plan',
      );
      expect(plan.description, contains('Basic features'));
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 'price_abc',
        'active': true,
        'amount': 1999,
        'currency': 'usd',
        'interval': 'month',
        'intervalCount': 1,
        'product': 'prod_xyz',
        'nickname': 'Standard',
        'features': ['Feature 1', 'Feature 2'],
      };
      final plan = spm.SubscriptionPlan.fromJson(json);
      expect(plan.id, 'price_abc');
      expect(plan.active, isTrue);
      expect(plan.amount, 1999);
      expect(plan.features, ['Feature 1', 'Feature 2']);
    });

    test('fromJson defaults when fields absent', () {
      final json = <String, dynamic>{};
      final plan = spm.SubscriptionPlan.fromJson(json);
      expect(plan.id, '');
      expect(plan.active, isFalse);
      expect(plan.amount, 0);
      expect(plan.currency, 'usd');
      expect(plan.features, isEmpty);
    });

    test('toJson includes required fields', () {
      final plan = spm.SubscriptionPlan(
        id: 'price_abc', active: true, amount: 999, currency: 'usd',
        interval: 'month', intervalCount: 1, product: 'prod_x', nickname: 'Basic',
      );
      final json = plan.toJson();
      expect(json['id'], 'price_abc');
      expect(json['active'], isTrue);
      expect(json['amount'], 999);
    });
  });
}
