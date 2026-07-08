import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../features/telemetry/telemetry.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_token_manager.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../dashboard/models/patient_model.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StartVisitPage extends StatefulWidget {
  final int patientId;
  final int? scheduledVisitId;
  
  const StartVisitPage({
    super.key,
    required this.patientId,
    this.scheduledVisitId,
  });

  @override
  State<StartVisitPage> createState() => _StartVisitPageState();
}

class _StartVisitPageState extends State<StartVisitPage> {
  Patient? _selectedPatient;
  String? _selectedServiceType;
  bool _isLoading = true;
  String? _error;

  // Service types for the dropdown
  final List<String> _serviceTypes = [
    'Personal Care',
    'Companion Care',
    'Respite Care',
    'Medication Management',
    'Transportation',
    'Meal Preparation',
    'Light Housekeeping',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadPatientDetails();
  }

  Future<void> _loadPatientDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Fetch patient details
      final caregiverId = user.caregiverId ?? user.id;
      final response = await ApiService.getCaregiverPatients(caregiverId);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        // Find the specific patient
        for (var json in data) {
          try {
            Map<String, dynamic> patientJson;
            if (json.containsKey('patient') && json['patient'] != null) {
              final patientData = json['patient'];
              if (patientData is Map) {
                patientJson = Map<String, dynamic>.from(patientData);
              } else {
                patientJson = Map<String, dynamic>.from(json);
              }
            } else {
              patientJson = Map<String, dynamic>.from(json);
            }

            final patient = Patient.fromJson(patientJson);
            if (patient.id == widget.patientId) {
              setState(() {
                _selectedPatient = patient;
                _isLoading = false;
              });
              return;
            }
          } catch (e) {
            print('Error parsing patient: $e');
          }
        }
        
        throw Exception('Patient not found');
      } else {
        throw Exception('Failed to load patient details: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _continueToCheckIn() {
    if (_selectedServiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Navigate to Check-In Location page with selected patient and service type
    unawaited(
      Telemetry.event('feature_use', {'feature': 'evv_start_visit'}),
    );
    final scheduledVisitParam = widget.scheduledVisitId != null ? '&scheduledVisitId=${widget.scheduledVisitId}' : '';
    context.push('/evv/checkin-location?patientId=${widget.patientId}&serviceType=${Uri.encodeComponent(_selectedServiceType!)}$scheduledVisitParam');
  }

  String _formatAddress(Patient patient) {
    final address = patient.address;
    if (address == null) {
      return 'Address not available';
    }

    final line1 = address.line1 ?? '';
    final line2 = address.line2 ?? '';
    final city = address.city ?? '';
    final state = address.state ?? '';
    final zip = address.zip ?? '';

    final addressParts = <String>[];
    if (line1.isNotEmpty) addressParts.add(line1);
    if (line2.isNotEmpty) addressParts.add(line2);
    if (city.isNotEmpty) addressParts.add(city);
    if (state.isNotEmpty) addressParts.add(state);
    if (zip.isNotEmpty) addressParts.add(zip);

    return addressParts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Start Visit'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/dashboard?role=CAREGIVER'),
            icon: const Icon(Icons.cancel, color: Colors.red),
            label: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return _buildErrorState();
    }
    
    if (_selectedPatient == null) {
      return _buildPatientNotFoundState();
    }
    
    return _buildStartVisitForm();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Error Loading Patient',
              style: AppTheme.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPatientDetails,
              style: AppTheme.primaryButtonStyle,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientNotFoundState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 64,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'Patient Not Found',
              style: AppTheme.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'The selected patient could not be found.',
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/evv/select-patient'),
              style: AppTheme.primaryButtonStyle,
              child: const Text('Back to Patient Selection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartVisitForm() {
    final theme = Theme.of(context);
    final patient = _selectedPatient!;
    final fullName = '${patient.firstName} ${patient.lastName}';
    final maNumber = patient.maNumber ?? 'MA${patient.id.toString().padLeft(9, '0')}';
    final address = _formatAddress(patient);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.play_circle_outline,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Start Visit',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
          ),
          // Form Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected Patient Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Patient:',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        fullName,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onPrimary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              maNumber,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        address,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Service Type Dropdown
                Text(
                  'Service Type *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.titleMedium?.color,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedServiceType,
                  decoration: InputDecoration(
                    hintText: 'Select service type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  items: _serviceTypes.map((String serviceType) {
                    return DropdownMenuItem<String>(
                      value: serviceType,
                      child: Text(serviceType),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedServiceType = newValue;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a service type';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                // EVV Compliance Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EVV Compliance:',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You\'ll need to provide your location for check-in and check-out to comply with Electronic Visit Verification requirements.',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Continue Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _continueToCheckIn,
                    icon: Icon(Icons.location_on, color: theme.colorScheme.onPrimary),
                    label: Text(
                      'Continue to Check-In',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
