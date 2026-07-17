import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/auth_token_manager.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../dashboard/models/patient_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CheckinLocationPage extends StatefulWidget {
  final int patientId;
  final String serviceType;
  final int? scheduledVisitId;

  const CheckinLocationPage({
    super.key,
    required this.patientId,
    required this.serviceType,
    this.scheduledVisitId,
  });

  @override
  State<CheckinLocationPage> createState() => _CheckinLocationPageState();
}

class _CheckinLocationPageState extends State<CheckinLocationPage> {
  Patient? _selectedPatient;
  bool _isLoading = true;
  String? _error;
  bool _isGettingLocation = false;
  Position? _currentPosition;

  // EVV federal compliance: track GPS failures and capture reason
  bool _gpsAttemptFailed = false;
  String? _selectedNoGpsReason;
  final TextEditingController _manualAddressController =
      TextEditingController();
  final bool _showManualEntry = false;

  static const List<Map<String, String>> _noGpsReasons = [
    {
      'value': 'HOME_VISIT_ADDRESS_USED',
      'label': 'Home visit – patient address used'
    },
    {'value': 'GPS_SERVICE_DISABLED', 'label': 'GPS/location service disabled'},
    {'value': 'PERMISSION_DENIED', 'label': 'Location permission not granted'},
    {'value': 'GPS_TIMEOUT', 'label': 'GPS signal timed out'},
    {'value': 'INDOOR_LOCATION', 'label': 'Indoors – no GPS signal'},
    {'value': 'COMMUNITY_VISIT', 'label': 'Community or facility visit'},
    {'value': 'OTHER', 'label': 'Other'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPatientDetails();
  }

  @override
  void dispose() {
    _manualAddressController.dispose();
    super.dispose();
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
        throw Exception(
            'Failed to load patient details: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isGettingLocation = false;
          _gpsAttemptFailed = true;
        });
        _showLocationError(
            'Location services are disabled. Please enable location services in your device settings.');
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isGettingLocation = false;
            _gpsAttemptFailed = true;
          });
          _showLocationError(
              'Location permissions are denied. Please enable location permissions to use GPS location.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isGettingLocation = false;
          _gpsAttemptFailed = true;
        });
        _showLocationError(
            'Location permissions are permanently denied. Please enable location permissions in your device settings.');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _currentPosition = position;
        _isGettingLocation = false;
      });

      //EVV Quality Guardrail (Issue #62) - warn if GPS accuracy exceeds 500m threshold
      if (position.accuracy > 500) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'GPS accuracy is ${position.accuracy.toStringAsFixed(0)}m which may not meet EVV compliance requirements (threshold: 500m). Consider using patient address instead.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Use Address',
                textColor: Colors.white,
                onPressed: _usePatientAddress,
              ),
            ),
          );
          setState(() {
            _isGettingLocation = false;
            _gpsAttemptFailed = true;
          });
          return;
        }
      }

      _navigateToVisitProgress(
        locationType: 'GPS',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );
    } catch (e) {
      setState(() {
        _isGettingLocation = false;
        _gpsAttemptFailed = true;
      });
      _showLocationError(
          'Failed to get current location: ${e.toString()}. Please select an alternative location option.');
    }
  }

  void _usePatientAddress() {
    _showNoGpsReasonDialog(
      defaultReason: _gpsAttemptFailed ? null : 'HOME_VISIT_ADDRESS_USED',
      onConfirm: (reason) {
        _navigateToVisitProgress(
          locationType: 'PATIENT_ADDRESS',
          noGpsReason: reason,
        );
      },
    );
  }

  void _useManualAddress() {
    if (_manualAddressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an address before continuing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedNoGpsReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reason for manual location entry.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _navigateToVisitProgress(
      locationType: 'MANUAL',
      noGpsReason: _selectedNoGpsReason,
      manualAddress: _manualAddressController.text.trim(),
    );
  }

  void _showNoGpsReasonDialog({
    String? defaultReason,
    required void Function(String reason) onConfirm,
  }) {
    String? selected = defaultReason;
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Location Reason Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Federal EVV regulations require a reason when GPS is not used. Please select the applicable reason:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _noGpsReasons
                    .map((r) => DropdownMenuItem(
                          value: r['value'],
                          child: Text(r['label']!,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => selected = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      onConfirm(selected!);
                    },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToVisitProgress({
    required String locationType,
    double? latitude,
    double? longitude,
    double? accuracyM,
    String? noGpsReason,
    String? manualAddress,
  }) {
    final queryParams = {
      'patientId': widget.patientId.toString(),
      'serviceType': widget.serviceType,
      'locationType': locationType,
    };

    if (latitude != null && longitude != null) {
      queryParams['latitude'] = latitude.toString();
      queryParams['longitude'] = longitude.toString();
    }
    if (accuracyM != null) {
      queryParams['accuracyM'] = accuracyM.toString();
    }
    if (noGpsReason != null) {
      queryParams['noGpsReason'] = noGpsReason;
    }
    if (manualAddress != null) {
      queryParams['manualAddress'] = manualAddress;
    }
    if (widget.scheduledVisitId != null) {
      queryParams['scheduledVisitId'] = widget.scheduledVisitId.toString();
    }

    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    context.push('/evv/visit-progress?$queryString');
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
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
        title: const Text('Check-In Location'),
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

    return _buildLocationSelection();
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

  Widget _buildLocationSelection() {
    final patient = _selectedPatient!;
    final fullName = '${patient.firstName} ${patient.lastName}';
    final address = _formatAddress(patient);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top instruction banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue[200]!,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.blue[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select your location to check in for the visit. Choose patient address for routine visits or GPS for precise location.',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Use Patient Address Card
          _buildLocationCard(
            icon: Icons.home,
            iconColor: Colors.blue[600]!,
            title: 'Use Patient Address',
            patientName: fullName,
            address: address,
            recommendation: 'Recommended for visits at patient\'s home',
            buttonText: 'Select Patient Address',
            buttonIcon: Icons.check_circle,
            onPressed: _usePatientAddress,
            isPrimary: true,
          ),
          const SizedBox(height: 16),

          // Get GPS Location Card
          _buildLocationCard(
            icon: Icons.location_on,
            iconColor: Colors.green[600]!,
            title: 'Get Current GPS Location',
            description: 'Use your device\'s GPS for precise coordinates',
            additionalInfo: 'May request location permission • Higher accuracy',
            buttonText: 'Get My GPS Location',
            buttonIcon: Icons.location_on,
            onPressed: _getCurrentLocation,
            isLoading: _isGettingLocation,
            isPrimary: false,
          ),
          const SizedBox(height: 16),

          // Enter Manual Location Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_location_alt,
                        color: Colors.orange[600]!, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Enter Manual Location',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Use when GPS is unavailable. Enter the visit address manually.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _manualAddressController,
                  decoration: InputDecoration(
                    labelText: 'Visit Address',
                    hintText: '123 Main St, City, State 12345',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.home_work),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedNoGpsReason,
                  decoration: InputDecoration(
                    labelText: 'Reason GPS Not Used',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.info_outline),
                  ),
                  items: _noGpsReasons
                      .map((r) => DropdownMenuItem<String>(
                            value: r['value'],
                            child: Text(r['label']!),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedNoGpsReason = val),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _useManualAddress,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Use Manual Address'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bottom EVV compliance banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue[200]!,
                width: 1,
              ),
            ),
            child: Text(
              'EVV Compliance: Both options satisfy Electronic Visit Verification requirements. Patient address is sufficient for most visits, while GPS provides exact coordinates when needed.',
              style: TextStyle(
                color: Colors.blue[800],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? patientName,
    String? address,
    String? description,
    String? additionalInfo,
    String? recommendation,
    required String buttonText,
    required IconData buttonIcon,
    required VoidCallback onPressed,
    bool isLoading = false,
    required bool isPrimary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title section
          Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Patient info (for patient address card)
          if (patientName != null && address != null) ...[
            Text(
              patientName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              address,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recommendation!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],

          // Description (for GPS card)
          if (description != null) ...[
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (additionalInfo != null) ...[
              const SizedBox(height: 4),
              Text(
                additionalInfo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],

          const SizedBox(height: 20),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onPressed,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      buttonIcon,
                      color: isPrimary ? Colors.white : Colors.grey[700],
                    ),
              label: Text(
                isLoading ? 'Getting Location...' : buttonText,
                style: TextStyle(
                  color: isPrimary ? Colors.white : Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPrimary ? Colors.blue[600] : Colors.white,
                foregroundColor: isPrimary ? Colors.white : Colors.grey[700],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isPrimary
                      ? BorderSide.none
                      : BorderSide(color: Colors.grey[300]!),
                ),
                elevation: isPrimary ? 2 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
