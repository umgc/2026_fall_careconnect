import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env_constant.dart';
import '../../services/auth_token_manager.dart';

class ApiConstants {
  static final String _host = getBackendBaseUrl();
  static final String informedDelivery = '$_host/v1/api/usps';
}

class InformedDeliveryService {
  static Future<Map<String, dynamic>> fetchInformedDelivery() async {
    final headers = await AuthTokenManager.getAuthHeaders();

    final response = await http.get(
      Uri.parse('${ApiConstants.informedDelivery}/mail'),
      headers: headers,
    );

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception("Not authorized. Please log in again.");
    } else {
      print("Status: ${response.statusCode}, Body: '${response.body}'");
      throw Exception("Failed to fetch informed delivery data");
    }
  }
}
