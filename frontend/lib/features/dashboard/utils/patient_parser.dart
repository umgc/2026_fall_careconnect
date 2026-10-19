import 'dart:convert';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';

/// Utility class for parsing patient data from various API response formats
class PatientParser {
  /// Parse a patient item from any supported API response format
  static Patient parsePatientItem(Map<String, dynamic> patientItem) {
    try {
      // Detailed logging of the raw patient item for debugging
      print('🔄 Processing patient item: ${json.encode(patientItem)}');

      // Handle nested patient structure (new API format)
      if (patientItem.containsKey('patient')) {
        final Map<String, dynamic> patientData = patientItem['patient'];
        print('📋 Found nested patient data: ${json.encode(patientData)}');

        // Extract the relationship
        String relationship = patientData['relationship'] ?? 'Unknown';

        // Initialize link data
        int? linkId;
        String linkStatus = 'ACTIVE';

        // Try to find linkId directly in the patient item (some APIs put it at the top level)
        if (patientItem.containsKey('linkId')) {
          linkId = patientItem['linkId'] is int
              ? patientItem['linkId']
              : int.tryParse(patientItem['linkId'].toString());
          print('🔍 Found linkId at top level: $linkId');
        }

        // Extract link data if available
        if (patientItem.containsKey('link')) {
          // Handle both Map and non-Map cases (like strings)
          if (patientItem['link'] is Map<String, dynamic>) {
            final linkData = patientItem['link'] as Map<String, dynamic>;
            print('🔍 Link data found (Map): ${json.encode(linkData)}');

            // Extract linkId - check all possible fields
            int? extractedLinkId = _extractLinkId(linkData);
            if (extractedLinkId != null) {
              linkId = extractedLinkId;
              print('✅ Using linkId from link data: $linkId');
            }

            // Extract linkStatus - check all possible fields
            linkStatus = _extractLinkStatus(linkData);

            // Get relationship from link type if available
            if (linkData.containsKey('linkType')) {
              relationship = patientData['relationship'] ??
                  linkData['linkType'] ??
                  'Unknown';
            }
          } else if (patientItem['link'] is String) {
            // Try to parse the string as JSON if it's a JSON string
            try {
              final linkData = json.decode(patientItem['link']);
              if (linkData is Map<String, dynamic>) {
                print(
                  '🔍 Link data found (JSON string): ${patientItem['link']}',
                );
                int? extractedLinkId = _extractLinkId(linkData);
                if (extractedLinkId != null) {
                  linkId = extractedLinkId;
                  print('✅ Using linkId from parsed link string: $linkId');
                }
                linkStatus = _extractLinkStatus(linkData);
              }
            } catch (e) {
              print(
                '⚠️ Failed to parse link string as JSON: ${patientItem['link']}',
              );
            }
          } else {
            print(
              '⚠️ Link data is not a map or string: ${patientItem['link'].runtimeType}',
            );
          }
        } else {
          print('⚠️ No link data found in patient item');
        }

        // TEMPORARY FIX: Generate a linkId if it's null but status is ACTIVE
        // This is only for testing and debugging purposes
        if (linkId == null && linkStatus == 'ACTIVE') {
          if (patientData.containsKey('id')) {
            // Use patient ID as a base for generating a linkId
            final patientId = patientData['id'] is int
                ? patientData['id'] as int
                : int.tryParse(patientData['id'].toString());
            if (patientId != null) {
              linkId = 100000 + patientId;
              print(
                '⚠️ Generated temporary linkId for testing: $linkId (based on patient.id: $patientId)',
              );
            }
          } else {
            print(
              '⚠️ Cannot generate temporary linkId: patient has no ID field',
            );
          }
        } else if (linkId == null) {
          print(
            '⚠️ Not generating temporary linkId because status is: $linkStatus',
          );
        }

        // If we still don't have a linkId, try to find it in patientData
        if (linkId == null && patientData.containsKey('linkId')) {
          linkId = patientData['linkId'] is int
              ? patientData['linkId']
              : int.tryParse(patientData['linkId'].toString());
          print('🔍 Found linkId in patient data: $linkId');
        }

        // Check if the id from patientItem might be a linkId (some APIs do this)
        if (linkId == null &&
            patientItem.containsKey('id') &&
            patientItem['id'] != patientData['id']) {
          linkId = patientItem['id'] is int
              ? patientItem['id']
              : int.tryParse(patientItem['id'].toString());
          print('🔍 Using top-level id as linkId: $linkId');
        }

        // Construct patient object with all required fields
        final Map<String, dynamic> completePatient = {
          'id': patientData['id'],
          'firstName': patientData['firstName'] ?? '',
          'lastName': patientData['lastName'] ?? '',
          'email': patientData['email'] ?? '',
          'phone': patientData['phone'] ?? '',
          'dob': patientData['dob'] ?? '',
          'relationship': relationship,
          'address': patientData['address'],
          'linkId': linkId,
          'linkStatus': linkStatus,
        };

        print(
          '✅ Parsed patient: ${completePatient['firstName']} ${completePatient['lastName']}, linkId: $linkId, status: $linkStatus',
        );
        return Patient.fromJson(completePatient);
      } else {
        // Direct patient object (legacy format)
        print('📋 Processing direct patient object (legacy format)');
        return Patient.fromJson(patientItem);
      }
    } catch (e, stackTrace) {
      print('❌ Error parsing patient: $e');
      print('❌ Stack trace: $stackTrace');
      return Patient(
        id: 0,
        firstName: 'Error',
        lastName: 'Loading',
        email: '',
        phone: '',
        dob: '',
        relationship: 'Error: $e',
      );
    }
  }

