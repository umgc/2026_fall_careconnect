import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:http/http.dart' as http;

/// Loads an image from [url] with auth headers and displays it, or [fallback] on error.
class AuthNetworkImage extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;

  const AuthNetworkImage({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveImageUrl(url);
    if (resolved == null || resolved.isEmpty) return fallback;
    return FutureBuilder<http.Response>(
      future: _fetchImage(resolved),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data!.statusCode == 200 &&
            snapshot.data!.bodyBytes.isNotEmpty) {
          return Image.memory(
            snapshot.data!.bodyBytes,
            width: width,
            height: height,
            fit: fit,
          );
        }
        return fallback;
      },
    );
  }

  static Future<http.Response> _fetchImage(String fullUrl) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    return await http.get(Uri.parse(fullUrl), headers: headers);
  }
}

/// Returns Material icon for ADL/IADL activity name (fallback when no URL).
IconData iconForActivityName(String name, String category) {
  final n = name.toLowerCase().trim();
  if (category.toUpperCase() == 'ADL') {
    if (n.contains('bathing')) return Icons.bathtub;
    if (n.contains('dressing')) return Icons.checkroom;
    if (n.contains('toileting')) return Icons.wc;
    if (n.contains('transferring')) return Icons.transfer_within_a_station;
    if (n.contains('mobility') || n.contains('ambulation'))
      return Icons.directions_walk;
    if (n.contains('eating')) return Icons.restaurant;
    if (n.contains('hygiene') || n.contains('grooming')) return Icons.face;
  } else {
    if (n.contains('meal') && n.contains('prep')) return Icons.soup_kitchen;
    if (n.contains('housekeeping')) return Icons.cleaning_services;
    if (n.contains('laundry')) return Icons.local_laundry_service;
    if (n.contains('medication')) return Icons.medication;
    if (n.contains('money')) return Icons.attach_money;
    if (n.contains('transportation')) return Icons.directions_car;
    if (n.contains('communication')) return Icons.chat;
    if (n.contains('community') || n.contains('participation'))
      return Icons.people;
    if (n.contains('shopping')) return Icons.shopping_cart;
    if (n.contains('safety')) return Icons.health_and_safety;
  }
  return Icons.task_alt;
}
