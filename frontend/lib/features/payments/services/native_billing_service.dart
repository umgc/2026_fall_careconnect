import 'dart:async';
import 'dart:io' show Platform;
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/app_config.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';


class NativeBillingService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final int userId;
  final void Function()? onPurchaseSuccess;
  final void Function(String error)? onPurchaseError;
  final AppLocalizations t;

  GooglePlayPurchaseDetails? _activePurchase;

  NativeBillingService({
    required this.userId,
    this.onPurchaseSuccess,
    this.onPurchaseError,
    required this.t,
  });

  void init() {
    final purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(_onPurchaseUpdated, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      onPurchaseError?.call(error.toString());
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }

  Future<void> buySubscription(String productId, {required int userId}) async {
    final available = await _iap.isAvailable();
    if (!available) throw Exception(t.billservice_inAppUnavailable);

    final ProductDetailsResponse response =
        await _iap.queryProductDetails({productId}.toSet());
    if (response.notFoundIDs.isNotEmpty) {
      throw Exception('${t.billservice_productNotFound}: $productId');
    }

    final product = response.productDetails.first;

    if (product is GooglePlayProductDetails) {
      final offerToken = product.offerToken;
      if (offerToken == null) throw Exception('${t.billservice_noOfferToken} $productId');

      GooglePlayPurchaseParam googleParam;

      if (_activePurchase != null && _activePurchase!.productID != productId) {
        googleParam = GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: offerToken,
          changeSubscriptionParam: ChangeSubscriptionParam(
            oldPurchaseDetails: _activePurchase!,
            replacementMode: ReplacementMode.withTimeProration,
          ),
        );
      } else {
        googleParam = GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: offerToken,
        );
      }

      await _iap.buyNonConsumable(purchaseParam: googleParam);
    } else {
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      try {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          if (purchase is GooglePlayPurchaseDetails) {
            _activePurchase = purchase;
          }
          await _verifyPurchaseWithServer(purchase);
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          onPurchaseSuccess?.call();
        } else if (purchase.status == PurchaseStatus.error) {
          onPurchaseError?.call(purchase.error?.message ?? t.nativebilling_purchaseFailed);
        }
      } catch (e) {
        onPurchaseError?.call('${t.billservice_verifyFailed}: $e');
      }
    }
  }

  Future<void> _verifyPurchaseWithServer(PurchaseDetails purchase) async {
    final source = Platform.isIOS ? 'apple' : 'google';
    final backendBase = AppConfig.getBackendBaseUrl();
    final uri = Uri.parse('$backendBase/v1/api/billing/pay/$source');

    final tierMap = {
      'standard_monthly': 2,
      'premium_monthly': 3,
      'free_monthly': 1,
    };
    final tierId = tierMap[purchase.productID] ?? 2;

    final body = {
      'token': purchase.verificationData.serverVerificationData,
      'tierId': tierId,
      'state': 'CA',
      'userId': userId,
    };

    final headers = <String, String>{'Content-Type': 'application/json'};
    final resp =
        await http.post(uri, headers: headers, body: jsonEncode(body));

    if (resp.statusCode != 200) {
      throw Exception('${t.billservice_paymentProcessFailed}: ${resp.body}');
    }
  }
}
