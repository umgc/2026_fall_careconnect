import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';

class SubscriptionTierSelectionPage extends StatefulWidget {
  final String? email;
  final String? userState;

  const SubscriptionTierSelectionPage({
    super.key,
    this.email,
    this.userState,
  });

  @override
  State<SubscriptionTierSelectionPage> createState() =>
      _SubscriptionTierSelectionPageState();
}

class _SubscriptionTierSelectionPageState
    extends State<SubscriptionTierSelectionPage> {
  String? _selectedTier;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 700;
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.subselection_choosePlan),
        backgroundColor: const Color(0xFF14366E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              t.subselection_selectPlan,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14366E),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.subselection_choosePlanDescr,
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildTierCard(
                        title: t.subselection_free,
                        price: '\$0',
                        period: t.subscriptionmodels_monthInterval,
                        features: [
                          t.subselection_freePlan1,
                          t.subselection_freePlan2,
                          t.subselection_freePlan3,
                        ],
                        tierId: 'free',
                        color: Colors.grey[600]!,
                        onTap: () => _selectTier('free'),
                        isSelected: _selectedTier == 'free',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTierCard(
                        title: t.subselection_standard,
                        price: '\$9.99',
                        period: t.subscriptionmodels_monthInterval,
                        features: [
                          t.subselection_standardPlan1,
                          t.subselection_standardPlan2,
                          t.subselection_standardPlan3,
                          t.subselection_standardPlan4,
                        ],
                        tierId: 'standard_monthly',
                        color: const Color(0xFF14366E),
                        isSelected: _selectedTier == 'standard_monthly',
                        onTap: () => _selectTier('standard_monthly'),
                        isPopular: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTierCard(
                        title: t.subselection_premium,
                        price: '\$29.99',
                        period: t.subscriptionmodels_monthInterval,
                        features: [
                          t.subselection_premiumPlan1,
                          t.subselection_premiumPlan2,
                          t.subselection_premiumPlan3,
                          t.subselection_premiumPlan4,
                          t.subselection_premiumPlan5,
                        ],
                        tierId: 'premium_monthly',
                        color: Colors.amber[700]!,
                        isSelected: _selectedTier == 'premium_monthly',
                        onTap: () => _selectTier('premium_monthly'),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  _buildTierCard(
                    title: t.subselection_free,
                    price: '\$0',
                    period: t.subscriptionmodels_monthInterval,
                    features: [
                      t.subselection_freePlan1,
                      t.subselection_freePlan2,
                      t.subselection_freePlan3,
                    ],
                    tierId: 'free',
                    color: Colors.grey[600]!,
                    onTap: () => _selectTier('free'),
                    isSelected: _selectedTier == 'free',
                  ),
                  const SizedBox(height: 16),
                  _buildTierCard(
                    title: t.subselection_standard,
                    price: '\$9.99',
                    period: t.subscriptionmodels_monthInterval,
                    features: [
                      t.subselection_standardPlan1,
                      t.subselection_standardPlan2,
                      t.subselection_standardPlan3,
                      t.subselection_standardPlan4,
                    ],
                    tierId: 'standard_monthly',
                    color: const Color(0xFF14366E),
                    isSelected: _selectedTier == 'standard_monthly',
                    onTap: () => _selectTier('standard_monthly'),
                    isPopular: true,
                  ),
                  const SizedBox(height: 16),
                  _buildTierCard(
                    title: t.subselection_premium,
                    price: '\$29.99',
                    period: t.subscriptionmodels_monthInterval,
                    features: [
                      t.subselection_premiumPlan1,
                      t.subselection_premiumPlan2,
                      t.subselection_premiumPlan3,
                      t.subselection_premiumPlan4,
                      t.subselection_premiumPlan5,
                    ],
                    tierId: 'premium_monthly',
                    color: Colors.amber[700]!,
                    isSelected: _selectedTier == 'premium_monthly',
                    onTap: () => _selectTier('premium_monthly'),
                  ),
                ],
              ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _selectedTier != null ? _continueToPayment : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14366E),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                t.subselection_continueToPayment,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _selectTier(String tierId) {
    setState(() { _selectedTier = tierId; });
  }

  void _continueToPayment() async {
    if (_selectedTier == null) return;

    // Free tier bypasses payment entirely
    if (_selectedTier == 'free') {
      final t = AppLocalizations.of(context)!;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.subselection_confirmFree),
          content: Text(t.subselection_selectedFree),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.voicecommand_confirmButton)),
          ],
        ),
      );
      if (confirm == true && mounted) {
        final session = await AuthTokenManager.getUserSession();
        final userId = session?['id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          try {
            final response = await ApiService.createSubscriptionByUser(userId, 'plan_free');
            print('Free plan response: ${response.statusCode} ${response.body}');
          } catch (e) {
            print('Free plan error: $e');
          }
        } else {
          print('Free plan: userId is empty, session: $session');
        }
        if (mounted) context.go('/subscription');

      }
      return;
    }


    final tierIdMap = {
      'standard_monthly': 2,
      'premium_monthly': 3,
    };

    final tierId = tierIdMap[_selectedTier] ?? 0;

    context.go('/web-pay', extra: {
      'tierId': tierId,
      'tier': _selectedTier,
      'email': widget.email,
      'state': widget.userState,
    });
  }

  Widget _buildTierCard({
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required String tierId,
    required Color color,
    required VoidCallback onTap,
    required bool isSelected,
    bool isPopular = false,
  }) {
    final t = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withValues(alpha:0.05) : Colors.white,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha:0.2), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  t.subselection_mostPopular,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            if (isPopular) const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: price,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                          ),
                          TextSpan(
                            text: period,
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? color : Colors.grey[300]!,
                      width: 2,
                    ),
                    color: isSelected ? color : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...features.map((feature) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(feature, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