  /// Extract link ID from link data checking multiple possible field names
  static int? _extractLinkId(Map<String, dynamic> linkData) {
    print('🔎 Examining link data keys: ${linkData.keys.toList()}');

    // Try to extract an integer from a field, handling both int and String types
    int? tryExtractInt(dynamic value, String fieldName) {
      if (value == null) return null;

      if (value is int) {
        print('🔍 Found linkId from $fieldName field (int): $value');
        return value;
      } else {
        try {
          int? parsed = int.tryParse(value.toString());
          if (parsed != null) {
            print(
              '🔍 Found linkId from $fieldName field (converted string): $parsed',
            );
            return parsed;
          }
        } catch (e) {
          print('⚠️ Failed to parse $fieldName as int: $value');
        }
      }
      return null;
    }

    // Check fields in priority order (most common field names first)
    final possibleFields = [
      'id',
      'linkId',
      'relationshipId',
      'link_id',
      'relationship_id',
    ];

    for (final field in possibleFields) {
      if (linkData.containsKey(field)) {
        final id = tryExtractInt(linkData[field], field);
        if (id != null) {
          print('✅ Using linkId from $field field: $id');
          return id;
        }
      }
    }

    // Check nested 'id' field if there's a nested 'link' object
    if (linkData.containsKey('link') &&
        linkData['link'] is Map<String, dynamic>) {
      final nestedLinkData = linkData['link'] as Map<String, dynamic>;
      if (nestedLinkData.containsKey('id')) {
        final id = tryExtractInt(nestedLinkData['id'], 'link.id');
        if (id != null) {
          print('✅ Using linkId from nested link.id field: $id');
          return id;
        }
      }
    }

    print('⚠️ No valid linkId found in link data');
    return null;
  }

  /// Extract link status from link data checking multiple possible field names
  static String _extractLinkStatus(Map<String, dynamic> linkData) {
    print('🔎 Examining link data for status fields');

    // Check for direct status field
    if (linkData.containsKey('status')) {
      final status = linkData['status']?.toString() ?? 'ACTIVE';
      print('🔍 Found linkStatus from status field: $status');
      return _normalizeStatusValue(status);
    }

    // Check for isActive or active boolean fields
    final booleanFields = [
      'isActive',
      'active',
      'is_active',
      'enabled',
      'is_enabled',
    ];
    for (final field in booleanFields) {
      if (linkData.containsKey(field)) {
        final isActive = linkData[field] == true;
        final status = isActive ? 'ACTIVE' : 'SUSPENDED';
        print('🔍 Derived linkStatus from $field field: $status');
        return status;
      }
    }

    // Check nested status in 'link' object
    if (linkData.containsKey('link') &&
        linkData['link'] is Map<String, dynamic>) {
      final nestedLink = linkData['link'] as Map<String, dynamic>;
      if (nestedLink.containsKey('status')) {
        final status = nestedLink['status']?.toString() ?? 'ACTIVE';
        print('🔍 Found linkStatus from nested link.status field: $status');
        return _normalizeStatusValue(status);
      }
    }

    print('⚠️ No status information found in link data, defaulting to ACTIVE');
    return 'ACTIVE';
  }

  /// Normalize status values to either ACTIVE or SUSPENDED
  static String _normalizeStatusValue(String status) {
    final lowerStatus = status.toLowerCase();

    if ([
      'active',
      'enabled',
      'true',
      '1',
      'yes',
      'valid',
    ].contains(lowerStatus)) {
      return 'ACTIVE';
    }

    if ([
      'inactive',
      'suspended',
      'disabled',
      'false',
      '0',
      'no',
      'invalid',
    ].contains(lowerStatus)) {
      return 'SUSPENDED';
    }

    // If it's already properly formatted or we don't recognize it
    return status.toUpperCase();
  }
}
