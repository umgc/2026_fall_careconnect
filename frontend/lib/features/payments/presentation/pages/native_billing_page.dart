import 'dart:io' show Platform;
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../config/app_config.dart';
import '../../../../services/billing_quote_service.dart';
import '../../services/native_billing_service.dart';

class NativeBillingPage extends StatefulWidget {
  final int tierId;
  final String? tier;
  final int? userId;

  const NativeBillingPage({
    super.key,
    this.tierId = 0,
    this.tier,
    this.userId,
  });

  @override
  State<NativeBillingPage> createState() => _NativeBillingPageState();
}

class _NativeBillingPageState extends State<NativeBillingPage> {
  late final NativeBillingService _billing;

  BillingQuote? _billingQuote;
  bool _loadingQuote = true;
  String? _quoteError;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    if (widget.tierId == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/home');
      });
      return;
    }
    _billing = NativeBillingService(
      t: AppLocalizations.of(context)!,
      userId: widget.userId ?? 0,
      onPurchaseSuccess: () {
        if (mounted) context.go('/subscription');
      },
      onPurchaseError: (error) {
        if (mounted) {
          final t = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${t.nativebilling_purchaseFailed}: $error'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isPurchasing = false);
        }
      },
    );
    _billing.init();
    _fetchBillingQuote();
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  Future<void> _fetchBillingQuote() async {
    try {
      final service = BillingQuoteService(backendBase: AppConfig.getBackendBaseUrl());
      final quote = await service.getQuote(
        tierId: widget.tierId,
        userId: widget.userId,
        state: 'CA',
      );
      if (mounted) {
        setState(() {
          _billingQuote = quote;
          _loadingQuote = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _quoteError = e.toString();
          _loadingQuote = false;
        });
      }
    }
  }

  String _productIdForTier() {
    final tierMap = {
      1: 'free_monthly',
      2: 'standard_monthly',
      3: 'premium_monthly',
    };
    return tierMap[widget.tierId] ?? widget.tier ?? 'standard_monthly';
  }

  Future<void> _startPurchase() async {
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);
    try {
      await _billing.buySubscription(
        _productIdForTier(),
        userId: widget.userId ?? 0,
      );
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.nativebilling_purchaseError}: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.nativebilling_completeYourPurchase),
        backgroundColor: const Color(0xFF00A7C8),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final t = AppLocalizations.of(context)!;
    if (_loadingQuote) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quoteError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_quoteError', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchBillingQuote, child: Text(t.nativebilling_retry)),
            ],
          ),
        ),
      );
    }

    final quote = _billingQuote;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quote != null) ...[
            _buildOrderSummary(quote),
            const SizedBox(height: 32),
          ],
          Text(
            kIsWeb
                ? t.nativebilling_completeYourPurchase
                : Platform.isIOS
                    ? t.nativebilling_viaAppStore
                    : t.nativebilling_viaGooglePlay,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00A7C8)),
          ),
          const SizedBox(height: 8),
          Text(
            kIsWeb
                ? t.nativebilling_processingWeb
                : Platform.isIOS
                    ? t.nativebilling_processingAppStore
                    : t.nativebilling_processingGooglePlay,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPurchasing ? null : _startPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A7C8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _isPurchasing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(t.nativebilling_subscribeNow,
                      style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.go('/subscription'),
              child: Text(t.cancel,
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(BillingQuote quote) {
    final t = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.nativebilling_orderSummary,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00A7C8))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(quote.tierName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
              Text(quote.subtotalDisplay,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
          Container(
              height: 1,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(vertical: 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${t.nativebilling_taxes} (${quote.taxPercentageDisplay})',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              Text(quote.taxDisplay,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
          Container(
              height: 1,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(vertical: 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.nativebilling_total,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00A7C8))),
              Text(quote.totalDisplay,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00A7C8))),
            ],
          ),
        ],
      ),
    );
  }
}
