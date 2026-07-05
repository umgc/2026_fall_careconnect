import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Pain level card
import '../widgets/pain_level_card.dart';

// Header
import '../widgets/patient_header_card.dart';

// Info tab pieces
import '../widgets/contact_info_card.dart';
import '../widgets/emergency_contact_card.dart';
import '../widgets/communication_history_card.dart';

// Mood tab
import '../widgets/mood_history_card.dart';

// Health tab
import '../widgets/current_medications_card.dart';
// Recent Activity tab
// Virtual Check-in history
// Virtual Check-In domain entities
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';

// Virtual Check-In UI
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_config_sheet.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_history_card.dart';

import '../widgets/recent_symptom_card.dart' as sympt;

// API and models
import '../../../../services/api_service.dart';
import '../../../../services/checkin_service.dart';
import '../../../health/medication-tracker/models/medication-model.dart';
import '../../../../providers/user_provider.dart';
import 'package:care_connect_app/features/activities/presentation/pages/adl_iadl_management_screen.dart';
import 'package:care_connect_app/features/activities/presentation/pages/behavioral_incident_screens.dart';
import 'package:care_connect_app/features/dashboards/dashboards_screen.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'incident_report_history_screen.dart';
import '../../../audit/audit_log_screen.dart';
import '../../../../widgets/post_call_telemetry_summary_screen.dart';

class PatientDetailsPage extends StatefulWidget {
  final String patientId;

  /// NEW: when true, caregiver UI (can configure); when false, patient UI (no configure).
  final bool isCaregiver;

  const PatientDetailsPage({
    super.key,
    required this.patientId,
    this.isCaregiver = false, // default to patient behavior
  });

  @override
  State<PatientDetailsPage> createState() => _PatientDetailsPageState();
}

class _PatientDetailsPageState extends State<PatientDetailsPage> {
  List<Medication> medications = [];
  bool _isLoadingMedications = false;
  String? _medicationError;

  Map<String, dynamic>? _patientProfile;
  bool _isLoadingPatient = false;
  String? _patientError;
  bool _isLoadingProfile = false;
  String? _profileError;

  String _patientName = 'Patient';
  String _mrn = 'ID--';
  int _age = 0;
  String _sex = 'Unknown';
  String _currentMoodLabel = 'Unknown';
  String _currentMoodEmoji = '😐';
  DateTime? _dob;

  String? _phone;
  String? _email;
  String? _addressLine1;
  String? _addressLine2;
  String? _city;
  String? _state;
  String? _postalCode;

  String _emergencyContactName = 'Emergency Contact';
  String _emergencyRelationship = 'Primary Contact';
  String? _emergencyPhone;

  List<String> _diagnoses = [];
  List<String> _allergies = [];
  List<String> _emergencyPhones = [];

  List<MoodHistoryEntry> _moodEntries = [];
  List<sympt.SymptomEntry> _symptomEntries = [];
  List<VirtualCheckIn> _virtualCheckIns = [];
  List<Map<String, dynamic>> _callHistoryEvents = [];
  bool _isDeletingCallHistory = false;
  int _callHistoryPatientUserId = 0;
  int? _caregiverLinkId;
  bool _patientInitiatedCallsEnabled = true;
  bool _isSavingPatientCallPolicy = false;
  bool _patientMessagingEnabled = true;
  bool _isSavingPatientMessagingPolicy = false;

  int _currentPain = 0;
  String _painLocation = 'Not provided';
  int _dizziness = 0;
  int _fatigue = 0;
  String _lastReportedPain = 'not available';

  final _likesController = TextEditingController();
  final _dislikesController = TextEditingController();
  final _habitsController = TextEditingController();
  final _phobiasController = TextEditingController();
  String? _preferredCommunicationMethod; // verbal | visual | written | gesture
  bool _isSavingPersonalization = false;
  bool _isEditingPersonalization = false;

  // Known Risks
  List<Map<String, dynamic>> _riskTypes = [];
  Map<int, int> _riskIdByTypeId = {}; // riskTypeId -> patient_risk id (for DELETE)
  bool _isLoadingRisks = false;
  String? _risksError;
  bool _isEditingRisks = false;
  Set<int> _editingCheckedTypeIds = {}; // while editing, which risk type ids are checked
  bool _isSavingRisks = false;

