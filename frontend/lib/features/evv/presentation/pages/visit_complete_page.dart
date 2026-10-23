import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/evv_service.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../dashboard/models/patient_model.dart';

class VisitCompletePage extends StatefulWidget {
  final int patientId;
  final String serviceType;
  final String checkinLocationType;
  final String checkoutLocationType;
  final double? checkinLatitude;
  final double? checkinLongitude;
  final double? checkoutLatitude;
  final double? checkoutLongitude;
  final String notes;
  final int duration; // Duration in seconds
  final int? scheduledVisitId;
  final String? checkinNoGpsReason;
  final String? checkoutNoGpsReason;
  final double? checkinAccuracyM;
  final double? checkoutAccuracyM;

  const VisitCompletePage({
    super.key,
    required this.patientId,
    required this.serviceType,
    required this.checkinLocationType,
    required this.checkoutLocationType,
    this.checkinLatitude,
    this.checkinLongitude,
    this.checkoutLatitude,
    this.checkoutLongitude,
    required this.notes,
    required this.duration,
    this.scheduledVisitId,
    this.checkinNoGpsReason,
    this.checkoutNoGpsReason,
    this.checkinAccuracyM,
    this.checkoutAccuracyM,
  });

  @override
  State<VisitCompletePage> createState() => _VisitCompletePageState();
}

class _VisitCompletePageState extends State<VisitCompletePage> {
  Patient? _selectedPatient;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  DateTime? _checkinTime;
  DateTime? _checkoutTime;
  String _checkinLocation = '';
  String _checkoutLocation = '';

