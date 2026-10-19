import '../../models/patient_model.dart';

class PatientParser {
  /// Parses a patient item from the API response
  static Patient parsePatientItem(Map<String, dynamic> patientItem) {
    try {
      // Handle nested patient structure
      if (patientItem.containsKey('patient')) {
        final Map<String, dynamic> patientData = patientItem['patient'];

        // Extract the relationship
        String relationship = patientData['relationship'] ?? 'Unknown';

        // Initialize link data
        int? linkId;
        String linkStatus = 'ACTIVE';

        // Extract link data if available
        if (patientItem.containsKey('link') &&
            patientItem['link'] is Map<String, dynamic>) {
          final linkData = patientItem['link'] as Map<String, dynamic>;
          print('🔍 Link data found: $linkData');

          // Extract linkId
          linkId = _extractLinkId(linkData);

          // Extract linkStatus
          linkStatus = _extractLinkStatus(linkData);

          // Get relationship from link type if available
          if (linkData.containsKey('linkType')) {
            relationship = patientData['relationship'] ??
                linkData['linkType'] ??
                'Unknown';
          }
        }

        // Construct patient object
        final Map<String, dynamic> completePatient = {
          'id': patientData['id'],
          'firstName': patientData['firstName'],
          'lastName': patientData['lastName'],
          'email': patientData['email'],
          'phone': patientData['phone'],
          'dob': patientData['dob'],
          'relationship': relationship,
          'address': patientData['address'],
          'linkId': linkId,
          'linkStatus': linkStatus,
        };

        print('🔍 Parsed patient with linkId: $linkId, status: $linkStatus');
        return Patient.fromJson(completePatient);
      } else {
        // Direct patient object (legacy format)
        return Patient.fromJson(patientItem);
      }
    } catch (e) {
      print('❌ Error parsing patient: $e');
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

  /// Extract link ID from link data
  static int? _extractLinkId(Map<String, dynamic> linkData) {
    // Try id field
    if (linkData.containsKey('id')) {
      if (linkData['id'] is int) {
        int id = linkData['id'];
        print('🔍 Found linkId from id field: $id');
        return id;
      } else if (linkData['id'] is String) {
        int? id = int.tryParse(linkData['id'].toString());
        print('🔍 Found linkId from id field (string): $id');
        return id;
      }
    }

    // Try linkId field
    if (linkData.containsKey('linkId')) {
      if (linkData['linkId'] is int) {
        int id = linkData['linkId'];
        print('🔍 Found linkId from linkId field: $id');
        return id;
      } else if (linkData['linkId'] is String) {
        int? id = int.tryParse(linkData['linkId'].toString());
        print('🔍 Found linkId from linkId field (string): $id');
        return id;
      }
    }

    print('⚠️ Link data does not contain id or linkId field');
    return null;
  }

  /// Extract link status from link data
  static String _extractLinkStatus(Map<String, dynamic> linkData) {
    // Try status field
    if (linkData.containsKey('status')) {
      String status = linkData['status']?.toString() ?? 'ACTIVE';
      print('🔍 Found linkStatus from status field: $status');
      return status;
    }

    // Try isActive field
    if (linkData.containsKey('isActive')) {
      bool isActive = linkData['isActive'] == true;
      String status = isActive ? 'ACTIVE' : 'SUSPENDED';
      print('🔍 Derived linkStatus from isActive field: $status');
      return status;
    }

    print('⚠️ Link data does not contain status field, defaulting to ACTIVE');
    return 'ACTIVE';
  }
}
