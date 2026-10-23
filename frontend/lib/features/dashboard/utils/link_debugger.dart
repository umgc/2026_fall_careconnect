import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

/// Add this helper class to debug the linkId extraction
class LinkDebugger {
  static Future<void> debugLinkIdForPatient(
    BuildContext context,
    Patient patient,
  ) async {
    try {
      print('');
      print('🔍 ----- LINK DEBUGGER STARTING -----');
      print(
          '🔍 Debugging linkId for patient: ${patient.id} - ${patient.firstName} ${patient.lastName}');
      print('🔍 Current patient data: $patient');
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        print('⚠️ Cannot debug - no logged in user');
        return;
      }
      print('🔍 Using caregiver ID: ${user.caregiverId}');

      final response = await ApiService.getCaregiverPatients(
        user.caregiverId ?? 0,
      );
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('📋 Raw API response: ${json.encode(responseData)}');

        // Check if we're dealing with a list or map structure
        if (responseData is List) {
          _searchInList(responseData, patient.id);
        } else if (responseData is Map<String, dynamic>) {
          // If there's a patients key containing a list
          if (responseData.containsKey('patients') &&
              responseData['patients'] is List) {
            _searchInList(responseData['patients'], patient.id);
          } else {
            print('⚠️ Unexpected response structure: ${responseData.keys}');
          }
        } else {
          print('⚠️ Unexpected response type: ${responseData.runtimeType}');
        }
      } else {
        print('❌ Failed to get API response: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error in debug: $e');
    }
  }

  static void _searchInList(List items, int patientId) {
    print(
      '🔍 Searching through ${items.length} items for patient ID: $patientId',
    );

    int mapItems = 0;
    int itemsWithId = 0;
    int itemsWithPatientField = 0;

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      mapItems++;

      if (item.containsKey('id')) itemsWithId++;
      if (item.containsKey('patient')) itemsWithPatientField++;

      // Direct patient structure
      if (item.containsKey('id') && item['id'] == patientId) {
        print('✅ Found patient with direct structure');
        print('📋 Patient data: ${json.encode(item)}');
        print('🔑 Available top-level keys: ${item.keys.toList()}');
        _checkForLinkIdInItem(item);
        return;
      }

      // Nested patient structure
      if (item.containsKey('patient') &&
          item['patient'] is Map<String, dynamic>) {
        final patient = item['patient'] as Map<String, dynamic>;
        if (patient.containsKey('id') && patient['id'] == patientId) {
          print('✅ Found patient with nested structure');
          print('📋 Container: ${json.encode(item)}');
          print('� Container keys: ${item.keys.toList()}');
          print('�📋 Patient data: ${json.encode(patient)}');
          print('🔑 Patient keys: ${patient.keys.toList()}');

          // Look for link data in container
          if (item.containsKey('link')) {
            print('📋 Link data found: ${json.encode(item['link'])}');
            if (item['link'] is Map<String, dynamic>) {
              final linkData = item['link'] as Map<String, dynamic>;
              print('🔑 Link keys: ${linkData.keys.toList()}');
              _checkForLinkIdInLink(linkData);

              // WORKAROUND: Try using the ID directly for testing
              if (linkData.containsKey('id')) {
                print(
                    '💡 RECOMMENDED: Use this ID for relationship operations: ${linkData['id']}');
              }
            } else {
              print('⚠️ Link data is not a map: ${item['link'].runtimeType}');
            }
          } else {
            print('⚠️ No link data found in container');
          }

          // Also check patient itself for linkId
          _checkForLinkIdInItem(patient);
          return;
        }
      }
    }

    print('⚠️ Patient ID $patientId not found in API response');
    print('📊 Summary: Searched through ${items.length} items');
    print(
        '📊 Found $mapItems maps, $itemsWithId with ID field, $itemsWithPatientField with patient field');
  }

  static void _checkForLinkIdInItem(Map<String, dynamic> item) {
    // Check for direct linkId
    if (item.containsKey('linkId')) {
      print('✅ linkId found directly: ${item['linkId']}');
    }

    // Check for id that might actually be linkId
    if (item.containsKey('id') && item.containsKey('patient')) {
      final patientData = item['patient'] as Map<String, dynamic>?;
      if (patientData != null && patientData.containsKey('id')) {
        if (item['id'] != patientData['id']) {
          print('✅ Possible linkId found as top-level id: ${item['id']}');
        }
      }
    }
  }

  static void _checkForLinkIdInLink(dynamic linkData) {
    if (linkData is! Map<String, dynamic>) {
      print('⚠️ Link data is not a map: $linkData');
      return;
    }

    print('🔎 Examining link data for ID field...');

    // Check for ID field - many possible formats
    int? foundId;
    String? idSource;

    if (linkData.containsKey('id')) {
      foundId = linkData['id'] is int
          ? linkData['id']
          : int.tryParse(linkData['id'].toString());
      idSource = 'link.id';
      print(
          '✅ linkId found in link.id: ${linkData['id']} (${linkData['id'].runtimeType})');
    } else if (linkData.containsKey('linkId')) {
      foundId = linkData['linkId'] is int
          ? linkData['linkId']
          : int.tryParse(linkData['linkId'].toString());
      idSource = 'link.linkId';
      print(
          '✅ linkId found in link.linkId: ${linkData['linkId']} (${linkData['linkId'].runtimeType})');
    } else if (linkData.containsKey('relationshipId')) {
      foundId = linkData['relationshipId'] is int
          ? linkData['relationshipId']
          : int.tryParse(linkData['relationshipId'].toString());
      idSource = 'link.relationshipId';
      print(
          '✅ linkId found in link.relationshipId: ${linkData['relationshipId']} (${linkData['relationshipId'].runtimeType})');
    } else {
      print(
        '⚠️ No linkId found in link data. Available keys: ${linkData.keys.toList()}',
      );
    }

    // Check for status field - many possible formats
    print('🔎 Examining link data for status field...');
    String? foundStatus;
    String? statusSource;

    if (linkData.containsKey('status')) {
      foundStatus = linkData['status']?.toString();
      statusSource = 'link.status';
      print(
          '✅ linkStatus found: ${linkData['status']} (${linkData['status'].runtimeType})');
    } else if (linkData.containsKey('isActive')) {
      final isActive = linkData['isActive'] == true;
      foundStatus = isActive ? 'ACTIVE' : 'SUSPENDED';
      statusSource = 'link.isActive';
      print('✅ isActive status found: ${linkData['isActive']} → $foundStatus');
    } else if (linkData.containsKey('active')) {
      final isActive = linkData['active'] == true;
      foundStatus = isActive ? 'ACTIVE' : 'SUSPENDED';
      statusSource = 'link.active';
      print('✅ active status found: ${linkData['active']} → $foundStatus');
    } else {
      print('⚠️ No status found in link data');
    }

    // Summary
    if (foundId != null && foundStatus != null) {
      print('');
      print('✅ SOLUTION FOUND:');
      print('  - Use linkId: $foundId (from $idSource)');
      print('  - Status is: $foundStatus (from $statusSource)');
      print('  - Use this ID for suspending/reactivating the relationship');
      print('');
    }
  }

  /// Provides actionable recommendations to fix the linkId issue
  static void suggestFixes(BuildContext context) {
    print('');
    print('🛠️ ----- RECOMMENDED FIXES -----');
    print(
        '1. Check if the API response includes a link object for each patient');
    print(
        '2. If no link object is found, check if there are IDs directly on the patient object');
    print(
        '3. Update PatientParser.dart to extract linkId from all possible locations:');
    print('   - From link.id');
    print('   - From link.linkId');
    print('   - From link.relationshipId');
    print('   - From container.id (if different from patient.id)');
    print(
        '4. Make sure your backend API returns relationship IDs consistently');
    print('');
    print(
        '💡 Temporary workaround: You can add a code to generate temporary linkIds');
    print('   in PatientParser.dart when linkId is null but status is ACTIVE:');
    print('');
    print('   // TEMPORARY: Generate a linkId if null but status is ACTIVE');
    print('   if (linkId == null && linkStatus == "ACTIVE") {');
    print('     linkId = 100000 + patient["id"];');
    print('     print("Generated temporary linkId: \$linkId");');
    print('   }');
    print('');
    print('🔍 ----- LINK DEBUGGER FINISHED -----');
  }
}

/// Add this extension method to the Patient class
extension PatientDebugExtension on Patient {
  Future<void> debugLinkId(BuildContext context) async {
    await LinkDebugger.debugLinkIdForPatient(context, this);
    LinkDebugger.suggestFixes(context);
  }
}