  @override
  void initState() {
    super.initState();
    _checkoutTime = DateTime.now();
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

              // Set check-in and check-out locations
              _setLocations(patient);
              return;
            }
          } catch (e) {
            print('Error parsing patient: $e');
          }
        }

        throw Exception('Patient not found');
      } else {
        throw Exception(
          'Failed to load patient details: ${response.statusCode}',
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setLocations(Patient patient) {
    // Set check-in location
    if (widget.checkinLocationType == 'patient_address') {
      final address = _formatAddress(patient);
      setState(() {
        _checkinLocation = address;
      });
    } else if (widget.checkinLocationType == 'gps' &&
        widget.checkinLatitude != null &&
        widget.checkinLongitude != null) {
      setState(() {
        _checkinLocation =
            'GPS: ${widget.checkinLatitude!.toStringAsFixed(6)}, ${widget.checkinLongitude!.toStringAsFixed(6)}';
      });
    }

    // Set check-out location
    if (widget.checkoutLocationType == 'patient_address') {
      final address = _formatAddress(patient);
      setState(() {
        _checkoutLocation = address;
      });
    } else if (widget.checkoutLocationType == 'gps' &&
        widget.checkoutLatitude != null &&
        widget.checkoutLongitude != null) {
      setState(() {
        _checkoutLocation =
            'GPS: ${widget.checkoutLatitude!.toStringAsFixed(6)}, ${widget.checkoutLongitude!.toStringAsFixed(6)}';
      });
    }

    // Set check-in time (approximately duration before check-out)
    setState(() {
      _checkinTime = _checkoutTime!.subtract(
        Duration(seconds: widget.duration),
      );
    });
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour;
    return '$displayHour:$minute:$second $amPm';
  }

  Future<void> _completeVisit() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Create EVV record using the EVV service
      final evvService = EvvService();

      // Get current user for caregiver ID
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Determine check-in location data
      String checkinLocationSource = widget.checkinLocationType.toUpperCase();
      double? checkinLat = widget.checkinLocationType.toUpperCase() == 'GPS'
          ? widget.checkinLatitude
          : null;
      double? checkinLng = widget.checkinLocationType.toUpperCase() == 'GPS'
          ? widget.checkinLongitude
          : null;

      // Determine check-out location data
      String checkoutLocationSource = widget.checkoutLocationType.toUpperCase();
      double? checkoutLat = widget.checkoutLocationType.toUpperCase() == 'GPS'
          ? widget.checkoutLatitude
          : null;
      double? checkoutLng = widget.checkoutLocationType.toUpperCase() == 'GPS'
          ? widget.checkoutLongitude
          : null;

      // Get state from patient address or default to MD
      String stateCode = _selectedPatient?.address?.state ?? 'MD';

      // Create EVV record request with both check-in and check-out locations
      final request = EvvRecordRequest(
        serviceType: widget.serviceType,
        patientId: widget.patientId,
        caregiverId: user.caregiverId ?? user.id,
        dateOfService: _checkinTime ?? DateTime.now(),
        timeIn: _checkinTime ?? DateTime.now(),
        timeOut: _checkoutTime ?? DateTime.now(),
        // Legacy fields for backward compatibility (use check-out data)
        locationLat: checkoutLat,
        locationLng: checkoutLng,
        locationSource: widget.checkoutLocationType,
        // New separate check-in and check-out location fields
        checkinLocationLat: checkinLat,
        checkinLocationLng: checkinLng,
        checkinLocationSource: checkinLocationSource,
        checkoutLocationLat: checkoutLat,
        checkoutLocationLng: checkoutLng,
        checkoutLocationSource: checkoutLocationSource,
        stateCode: stateCode,
        scheduledVisitId: widget.scheduledVisitId,
        checkinNoGpsReason: widget.checkinNoGpsReason,
        checkoutNoGpsReason: widget.checkoutNoGpsReason,
        checkinAccuracyM: widget.checkinAccuracyM,
        checkoutAccuracyM: widget.checkoutAccuracyM,
      );

      // Submit the EVV record
      await evvService.createRecord(request);

      // Show success message and navigate to success page
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Visit completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to visit completed success page
      final queryParams = {
        'patientId': widget.patientId.toString(),
        'serviceType': widget.serviceType,
        'checkinLocationType': widget.checkinLocationType,
        'checkoutLocationType': widget.checkoutLocationType,
        'notes': widget.notes,
        'duration': widget.duration.toString(),
        'checkinTime': _checkinTime?.toIso8601String() ?? '',
        'checkoutTime': _checkoutTime?.toIso8601String() ?? '',
      };

      if (widget.checkinLatitude != null && widget.checkinLongitude != null) {
        queryParams['checkinLatitude'] = widget.checkinLatitude.toString();
        queryParams['checkinLongitude'] = widget.checkinLongitude.toString();
      }

      if (widget.checkoutLatitude != null && widget.checkoutLongitude != null) {
        queryParams['checkoutLatitude'] = widget.checkoutLatitude.toString();
        queryParams['checkoutLongitude'] = widget.checkoutLongitude.toString();
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      context.push('/evv/visit-completed-success?$queryString');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error completing visit: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Visit Complete'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/evv'),
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

    return _buildVisitComplete();
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

  Widget _buildVisitComplete() {
    final patient = _selectedPatient!;
    final fullName = '${patient.firstName} ${patient.lastName}';
    final maNumber =
        patient.maNumber ?? 'MA${patient.id.toString().padLeft(9, '0')}';
    final cs = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return SingleChildScrollView(
      child: Column(
        children: [
          // Success message banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Visit successfully completed and ready for submission',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Visit Summary section
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visit Summary',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Patient:', fullName),
                _buildSummaryRow('MA Number:', maNumber),
                _buildSummaryRow('Service Type:', widget.serviceType),
                _buildSummaryRow(
                  'Check-in:',
                  _checkinTime != null ? _formatTime(_checkinTime!) : 'Unknown',
                ),
                _buildSummaryRow(
                  'Check-out:',
                  _checkoutTime != null
                      ? _formatTime(_checkoutTime!)
                      : 'Unknown',
                ),
                _buildSummaryRow(
                  'Duration:',
                  _formatDuration(Duration(seconds: widget.duration)),
                ),
                _buildSummaryRow('Check-in Location:', _checkinLocation),
                _buildSummaryRow('Check-out Location:', _checkoutLocation),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Complete Visit button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _completeVisit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: shape,
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(
                  _isSubmitting ? 'Completing Visit...' : 'Complete Visit'),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