  Future<void> _startVideoCall(String patientName) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to determine your account.')),
      );
      return;
    }

    final role = user.role.toUpperCase();
    final currentUserId = user.id;

    int? targetUserId;
    var recipientName = patientName;

    if (role == 'CAREGIVER') {
      targetUserId = int.tryParse(widget.patientId);
      if (targetUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid patient ID for video call.')),
        );
        return;
      }
    } else if (role == 'PATIENT') {
      final linkedCaregiverUserIds =
          await ApiService.getPatientLinkedCaregiverUserIds(currentUserId);

      if (!mounted) return;

      if (linkedCaregiverUserIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No assigned caregiver found for video call.'),
          ),
        );
        return;
      }

      targetUserId = linkedCaregiverUserIds.first;
      recipientName = 'Caregiver';
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video calling is not available for this role.'),
        ),
      );
      return;
    }

    final allowed = await ApiService.canInitiateVideoCall(
      currentUserId: currentUserId,
      currentUserRole: role,
      targetUserId: targetUserId,
      caregiverId: user.caregiverId,
    );

    if (!mounted) return;

    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not allowed to start this video call.'),
        ),
      );
      return;
    }

    final callId = 'chime_call_${DateTime.now().millisecondsSinceEpoch}';

    await context.push(
      '/video-call-chime'
      '?userId=$currentUserId'
      '&recipientId=$targetUserId'
      '&userRole=${Uri.encodeComponent(role)}'
      '&userName=${Uri.encodeComponent(user.name ?? role)}'
      '&recipientName=${Uri.encodeComponent(recipientName)}'
      '&initiator=true'
      '&video=true'
      '&audio=true'
      '&callId=$callId'
      '&returnPatientDetailsId=${Uri.encodeComponent(widget.patientId)}'
      '&forcePatientDetailsOnExit=true'
      '&returnAsCaregiver=${widget.isCaregiver ? 'true' : 'false'}',
    );

    if (!mounted) return;
    await _refreshCallHistoryAfterCall(callId);
  }

  Future<void> _refreshCallHistoryAfterCall(String endedCallId) async {
    await _loadPatientData();
    if (!mounted) return;

    if (endedCallId.trim().isNotEmpty) {
      const maxAttempts = 6;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) return;

        final callEvents = await ApiService.getCallTelemetry(endedCallId);
        if (_hasFinalizedCallTelemetry(callEvents)) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    try {
      final telemetryData = await ApiService.getMyCallTelemetry();
      if (!mounted) return;

      setState(() {
        _applyCallHistoryData(
          patientUserId: _callHistoryPatientUserId,
          telemetryData: telemetryData,
        );
      });
    } catch (_) {
      // Keep the immediate refresh result if follow-up call fails.
    }
  }

  bool _hasFinalizedCallTelemetry(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return false;
    }

    for (final event in events) {
      final eventType =
          (event['eventType'] as String?)?.trim().toUpperCase() ?? '';
      if (eventType == 'SENTIMENT_FINAL' ||
          eventType == 'WS_END_CALL' ||
          eventType == 'CALL_END') {
        return true;
      }
    }
    return false;
  }

  Future<void> _openCallHistoryDetail(String callId) async {
    final trimmedCallId = callId.trim();
    if (trimmedCallId.isEmpty || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostCallTelemetrySummaryScreen(
          callId: trimmedCallId,
          recipientName: _patientName,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPatientData();
    _fetchRiskTypes();
    _fetchPatientRisks();
  }

  @override
  void dispose() {
    _likesController.dispose();
    _dislikesController.dispose();
    _habitsController.dispose();
    _phobiasController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientData() async {
    final patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null) {
      setState(() {
        _patientError = 'Invalid patient ID';
        _isLoadingProfile = false;
        _profileError = 'Invalid patient ID';
      });
      return;
    }

    setState(() {
      _isLoadingPatient = true;
      _patientError = null;
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;

      final profileFuture = ApiService.getPatientCompleteProfile(patientIdInt);
      final detailsFuture = ApiService.getPatientDetails(patientIdInt);
      final familyFuture = ApiService.getPatientFamilyMembers(patientIdInt);
      final symptomsFuture = ApiService.getSymptomsForPatient(patientIdInt);
      final telemetryFuture = ApiService.getMyCallTelemetry();
      final medsFuture = _fetchMedications();

      Future<Map<String, dynamic>?> caregiverViewFuture;
      if (widget.isCaregiver && user?.caregiverId != null) {
        caregiverViewFuture = ApiService.getPatientForCaregiver(
          user!.caregiverId!,
          patientIdInt,
        );
      } else {
        caregiverViewFuture = Future.value(null);
      }

      final profileResp = await profileFuture;
      final detailsResp = await detailsFuture;
      final familyMembers = await familyFuture;
      final symptomData = await symptomsFuture;
      final telemetryData = await telemetryFuture;
      final caregiverData = await caregiverViewFuture;
      final checkInSummaries = await CheckinService.fetchCheckInsForPatient(
        widget.patientId,
      );
      await medsFuture;

      final profilePayload = _extractProfilePayload(profileResp);
      final detailsPayload = _extractResponseMap(detailsResp);

      if (profilePayload.isNotEmpty) {
        _patientProfile = profilePayload;
        _populatePersonalizationControllers(profilePayload);
      }

      final moodUserId = _resolveMoodUserId(
        detailsPayload: detailsPayload,
        profilePayload: profilePayload,
        caregiverData: caregiverData,
      );

      final moodData = await ApiService.getMoodHistory(moodUserId);

      _applyPatientIdentity(
        profilePayload: profilePayload,
        detailsPayload: detailsPayload,
        caregiverData: caregiverData,
        familyMembers: familyMembers,
      );
      _applyCaregiverCallPolicy(caregiverData);
      _applyMoodData(moodData);
      _applySymptomData(symptomData);
      if (checkInSummaries.isNotEmpty) {
        _applyVirtualCheckInSummaries(checkInSummaries);
      } else {
        _applyVirtualCheckIns(detailsPayload);
      }
      _callHistoryPatientUserId = moodUserId;
      _applyCallHistoryData(
        patientUserId: moodUserId,
        telemetryData: telemetryData,
      );
      _profileError = null;
    } catch (e) {
      _patientError = 'Error loading patient details: $e';
      if (_patientProfile == null) {
        _profileError = 'Error loading patient profile: $e';
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPatient = false;
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _fetchPatientProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    final patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null) {
      setState(() {
        _isLoadingProfile = false;
        _profileError = 'Invalid patient ID';
      });
      return;
    }

    try {
      final resp = await ApiService.getPatientProfile(patientIdInt);
      if (resp.statusCode != 200) {
        setState(() {
          _isLoadingProfile = false;
          _profileError = 'Failed to load patient profile: ${resp.statusCode}';
        });
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      setState(() {
        _patientProfile = data;
        _isLoadingProfile = false;
      });

      _populatePersonalizationControllers(data);
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
        _profileError = 'Error loading patient profile: $e';
      });
    }
  }

  void _populatePersonalizationControllers(Map<String, dynamic> data) {
    // Support both camelCase and snake_case keys until backend is consistent.
    String? readString(String camel, String snake) {
      final v = data[camel] ?? data[snake];
      if (v == null) return null;
      return v.toString();
    }

    _likesController.text = readString('likes', 'likes') ?? '';
    _dislikesController.text = readString('dislikes', 'dislikes') ?? '';
    _habitsController.text = readString('habits', 'habits') ?? '';
    _phobiasController.text = readString('phobias', 'phobias') ?? '';

    final pref = readString(
      'preferredCommunicationMethod',
      'preferred_communication_method',
    );
    final normalized = pref?.trim().toLowerCase();
    const allowed = {'verbal', 'visual', 'written', 'gesture'};
    setState(() {
      _preferredCommunicationMethod =
          allowed.contains(normalized) ? normalized : null;
    });
  }

  Future<void> _savePersonalization() async {
    final patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid patient ID')),
      );
      return;
    }

    setState(() => _isSavingPersonalization = true);
    try {
      // Preserve existing fields by starting from the fetched profile map.
      final payload = <String, dynamic>{...?_patientProfile};

      payload['likes'] = _likesController.text.trim();
      payload['dislikes'] = _dislikesController.text.trim();
      payload['habits'] = _habitsController.text.trim();
      payload['phobias'] = _phobiasController.text.trim();
      payload['preferredCommunicationMethod'] = _preferredCommunicationMethod;

      final resp = await ApiService.updatePatientProfile(patientIdInt, payload);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final updated = (body['data'] ?? body) as Map<String, dynamic>;
        setState(() {
          _patientProfile = updated;
        });
        _populatePersonalizationControllers(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Personalization saved')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Save failed: ${resp.statusCode}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPersonalization = false;
          _isEditingPersonalization = false;
        });
      }
    }
  }

  Widget _buildPersonalizationCard() {
    final theme = Theme.of(context);

    if (_isLoadingProfile) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Loading personalization...'),
            ],
          ),
        ),
      );
    }

    if (_profileError != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personalization',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _profileError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _fetchPatientProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final canEdit = widget.isCaregiver;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    Widget row({
      required IconData icon,
      required String label,
      required TextEditingController controller,
    }) {
      if (_isEditingPersonalization && canEdit) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Icon(icon,
                  size: 20, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: true,
                maxLines: 2,
                decoration: deco(label),
              ),
            ),
          ],
        );
      } else {
        final value = controller.text.trim();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(icon,
                  size: 20, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? 'Not set' : value,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        );
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Personalization',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                    if (canEdit)
                      ElevatedButton.icon(
                        onPressed: _isSavingPersonalization
                            ? null
                            : () {
                                if (_isEditingPersonalization) {
                                  _savePersonalization();
                                } else {
                                  setState(() {
                                    _isEditingPersonalization = true;
                                  });
                                }
                              },
                        icon: _isSavingPersonalization
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _isEditingPersonalization
                                    ? Icons.check
                                    : Icons.edit,
                              ),
                        label: Text(
                          _isEditingPersonalization ? 'Save' : 'Edit',
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 12),
                row(
                  icon: Icons.thumb_up_alt_outlined,
                  label: 'Likes',
                  controller: _likesController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.thumb_down_alt_outlined,
                  label: 'Dislikes',
                  controller: _dislikesController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.repeat_rounded,
                  label: 'Habits',
                  controller: _habitsController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.warning_amber_outlined,
                  label: 'Phobias',
                  controller: _phobiasController,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, right: 8),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                      ),
                    ),
                    Expanded(
                      child: _isEditingPersonalization && canEdit
                          ? DropdownButtonFormField<String>(
                              initialValue: _preferredCommunicationMethod,
                              items: const [
                                DropdownMenuItem(
                                  value: 'verbal',
                                  child: Text('Verbal'),
                                ),
                                DropdownMenuItem(
                                  value: 'visual',
                                  child: Text('Visual'),
                                ),
                                DropdownMenuItem(
                                  value: 'written',
                                  child: Text('Written'),
                                ),
                                DropdownMenuItem(
                                  value: 'gesture',
                                  child: Text('Gesture'),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => _preferredCommunicationMethod = v,
                              ),
                              decoration:
                                  deco('Preferred communication method'),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preferred communication method',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (_preferredCommunicationMethod ?? '')
                                          .isEmpty
                                      ? 'Not set'
                                      : _preferredCommunicationMethod!
                                          .substring(0, 1)
                                          .toUpperCase() +
                                          _preferredCommunicationMethod!
                                              .substring(1),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _extractResponseMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {};
  }

  Map<String, dynamic> _extractProfilePayload(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return {};
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return decoded;
  }

  void _applyPatientIdentity({
    required Map<String, dynamic> profilePayload,
    required Map<String, dynamic> detailsPayload,
    required Map<String, dynamic>? caregiverData,
    required List<Map<String, dynamic>> familyMembers,
  }) {
    final caregiverPatient = caregiverData?['patient'];
    final caregiverPatientMap = caregiverPatient is Map<String, dynamic>
        ? caregiverPatient
        : <String, dynamic>{};

    final source = {
      ...detailsPayload,
      ...profilePayload,
      ...caregiverPatientMap,
    };

    final firstName = _firstNonEmpty([
      source['firstName'],
      detailsPayload['firstName'],
      profilePayload['firstName'],
      caregiverPatientMap['firstName'],
    ]);
    final lastName = _firstNonEmpty([
      source['lastName'],
      detailsPayload['lastName'],
      profilePayload['lastName'],
      caregiverPatientMap['lastName'],
    ]);
    final fullName = '$firstName $lastName'.trim();

    final dobText = _firstNonEmpty([
      source['dob'],
      source['dateOfBirth'],
      source['birthDate'],
    ]);
    final parsedDob = _parseDate(dobText);

    final genderRaw = _firstNonEmpty([source['gender'], source['sex']]);

    final addressMap = source['address'] is Map<String, dynamic>
        ? source['address'] as Map<String, dynamic>
        : <String, dynamic>{};

    final allergyList = (profilePayload['allergies'] is List)
        ? (profilePayload['allergies'] as List)
        : const [];

    final mappedAllergies = allergyList
        .map((item) {
          if (item is Map<String, dynamic>) {
            final allergen = _firstNonEmpty([item['allergen']]);
            final severity = _firstNonEmpty([item['severity']]);
            if (allergen.isEmpty) {
              return '';
            }
            return severity.isEmpty ? allergen : '$allergen ($severity)';
          }
          return item?.toString() ?? '';
        })
        .where((value) => value.trim().isNotEmpty)
        .toList();

    final diagnoses = <String>{
      ..._extractStringList(source['diagnoses']),
      ..._extractStringList(source['conditions']),
      ..._extractStringList(source['conditionList']),
      if (_firstNonEmpty([source['diagnosis']]).isNotEmpty)
        _firstNonEmpty([source['diagnosis']]),
    }.toList();

    final phone = _firstNonEmpty([
      source['phone'],
      detailsPayload['phone'],
      profilePayload['phone'],
      caregiverPatientMap['phone'],
    ]);

    final mrnRaw = _firstNonEmpty([
      source['maNumber'],
      source['mrn'],
      source['id'],
    ]);

    _patientName = fullName.isNotEmpty ? fullName : _patientName;
    _mrn = mrnRaw.isNotEmpty ? mrnRaw : 'ID-${widget.patientId}';
    _dob = parsedDob;
    _age = _calculateAge(parsedDob);
    _sex = _humanizeGender(genderRaw);
    _email = _firstNonEmpty([
      source['email'],
      detailsPayload['email'],
      profilePayload['email'],
      caregiverPatientMap['email'],
    ]);
    _phone = phone.isNotEmpty ? phone : null;

    _addressLine1 = _firstNonEmpty([
      addressMap['line1'],
      addressMap['addressLine1'],
    ]);
    _addressLine2 = _firstNonEmpty([
      addressMap['line2'],
      addressMap['addressLine2'],
    ]);
    _city = _firstNonEmpty([addressMap['city']]);
    _state = _firstNonEmpty([addressMap['state']]);
    _postalCode = _firstNonEmpty([addressMap['zip'], addressMap['postalCode']]);

    _allergies = mappedAllergies;
    _diagnoses = diagnoses;

    final primaryFamilyMember = familyMembers.isNotEmpty
        ? familyMembers.first
        : const <String, dynamic>{};

    final emergencyName = _firstNonEmpty([
      primaryFamilyMember['familyMemberName'],
      primaryFamilyMember['name'],
      primaryFamilyMember['fullName'],
    ]);
    final emergencyRelationship = _firstNonEmpty([
      primaryFamilyMember['relationship'],
      source['relationship'],
    ]);
    final emergencyPhone = _firstNonEmpty([
      primaryFamilyMember['familyMemberPhone'],
      primaryFamilyMember['phone'],
      source['emergencyPhone'],
      phone,
    ]);

    final emergencyPhones = <String>[];
    if (emergencyPhone.isNotEmpty) {
      emergencyPhones.add(emergencyPhone);
    }
    _emergencyPhones = emergencyPhones;
    _emergencyPhone = emergencyPhone.isNotEmpty ? emergencyPhone : null;
    _emergencyContactName = emergencyName.isNotEmpty
        ? emergencyName
        : 'Emergency Contact';
    _emergencyRelationship = emergencyRelationship.isNotEmpty
        ? emergencyRelationship
        : 'Primary Contact';
  }

  int _resolveMoodUserId({
    required Map<String, dynamic> detailsPayload,
    required Map<String, dynamic> profilePayload,
    required Map<String, dynamic>? caregiverData,
  }) {
    final linkMap = caregiverData?['link'] is Map<String, dynamic>
        ? caregiverData!['link'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final detailsUser = detailsPayload['user'] is Map<String, dynamic>
        ? detailsPayload['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final profileUser = profilePayload['user'] is Map<String, dynamic>
        ? profilePayload['user'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final candidates = <dynamic>[
      linkMap['patientUserId'],
      detailsUser['id'],
      profileUser['id'],
      widget.patientId,
    ];

    for (final value in candidates) {
      if (value is int) return value;
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  List<String> _extractStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map<String, dynamic>) {
            return _firstNonEmpty([
              item['name'],
              item['label'],
              item['title'],
              item['value'],
            ]);
          }
          return (item ?? '').toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _applyMoodData(List<dynamic> moodData) {
    final entries = moodData.whereType<Map<String, dynamic>>().map((entry) {
      final date =
          _parseDate(
            entry['createdAt'] ?? entry['timestamp'] ?? entry['date'],
          ) ??
          DateTime.now();
      final scoreRaw = entry['score'];
      final score = scoreRaw is int
          ? scoreRaw
          : int.tryParse(scoreRaw?.toString() ?? '') ?? 5;
      final score5 = score <= 5
          ? score.clamp(1, 5)
          : ((score / 2).round()).clamp(1, 5);
      final label = _firstNonEmpty([
        entry['label'],
        _moodLabelFromScore(score),
      ]);
      final emoji = _moodEmoji(score, label);

      return MoodHistoryEntry(
        date: date,
        label: label,
        score5: score5,
        emoji: emoji,
        note: _firstNonEmpty([entry['note'], entry['notes'], entry['comment']]),
      );
    }).toList();

    entries.sort((a, b) => b.date.compareTo(a.date));
    _moodEntries = entries;

    if (entries.isNotEmpty) {
      _currentMoodLabel = entries.first.label;
      _currentMoodEmoji = entries.first.emoji ?? '😐';
    }
  }

  void _applySymptomData(List<Map<String, dynamic>> symptomData) {
    final mapped = symptomData.map((entry) {
      final symptomKey = _firstNonEmpty([entry['symptomKey']]);
      final symptomValue = _firstNonEmpty([entry['symptomValue']]);
      final severity = _symptomSeverityLabel(entry['severity']);
      final date =
          _parseDate(entry['takenAt'] ?? entry['createdAt']) ?? DateTime.now();
      final name = symptomValue.isNotEmpty
          ? '$symptomKey $symptomValue'.trim()
          : symptomKey;

      return sympt.SymptomEntry(
        id: (entry['id'] ?? '').toString(),
        date: date,
        name: name.isNotEmpty ? name : 'Symptom',
        severity: severity,
        note: _firstNonEmpty([entry['clinicalNotes'], entry['notes']]),
      );
    }).toList();

    mapped.sort((a, b) => b.date.compareTo(a.date));
    _symptomEntries = mapped;

    if (mapped.isNotEmpty) {
      final latest = mapped.first;
      _currentPain = _severityLabelToInt(latest.severity);
      _painLocation = latest.name;
      _dizziness = (_currentPain / 2).round().clamp(0, 10);
      _fatigue = (_currentPain * 2).clamp(0, 10);
      _lastReportedPain = _timeAgo(latest.date);
    }
  }

  void _applyVirtualCheckIns(Map<String, dynamic> detailsPayload) {
    final raw = detailsPayload['virtualCheckIns'];
    if (raw is! List) {
      _virtualCheckIns = [];
      return;
    }

    _virtualCheckIns = raw.whereType<Map<String, dynamic>>().map((entry) {
      final statusText = _firstNonEmpty([entry['status']]).toLowerCase();
      final typeText = _firstNonEmpty([entry['type']]).toLowerCase();
      final startedAt = _parseDate(entry['startedAt']) ?? DateTime.now();

      return VirtualCheckIn(
        id: _firstNonEmpty([entry['id'], entry['checkInId']]),
        type: switch (typeText) {
          'followup' || 'follow_up' || 'follow-up' => CheckInType.followUp,
          'urgent' => CheckInType.urgent,
          _ => CheckInType.routine,
        },
        clinicianName: _firstNonEmpty([
          entry['clinicianName'],
          entry['caregiverName'],
          'Care Team',
        ]),
        startedAt: startedAt,
        durationMinutes: _safeInt(entry['durationMinutes']),
        status: switch (statusText) {
          'missed' => CheckInStatus.missed,
          'cancelled' || 'canceled' => CheckInStatus.cancelled,
          _ => CheckInStatus.completed,
        },
        moodLabel: _firstNonEmpty([entry['moodLabel'], _currentMoodLabel]),
        nextCheckIn: _parseDate(entry['nextCheckIn']) ?? startedAt,
        summary: _firstNonEmpty([entry['summary'], entry['notes']]),
      );
    }).toList();
  }

  void _applyVirtualCheckInSummaries(List<CheckInSummary> summaries) {
    _virtualCheckIns = summaries.map((entry) {
      final startedAt = entry.createdAt ?? DateTime.now();
      final status = entry.submittedAt == null
          ? CheckInStatus.missed
          : CheckInStatus.completed;
      final summaryText = entry.submittedAt == null
          ? '${entry.questionCount} configured questions pending patient submission.'
          : '${entry.questionCount} question responses submitted.';

      return VirtualCheckIn(
        id: entry.checkInId.toString(),
        type: CheckInType.routine,
        clinicianName: 'Care Team',
        startedAt: startedAt,
        durationMinutes: 0,
        status: status,
        moodLabel: _currentMoodLabel,
        nextCheckIn: startedAt,
        summary: summaryText,
      );
    }).toList();
  }

  int? _latestVirtualCheckInId() {
    final ordered = [..._virtualCheckIns]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    for (final entry in ordered) {
      final parsed = int.tryParse(entry.id);
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<int>? _extractCatalogQuestionIds(List<VirtualCheckInQuestion> questions) {
    final ids = <int>{};
    for (final question in questions) {
      final parsed = int.tryParse(question.id.trim());
      if (parsed == null) return null;
      ids.add(parsed);
    }
    return ids.toList();
  }

  void _showConfigureFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _saveVirtualCheckInConfiguration(
    List<VirtualCheckInQuestion> updated,
  ) async {
    final selectedQuestionIds = _extractCatalogQuestionIds(updated);
    if (selectedQuestionIds == null) {
      _showConfigureFeedback(
        'Custom questions are not supported yet. Please add questions from the catalog.',
      );
      return false;
    }
    if (selectedQuestionIds.isEmpty) {
      _showConfigureFeedback('Select at least one question to save.');
      return false;
    }

    final createdCheckInId = await CheckinService.createCheckinWithSelectedQuestions(
      patientId: widget.patientId,
      selectedQuestionIds: selectedQuestionIds,
    );
    if (createdCheckInId == null) {
      _showConfigureFeedback('Failed to save virtual check-in configuration.');
      return false;
    }

    await _loadPatientData();
    _showConfigureFeedback('Virtual check-in configuration saved');
    return true;
  }

  void _applyCallHistoryData({
    required int patientUserId,
    required List<Map<String, dynamic>> telemetryData,
  }) {
    final filtered = telemetryData.where((event) {
      if (patientUserId <= 0) {
        return true;
      }

      final actorId = _safeUserId(event['actorUserId']);
      final targetId = _safeUserId(event['targetUserId']);
      if (actorId == patientUserId || targetId == patientUserId) {
        return true;
      }

      final metadata = _extractJsonMap(event['metadataJson']);
      final contextRaw = metadata['contextPatientUserIds'];
      if (contextRaw is List) {
        for (final item in contextRaw) {
          final contextId = _safeUserId(item);
          if (contextId == patientUserId) {
            return true;
          }
        }
      }
      final singleContext = _safeUserId(metadata['contextPatientUserId']);
      return singleContext == patientUserId;
    }).toList();

    filtered.sort((a, b) {
      final bTime =
          _parseDate(b['occurredAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final aTime =
          _parseDate(a['occurredAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    _callHistoryEvents = filtered;
  }

  Map<String, dynamic> _extractJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  void _applyCaregiverCallPolicy(Map<String, dynamic>? caregiverData) {
    if (caregiverData == null) {
      return;
    }
    final link = caregiverData['link'];
    if (link is! Map<String, dynamic>) {
      return;
    }

    final linkIdRaw = link['linkId'] ?? link['id'];
    final linkId = linkIdRaw is int
        ? linkIdRaw
        : int.tryParse(linkIdRaw?.toString() ?? '');

    final enabledRaw = link['patientVideoCallsEnabled'];
    final enabled = enabledRaw is bool
        ? enabledRaw
        : enabledRaw == null
            ? true
            : enabledRaw.toString().toLowerCase() != 'false';

    final msgRaw = link['patientMessagingEnabled'];
    final messagingEnabled = msgRaw is bool
        ? msgRaw
        : msgRaw == null
            ? true
            : msgRaw.toString().toLowerCase() != 'false';

    _caregiverLinkId = linkId;
    _patientInitiatedCallsEnabled = enabled;
    _patientMessagingEnabled = messagingEnabled;
  }

  Future<void> _togglePatientInitiatedCalls(bool enabled) async {
    final linkId = _caregiverLinkId;
    if (linkId == null || _isSavingPatientCallPolicy) {
      return;
    }

    setState(() {
      _isSavingPatientCallPolicy = true;
      _patientInitiatedCallsEnabled = enabled;
    });

    final success = await ApiService.setPatientVideoCallsEnabledForLink(
      linkId: linkId,
      enabled: enabled,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      setState(() {
        _patientInitiatedCallsEnabled = !enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update patient call policy. Please retry.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Patient-initiated calls are enabled.'
                : 'Patient-initiated calls are disabled.',
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isSavingPatientCallPolicy = false;
      });
    }
  }

  Future<void> _togglePatientMessaging(bool enabled) async {
    final linkId = _caregiverLinkId;
    if (linkId == null || _isSavingPatientMessagingPolicy) return;

    setState(() {
      _isSavingPatientMessagingPolicy = true;
      _patientMessagingEnabled = enabled;
    });

    final success = await ApiService.setPatientMessagingEnabledForLink(
      linkId: linkId,
      enabled: enabled,
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _patientMessagingEnabled = !enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update patient messaging policy. Please retry.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Patient messaging is enabled.'
                : 'Patient messaging is disabled.',
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isSavingPatientMessagingPolicy = false;
      });
    }
  }

  int? _safeUserId(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  int _calculateAge(DateTime? dob) {
    if (dob == null) return 0;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final item in candidates) {
      final value = item?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  int _safeInt(dynamic value) {
    if (value is int) return value.clamp(0, 10);
    return (int.tryParse(value?.toString() ?? '') ?? 0).clamp(0, 10);
  }

  String _humanizeGender(String raw) {
    if (raw.isEmpty) return 'Unknown';
    final normalized = raw.replaceAll('_', ' ').toLowerCase();
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _moodEmoji(int score, String label) {
    if (score >= 8) return '😄';
    if (score >= 6) return '🙂';
    if (score >= 4) return '😐';
    if (score >= 2) return '😟';

    final l = label.toLowerCase();
    if (l.contains('good') || l.contains('excellent') || l.contains('happy')) {
      return '🙂';
    }
    if (l.contains('poor') || l.contains('sad') || l.contains('bad')) {
      return '😟';
    }
    return '😐';
  }

  String _moodLabelFromScore(int score) {
    if (score >= 8) return 'Excellent';
    if (score >= 6) return 'Good';
    if (score >= 4) return 'Fair';
    return 'Poor';
  }

  String _symptomSeverityLabel(dynamic severityRaw) {
    final severity = _safeInt(severityRaw);
    if (severity >= 7) return 'Severe';
    if (severity >= 4) return 'Moderate';
    return 'Mild';
  }

  int _severityLabelToInt(String label) {
    final l = label.toLowerCase();
    if (l.contains('severe')) return 8;
    if (l.contains('moderate')) return 5;
    return 2;
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool get _canDeleteCallHistoryInThisBuild => !kReleaseMode;

  Future<void> _deleteCallHistoryForPatientDevOnly() async {
    if (!_canDeleteCallHistoryInThisBuild || _isDeletingCallHistory) {
      return;
    }

    final patientUserId = _callHistoryPatientUserId;

    if (patientUserId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No patient call history is available to delete.')),
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Call History (Dev Only)'),
            content: Text(
              'Delete all call history tied to this patient, including telemetry rows that feed the Call History tile, plus summaries, transcripts, archives, recording records, and recording files? This is only for local/dev mode.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() {
      _isDeletingCallHistory = true;
    });

    var deletedEvents = 0;
    var deletedSummaries = 0;
    var deletedTranscriptSegments = 0;
    var deletedTranscriptArchives = 0;
    var deletedRecordingRows = 0;
    var deletedRecordingObjects = 0;
    var deletedCalls = 0;

    try {
      final deleteResult = await ApiService.deletePatientCallHistoryDev(
        patientUserId,
      );
      deletedEvents += (deleteResult['deletedEvents'] as num?)?.toInt() ?? 0;
      deletedCalls += (deleteResult['deletedCalls'] as num?)?.toInt() ?? 0;
      deletedSummaries +=
          (deleteResult['deletedSummaries'] as num?)?.toInt() ?? 0;
      deletedTranscriptSegments +=
          (deleteResult['deletedTranscriptSegments'] as num?)?.toInt() ?? 0;
      deletedTranscriptArchives +=
          (deleteResult['deletedTranscriptArchives'] as num?)?.toInt() ?? 0;
      deletedRecordingRows +=
          (deleteResult['deletedRecordingRows'] as num?)?.toInt() ?? 0;
      deletedRecordingObjects +=
          (deleteResult['deletedRecordingS3Objects'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      await _loadPatientData();

      if (!mounted) return;
      final footprintNote =
          ' Removed $deletedSummaries summary row(s), '
          '$deletedTranscriptSegments transcript segment(s), '
          '$deletedTranscriptArchives transcript archive(s), '
          '$deletedRecordingRows recording row(s), and '
          '$deletedRecordingObjects recording object(s).';
      final message =
          'Deleted $deletedEvents telemetry event(s) across $deletedCalls call(s) in dev mode.$footprintNote';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingCallHistory = false;
        });
      }
    }
  }

  /// Fetch medications from the backend API
  Future<void> _fetchMedications() async {
    setState(() {
      _isLoadingMedications = true;
      _medicationError = null;
    });

    try {
      // Parse patientId from String to int
      final patientIdInt = int.tryParse(widget.patientId);

      if (patientIdInt == null) {
        setState(() {
          _isLoadingMedications = false;
          _medicationError = 'Invalid patient ID';
        });
        return;
      }

      final http.Response resp =
          await ApiService.getPatientMedicationsForPatient(patientIdInt);

      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);

        setState(() {
          medications = data.map((json) => Medication.fromJson(json)).toList();
          _isLoadingMedications = false;
        });
      } else {
        setState(() {
          _isLoadingMedications = false;
          _medicationError = 'Failed to load medications: ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMedications = false;
        _medicationError = 'Error loading medications: $e';
      });
    }
  }

  Future<void> _fetchRiskTypes() async {
    setState(() { _isLoadingRisks = true; _risksError = null; });
    try {
      final resp = await ApiService.getRiskTypes();
      if (resp.statusCode == 200) {
        final list = (jsonDecode(resp.body) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() { _riskTypes = list; });
      } else {
        setState(() { _risksError = 'Failed to load risk types'; });
      }
    } catch (e) {
      setState(() { _risksError = 'Error: $e'; });
    }
    if (mounted) setState(() { _isLoadingRisks = false; });
  }

  Future<void> _fetchPatientRisks() async {
    final patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null) return;
    try {
      final resp = await ApiService.getPatientRisks(patientIdInt);
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        final map = <int, int>{};
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          final rtId = m['riskTypeId'] is int ? m['riskTypeId'] as int : int.tryParse(m['riskTypeId'].toString());
          final id = m['id'] is int ? m['id'] as int : int.tryParse(m['id'].toString());
          if (rtId != null && id != null) map[rtId] = id;
        }
        setState(() { _riskIdByTypeId = map; });
      }
    } catch (_) {}
  }

  /// Flagged risk names for the persistent alert banner (derived from _riskTypes + _riskIdByTypeId).
  List<String> get _flaggedRiskNames {
    final names = <String>[];
    for (final rt in _riskTypes) {
      final id = rt['id'] is int ? rt['id'] as int : int.tryParse(rt['id'].toString());
      if (id != null && _riskIdByTypeId.containsKey(id)) {
        final name = rt['name']?.toString();
        if (name != null && name.isNotEmpty) names.add(name);
      }
    }
    return names;
  }

  /// Persistent risk alert banner at top of patient profile when client has flagged risks.
  Widget _buildRiskBanner() {
    final names = _flaggedRiskNames;
    if (names.isEmpty) return const SizedBox.shrink();
    final text = 'Known Risks: ${names.join(', ')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.red.shade700,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tappable card in In-home: "Dashboards" → opens dashboards hub (Competency Trends, etc.).
  Widget _buildDashboardsCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => DashboardsScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.dashboard_outlined, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Dashboards',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View competency trends and other reports',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only Audit Log viewer for supervisors/caregivers.
  Widget _buildAuditLogCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AuditLogScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Audit Log',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View read-only history of caregiver-entered records',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Tappable card in the Health tab: "ADL/IADL management" → opens hub to manage ADL & IADL.
  Widget _buildAdlIadlManagementCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AdlIadlManagementScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.self_improvement, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ADL / IADL management',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log and manage daily living activities for this client',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBehaviorLogCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => BehavioralIncidentFormScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.report_problem_outlined, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Log Behavior',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Document behavioral incidents during visits',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBehaviorHistoryCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => BehavioralIncidentHistoryScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.history, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Behavioral history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View prior behavioral incident logs',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentReportsCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => IncidentReportWizardScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.report, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'File incident report',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Record structured medical or risk incidents',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentHistoryCard(String patientName) {
    final theme = Theme.of(context);
    final clientId = int.tryParse(widget.patientId);
    if (clientId == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => IncidentReportHistoryScreen(
                clientId: clientId,
                clientName: patientName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.history, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Incident report history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View structured incident reports for this client',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKnownRisksCard() {
    final theme = Theme.of(context);
    final canEdit = widget.isCaregiver;

    if (_isLoadingRisks && _riskTypes.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _risksError != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Known Risks', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_risksError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // View mode: show only selected risks + Edit button
    if (!_isEditingRisks) {
      final selectedNames = <String>[];
      for (final rt in _riskTypes) {
        final id = rt['id'] is int ? rt['id'] as int : int.tryParse(rt['id'].toString());
        if (id != null && _riskIdByTypeId.containsKey(id)) {
          selectedNames.add(rt['name']?.toString() ?? '');
        }
      }
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Known Risks',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canEdit)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isEditingRisks = true;
                          _editingCheckedTypeIds = _riskIdByTypeId.keys.toSet();
                        });
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (selectedNames.isEmpty)
                Text('No risks flagged.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              else
                ...selectedNames.map((name) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                )),
            ],
          ),
        ),
      );
    }

    // Edit mode: all checkboxes + Save button
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Known Risks',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (canEdit)
                  ElevatedButton.icon(
                    onPressed: _isSavingRisks ? null : () => _saveKnownRisks(),
                    icon: _isSavingRisks
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Save'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_riskTypes.isEmpty && !_isLoadingRisks)
              Text('No risk types available.', style: theme.textTheme.bodySmall)
            else
              ..._riskTypes.map((rt) {
                final id = rt['id'] is int ? rt['id'] as int : int.tryParse(rt['id'].toString());
                final name = rt['name']?.toString() ?? '';
                if (id == null) return const SizedBox.shrink();
                final isChecked = _editingCheckedTypeIds.contains(id);
                return CheckboxListTile(
                  value: isChecked,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _editingCheckedTypeIds.add(id);
                      } else {
                        _editingCheckedTypeIds.remove(id);
                      }
                    });
                  },
                  title: Text(name),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _saveKnownRisks() async {
    final patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null || !widget.isCaregiver) return;

    setState(() => _isSavingRisks = true);
    try {
      final toAdd = _editingCheckedTypeIds.where((id) => !_riskIdByTypeId.containsKey(id)).toList();
      final toRemove = _riskIdByTypeId.keys.where((id) => !_editingCheckedTypeIds.contains(id)).toList();

      for (final riskTypeId in toAdd) {
        final res = await ApiService.flagPatientRisk(patientIdInt, riskTypeId);
        if (res.statusCode != 201 && res.statusCode != 200) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add risk: ${res.statusCode}')));
          return;
        }
      }
      for (final riskTypeId in toRemove) {
        final riskId = _riskIdByTypeId[riskTypeId];
        if (riskId != null) {
          final res = await ApiService.unflagPatientRisk(patientIdInt, riskId);
          if (res.statusCode != 204 && res.statusCode != 200) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove risk: ${res.statusCode}')));
            return;
          }
        }
      }

      await _fetchPatientRisks();
      if (mounted) {
        setState(() {
          _isEditingRisks = false;
          _isSavingRisks = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Known risks saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingRisks = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  /// Build the medications section with loading/error handling
  Widget _buildMedicationsSection() {
    if (_isLoadingMedications) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (_medicationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _medicationError!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchMedications,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Get caregiverId from user provider
    final caregiverId = Provider.of<UserProvider>(
      context,
      listen: false,
    ).user?.caregiverId;

    return CurrentMedicationsSection(
      entries: medications,
      onMedicationUpdated: _fetchMedications,
      // Refresh medications after delete/approve
      caregiverId: caregiverId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitlePrefix = _patientError == null
        ? 'Patient Details • $_mrn'
        : 'Patient Details';

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: _DetailsAppBar(title: _patientName, subtitle: subtitlePrefix),
        body: _isLoadingPatient
            ? Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : _patientError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _patientError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loadPatientData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  _buildRiskBanner(),
                  PatientHeaderCard(
                    fullName: _patientName,
                    mrn: _mrn,
                    age: _age,
                    sex: _sex,
                    currentMoodLabel: _currentMoodLabel,
                    currentMoodEmoji: _currentMoodEmoji,
                    diagnoses: _diagnoses,
                    allergies: _allergies,
                    /*heartRateBpm: 72,
              bpSystolic: 120,
              bpDiastolic: 80,
              oxygenPercent: 98,
              temperatureF: 98.0,*/
                    emergencyPhones: _emergencyPhones,
                    onStartVideoCall: () => _startVideoCall(_patientName),
                  ),

                  // Tab bar row (like your mock)
                  const _TabsStrip(),

                  // Tab views
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Info
                        ListView(
                          padding: const EdgeInsets.only(top: 12, bottom: 16),
                          children: [
                            ContactInfoCard(
                              phone: _phone,
                              email: _email,
                              dateOfBirth: _dob,
                              addressLine1: _addressLine1,
                              addressLine2: _addressLine2,
                              city: _city,
                              state: _state,
                              postalCode: _postalCode,
                            ),
                            EmergencyContactCard(
                              contactName: _emergencyContactName,
                              relationship: _emergencyRelationship,
                              phone: _emergencyPhone,
                            ),
                            _buildPersonalizationCard(),
                            if (_canDeleteCallHistoryInThisBuild)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: _isDeletingCallHistory
                                        ? null
                                        : _deleteCallHistoryForPatientDevOnly,
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(
                                      _isDeletingCallHistory
                                          ? 'Deleting call history...'
                                          : 'Delete Call History (Dev)',
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.isCaregiver && _caregiverLinkId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    title: const Text('Allow Patient-Initiated Video Calls'),
                                    subtitle: Text(
                                      _patientInitiatedCallsEnabled
                                          ? 'This patient can initiate video calls to their care team.'
                                          : 'Patient-initiated video calls are currently blocked.',
                                    ),
                                    value: _patientInitiatedCallsEnabled,
                                    onChanged: _isSavingPatientCallPolicy
                                        ? null
                                        : _togglePatientInitiatedCalls,
                                  ),
                                ),
                              ),
                            if (widget.isCaregiver && _caregiverLinkId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    title: const Text('Allow Patient Messaging'),
                                    subtitle: Text(
                                      _patientMessagingEnabled
                                          ? 'This patient can send messages to their care team.'
                                          : 'Patient messaging is currently blocked.',
                                    ),
                                    value: _patientMessagingEnabled,
                                    onChanged: _isSavingPatientMessagingPolicy
                                        ? null
                                        : _togglePatientMessaging,
                                  ),
                                ),
                              ),
                            CommunicationHistoryCard(
                              events: _callHistoryEvents,
                              onCallTap: _openCallHistoryDetail,
                            ),
                          ],
                        ),

                        // Mood
                        ListView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          children: [MoodHistorySection(entries: _moodEntries)],
                        ),

                        // Health
                        ListView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          children: [
                            _buildKnownRisksCard(),
                            const SizedBox(height: 8),
                            PainLevelCard(
                              lastReportedText: _lastReportedPain,
                              currentPain: _currentPain,
                              location: _painLocation,
                              dizziness: _dizziness,
                              fatigue: _fatigue,
                            ),
                            // Recent Symptoms (UI-typed list)
                            sympt.RecentSymptomsSection(
                              entries: _symptomEntries,
                            ),
                            const SizedBox(height: 8),
                            _buildMedicationsSection(),
                          ],
                        ),

                        // In-home
                        ListView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          children: [
                            if (int.tryParse(widget.patientId) != null)
                              _buildAdlIadlManagementCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null)
                              _buildBehaviorLogCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null)
                              _buildIncidentReportsCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null)
                              _buildDashboardsCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null)
                              _buildBehaviorHistoryCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null)
                              _buildIncidentHistoryCard(_patientName),
                            const SizedBox(height: 8),
                            if (int.tryParse(widget.patientId) != null &&
                                widget.isCaregiver)
                              _buildAuditLogCard(_patientName),
                          ],
                        ),

                        // ---- Virtual Check-In tab ----
                        // ---- Virtual Check-In tab ----
                        ListView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          children: [
                            VirtualCheckInHistoryCard(
                              entries: _virtualCheckIns,
                              showConfigure:
                                  widget.isCaregiver, // caregivers only
                              onConfigure: widget.isCaregiver
                                  ? () async {
                                      // Seed with your current config if you have it:
                                      final initialQuestions =
                                          <VirtualCheckInQuestion>[];
                                      final checkInId = _latestVirtualCheckInId();

                                      final updated =
                                          await showModalBottomSheet<
                                            List<VirtualCheckInQuestion>?
                                          >(
                                            context: context,
                                            isScrollControlled: true,
                                            useSafeArea: true,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(16),
                                                  ),
                                            ),
                                            builder: (_) =>
                                                VirtualCheckInConfigSheet(
                                                  checkInId: checkInId,
                                                  initial: initialQuestions,
                                                ),
                                          );

                                      if (!context.mounted) return;
                                      if (updated != null) {
                                        await _saveVirtualCheckInConfiguration(
                                          updated,
                                        );
                                      }
                                    }
                                  : null, // patients: no button
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

/// shows back arrow + name + MRN line
class _DetailsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailsAppBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      elevation: 0,
      backgroundColor: cs.surface,
      iconTheme: IconThemeData(color: cs.onSurface),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The tab buttons row (Info • Mood • Health • Virtual Check-In)
class _TabsStrip extends StatelessWidget {
  const _TabsStrip(); // <-- add const + super.key

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 430;
    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: TabBar(
          isScrollable: narrow,
          labelPadding: narrow
              ? const EdgeInsets.symmetric(horizontal: 10)
              : const EdgeInsets.symmetric(horizontal: 16),
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withValues(alpha: .7),
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: cs.primary, width: 3),
          ),
          tabs: const [
            Tab(text: 'Info', icon: Icon(Icons.info_outline, size: 18)),
            Tab(text: 'Mood', icon: Icon(Icons.favorite_border, size: 18)),
            Tab(
              text: 'Health',
              icon: Icon(Icons.health_and_safety_outlined, size: 18),
            ),
            Tab(text: 'In-home', icon: Icon(Icons.home_outlined, size: 18)),
            Tab(
              text: 'Virtual Check-In',
              icon: Icon(Icons.video_call_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
