import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/analytics/models/dashboard_analytics_model.dart';
import 'package:care_connect_app/widgets/enhanced_patient_notes_widget.dart';
import 'package:care_connect_app/widgets/patient_tasks_widget.dart';

class PatientStatusPage extends StatefulWidget {
  final int? patientId;
  const PatientStatusPage({super.key, this.patientId});

  @override
  State<PatientStatusPage> createState() => _PatientStatusPageState();
}

class _PatientStatusPageState extends State<PatientStatusPage> {
  Patient? patient;
  DashboardAnalytics? vitals;
  bool loading = true;
  String? error;

  /// Flagged risk names for the persistent alert banner (from GET patient or GET risks).
  List<String> _flaggedRiskNames = [];

  // In-Home personalization fields
  final _likesController = TextEditingController();
  final _dislikesController = TextEditingController();
  final _habitsController = TextEditingController();
  final _phobiasController = TextEditingController();
  String? _preferredCommunicationMethod; // verbal | visual | written | gesture
  bool _isSavingPersonalization = false;
  bool _isEditingPersonalization = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchData();
  }

  @override
  void dispose() {
    _likesController.dispose();
    _dislikesController.dispose();
    _habitsController.dispose();
    _phobiasController.dispose();
    super.dispose();
  }

  Future<void> fetchData() async {
    setState(() {
      loading = true;
      error = null;
    });
    final t = AppLocalizations.of(context)!;

    try {
      // Use the patientId passed to the widget if available,
      // otherwise get it from the current user
      int? patientId;
      final user = Provider.of<UserProvider>(context, listen: false).user;

      if (user == null) {
        setState(() {
          error = t.ptdashboard_userNotLoggedIn;
          loading = false;
        });
        return;
      }

      if (widget.patientId != null) {
        patientId = widget.patientId;
        print('🔍 Using patientId from route parameter: $patientId');
      } else {
        patientId = user.patientId;
        print('🔍 Using patientId from user object: $patientId');
      }

      if (patientId == null) {
        setState(() {
          error = t.ptstatusscreen_noPtID;
          loading = false;
        });
        return;
      }

      // Determine the appropriate API URL based on user role
      final authHeaders = await ApiService.getAuthHeaders();
      final String apiUrl;

      // If the user is a caregiver, use the caregivers endpoint
      if (user.role.toUpperCase() == 'CAREGIVER' ||
          user.role.toUpperCase() == 'FAMILY_LINK') {
        final caregiverId = user.caregiverId;
        apiUrl =
            '${ApiConstants.baseUrl}caregivers/$caregiverId/patients/$patientId';
        print('🔍 Using caregiver-specific endpoint: $apiUrl');
      } else {
        // If the user is a patient, use the users endpoint
        apiUrl = '${ApiConstants.users}/$patientId';
        print('🔍 Using standard users endpoint: $apiUrl');
      }

      // Fetch patient profile
      final profileRes = await http.get(
        Uri.parse(apiUrl),
        headers: authHeaders,
      );
      if (profileRes.statusCode != 200) {
        setState(() {
          error =
              '${t.ptstatusscreen_failedToLoadProfile}: ${profileRes.statusCode}';
          loading = false;
        });
        print('🔍 API Error: ${profileRes.statusCode} - ${profileRes.body}');
        return;
      }

      // Decode the response
      final responseData = json.decode(profileRes.body);
      print('🔍 API Response: $responseData');

      // Extract patient data - handle different response structures
      final Map<String, dynamic> patientData;

      if (user.role.toUpperCase() == 'CAREGIVER' ||
          user.role.toUpperCase() == 'FAMILY_LINK') {
        // For caregiver endpoint, the patient data may be nested
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('patient')) {
          patientData = responseData['patient'] as Map<String, dynamic>;
        } else {
          // If not nested, use the response as is
          patientData = responseData as Map<String, dynamic>;
        }
      } else {
        // For patient/user endpoint, use response directly
        patientData = responseData as Map<String, dynamic>;
      }

      patient = Patient.fromJson(patientData);

      // Extract flagged risks for the persistent banner
      if (user.role.toUpperCase() == 'CAREGIVER' ||
          user.role.toUpperCase() == 'FAMILY_LINK') {
        final raw = responseData['flaggedRisks'] ?? responseData['flagged_risks'];
        if (raw is List) {
          _flaggedRiskNames = raw
              .map((e) => e is Map ? (e['riskTypeName'] as String?) : null)
              .whereType<String>()
              .toList();
        } else {
          // Fallback: fetch risks from API if response shape differs or backend omits field
          try {
            final risksRes = await ApiService.getPatientRisks(patientId);
            if (risksRes.statusCode == 200) {
              final list = json.decode(risksRes.body) as List?;
              _flaggedRiskNames = list
                  ?.map((e) =>
                      e is Map ? (e['riskTypeName'] as String?) : null)
                  .whereType<String>()
                  .toList() ??
                  [];
            } else {
              _flaggedRiskNames = [];
            }
          } catch (_) {
            _flaggedRiskNames = [];
          }
        }
      } else {
        // Patient view: fetch risks from API
        try {
          final risksRes = await ApiService.getPatientRisks(patientId);
          if (risksRes.statusCode == 200) {
            final list = json.decode(risksRes.body) as List?;
            _flaggedRiskNames = list
                ?.map((e) =>
                    e is Map ? (e['riskTypeName'] as String?) : null)
                .whereType<String>()
                .toList() ??
                [];
          } else {
            _flaggedRiskNames = [];
          }
        } catch (_) {
          _flaggedRiskNames = [];
        }
      }

      // Fetch vitals summary - always use analytics endpoint
      final vitalsUrl =
          '${ApiConstants.analytics}/dashboard?patientId=$patientId&days=7';
      print('🔍 Fetching vitals from: $vitalsUrl');

      final vitalsRes = await http.get(
        Uri.parse(vitalsUrl),
        headers: authHeaders,
      );

      if (vitalsRes.statusCode != 200) {
        setState(() {
          error =
              '${t.ptstatusscreen_failedToLoadVitals}: ${vitalsRes.statusCode}';
          loading = false;
        });
        print(
          '🔍 Vitals API Error: ${vitalsRes.statusCode} - ${vitalsRes.body}',
        );
        return;
      }

      final vitalsData = json.decode(vitalsRes.body);
      vitals = DashboardAnalytics.fromJson(vitalsData);

      _populatePersonalizationControllers();

      setState(() {
        loading = false;
      });
    } catch (e) {
      print('🔍 Error fetching patient data: $e');
      setState(() {
        error = '${t.voicecommand_phaseLabelError}: $e';
        loading = false;
      });
    }
  }

  void _populatePersonalizationControllers() {
    final p = patient;
    if (p == null) return;

    String? read(String? v) => (v == null || v.isEmpty) ? null : v;

    _likesController.text = read(p.likes) ?? '';
    _dislikesController.text = read(p.dislikes) ?? '';
    _habitsController.text = read(p.habits) ?? '';
    _phobiasController.text = read(p.phobias) ?? '';

    final normalized =
        (p.preferredCommunicationMethod ?? '').trim().toLowerCase();
    const allowed = {'verbal', 'visual', 'written', 'gesture'};
    _preferredCommunicationMethod =
        allowed.contains(normalized) ? normalized : null;
  }

  Future<void> _saveInHomePersonalization() async {
    final p = patient;
    final t = AppLocalizations.of(context)!;
    if (p == null) return;

    setState(() => _isSavingPersonalization = true);
    try {
      final payload = <String, dynamic>{
        'likes': _likesController.text.trim(),
        'dislikes': _dislikesController.text.trim(),
        'habits': _habitsController.text.trim(),
        'phobias': _phobiasController.text.trim(),
        'preferredCommunicationMethod': _preferredCommunicationMethod,
      };

      final resp = await ApiService.updatePatientProfile(p.id, payload);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final data = (body['data'] ?? body) as Map<String, dynamic>;

        setState(() {
          patient = p.copyWith(
            likes: data['likes'] as String?,
            dislikes: data['dislikes'] as String?,
            habits: data['habits'] as String?,
            phobias: data['phobias'] as String?,
            preferredCommunicationMethod:
                data['preferredCommunicationMethod'] as String?,
          );
        });
        _populatePersonalizationControllers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.ptstatusscreen_personaliztionSaved)),
          );
          setState(() {
            _isEditingPersonalization = false;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${t.ptstatusscreen_saveFailed}: ${resp.statusCode}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.ptstatusscreen_saveFailed}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingPersonalization = false);
      }
    }
  }

  Widget _buildInHomePersonalizationSection() {
    final t = AppLocalizations.of(context)!;
    final p = patient;
    if (p == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final canEdit = true; // caregivers typically see this screen

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
      if (_isEditingPersonalization) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 8),
              child: Icon(icon,
                  size: 20, color: theme.colorScheme.primary.withOpacity(0.8)),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: canEdit,
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
                  size: 20, color: theme.colorScheme.primary.withOpacity(0.8)),
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
                    value.isEmpty ? t.ptstatusscreen_notSaved : value,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        );
      }
    }

    return _buildInfoSection(
      t.ptstatusscreen_personalization,
      Icons.favorite_outline,
      [],
      customContent: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.ptstatusscreen_personalization,
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
                                  _saveInHomePersonalization();
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
                          _isEditingPersonalization ? t.save : t.ptstatusscreen_edit,
                        ),
                      ),
            ],
          ),
          const SizedBox(height: 12),
                row(
                  icon: Icons.thumb_up_alt_outlined,
                  label: t.ptstatusscreen_likes,
                  controller: _likesController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.thumb_down_alt_outlined,
                  label: t.ptstatusscreen_dislikes,
                  controller: _dislikesController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.repeat_rounded,
                  label: t.ptstatusscreen_habits,
                  controller: _habitsController,
                ),
                const SizedBox(height: 12),
                row(
                  icon: Icons.warning_amber_outlined,
                  label: t.ptstatusscreen_phobia,
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
                        color: theme.colorScheme.primary.withOpacity(0.8),
                      ),
                    ),
                    Expanded(
                      child: _isEditingPersonalization
                          ? DropdownButtonFormField<String>(
                              initialValue: _preferredCommunicationMethod,
                              items: [
                                DropdownMenuItem(
                                  value: 'verbal',
                                  child: Text(t.ptstatusscreen_verbal),
                                ),
                                DropdownMenuItem(
                                  value: 'visual',
                                  child: Text(t.ptstatusscreen_visual),
                                ),
                                DropdownMenuItem(
                                  value: 'written',
                                  child: Text(t.ptstatusscreen_written),
                                ),
                                DropdownMenuItem(
                                  value: 'gesture',
                                  child: Text(t.ptstatusscreen_gesture),
                                ),
                              ],
                              onChanged: (v) => setState(
                                        () =>
                                            _preferredCommunicationMethod = v,
                                      ),
                              decoration:
                                  deco(t.ptstatusscreen_preferComMethod),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.ptstatusscreen_preferComMethod,
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
                                      ? t.ptstatusscreen_notSaved
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
    );
  }

  Widget _buildInfoSection(
    String title,
    IconData icon,
    List<Widget> children, {
    Widget? customContent,
  }) {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (customContent != null) ...[
              const SizedBox(height: 16),
              customContent,
            ] else if (children.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...children,
            ] else ...[
              const SizedBox(height: 16),
              Text(
                t.ptstatusscreen_noInfoAvail,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label:',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.visible,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    '$label:',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(value, style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
    );
  }

  Widget _buildMedicalInfoSection() {
    final hasAllergies = patient!.allergies?.isNotEmpty == true;
    final hasVitalConditions = patient!.vitalConditions?.isNotEmpty == true;
    final t = AppLocalizations.of(context)!;

    // Safely extract medications from various possible sources
    String? medications;

    // Try to get medications from vitalConditions
    if (hasVitalConditions &&
        patient!.vitalConditions!.containsKey('medications')) {
      final medicationsValue = patient!.vitalConditions!['medications'];
      if (medicationsValue != null && medicationsValue.toString().isNotEmpty) {
        medications = medicationsValue.toString();
      }
    }

    // Try to get medications from patient direct property if available
    // This would be if the patient model has a medications field directly

    final hasMedications = medications?.isNotEmpty == true;

    // Check if we have any medical information to display
    if (!hasAllergies && !hasVitalConditions && !hasMedications) {
      return _buildInfoSection(
        t.ptstatusscreen_medInfo,
        Icons.medical_information,
        [],
      );
    }

    final children = <Widget>[];

    // Add allergies (always show)
    final allergiesText = hasAllergies
        ? (patient!.allergies is List
              ? (patient!.allergies as List).join(', ')
              : patient!.allergies.toString())
        : t.ptstatusscreen_noAllergies;
    children.add(_buildInfoRow(t.ptstatusscreen_allergies, allergiesText));

    // Add medications if available
    if (hasMedications) {
      children.add(_buildInfoRow(t.ptstatusscreen_currentMed, medications!));
    }

    // Add vital signs if available
    if (hasVitalConditions) {
      final vitals = patient!.vitalConditions!;

      // Safely check and add each vital sign
      if (vitals.containsKey('heartRate') && vitals['heartRate'] != null) {
        final heartRate = vitals['heartRate'].toString();
        if (heartRate.isNotEmpty && heartRate != 'null') {
          children.add(_buildInfoRow(t.ptstatusscreen_heartRate, '$heartRate ${t.ptstatusscreen_bpm}'));
        }
      }

      if (vitals.containsKey('bloodPressure') &&
          vitals['bloodPressure'] != null) {
        final bloodPressure = vitals['bloodPressure'].toString();
        if (bloodPressure.isNotEmpty && bloodPressure != 'null') {
          children.add(_buildInfoRow(t.ptstatusscreen_bloodPressure, '$bloodPressure mmHg'));
        }
      }

      if (vitals.containsKey('temperature') && vitals['temperature'] != null) {
        final temperature = vitals['temperature'].toString();
        if (temperature.isNotEmpty && temperature != 'null') {
          children.add(_buildInfoRow(t.ptstatusscreen_temp, '$temperature°F'));
        }
      }

      if (vitals.containsKey('oxygenSaturation') &&
          vitals['oxygenSaturation'] != null) {
        final oxygenSat = vitals['oxygenSaturation'].toString();
        if (oxygenSat.isNotEmpty && oxygenSat != 'null') {
          children.add(_buildInfoRow(t.ptstatusscreen_oxSat, '$oxygenSat%'));
        }
      }

      // Add any other vital conditions that might be present
      vitals.forEach((key, value) {
        if (value != null &&
            value.toString().isNotEmpty &&
            value.toString() != 'null' &&
            ![
              'heartRate',
              'bloodPressure',
              'temperature',
              'oxygenSaturation',
              'medications',
            ].contains(key)) {
          // Format the key to be more readable
          final formattedKey = key
              .replaceAllMapped(
                RegExp(r'([A-Z])'),
                (match) => ' ${match.group(1)}',
              )
              .toLowerCase()
              .split(' ')
              .map(
                (word) => word.isNotEmpty
                    ? '${word[0].toUpperCase()}${word.substring(1)}'
                    : '',
              )
              .join(' ');

          children.add(_buildInfoRow(formattedKey, value.toString()));
        }
      });
    }

    return _buildInfoSection(
      t.ptstatusscreen_medInfo,
      Icons.medical_information,
      children,
    );
  }

  /// Persistent risk alert banner shown at top of dashboard when client has flagged risks.
  Widget _buildRiskBanner() {
    final t = AppLocalizations.of(context)!;
    if (_flaggedRiskNames.isEmpty) return const SizedBox.shrink();
    final names = _flaggedRiskNames.join(', ');
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
                '${t.ptstatusscreen_knownRisk}: $names',
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final user = Provider.of<UserProvider>(context).user;
    final isCaregiver = user != null &&
        (user.role.toUpperCase() == 'CAREGIVER' ||
         user.role.toUpperCase() == 'FAMILY_LINK');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarHelper.createAppBar(context, title: t.ptstatusscreen_ptStatus),
      drawer: const CommonDrawer(currentRoute: '/patient'),
      body: _buildDashboardBody(context, isMobile, isCaregiver),
    );
  }

  Widget _buildDashboardBody(
      BuildContext context, bool isMobile, bool isCaregiver) {
    final t = AppLocalizations.of(context)!;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (patient == null) {
      return Center(child: Text(t.ptstatusscreen_noPtData));
    }
    final scrollContent = SingleChildScrollView(
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient header - responsive layout
              isMobile
                  ? Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: NetworkImage(
                            (patient!.profileImageUrl ??
                                'https://randomuser.me/api/portraits/men/32.jpg'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${patient!.firstName} ${patient!.lastName}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (patient!.dob.isNotEmpty)
                              Text(
                                '${t.ptstatusscreen_age}: ${_calculateAge(patient!.dob)}',
                                textAlign: TextAlign.center,
                              ),
                            if (patient!.phone.isNotEmpty)
                              Text(
                                '${t.ptstatusscreen_phone}: ${patient!.phone}',
                                textAlign: TextAlign.center,
                              ),
                            if (patient!.email.isNotEmpty)
                              Text(
                                '${t.resetpassword_emailTitle}: ${patient!.email}',
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: NetworkImage(
                            (patient!.profileImageUrl ??
                                'https://randomuser.me/api/portraits/men/32.jpg'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${patient!.firstName} ${patient!.lastName}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (patient!.dob.isNotEmpty)
                                Text('${t.ptstatusscreen_age}: ${_calculateAge(patient!.dob)}'),
                              if (patient!.phone.isNotEmpty)
                                Text('${t.ptstatusscreen_phone}: ${patient!.phone}'),
                              if (patient!.email.isNotEmpty)
                                Text('${t.resetpassword_emailTitle}: ${patient!.email}'),
                            ],
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),
              // Content sections with responsive layout
              isMobile
                  ? Column(
                      children: [
                        // Patient Information Section
                        _buildInfoSection(t.ptstatusscreen_ptInfo, Icons.person, [
                          if (patient!.relationship.isNotEmpty)
                            _buildInfoRow(t.ptstatusscreen_relationship, patient!.relationship),
                          if (patient!.gender != null &&
                              patient!.gender!.isNotEmpty)
                            _buildInfoRow(t.signup_accountGender, patient!.gender!),
                          if (patient!.dob.isNotEmpty)
                            _buildInfoRow('Date of Birth', patient!.dob),
                        ]),
                        const SizedBox(height: 16),
                        // Address Section
                        if (patient!.address != null) ...[
                          _buildInfoSection(t.signup_accountAddress, Icons.location_on, [
                            if (patient!.address!.line1?.isNotEmpty == true)
                              _buildInfoRow(
                                t.signup_accountAddress,
                                '${patient!.address!.line1}${patient!.address!.line2?.isNotEmpty == true ? '\n${patient!.address!.line2}' : ''}',
                              ),
                            if (patient!.address!.city?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountCity, patient!.address!.city!),
                            if (patient!.address!.state?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountState, patient!.address!.state!),
                            if (patient!.address!.zip?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountZIP, patient!.address!.zip!),
                          ]),
                          const SizedBox(height: 16),
                        ],
                        // Personalization Section (In-Home)
                        _buildInHomePersonalizationSection(),
                        const SizedBox(height: 16),
                        // Medical Information Section
                        _buildMedicalInfoSection(),
                        const SizedBox(height: 16),
                        // Vitals Summary Section
                        _buildInfoSection(
                          t.ptstatusscreen_vitalSummary,
                          Icons.favorite,
                          [],
                          customContent: buildVitalsSummary(vitals),
                        ),
                        const SizedBox(height: 16),
                        // Medical Notes Section - Full width on mobile
                        EnhancedPatientNotesWidget(
                          patientId: patient!.id,
                          showCompactView: false,
                          initialItemCount: 3,
                        ),
                        const SizedBox(height: 16),
                        PatientTasksWidget(
                          patientId: patient!.id,
                          patientName: '${patient!.firstName} ${patient!.lastName}',
                          isCaregiver: isCaregiver,
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        // Patient Information Section
                        _buildInfoSection(t.ptstatusscreen_ptInfo, Icons.person, [
                          if (patient!.relationship.isNotEmpty)
                            _buildInfoRow(t.ptstatusscreen_relationship, patient!.relationship),
                          if (patient!.gender != null &&
                              patient!.gender!.isNotEmpty)
                            _buildInfoRow(t.signup_accountGender, patient!.gender!),
                          if (patient!.dob.isNotEmpty)
                            _buildInfoRow(t.signup_accountDOB, patient!.dob),
                        ]),
                        const SizedBox(height: 24),
                        // Address Section
                        if (patient!.address != null) ...[
                          _buildInfoSection(t.signup_accountAddress, Icons.location_on, [
                            if (patient!.address!.line1?.isNotEmpty == true)
                              _buildInfoRow(
                                t.signup_accountAddress,
                                '${patient!.address!.line1}${patient!.address!.line2?.isNotEmpty == true ? '\n${patient!.address!.line2}' : ''}',
                              ),
                            if (patient!.address!.city?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountCity, patient!.address!.city!),
                            if (patient!.address!.state?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountState, patient!.address!.state!),
                            if (patient!.address!.zip?.isNotEmpty == true)
                              _buildInfoRow(t.signup_accountZIP, patient!.address!.zip!),
                          ]),
                          const SizedBox(height: 24),
                        ],
                        // Personalization Section (In-Home)
                        _buildInHomePersonalizationSection(),
                        const SizedBox(height: 24),
                        // Medical Information Section
                        _buildMedicalInfoSection(),
                        const SizedBox(height: 24),
                        // Vitals Summary Section
                        _buildInfoSection(
                          t.ptstatusscreen_vitalSummary,
                          Icons.favorite,
                          [],
                          customContent: buildVitalsSummary(vitals),
                        ),
                        const SizedBox(height: 24),
                        // Medical Notes Section
                        EnhancedPatientNotesWidget(
                          patientId: patient!.id,
                          showCompactView: false,
                          initialItemCount: 3,
                        ),
                        const SizedBox(height: 24),
                        PatientTasksWidget(
                          patientId: patient!.id,
                          patientName: '${patient!.firstName} ${patient!.lastName}',
                          isCaregiver: isCaregiver,
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );

    if (_flaggedRiskNames.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRiskBanner(),
          Expanded(child: scrollContent),
        ],
      );
    }
    return scrollContent;
  }

  Widget buildVitalsSummary(DashboardAnalytics? vitals) {
    final t = AppLocalizations.of(context)!;
    if (vitals == null) {
      return Text(
        t.ptstatusscreen_noVitalsData,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vitals.avgHeartRate != null)
          _buildVitalRow(
            t.ptstatusscreen_heartRate,
            '${vitals.avgHeartRate!.toStringAsFixed(1)} ${t.ptstatusscreen_bpm}',
          ),
        if (vitals.avgSpo2 != null)
          _buildVitalRow('SpO₂', '${vitals.avgSpo2!.toStringAsFixed(1)}%'),
        if (vitals.avgSystolic != null)
          _buildVitalRow(
            'Systolic BP',
            '${vitals.avgSystolic!.toStringAsFixed(1)} mmHg',
          ),
        if (vitals.avgDiastolic != null)
          _buildVitalRow(
            'Diastolic BP',
            '${vitals.avgDiastolic!.toStringAsFixed(1)} mmHg',
          ),
        if (vitals.avgWeight != null)
          _buildVitalRow(
            'Weight',
            '${vitals.avgWeight!.toStringAsFixed(1)} lbs',
          ),
        if (vitals.adherenceRate != null)
          _buildVitalRow(
            'Adherence Rate',
            '${vitals.adherenceRate!.toStringAsFixed(1)}%',
          ),
      ],
    );
  }

  Widget _buildVitalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  int _calculateAge(String? dob) {
    if (dob == null) return 0;
    try {
      final parts = dob.split('/');
      if (parts.length == 3) {
        final birthDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        final today = DateTime.now();
        int age = today.year - birthDate.year;
        if (today.month < birthDate.month ||
            (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
        return age;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
