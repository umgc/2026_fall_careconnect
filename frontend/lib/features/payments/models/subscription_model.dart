import 'package:care_connect_app/l10n/app_localizations.dart';

class Subscription {
  final String id; // Database ID
  final String
  paymentSubscriptionId; // Payment subscription ID for API operations
  final String customerId; // Payment customer ID
  final String status;
  final String currentPeriodStart;
  final String currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String planId;
  final String planName;
  final double planAmount;
  final String planInterval;

  Subscription({
    required this.id,
    required this.paymentSubscriptionId,
    required this.customerId,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.planId,
    required this.planName,
    required this.planAmount,
    required this.planInterval,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    // Handle different API response formats
    // Support both payment provider format and our backend's custom format

    // Check if this is the new API format with our backend structure
    if (json.containsKey('paymentSubscriptionId') ||
        json.containsKey('paymentCustomerId')) {
      // New backend format
      final paymentSubId = json['paymentSubscriptionId']?.toString() ?? '';
      return Subscription(
        id: json['id']?.toString() ?? '', // Database ID
        paymentSubscriptionId:
            paymentSubId, // Payment subscription ID for API operations
        customerId:
            json['paymentCustomerId']?.toString() ??
            json['customer']?.toString() ??
            json['customerId']?.toString() ??
            '',
        status: json['status']?.toString() ?? '',
        currentPeriodStart: json['startedAt']?.toString() ?? '',
        currentPeriodEnd: json['currentPeriodEnd']?.toString() ?? '',
        cancelAtPeriodEnd: false, // Default since it's not in the new format
        planId:
            json['planId']?.toString() ?? json['planCode']?.toString() ?? '',
        planName: json['planName']?.toString() ?? '',
        planAmount: json['priceCents'] != null
            ? ((json['priceCents'] as num).toDouble() / 100)
            : 0.0,
        planInterval: 'month', // Default value
      );
    }

    // Original Payment format
    final planData =
        json['plan'] as Map<String, dynamic>? ??
        json['items']?['data']?[0]?['plan'] as Map<String, dynamic>? ??
        {};

    final paymentId = json['id']?.toString() ?? '';
    return Subscription(
      id: paymentId, // In direct Payment format, id is the subscription ID
      paymentSubscriptionId:
          paymentId, // Same value as id for direct Payment format
      customerId: (json['customer'] ?? '').toString(),
      status: json['status']?.toString() ?? '',
      currentPeriodStart: json['current_period_start']?.toString() ?? '',
      currentPeriodEnd: json['current_period_end']?.toString() ?? '',
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      planId: planData['id']?.toString() ?? '',
      planName: planData['nickname']?.toString() ?? '',
      planAmount: ((planData['amount'] ?? 0) as num).toDouble() / 100,
      planInterval: planData['interval']?.toString() ?? 'month',
    );
  }

  bool get isActive =>
      status.toLowerCase() == 'active' || status.toLowerCase() == 'trialing';
  bool get isCancelled =>
      status.toLowerCase() == 'canceled' || cancelAtPeriodEnd;

  String get formattedAmount => '\$${planAmount.toStringAsFixed(2)}';

  String formattedInterval(AppLocalizations t) {
    if (planInterval == 'month') return t.subscriptionmodels_monthly;
    if (planInterval == 'year') return t.subscriptionmodels_yearly;
    return planInterval;
  }

  String statusDisplay(AppLocalizations t) {
    final lowerStatus = status.toLowerCase();
    if (cancelAtPeriodEnd) return t.subscriptionmodels_cancelOnPeriod;
    if (lowerStatus == 'active') return t.subscriptionmodels_active;
    if (lowerStatus == 'trialing') return t.subscriptionmodels_trial;
    if (lowerStatus == 'canceled') return t.subscriptionmodels_cancelled;
    if (lowerStatus == 'unpaid') return t.subscriptionmodels_unpaid;
    return status;
  }
}

class SubscriptionPlan {
  final String id; // This can be the plan ID or price ID depending on source
  final String name;
  final String description;
  final double amount;
  final String interval;
  final List<String> features;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.amount,
    required this.interval,
    required this.features,
  });

  String get formattedAmount => '\$${amount.toStringAsFixed(2)}';
  String formattedInterval(AppLocalizations t) {
    if (interval == 'month') return t.subscriptionmodels_monthInterval;
    if (interval == 'year') return t.subscriptionmodels_yearInterval;
    return '/$interval';
  }
}

// Define available plans
final List<SubscriptionPlan> availablePlans = [
  SubscriptionPlan(
    id: 'price_basic',
    name: 'Basic Plan',
    description: 'Essential care coordination features',
    amount: 9.99,
    interval: 'month',
    features: [
      'Up to 3 patients',
      'Core monitoring features',
      'Basic analytics',
      'Email support',
    ],
  ),
  SubscriptionPlan(
    id: 'price_standard',
    name: 'Standard Plan (Legacy)',
    description: 'Advanced features for better care management',
    amount: 19.99,
    interval: 'month',
    features: [
      'Up to 10 patients',
      'Advanced monitoring',
      'Full analytics dashboard',
      'Priority email support',
      'AI-powered insights',
    ],
  ),
  SubscriptionPlan(
    id: 'price_premium',
    name: 'Premium Plan',
    description: 'Comprehensive care management solution',
    amount: 29.99,
    interval: 'month',
    features: [
      'Unlimited patients',
      'Premium monitoring features',
      'Advanced analytics with exports',
      '24/7 priority support',
      'AI-powered insights and recommendations',
      'Team access controls',
    ],
  ),
];
