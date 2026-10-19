import 'package:http/http.dart' as http;
import 'dart:convert';

/// Model for a Google Places address suggestion
class AddressSuggestion {
  final String mainText; // e.g., "123 Main Street"
  final String secondaryText; // e.g., "New York, NY"
  final String placeId; // For future place details lookup
  final String fullDescription; // Complete address text

  AddressSuggestion({
    required this.mainText,
    required this.secondaryText,
    required this.placeId,
    required this.fullDescription,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    return AddressSuggestion(
      mainText: json['main_text'] as String? ?? '',
      secondaryText: json['secondary_text'] as String? ?? '',
      placeId: json['place_id'] as String? ?? '',
      fullDescription: json['description'] as String? ?? '',
    );
  }

  @override
  String toString() => fullDescription;
}

/// Model for parsed address components
class ParsedAddress {
  final String street; // Street address (line1)
  final String city;
  final String state; // 2-letter state code
  final String zip;
  final String country;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  ParsedAddress({
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    this.country = 'US',
    this.latitude,
    this.longitude,
    this.placeId,
  });

  /// Parse a full address string into components
  /// This is a fallback parser for when Google Places API isn't available
  static ParsedAddress parseFromString(String address) {
    // Simple regex-based parsing (fallback)
    // Format: "street, city, state zip"
    final parts = address.split(',').map((p) => p.trim()).toList();

    String street = '';
    String city = '';
    String state = '';
    String zip = '';

    if (parts.isNotEmpty) {
      street = parts[0];
    }
    if (parts.length > 1) {
      city = parts[1];
    }
    if (parts.length > 2) {
      final stateZip = parts[2].split(RegExp(r'\s+'));
      if (stateZip.length >= 2) {
        state = stateZip[0].toUpperCase();
        zip = stateZip.sublist(1).join(' ');
      }
    }

    return ParsedAddress(
      street: street,
      city: city,
      state: state,
      zip: zip,
    );
  }
}

class GooglePlacesService {
  final String? apiKey;
  final String backendBase;

  GooglePlacesService({this.apiKey, required this.backendBase});

  /// Get address suggestions from backend proxy (which calls Google Places API)
  /// Returns empty list if no backend connection or API key not configured
  Future<List<AddressSuggestion>> getSuggestions(String input) async {
    // If input is empty, return empty list
    if (input.trim().isEmpty) {
      return [];
    }

    try {
      // Call backend endpoint instead of Google API directly
      // This avoids CORS issues and keeps API key secure on backend
      final uri = Uri.parse('$backendBase/v1/api/address/suggestions').replace(
        queryParameters: {
          'input': input,
        },
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 5),
            onTimeout: () => http.Response('timeout', 500),
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final status = json['status'] as String?;

        // Check if API key is not configured
        if (status == 'NO_API_KEY') {
          print('⚠️ Google Places API key not configured on backend');
          return [];
        }

        final predictions =
            (json['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        return predictions
            .map((p) => AddressSuggestion(
                  mainText: p['main_text'] as String? ?? '',
                  secondaryText: p['secondary_text'] as String? ?? '',
                  placeId: p['place_id'] as String? ?? '',
                  fullDescription: p['description'] as String? ?? '',
                ))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching address suggestions: $e');
      return [];
    }
  }

  /// Get detailed place information from backend proxy
  /// Uses simplified address parsing without requiring API call
  Future<ParsedAddress> getPlaceDetails(String placeIdOrAddress) async {
    // For addresses that aren't place IDs, parse them directly
    if (placeIdOrAddress.contains(',')) {
      return ParsedAddress.parseFromString(placeIdOrAddress);
    }

    try {
      // Call backend endpoint to get place details
      final uri = Uri.parse('$backendBase/v1/api/address/details').replace(
        queryParameters: {
          'placeId': placeIdOrAddress,
        },
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 5),
            onTimeout: () => http.Response('timeout', 500),
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = json['result'] as Map<String, dynamic>?;

        if (result != null) {
          return _parseAddressComponents(result);
        }
      }
      return ParsedAddress.parseFromString(placeIdOrAddress);
    } catch (e) {
      print('Error fetching place details: $e');
      return ParsedAddress.parseFromString(placeIdOrAddress);
    }
  }

  /// Parse Google Place Details address components into ParsedAddress
  ParsedAddress _parseAddressComponents(Map<String, dynamic> placeResult) {
    String street = '';
    String city = '';
    String state = '';
    String zip = '';
    double? lat;
    double? lng;

    // Parse address components
    final components = (placeResult['address_components'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    for (final component in components) {
      final types = (component['types'] as List?)?.cast<String>() ?? [];
      final longName = component['long_name'] as String? ?? '';
      final shortName = component['short_name'] as String? ?? '';

      if (types.contains('street_number')) {
        street = '$longName ';
      } else if (types.contains('route')) {
        street += longName;
      } else if (types.contains('locality')) {
        city = longName;
      } else if (types.contains('administrative_area_level_1')) {
        state = shortName.toUpperCase();
      } else if (types.contains('postal_code')) {
        zip = longName;
      }
    }

    // Parse geometry
    final geometry = placeResult['geometry'] as Map<String, dynamic>?;
    if (geometry != null) {
      final location = geometry['location'] as Map<String, dynamic>?;
      if (location != null) {
        lat = (location['lat'] as num?)?.toDouble();
        lng = (location['lng'] as num?)?.toDouble();
      }
    }

    return ParsedAddress(
      street: street.trim(),
      city: city,
      state: state,
      zip: zip,
      latitude: lat,
      longitude: lng,
    );
  }
}
