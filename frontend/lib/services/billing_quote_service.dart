import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_token_manager.dart';

class BillingQuote {
  final int tierId;
  final String tierName;
  final int subtotalCents;
  final int taxCents;
  final int totalCents;
  final String currency;
  final double taxRate;
  final String taxJurisdiction;
  final String? errorMessage;

  BillingQuote({
    required this.tierId,
    required this.tierName,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.currency,
    required this.taxRate,
    required this.taxJurisdiction,
    this.errorMessage,
  });

  factory BillingQuote.fromJson(Map<String, dynamic> json) {
    return BillingQuote(
      tierId: json['tierId'] as int? ?? 0,
      tierName: json['tierName'] as String? ?? '',
      subtotalCents: json['subtotalCents'] as int? ?? 0,
      taxCents: json['taxCents'] as int? ?? 0,
      totalCents: json['totalCents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.0,
      taxJurisdiction: json['taxJurisdiction'] as String? ?? 'UNKNOWN',
      errorMessage: json['errorMessage'] as String?,
    );
  }

  String get subtotalDisplay => '\$${(subtotalCents / 100).toStringAsFixed(2)}';
  String get taxDisplay => '\$${(taxCents / 100).toStringAsFixed(2)}';
  String get totalDisplay => '\$${(totalCents / 100).toStringAsFixed(2)}';
  String get taxPercentageDisplay => '${(taxRate * 100).toStringAsFixed(2)}%';
}

class BillingQuoteService {
  final String backendBase;

  BillingQuoteService({required this.backendBase});

  /// Fetch a billing quote for a subscription tier
  /// Requires: tierId (required), state (required or user must have stored address)
  /// Optional: userId, postalCode, city
  Future<BillingQuote> getQuote({
    required int tierId,
    int? userId,
    String? state,
    String? postalCode,
    String? city,
  }) async {
    try {
      final uri = Uri.parse('$backendBase/v1/api/billing/quote');

      final requestBody = {
        'tierId': tierId,
        if (userId != null) 'userId': userId,
        if (state != null) 'state': state,
        if (postalCode != null) 'postalCode': postalCode,
        if (city != null) 'city': city,
      };

      // Try to get auth headers, but make them optional
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      try {
        final authHeaders = await AuthTokenManager.getAuthHeaders();
        headers.addAll(authHeaders);
      } catch (e) {
        // JWT not available - continue without it
        // The billing quote endpoint should work for unauthenticated users
      }

      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return BillingQuote.fromJson(json);
      } else if (response.statusCode == 401) {
        // Unauthenticated - return a default quote with a message
        throw Exception(
            'Billing quote requires authentication. Please ensure you are logged in. Response: ${response.body}');
      } else {
        throw Exception(
            'Failed to fetch billing quote: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
