import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../dashboard/models/patient_model.dart';
import 'incident_report_screens.dart';

class VisitInProgressPage extends StatefulWidget {
  final int patientId;
  final String serviceType;
  final String locationType;
  final double? latitude;
  final double? longitude;
  final int? scheduledVisitId;
  final String? noGpsReason;
  final double? accuracyM;

  const VisitInProgressPage({
    super.key,
    required this.patientId,
    required this.serviceType,
    required this.locationType,
    this.latitude,
    this.longitude,
    this.scheduledVisitId,
    this.noGpsReason,
    this.accuracyM,
  });

  @override
  State<VisitInProgressPage> createState() => _VisitInProgressPageState();
}

class _VisitInProgressPageState extends State<VisitInProgressPage> {
  Patient? _selectedPatient;
  bool _isLoading = true;
  String? _error;
  String _checkInLocation = '';
  DateTime? _checkInTime;

  // Timer variables
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  // Notes controller
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkInTime = DateTime.now();
    _loadPatientDetails();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1);
      });
    });
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

              // Set check-in location based on location type
              _setCheckInLocation(patient);
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

  void _setCheckInLocation(Patient patient) {
    if (widget.locationType == 'patient_address') {
      final address = _formatAddress(patient);
      setState(() {
        _checkInLocation = address;
      });
    } else if (widget.locationType == 'gps' &&
        widget.latitude != null &&
        widget.longitude != null) {
      setState(() {
        _checkInLocation =
            'GPS: ${widget.latitude!.toStringAsFixed(6)}, ${widget.longitude!.toStringAsFixed(6)}';
      });
    }
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

  String _formatCheckInTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour;
    return '$displayHour:$minute:$second $amPm';
  }

  void _readyToCheckOut() {
    // Navigate to Check-Out Location page with check-in location data
    final queryParams = {
      'patientId': widget.patientId.toString(),
      'serviceType': widget.serviceType,
      'locationType': widget.locationType,
      'notes': _notesController.text,
      'duration': _elapsedTime.inSeconds.toString(),
    };

    // Include check-in GPS coordinates if available
    if (widget.latitude != null && widget.longitude != null) {
      queryParams['latitude'] = widget.latitude.toString();
      queryParams['longitude'] = widget.longitude.toString();
    }
    if (widget.accuracyM != null) {
      queryParams['checkinAccuracyM'] = widget.accuracyM.toString();
    }
    if (widget.noGpsReason != null) {
      queryParams['checkinNoGpsReason'] = widget.noGpsReason!;
    }

    if (widget.scheduledVisitId != null) {
      queryParams['scheduledVisitId'] = widget.scheduledVisitId.toString();
    }

    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    context.push('/evv/checkout-location?$queryString');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Visit in Progress'),
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

    return _buildVisitInProgress();
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

  Widget _buildVisitInProgress() {
    final patient = _selectedPatient!;
    final fullName = '${patient.firstName} ${patient.lastName}';
    final maNumber =
        patient.maNumber ?? 'MA${patient.id.toString().padLeft(9, '0')}';

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with status and timer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status indicator
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Visit in Progress',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                  ],
                ),
                // Timer
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(_elapsedTime),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Visit Details section
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Patient:', fullName),
                _buildDetailRow('MA Number:', maNumber),
                _buildDetailRow('Service:', widget.serviceType),
                _buildDetailRow(
                    'Check-in Time:',
                    _checkInTime != null
                        ? _formatCheckInTime(_checkInTime!)
                        : 'Unknown'),
                _buildDetailRow('Check-in Location:', _checkInLocation),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Visit Notes section
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Add any notes about the visit...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Incident report button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () {
                final name = fullName.trim().isEmpty ? 'Client' : fullName;
                Navigator.of(context).push(
                  TitledMaterialPageRoute<void>(
                    title: 'Report Incident',
                    builder: (context) => IncidentReportWizardScreen(
                      clientId: patient.id,
                      clientName: name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.report, color: Colors.redAccent),
              label: const Text(
                'File Incident Report',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Ready to Check Out button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: _readyToCheckOut,
              icon: Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                'Ready to Check Out',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
