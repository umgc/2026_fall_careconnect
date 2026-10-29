import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import '../../models/patient_model.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:http/http.dart' as http;
import '../../../../services/subscription_service.dart';
import '../../../../widgets/responsive_page_wrapper.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import '../../../../services/messaging_service.dart';
import '../../../../widgets/messaging_widget.dart';
import '../../../../widgets/call_notification_status_indicator.dart';
import '../../../../widgets/hybrid_video_call_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/notifications_panel_widget.dart';

import 'patient_medical_notes_page.dart';

class CaregiverDashboard extends StatefulWidget {
  final String userRole;
  final int? patientId;
  final int caregiverId;

  const CaregiverDashboard({
    super.key,
    this.userRole = 'CAREGIVER',
    this.patientId,
    this.caregiverId = 1,
  });

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  List<Patient> patients = [];
  bool loading = true;
  String? error;
  String? caregiverName;

  // Real-time call notification state
  bool _callNotificationInitialized = false;

  // ===== Notifications (collapsible) state =====
  List<NotificationItem> _notifications = [];

  // Main content builder method
  Widget _buildMainContent() {
    return _buildContentBasedOnState();
  }

  @override
  void initState() {
    super.initState();
    // Use Future.microtask to avoid calling setState during build
    Future.microtask(() => fetchPatients());
    _loadCaregiverName();
    _initializeServices();
    _callNotificationInitialized = true;
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      // TODO: wire to your real service, e.g.:
      // final items = await NotificationService.fetchForCaregiver(userId);
      // setState(() => _notifications = items);

      // No hardcoded items; keep empty until service is wired
      setState(() => _notifications = []);
    } catch (_) {
      // keep UI stable on error
    }
  }

  Future<void> _initializeServices() async {
    try {
      // await VideoCallService.initializeService();
      await MessagingService.initialize();
    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  Future<void> _loadCaregiverName() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      if (userProvider.user?.name != null) {
        setState(() {
          caregiverName = userProvider.user!.name;
        });
      }
    } catch (e) {
      print('Error loading caregiver name: $e');
    }
  }

  @override
  void didUpdateWidget(CaregiverDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh if the caregiverId changed
    if (oldWidget.caregiverId != widget.caregiverId) {
      fetchPatients();
    }
  }

  @override
  void dispose() {
    // Clean up call notification service
    super.dispose();
  }

  Future<void> fetchPatients() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiverId = userProvider.user?.caregiverId ?? widget.caregiverId;

      // Get auth headers
      final headers = await AuthTokenManager.getAuthHeaders();
      final baseUrl = ApiConstants.baseUrl;
      final url = Uri.parse('${baseUrl}caregivers/$caregiverId/patients');
      print('🔍 Fetching patients from: $url');
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('🔍 Received patient data: $data');

        List<Patient> parsedPatients = [];
        for (var json in data) {
          try {
            Map<String, dynamic> patientJson;
            if (json.containsKey('patient') && json['patient'] != null) {
              // Safely convert to Map<String, dynamic>
              final patientData = json['patient'];
              if (patientData is Map) {
                patientJson = Map<String, dynamic>.from(patientData);
              } else {
                print('⚠️ Warning: patient data is not a Map: $patientData');
                continue;
              }

              // Merge link info
              if (json.containsKey('link') && json['link'] != null) {
                final linkData = json['link'];
                if (linkData is Map) {
                  final link = Map<String, dynamic>.from(linkData);
                  patientJson['linkId'] = link['id'];
                  patientJson['linkStatus'] = link['status'] ?? 'ACTIVE';
                  // Always set relationship from link if present
                  patientJson['relationship'] = patientJson['relationship'] ??
                      (link['relationship'] ?? 'Patient');
                }
              }
            } else {
              // Handle case where json is the patient data directly
              if (json is Map) {
                patientJson = Map<String, dynamic>.from(json);
              } else {
                print('⚠️ Warning: json data is not a Map: $json');
                continue;
              }
            }
            // Ensure null gender is handled
            if (!patientJson.containsKey('gender') ||
                patientJson['gender'] == null) {
              patientJson['gender'] = '';
            }
            // Ensure linkId and linkStatus are present
            if (!patientJson.containsKey('linkId') &&
                json.containsKey('link')) {
              patientJson['linkId'] = json['link']?['id'];
            }
            if (!patientJson.containsKey('linkStatus') &&
                json.containsKey('link')) {
              patientJson['linkStatus'] = json['link']?['status'] ?? 'ACTIVE';
            }

            // Ensure essential fields have default values
            patientJson['firstName'] =
                patientJson['firstName']?.toString() ?? '';
            patientJson['lastName'] = patientJson['lastName']?.toString() ?? '';
            patientJson['email'] = patientJson['email']?.toString() ?? '';
            patientJson['phone'] = patientJson['phone']?.toString() ?? '';
            patientJson['dob'] = patientJson['dob']?.toString() ?? '';
            patientJson['relationship'] =
                patientJson['relationship']?.toString() ?? 'Patient';

            // --- Fetch enhanced profile for allergies and vitals ---
            try {
              final enhancedRes = await http.get(
                Uri.parse(
                  '${ApiConstants.baseUrl}patients/${patientJson['id']}/profile/enhanced',
                ),
                headers: headers,
              );
              if (enhancedRes.statusCode == 200) {
                final enhancedJson = jsonDecode(enhancedRes.body);
                final enhancedData = enhancedJson['data'];

                // Defensive: handle allergies as list of string or objects, or null
                final allergiesRaw = enhancedData?['allergies'];
                if (allergiesRaw == null) {
                  patientJson['allergies'] = [];
                } else if (allergiesRaw is List) {
                  // Accept both List<String> and List<Map>
                  patientJson['allergies'] = List.from(allergiesRaw);
                } else {
                  print(
                    '⚠️ Warning: allergies data is not a List: $allergiesRaw',
                  );
                  patientJson['allergies'] = [];
                }

                // Defensive: handle latestVitals as map or null
                final vitalsRaw = enhancedData?['latestVitals'];
                if (vitalsRaw == null) {
                  patientJson['latestVitals'] = <String, dynamic>{};
                } else if (vitalsRaw is Map) {
                  patientJson['latestVitals'] = Map<String, dynamic>.from(
                    vitalsRaw,
                  );
                } else {
                  print(
                    '⚠️ Warning: latestVitals data is not a Map: $vitalsRaw',
                  );
                  patientJson['latestVitals'] = <String, dynamic>{};
                }

                // Defensive: handle medications as list or null
                final medicationsRaw = enhancedData?['medications'];
                if (medicationsRaw == null) {
                  patientJson['medications'] = [];
                } else if (medicationsRaw is List) {
                  patientJson['medications'] = List.from(medicationsRaw);
                } else {
                  print(
                    '⚠️ Warning: medications data is not a List: $medicationsRaw',
                  );
                  patientJson['medications'] = [];
                }
              } else {
                // Set default values if enhanced profile fetch fails
                patientJson['allergies'] = [];
                patientJson['latestVitals'] = <String, dynamic>{};
                patientJson['medications'] = [];
                print(
                  '⚠️ Enhanced profile fetch failed with status: ${enhancedRes.statusCode}',
                );
              }
            } catch (e) {
              print(
                'Failed to fetch enhanced profile for patient ${patientJson['id']}: $e',
              );
              // Set default values on error
              patientJson['allergies'] = [];
              patientJson['latestVitals'] = <String, dynamic>{};
              patientJson['medications'] = [];
            }
            // ------------------------------------------------------

            final patient = Patient.fromJson(patientJson);
            if (patient.id > 0) {
              parsedPatients.add(patient);
              print(
                '✅ Successfully parsed patient with ID: ${patient.id}, name: ${patient.firstName} ${patient.lastName}',
              );
            } else {
              print(
                '⚠️ Warning: Parsed patient has invalid ID (${patient.id}): $patientJson',
              );
            }
          } catch (e) {
            print('❌ Error parsing patient: $e, data: $json');
          }
        }

        setState(() {
          patients = parsedPatients;
          loading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load patients. Status: ${response.statusCode}';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        loading = false;
      });
    }
  }

  // Calculate age from date of birth
  int _calculateAgeFromDob(String dob) {
    if (dob.isEmpty) {
      return 0;
    }

    try {
      // Parse MM/DD/YYYY format
      final parts = dob.split('/');
      if (parts.length != 3) {
        print('🔍 Invalid DOB format: $dob');
        return 0;
      }

      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);

      if (month == null || day == null || year == null) {
        print('🔍 Could not parse date parts from DOB: $dob');
        return 0;
      }

      final birthDate = DateTime(year, month, day);
      final today = DateTime.now();

      int age = today.year - birthDate.year;

      // Adjust age if birthday hasn't occurred yet this year
      final birthMonth = birthDate.month;
      final birthDay = birthDate.day;
      final currentMonth = today.month;
      final currentDay = today.day;

      if (currentMonth < birthMonth ||
          (currentMonth == birthMonth && currentDay < birthDay)) {
        age--;
      }

      // Sanity check - ages should be reasonable
      if (age < 0 || age > 120) {
        print('🔍 Unusual age calculated: $age from DOB: $dob');
        return 0;
      }

      return age;
    } catch (e) {
      // Log the error for debugging
      print('🔍 Error calculating age from DOB: $dob, error: $e');
      return 0;
    }
  }

  // Helper method to format vital conditions summary
  String _getVitalConditionsSummary(Patient patient) {
    if (patient.vitalConditions == null || patient.vitalConditions!.isEmpty) {
      return 'No vital data available';
    }

    final vitals = patient.vitalConditions!;
    List<String> summaryItems = [];

    // Check for heart rate
    if (vitals.containsKey('heartRate')) {
      final hr = vitals['heartRate'];
      if (hr != null) {
        final status = _getVitalStatus(hr, 'heartRate');
        summaryItems.add('HR: $hr bpm $status');
      }
    }

    // Check for blood pressure
    if (vitals.containsKey('bloodPressure')) {
      final bp = vitals['bloodPressure'];
      if (bp != null) {
        final status = _getVitalStatus(bp, 'bloodPressure');
        summaryItems.add('BP: $bp $status');
      }
    }

    // Check for systolic/diastolic separately
    if (vitals.containsKey('systolic') && vitals.containsKey('diastolic')) {
      final sys = vitals['systolic'];
      final dia = vitals['diastolic'];
      if (sys != null && dia != null) {
        summaryItems.add('BP: $sys/$dia mmHg ✓');
      }
    }

    // Check for temperature
    if (vitals.containsKey('temperature')) {
      final temp = vitals['temperature'];
      if (temp != null) {
        final status = _getVitalStatus(temp, 'temperature');
        summaryItems.add('Temp: $temp°F $status');
      }
    }

    // Check for oxygen saturation
    if (vitals.containsKey('oxygenSaturation')) {
      final o2 = vitals['oxygenSaturation'];
      if (o2 != null) {
        final status = _getVitalStatus(o2, 'oxygenSaturation');
        summaryItems.add('O2: $o2% $status');
      }
    }

    // Check for SpO2 (alternative oxygen saturation field)
    if (vitals.containsKey('spo2')) {
      final spo2 = vitals['spo2'];
      if (spo2 != null) {
        final status = _getVitalStatus(spo2, 'oxygenSaturation');
        summaryItems.add('SpO₂: $spo2% $status');
      }
    }

    // Check for respiratory rate
    if (vitals.containsKey('respiratoryRate')) {
      final rr = vitals['respiratoryRate'];
      if (rr != null) {
        final status = _getVitalStatus(rr, 'respiratoryRate');
        summaryItems.add('RR: $rr/min $status');
      }
    }

    // Check for weight
    if (vitals.containsKey('weight')) {
      final weight = vitals['weight'];
      if (weight != null) {
        summaryItems.add('Weight: $weight lbs');
      }
    }

    // Check for height
    if (vitals.containsKey('height')) {
      final height = vitals['height'];
      if (height != null) {
        summaryItems.add('Height: $height');
      }
    }

    // Check for glucose
    if (vitals.containsKey('glucose')) {
      final glucose = vitals['glucose'];
      if (glucose != null) {
        final status = _getVitalStatus(glucose, 'glucose');
        summaryItems.add('Glucose: $glucose mg/dL $status');
      }
    }

    return summaryItems.isNotEmpty
        ? summaryItems.join(', ') // Show all available vitals
        : 'Vitals monitoring active';
  }

  // Helper method to determine vital status (normal, high, low)
  String _getVitalStatus(dynamic value, String type) {
    if (value == null) return '';

    try {
      final numValue = double.tryParse(value.toString()) ?? 0.0;

      switch (type) {
        case 'heartRate':
          if (numValue >= 60 && numValue <= 100) return '✓';
          if (numValue > 100) return '⚠️';
          if (numValue < 60) return '⚠️';
          break;
        case 'temperature':
          if (numValue >= 97.0 && numValue <= 99.5) return '✓';
          if (numValue > 99.5) return '🔥';
          if (numValue < 97.0) return '❄️';
          break;
        case 'oxygenSaturation':
          if (numValue >= 95) return '✓';
          if (numValue < 95) return '⚠️';
          break;
        case 'respiratoryRate':
          if (numValue >= 12 && numValue <= 20) return '✓';
          if (numValue > 20) return '⚠️';
          if (numValue < 12) return '⚠️';
          break;
        case 'glucose':
          if (numValue >= 70 && numValue <= 140) return '✓';
          if (numValue > 140) return '⚠️';
          if (numValue < 70) return '⚠️';
          break;
        case 'bloodPressure':
          // For blood pressure, we'll just show checkmark for now
          // As it's typically in format "120/80"
          return '✓';
      }
    } catch (e) {
      // If parsing fails, just return empty
      return '';
    }

    return '';
  }

  // Helper method to format allergies summary
  String _getAllergiesSummary(List<dynamic>? allergies) {
    if (allergies == null || allergies.isEmpty) {
      return 'No allergies listed';
    }

    List<String> allergyStrings = [];

    for (var allergy in allergies) {
      if (allergy is String) {
        // Simple string allergy
        allergyStrings.add(allergy);
      } else if (allergy is Map<String, dynamic>) {
        // Object with allergen and severity
        final allergen = allergy['allergen']?.toString() ?? 'Unknown';
        final severity = allergy['severity']?.toString();

        if (severity != null && severity.isNotEmpty) {
          allergyStrings.add('$allergen ($severity)');
        } else {
          allergyStrings.add(allergen);
        }
      }
    }

    return allergyStrings.isNotEmpty
        ? 'Allergies: ${allergyStrings.join(', ')}'
        : 'No allergies listed';
  }

  // Initiate video/audio call with patient
  Future<void> _initiateCall(Patient patient, bool isVideoCall) async {
    try {
      // Check subscription access for caregivers before initiating call
      final canUseVideoCalls =
          await SubscriptionService.checkPremiumAccessWithDialog(
        context,
        isVideoCall ? 'Video Calls' : 'Voice Calls',
      );

      if (!canUseVideoCalls) {
        return; // User doesn't have premium access, dialog was shown
      }

      // Check if patient is available for call
      // final isAvailable = await VideoCallService.checkUserAvailability(
      //   patient.id.toString(),
      // );
      // if (!isAvailable) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content: Text('${patient.firstName} is currently unavailable'),
      //     ),
      //   );
      //   return;
      // }

      // Generate unique call ID
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

      // Navigate immediately; invitation is sent only after caller joins and is waiting.
      if (!mounted) return;
      Navigator.of(context).push(
        TitledMaterialPageRoute(
          title: 'Video Call',
          builder: (context) => HybridVideoCallWidget(
            userId: widget.caregiverId.toString(),
            callId: callId,
            recipientId: patient.id.toString(),
            userRole: 'CAREGIVER',
            returnPatientDetailsId: patient.id.toString(),
            forcePatientDetailsOnExit: true,
            returnAsCaregiver: true,
            isInitiator: true,
            isVideoEnabled: isVideoCall,
            isAudioEnabled: true,
            userName: caregiverName ?? 'Caregiver',
            recipientName: '${patient.firstName} ${patient.lastName}',
          ),
        ),
      );

      // Also use the existing video call service for backward compatibility
      // final callData = await VideoCallService.initiateCall(
      //   callId: callId,
      //   callerId: widget.caregiverId.toString(),
      //   recipientId: patient.id.toString(),
      //   isVideoCall: isVideoCall,
      // );

      // if (callData['success'] == true) {
      //   // Navigate to video call screen
      //   Navigator.of(context).push(
      //     MaterialPageRoute(
      //       builder: (context) => VideoCallWidget(
      //         callId: callData['callId'],
      //         currentUserId: widget.caregiverId.toString(),
      //         currentUserName: caregiverName ?? 'Caregiver',
      //         otherUserId: patient.id.toString(),
      //         otherUserName: '${patient.firstName} ${patient.lastName}',
      //         isVideoCall: isVideoCall,
      //         isIncoming: false,
      //       ),
      //     ),
      //   );
      // } else {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(
      //       content: Text('Failed to initiate call. Please try again.'),
      //     ),
      //   );
      // }
    } catch (e) {
      print('Error initiating call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error initiating call. Please check your connection.'),
        ),
      );
    }
  }

  // Helper method to handle suspend action
  Future<void> _handleSuspendAction(Patient patient) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspend Relationship'),
        content: Text(
          'Are you sure you want to suspend your relationship with ${patient.firstName} ${patient.lastName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('SUSPEND'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final linkId = patient.linkId;
        if (linkId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Missing link ID')),
          );
          return;
        }
        final response = await ApiService.suspendCaregiverPatientLink(linkId);
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Relationship with ${patient.firstName} suspended'),
            ),
          );
          fetchPatients();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to suspend relationship: ${response.statusCode}',
              ),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // Helper method to handle reactivate action
  Future<void> _handleReactivateAction(Patient patient) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reactivate Relationship'),
        content: Text(
          'Do you want to reactivate your relationship with ${patient.firstName} ${patient.lastName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('REACTIVATE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final linkId = patient.linkId;
        if (linkId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Missing link ID')),
          );
          return;
        }
        final response = await ApiService.reactivateCaregiverPatientLink(
          linkId,
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Relationship with ${patient.firstName} reactivated',
              ),
            ),
          );
          fetchPatients();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to reactivate relationship: ${response.statusCode}',
              ),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _handlePatientVideoCallPolicy(
    Patient patient, {
    required bool enabled,
  }) async {
    final linkId = patient.linkId;
    if (linkId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
          const SnackBar(content: Text('Missing caregiver link ID.')));
      return;
    }

    final success = await ApiService.setPatientVideoCallsEnabledForLink(
      linkId: linkId,
      enabled: enabled,
    );
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Patient-initiated video calls enabled.'
                : 'Patient-initiated video calls disabled.',
          ),
        ),
      );
      await fetchPatients();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to update video call policy.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    if (user == null) {
      Future.microtask(() => context.go('/login'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isLargeScreen = MediaQuery.of(context).size.width >= 1200;
    return ResponsiveScaffold(
      title: caregiverName != null
          ? 'Welcome, $caregiverName'
          : 'Caregiver Dashboard',
      appBarActions: isLargeScreen
          ? [
              CallNotificationStatusIndicator(
                isInitialized: _callNotificationInitialized,
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Help documentation coming soon'),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ]
          : [
              CallNotificationStatusIndicator(
                isInitialized: _callNotificationInitialized,
              ),
              const SizedBox(width: 8),
            ],
      currentRoute: '/dashboard',
      body: _buildMainContent(),
    );
  }

  Widget _buildContentBasedOnState() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      return _buildErrorState();
    } else if (patients.isEmpty) {
      return _buildEmptyStateContent();
    } else {
      return _buildPatientListContent();
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Patients',
              style: AppTheme.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: fetchPatients,
              style: AppTheme.primaryButtonStyle,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateContent() {
    // Use responsive utils for width calculation
    final isMobile = MediaQuery.of(context).size.width < 768;
    final screenWidth = MediaQuery.of(context).size.width;

    // Create a container with responsive width
    return Center(
      child: Container(
        width: isMobile
            ? screenWidth * 0.85
            : (screenWidth > 600 ? 400.0 : screenWidth * 0.9),
        padding: const EdgeInsets.all(24),
        decoration: !isMobile
            ? BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Notifications (collapsible) at top =====
            NotificationsPanel(
              notifications: _notifications, // List<NotificationItem>
              heading: 'Notifications',
              initiallyExpanded: true,
            ),
            const SizedBox(height: 16),

            Icon(
              Icons.person_search,
              size: isMobile ? 80.0 : 96.0,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 24),
            Text(
              'No patients yet',
              style: AppTheme.headingMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Add patients to begin monitoring',
              style: AppTheme.bodyLarge.copyWith(
                color: Theme.of(context).hintColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: isMobile ? double.infinity : 200.0,
              child: ElevatedButton.icon(
                style: AppTheme.primaryButtonStyle.copyWith(
                  // Ensure proper button sizing for touch
                  minimumSize: WidgetStateProperty.all(const Size(150, 48)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                icon: const Icon(Icons.person_add),
                label: const Text('Add Patient'),
                onPressed: () {
                  print('🔍 Add Patient (empty state) button pressed');
                  print('🔍 Add Patient (empty state) button pressed');
                  try {
                    context.go('/add-patient');
                  } catch (e) {
                    print('🔍 Navigation error: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Navigation error. Please try again.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientListContent() {
    // Use direct MediaQuery for margins
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalMargin = screenWidth >= 1200
        ? 32.0
        : screenWidth >= 768
            ? 24.0
            : 16.0;

    return RefreshIndicator(
      onRefresh: fetchPatients,
      child: CustomScrollView(
        slivers: [
          // ===== Notifications (collapsible) at top =====
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalMargin,
                16,
                horizontalMargin,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NotificationsPanel(
                    notifications: _notifications, // List<NotificationItem>
                    heading: 'Notifications',
                    initiallyExpanded: true,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Show patient count
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalMargin,
              20,
              horizontalMargin,
              8.0,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Showing ${patients.length} patients',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          // Use responsive grid for larger screens or list for smaller screens
          // Use direct screen width check instead of extension
          MediaQuery.of(context).size.width >= 1024
              ? _buildResponsivePatientGrid(horizontalMargin)
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalMargin,
                    0,
                    horizontalMargin,
                    16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final patient = patients[index];
                      return _buildPatientCard(patient);
                    }, childCount: patients.length),
                  ),
                ),
        ],
      ),
    );
  }

  // New method to create a responsive grid for larger screens
  Widget _buildResponsivePatientGrid(double horizontalMargin) {
    // Use direct MediaQuery instead of extension
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth >= 1200 ? 2 : 1;

    // Ensure we have at least 1 column and limit based on screen size
    // Ensure we have at least 1 column and limit based on screen size
    if (crossAxisCount > 2) {
      crossAxisCount =
          2; // Limit to 2 columns max for patient cards to make them wider
    }
    if (crossAxisCount < 1) {
      crossAxisCount = 1; // Ensure at least 1 column
    }

    // Calculate aspect ratio based on screen size
    double aspectRatio = screenWidth >= 1200 ? 0.9 : 0.85;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: aspectRatio, // Make cards taller and more readable
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final patient = patients[index];
          return _buildPatientCard(patient);
        }, childCount: patients.length),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 500;
        final isSmallMobile = screenWidth < 350;

        return Container(
            margin: EdgeInsets.only(right: isMobile ? 6 : 8),
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: isSmallMobile ? 8 : (isMobile ? 10 : 12),
                      horizontal: isSmallMobile ? 6 : (isMobile ? 8 : 12),
                    ),
                    constraints: BoxConstraints(
                      minWidth: isSmallMobile ? 60 : (isMobile ? 65 : 75),
                      maxWidth: isSmallMobile ? 80 : (isMobile ? 90 : 110),
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: Theme.of(context).colorScheme.primary,
                          size: isSmallMobile ? 18 : (isMobile ? 20 : 22),
                        ),
                        SizedBox(height: isSmallMobile ? 3 : 4),
                        Text(
                          label,
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallMobile ? 9 : (isMobile ? 10 : 12),
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                )));
      },
    );
  }

  Widget _buildPatientCard(Patient patient) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isGridView = screenWidth >= 1024;
    final double avatarSize = screenWidth >= 1024 ? 45.0 : 35.0;

    // Use flexible max width based on screen size
    double maxCardWidth = screenWidth;
    if (screenWidth >= 1024) {
      maxCardWidth = 800.0;
    } else if (screenWidth >= 768) {
      maxCardWidth = 600.0;
    }

    return Card(
      margin: isGridView ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shadowColor: Theme.of(context).shadowColor.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxCardWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).cardColor,
              Theme.of(context).cardColor.withOpacity(0.95),
            ],
          ),
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: CircleAvatar(
                radius: avatarSize,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.2),
                child: Text(
                  patient.firstName.isNotEmpty
                      ? patient.firstName.substring(0, 1).toUpperCase()
                      : patient.lastName.isNotEmpty
                          ? patient.lastName.substring(0, 1).toUpperCase()
                          : '?',
                  style: AppTheme.headingSmall.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: isGridView ? 28 : 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                "${patient.firstName} ${patient.lastName}",
                style: AppTheme.headingSmall.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  // Action buttons row with responsive overflow handling
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildActionButton(
                            icon: Icons.message,
                            label: 'Message',
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                TitledMaterialPageRoute(
                                  title: 'Messages',
                                  builder: (context) => MessagingWidget(
                                    currentUserId:
                                        widget.caregiverId.toString(),
                                    currentUserName:
                                        caregiverName ?? 'Caregiver',
                                    recipientId: patient.id.toString(),
                                    recipientName:
                                        '${patient.firstName} ${patient.lastName}',
                                  ),
                                ),
                              );
                              if (result == 'video_call') {
                                await _initiateCall(patient, true);
                              } else if (result == 'audio_call') {
                                await _initiateCall(patient, false);
                              }
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.video_call,
                            label: 'Video Call',
                            onPressed: () async {
                              await _initiateCall(patient, true);
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.call,
                            label: 'Audio Call',
                            onPressed: () async {
                              await _initiateCall(patient, false);
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.analytics,
                            label: 'Analytics',
                            onPressed: () {
                              if (patient.id <= 0) {
                                print(
                                  '⚠️ Warning: Attempted to navigate to analytics with invalid patient ID: ${patient.id}',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Error: Invalid patient ID'),
                                  ),
                                );
                                return;
                              }
                              print(
                                '✅ Navigating to analytics for patient: ${patient.id}',
                              );
                              context.go('/analytics?patientId=${patient.id}');
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.medical_information,
                            label: 'Medical Notes',
                            onPressed: () {
                              Navigator.of(context).push(
                                TitledMaterialPageRoute(
                                  title: 'Patient Medical Notes',
                                  builder: (context) => PatientMedicalNotesPage(
                                    patientId: patient.id,
                                    patientName:
                                        '${patient.firstName} ${patient.lastName}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.cake,
                        size: 15,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          patient.dob.isNotEmpty
                              ? 'Age ${_calculateAgeFromDob(patient.dob)}'
                              : 'Age not specified',
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).hintColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 15,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          patient.gender?.isNotEmpty == true
                              ? patient.gender!
                              : 'Gender not specified',
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).hintColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.family_restroom,
                        size: 15,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          patient.relationship.isNotEmpty
                              ? patient.relationship
                              : 'Patient',
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).hintColor,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 15,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getAllergiesSummary(patient.allergies),
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).hintColor,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getVitalConditionsSummary(patient),
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onSelected: (value) {
                  if (patient.id <= 0) {
                    print('⚠️ Warning: Invalid patient ID: ${patient.id}');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error: Invalid patient ID'),
                      ),
                    );
                    return;
                  }
                  if (value == 'view') {
                    print('✅ Navigating to patient profile: ${patient.id}');
                    context.go('/patient/${patient.id}');
                  } else if (value == 'suspend') {
                    _handleSuspendAction(patient);
                  } else if (value == 'reactivate') {
                    _handleReactivateAction(patient);
                  } else if (value == 'disable_patient_video_calls') {
                    _handlePatientVideoCallPolicy(patient, enabled: false);
                  } else if (value == 'enable_patient_video_calls') {
                    _handlePatientVideoCallPolicy(patient, enabled: true);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text('View Profile'),
                      ],
                    ),
                  ),
                  if (patient.linkStatus.toUpperCase() == 'ACTIVE')
                    PopupMenuItem<String>(
                      value: 'suspend',
                      child: Row(
                        children: [
                          Icon(
                            Icons.pause_circle_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          const Text('Suspend Relationship'),
                        ],
                      ),
                    ),
                  if (patient.linkStatus.toUpperCase() == 'SUSPENDED')
                    PopupMenuItem<String>(
                      value: 'reactivate',
                      child: Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Reactivate Relationship'),
                        ],
                      ),
                    ),
                  if (patient.linkStatus.toUpperCase() == 'ACTIVE' &&
                      patient.patientVideoCallsEnabled)
                    PopupMenuItem<String>(
                      value: 'disable_patient_video_calls',
                      child: Row(
                        children: [
                          Icon(
                            Icons.videocam_off,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          const Text('Disable Patient Video Calls'),
                        ],
                      ),
                    ),
                  if (patient.linkStatus.toUpperCase() == 'ACTIVE' &&
                      !patient.patientVideoCallsEnabled)
                    PopupMenuItem<String>(
                      value: 'enable_patient_video_calls',
                      child: Row(
                        children: [
                          Icon(
                            Icons.videocam,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Enable Patient Video Calls'),
                        ],
                      ),
                    ),
                ],
              ),
              onTap: () {
                if (patient.id <= 0) {
                  print(
                    '⚠️ Warning: Attempted to navigate to patient profile with invalid ID: ${patient.id}',
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error: Invalid patient ID')),
                  );
                  return;
                }
                print('✅ Navigating to patient profile: ${patient.id}');
                context.go('/patient/${patient.id}');
              },
            ),
            // Add visual separator between content and status
            // Add visual separator between content and status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withOpacity(0.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        patient.linkStatus == 'ACTIVE'
                            ? Icons.check_circle
                            : Icons.pause_circle_filled,
                        color: patient.linkStatus == 'ACTIVE'
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).disabledColor,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const SizedBox(width: 6),
                      Text(
                        patient.linkStatus == 'ACTIVE'
                            ? 'Active'
                            : patient.linkStatus,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: patient.linkStatus == 'ACTIVE'
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).disabledColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
