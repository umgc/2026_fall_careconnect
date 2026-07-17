import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import '../../models/subscription_model.dart';

class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({super.key});

  @override
  State<SubscriptionManagementPage> createState() =>
      _SubscriptionManagementPageState();

}

class _SubscriptionManagementPageState
    extends State<SubscriptionManagementPage> {
  bool _isLoading = true;
  String? _error;
  Subscription? _currentSubscription;
  String? _customerId;
  bool _processingAction = false;
  SubscriptionPlan? _selectedPlan;
  List<SubscriptionPlan> _plans = [];

  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if(_initialized) return;
    _initialized = true;
    _loadSubscriptionData();
  }

  Future<void> _loadSubscriptionData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final t = AppLocalizations.of(context)!;
    try {
      // We no longer need a separate call to get customer ID, as we'll extract it from the subscription data

      // Now we don't need a separate call to getCurrentSubscription since we use getUserSubscriptions
      final response = await ApiService.getCurrentSubscription();

      // Fetch available plans from API
      final plansResponse = await ApiService.getAvailablePlans();

      if (plansResponse.statusCode == 200) {
        final plansData = jsonDecode(plansResponse.body);
        if (plansData != null && plansData is List) {
          _plans = plansData.map((planData) {
            // Generate default features based on the plan
            final List<String> features = [];

            // Basic features for all plans
            features.add(t.submangement_coreMonitorFeature);
            features.add(t.submangement_emailSupportFeature);

            // Additional features based on plan name/nickname
            final nickname = (planData['nickname'] ?? '')
                .toString()
                .toLowerCase();
            if (nickname.contains('premium')) {
              features.add(t.submangement_unlimitedPtFeature);
              features.add(t.submangement_premMonitorFeature);
              features.add(t.submangement_advAnlFeature);
              features.add(t.submangement_prioritySupportFeature);
              features.add(t.submangement_aiInsightsFeature);
            } else if (nickname.contains('standard')) {
              features.add(t.submangement_tenPtFeature);
              features.add(t.submangement_advMonitorFeature);
              features.add(t.submangement_fullAnlFeature);
              features.add(t.submangement_prioEmailFeature);
            } else {
              features.add(t.submangement_threePtFeature);
              features.add(t.submangement_basicAnlFeature);
            }

            return SubscriptionPlan(
              id:
                  planData['priceId'] ??
                  planData['id'], // Use priceId if available
              name: _translatePlanName(planData['nickname']),
              description: planData['active'] == true
                  ? t.submangement_activePlan
                  : t.submangement_inactivePlan,
              amount:
                  (planData['amount'] ?? 0) / 100, // Convert cents to dollars
              interval: planData['interval'] ?? 'month',
              features: features,
            );
          }).toList();
        } else {
          // Fall back to default plans if the response isn't in the expected format
          _plans = availablePlans;
        }
      } else {
        // Fall back to default plans if API call fails
        _plans = availablePlans;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null) {
          // If data is a list, find the active subscription
          if (data is List) {
            final activeSubscriptions = data
                .where(
                  (sub) =>
                      sub is Map<String, dynamic> &&
                      sub.containsKey('status') &&
                      sub['status'].toString().toLowerCase() == 'active',
                )
                .toList();

            // Use the first active subscription or null if none found
            final activeSubscription = activeSubscriptions.isNotEmpty
                ? activeSubscriptions.first
                : null;

            // Extract customer ID from the subscription data
            if (activeSubscription != null &&
                activeSubscription is Map<String, dynamic>) {
              if (activeSubscription.containsKey('paymentCustomerId')) {
                _customerId = activeSubscription['paymentCustomerId'];
              } else if (activeSubscription.containsKey('customer')) {
                _customerId = activeSubscription['customer'];
              } else if (activeSubscription.containsKey('customerId')) {
                _customerId = activeSubscription['customerId'];
              }
            } else if (data.isNotEmpty && data.first is Map<String, dynamic>) {
              if (data.first.containsKey('paymentCustomerId')) {
                _customerId = data.first['paymentCustomerId'];
              } else if (data.first.containsKey('customer')) {
                _customerId = data.first['customer'];
              } else if (data.first.containsKey('customerId')) {
                _customerId = data.first['customerId'];
              }
            }

            setState(() {
              _currentSubscription = activeSubscription != null
                  ? Subscription.fromJson(activeSubscription)
                  : null;

              // Set the selected plan based on current subscription
              if (_currentSubscription != null) {
                if (_plans.isNotEmpty) {
                  // Try to find a matching plan by ID first
                  try {
                    _selectedPlan = _plans.firstWhere(
                      (plan) => plan.id == _currentSubscription!.planId,
                      orElse: () => _plans.length > 1
                          ? _plans[1]
                          : _plans[0], // Default to standard plan if available
                    );
                  } catch (e) {
                    print('Error finding plan match: $e');
                    // Fallback to match by name if ID doesn't match
                    try {
                      _selectedPlan = _plans.firstWhere(
                        (plan) => plan.name.toLowerCase().contains(
                          _currentSubscription!.planName.toLowerCase(),
                        ),
                        orElse: () => _plans.length > 1 ? _plans[1] : _plans[0],
                      );
                    } catch (e) {
                      print('Error finding plan by name: $e');
                      // Last resort: just use the first plan
                      _selectedPlan = _plans.isNotEmpty ? _plans[0] : null;
                    }
                  }
                }
              } else {
                _selectedPlan = _plans.isNotEmpty
                    ? _plans[0]
                    : null; // Default to basic plan if no subscription
              }
            });
          }
          // Handle the case if it's still returning a single subscription object
          else if (data is Map<String, dynamic> && data.containsKey('id')) {
            setState(() {
              _currentSubscription = Subscription.fromJson(data);

              // Set the selected plan based on current subscription
              if (_currentSubscription != null) {
                if (_plans.isNotEmpty) {
                  // Try to find a matching plan by ID first
                  try {
                    _selectedPlan = _plans.firstWhere(
                      (plan) => plan.id == _currentSubscription!.planId,
                      orElse: () => _plans.length > 1
                          ? _plans[1]
                          : _plans[0], // Default to standard plan if available
                    );
                  } catch (e) {
                    print('Error finding plan match: $e');
                    // Fallback to match by name if ID doesn't match
                    try {
                      _selectedPlan = _plans.firstWhere(
                        (plan) => plan.name.toLowerCase().contains(
                          _currentSubscription!.planName.toLowerCase(),
                        ),
                        orElse: () => _plans.length > 1 ? _plans[1] : _plans[0],
                      );
                    } catch (e) {
                      print('Error finding plan by name: $e');
                      // Last resort: just use the first plan
                      _selectedPlan = _plans.isNotEmpty ? _plans[0] : null;
                    }
                  }
                }
              }
            });
          } else {
            setState(() {
              _currentSubscription = null;
              _selectedPlan = _plans.isNotEmpty
                  ? _plans[0]
                  : null; // Default to basic plan if no subscription
            });
          }
        } else {
          setState(() {
            _currentSubscription = null;
            _selectedPlan = _plans.isNotEmpty
                ? _plans[0]
                : null; // Default to basic plan if no subscription
          });
        }
      } else if (response.statusCode == 404) {
        // No subscription found, which is a valid state
        setState(() {
          _currentSubscription = null;
          _selectedPlan = _plans.isNotEmpty
              ? _plans[0]
              : null; // Default to basic plan
        });
      } else {
        setState(() {
          _error =
              '${t.submangement_failToLoadSub}: ${response.statusCode}. ${t.submangement_pleaseTryAgain}';
        });
        print('Subscription API error: ${response.statusCode}');
        try {
          print('Response body: ${response.body}');
        } catch (e) {
          // Ignore body parsing errors
        }
      }
    } catch (e) {
      setState(() {
        _error =
            t.submangement_errorLoadingSub;
      });
      print('Exception in _loadSubscriptionData: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changePlan(SubscriptionPlan newPlan) async {

    // Ensure we have a customerId for new subscriptions
    if (_processingAction) return;

    // For existing active subscriptions that need to be changed,
    // first cancel the existing subscription, then redirect to checkout
    final t = AppLocalizations.of(context)!;
    if (_currentSubscription != null && _currentSubscription!.isActive) {
      // Enhanced confirmation dialog showing plan comparison
      final bool? confirmSwitch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(t.submangement_confirmPlanChange),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t.submangement_changeSubPlan}:',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),

                // Current plan info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha:0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.remove_circle_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.submangement_currentPlan,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_currentSubscription!.planName} - ${_currentSubscription!.formattedAmount}/${_currentSubscription!.formattedInterval(t)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // New plan info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha:0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: Theme.of(context).colorScheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.submangement_newPlan,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${newPlan.name} - ${newPlan.formattedAmount}/${newPlan.formattedInterval(t)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.secondary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${t.submangement_whatHappensNext}:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${t.submangement_whatNextDescr1}\n ${t.submangement_whatNextDescr2}\n ${t.submangement_whatNextDescr3}\n ${t.submangement_whatNextDescr4}',
                        style: TextStyle(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.submangement_cancelCaps),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.submangement_confirmCaps),
            ),
          ],
        ),
      );

      if (confirmSwitch != true) return;

      setState(() {
        _processingAction = true;
      });

      try {
        // First cancel the current subscription
        final response = await ApiService.cancelSubscription(
          _currentSubscription!.paymentSubscriptionId,
        );

        if (response.statusCode != 200) {
          final errorData = jsonDecode(response.body);
          throw Exception(
            errorData['error'] ?? t.submangement_failedToCancel,
          );
        }

        // Get the user's ID for checkout
        final userSession = await AuthTokenManager.getUserSession();
        final userId = userSession != null
            ? userSession['id']?.toString()
            : null;

        // Extract customer ID from existing subscription
        final customerId = _currentSubscription!.customerId;

        // Now redirect to checkout flow with the new plan
        _redirectToCheckout(newPlan, userId, customerId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${t.voicecommand_phaseLabelError}: $e')));
        setState(() {
          _processingAction = false;
        });
      }

    } else {
      // For new subscriptions or inactive subscriptions,
      // get the user ID and customer ID if available, then redirect to checkout
      try {
        final userSession = await AuthTokenManager.getUserSession();
        final userId = userSession != null
            ? userSession['id']?.toString()
            : null;

      // Redirect to checkout flow for a new subscription
      _redirectToCheckout(newPlan, userId, _customerId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${t.voicecommand_phaseLabelError}: $e')));
      }

    }
  }

  String _translatePlanName(String name){
    final t = AppLocalizations.of(context)!;
    switch(name){
      case('Standard Plan'):
        return t.submangement_standardPlan;
      case('Premium Plan'):
        return t.submangement_premiumPlan;
      default:
        return name;
    }
  }

  void _redirectToCheckout(
    SubscriptionPlan plan,
    String? userId,
    String? customerId,
  ) {
    final t = AppLocalizations.of(context)!;
    final tierId = int.tryParse(plan.id) ?? 0;
    final userIdInt = userId != null ? int.tryParse(userId) : null;

    // Free plan bypasses payment entirely
    if (tierId == 1 || plan.amount == 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.submangement_confirmFreePlan),
          content: Text(t.submangement_selectedFreePlan),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.cancel)),
            ElevatedButton(onPressed: () async {
              Navigator.of(ctx).pop();
              final session = await AuthTokenManager.getUserSession();
              final userId = session?['id']?.toString() ?? '';
              if (userId.isNotEmpty) { await ApiService.createSubscriptionByUser(userId, 'plan_free'); }
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) {
                await _loadSubscriptionData();
                setState(() => _processingAction = false);
              }
            }, child: Text(t.voicecommand_confirmButton)),
          ],
        ),
      );
      return;
    }

    if (kIsWeb) {
      context.go('/web-pay', extra: {
        'tierId': tierId,
        'tier': plan.name,
        'userId': userIdInt,
      });
    } else {
      context.go('/native-billing', extra: {
        'tierId': tierId,
        'tier': plan.name,
        'userId': userIdInt,
      });
    }
  }

  Future<void> _cancelSubscription() async {
    if (_processingAction || _currentSubscription == null) return;

    // First confirmation dialog with clear warning about loss of access
    final t = AppLocalizations.of(context)!;
    final bool? initialConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.submangement_cancelSub),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.submangement_warningHeader,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(t.submangement_warningDescr1),
            Text(
              t.submangement_warningDescr2,
            ),
            Text(
              t.submangement_warningDescr3,
            ),
            SizedBox(height: 16),
            Text(t.submangement_warningDescr4),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.submangement_noKeepPlan),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.submangement_yesCancel),
          ),
        ],
      ),
    );

    if (initialConfirm != true) return;

    // Second confirmation as an extra safety measure
    if (!mounted) return;

        // Second confirmation as an extra safety measure
        final bool? finalConfirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.submangement_finalConfirmation),
            content: Text(
              t.submangement_finalWarning,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.submangement_noGoBack),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.submangement_yesFinal),
              ),
            ],
          ),
        );

    if (finalConfirm != true) return;

    setState(() {
      _processingAction = true;
    });

    try {
      final response = await ApiService.cancelSubscription(
        _currentSubscription!.paymentSubscriptionId,
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.submangement_subCanceledSuccess,
            ),
          ),
        );

        // Capture all context-dependent references before any async gaps
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final navigator = GoRouter.of(context);

        // Small delay to show the message before logout
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        // Force logout by clearing the user session
        await AuthTokenManager.clearAuthData();
        userProvider.clearUser();

        // Clear navigation history and go to login
        navigator.go('/login');

      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? t.submangement_subCanceledFailed);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${t.voicecommand_phaseLabelError}: $e')));

      setState(() {
        _processingAction = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: t.submangement_subManagement,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      drawer: const CommonDrawer(currentRoute: '/select-package'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              t.submangement_errorLoadingSubMang,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? t.submangement_unknownErrorOccur,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadSubscriptionData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(t.submangement_tryAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrentSubscription(),
          const SizedBox(height: 24),
          _buildAvailablePlans(),
        ],
      ),
    );
  }

  Widget _buildCurrentSubscription() {
    final t = AppLocalizations.of(context)!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.credit_card,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  t.submangement_currentSub,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 32),

            if (_currentSubscription == null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha:0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.submangement_noActiveSub,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.submangement_chooseAPlan,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Enhanced subscription details with better visual hierarchy
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary.withValues(alpha:0.1),
                      Theme.of(context).colorScheme.secondary.withValues(alpha:0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha:0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plan name prominently displayed
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentSubscription!.planName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const Spacer(),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              _currentSubscription!.status,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _currentSubscription!.statusDisplay(t).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Amount paid and billing info
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.submangement_amountPaid,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withValues(alpha:0.7),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentSubscription!.formattedAmount,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                              Text(
                                '/ ${_currentSubscription!.formattedInterval(t)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withValues(alpha:0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 50,
                          width: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha:0.3),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.submangement_nextBilling,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withValues(alpha:0.7),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(
                                  _currentSubscription!.currentPeriodEnd,
                                ),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Additional subscription details
              _buildInfoRow(
                icon: Icons.event,
                label: t.submangement_currentPeriod,
                value:
                    '${_formatDate(_currentSubscription!.currentPeriodStart)} - ${_formatDate(_currentSubscription!.currentPeriodEnd)}',
              ),

              if (_currentSubscription!.cancelAtPeriodEnd) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha:0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_outlined,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.submangement_subWillBeCancelled,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons
              if (!_currentSubscription!.cancelAtPeriodEnd &&
                  _currentSubscription!.isActive &&
                  _currentSubscription!.planAmount > 0) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _processingAction
                            ? null
                            : _cancelSubscription,
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(t.submangement_cancelSub),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String timestamp) {
    if (timestamp.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      return DateFormat.yMMMd().format(date);
    } catch (_) {
      try {
        final date = DateTime.fromMillisecondsSinceEpoch(
          int.parse(timestamp) * 1000,
        );
        return DateFormat.yMMMd().format(date);
      } catch (_) {
        return timestamp;
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'trialing':
        return AppTheme.success;
      case 'past_due':
      case 'unpaid':
        return AppTheme.warning;
      case 'canceled':
      case 'incomplete':
      case 'incomplete_expired':
        return AppTheme.error;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: valueColor != null
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildAvailablePlans() {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.submangement_availablePlan,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        if (_plans.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.submangement_noSubPlan,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.submangement_checkBackLater,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._plans.map((plan) {
            final isCurrentPlan =
                _currentSubscription != null &&
                (_currentSubscription!.planId == plan.id ||
                    _currentSubscription!.planName.toLowerCase().contains(
                      plan.name.toLowerCase(),
                    ) ||
                    plan.name.toLowerCase().contains(
                      _currentSubscription!.planName.toLowerCase(),
                    ) ||
                    (_currentSubscription!.planAmount > 0 &&
                        plan.amount > 0 &&
                        _currentSubscription!.planAmount == plan.amount));
            final isSelectedPlan = _selectedPlan?.id == plan.id;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: isSelectedPlan ? 4 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelectedPlan
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedPlan = plan;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                RadioGroup<String>(
                                  groupValue: _selectedPlan?.id ?? '',
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedPlan = _plans.firstWhere(
                                          (p) => p.id == value,
                                        );
                                      });
                                    }
                                  },
                                  child: Radio<String>(
                                    value: plan.id,
                                    activeColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        plan.description,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color
                                                  ?.withValues(alpha: 0.7),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                plan.formattedAmount,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                              Text(
                                plan.formattedInterval(t),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      ...plan.features.map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(feature)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (isCurrentPlan)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                const SizedBox(width: 8),
                                Text(t.submangement_currentActivePlan),
                              ],
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _processingAction
                                ? null
                                : () => _changePlan(plan),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              disabledBackgroundColor: Theme.of(
                                context,
                              ).disabledColor,
                            ),
                            child: _processingAction && isSelectedPlan
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _currentSubscription != null &&
                                            _currentSubscription!.isActive
                                        ? t.submangement_switchToNewPlan
                                        : t.nativebilling_subscribeNow,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
