import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../payments/models/subscription_plan_model.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/responsive_container.dart';

class SelectPackagePage extends StatefulWidget {
  final String? userId;
  const SelectPackagePage({super.key, this.userId});

  @override
  State<SelectPackagePage> createState() => _SelectPackagePageState();
}

class _SelectPackagePageState extends State<SelectPackagePage> {
  List<SubscriptionPlan> plans = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    print('🚀 SelectPackagePage initState called');
    print('🔗 Base URL: ${ApiConstants.baseUrl}');
    _fetchSubscriptionPlans();
  }

  Future<void> _fetchSubscriptionPlans() async {
    print('🔍 Starting to fetch subscription plans...');
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final url = '${ApiConstants.baseUrl}subscriptions/plans';
      print('📡 Making API call to: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      print('📊 Response status: ${response.statusCode}');
      print('📋 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> plansJson = json.decode(response.body);
        print('✅ Successfully parsed ${plansJson.length} plans');

        setState(() {
          plans = plansJson
              .map((json) => SubscriptionPlan.fromJson(json))
              .where((plan) => plan.active) // Only show active plans
              .toList();
          isLoading = false;
        });

        print('🎯 Filtered to ${plans.length} active plans');
      } else {
        print('❌ API call failed with status: ${response.statusCode}');
        setState(() {
          errorMessage =
              'Failed to load subscription plans (Status: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      print('🚨 Exception occurred: $e');
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  // Build plan information section (title, description, features)
  Widget _buildPlanInfo(SubscriptionPlan plan, ThemeData theme) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.nickname,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          plan.description(t),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha:0.7),
          ),
        ),
        const SizedBox(height: 16),
        ...plan.features.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(feature, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Build plan price section with select button
  Widget _buildPlanPrice(
    SubscriptionPlan plan,
    ThemeData theme,
    BuildContext context,
  ) {
    final String formattedPrice = '\$${(plan.amount / 100).toStringAsFixed(2)}';
    final String interval = plan.interval == 'month' ? '/month' : '/year';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formattedPrice,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          interval,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            final tierId = plan.id;
            final userIdInt = widget.userId != null ? int.tryParse(widget.userId!) : null;
            if (kIsWeb) {
              context.go('/web-pay', extra: {
                'tierId': int.tryParse(tierId) ?? 0,
                'tier': plan.nickname,
                'userId': userIdInt,
              });
            } else {
              context.go('/native-billing', extra: {
                'tierId': int.tryParse(tierId) ?? 0,
                'tier': plan.nickname,
                'userId': userIdInt,
              });
            }
          },
          child: const Text('SELECT'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Choose Your Package',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSubscriptionPlans,
            tooltip: 'Refresh Plans',
          ),
        ],
      ),
      drawer: const CommonDrawer(currentRoute: '/select-package'),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? _buildErrorView(theme)
          : plans.isEmpty
          ? _buildEmptyView(theme)
          : _buildPackageListView(theme),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: ResponsiveContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error.withValues(alpha:0.7),
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              onPressed: _fetchSubscriptionPlans,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: ResponsiveContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha:0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'No subscription plans available',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please check back later or contact support',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageListView(ThemeData theme) {
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // For larger screens, display plans in a grid layout
          if (constraints.maxWidth > 900) {
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: plans.length,
              itemBuilder: (context, index) =>
                  _buildPlanCard(plans[index], theme),
            );
          }
          // For medium screens, 2 columns
          else if (constraints.maxWidth > 600) {
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.9,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: plans.length,
              itemBuilder: (context, index) =>
                  _buildPlanCard(plans[index], theme),
            );
          }
          // For mobile screens, use list view
          else {
            return ListView.builder(
              itemCount: plans.length,
              itemBuilder: (context, index) =>
                  _buildPlanCard(plans[index], theme),
            );
          }
        },
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha:0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWideScreen = constraints.maxWidth > 500;

            return isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildPlanInfo(plan, theme)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildPlanPrice(plan, theme, context),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPlanInfo(plan, theme),
                      const SizedBox(height: 16),
                      _buildPlanPrice(plan, theme, context),
                    ],
                  );
          },
        ),
      ),
    );
  }
}
