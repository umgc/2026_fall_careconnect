import 'dart:convert';

import 'package:care_connect_app/features/auth/presentation/pages/sign_up_screen.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/models/patient-info.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/patient-info-card.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/widgets/default_app_header.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Main screen for caregivers to view and manage their patient list.
///
/// This widget provides a comprehensive interface for caregivers to:
/// - View statistics of urgent and normal cases
/// - Search through their patient list
/// - View patient cards with essential health information
/// - Navigate to individual patient details
///
/// The screen includes pull-to-refresh functionality and real-time search filtering.
class CaregiverPatientList extends StatefulWidget {
  /// Creates a CaregiverPatientList widget.
  const CaregiverPatientList({super.key});

  @override
  State<CaregiverPatientList> createState() => _CaregiverPatientList();
}

/// Private state class for CaregiverPatientList.
///
/// Manages patient data loading, filtering, and search functionality.
class _CaregiverPatientList extends State<CaregiverPatientList> {
  /// Complete list of all patients assigned to this caregiver
  List<Patient> _allPatients = [];

  /// Filtered list of patients based on search query
  List<Patient> _filteredPatients = [];

  /// Controller for the search text field
  final TextEditingController _searchController = TextEditingController();

  /// Loading state indicator for async operations
  bool _isLoading = false;

  static const String _unknownMoodLabel = 'Unknown';
  static const String _unknownMoodEmoji = '😐';

  /// Initializes the widget state.
  ///
  /// Sets up the search controller listener and loads initial patient data.
  @override
  void initState() {
    super.initState();
    _loadPatients();
    _searchController.addListener(_onSearchChanged);
  }

  /// Cleans up resources when the widget is disposed.
  ///
  /// Removes the search controller listener and disposes of the controller.
  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Loads patient data from the server.
  ///
  /// Fetches the caregiver's assigned patients from the API.
  ///
  /// Returns:
  /// * Future<void> - Completes when patient data is loaded
  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      if (userProvider.user?.caregiverId == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _allPatients = [];
          _filteredPatients = [];
        });
        return;
      }

      final response = await ApiService.getCaregiverPatients(
        userProvider.user!.caregiverId!,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        print(response.body);
        final List<dynamic> data = jsonDecode(response.body);
        final rows = data.whereType<Map<String, dynamic>>().toList();
        final moodByUserId = await _loadLatestMoodByPatientUserId(rows);
        final unreadByUserId =
            await _loadInboxUnreadByUserId(userProvider.user!.id);

        if (!mounted) return;

        final patients = rows
            .map((json) => _patientFromJson(json, moodByUserId,
                unreadByUserId: unreadByUserId))
            .toList();

        setState(() {
          _allPatients = patients;
          _filteredPatients = patients;
          _isLoading = false;
        });
      } else {
        setState(() {
          _allPatients = [];
          _filteredPatients = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading patients: $e');
      if (!mounted) return;
      setState(() {
        _allPatients = [];
        _filteredPatients = [];
        _isLoading = false;
      });
    }
  }

  /// Converts API JSON response to Patient model
  Patient _patientFromJson(
    Map<String, dynamic> json,
    Map<int, _MoodSnapshot> moodByUserId, {
    Map<int, bool> unreadByUserId = const {},
  }) {
    final patient = json['patient'] ?? {};
    final link = json['link'] ?? {};
    final patientUserId = _safeInt(link['patientUserId']);
    final moodSnapshot =
        patientUserId == null ? null : moodByUserId[patientUserId];

    return Patient(
      id: patient['id']?.toString() ?? '',
      patientUserId: patientUserId,
      linkId: _safeInt(link['id'] ?? link['linkId']),
      firstName: patient['firstName'] ?? '',
      lastName: patient['lastName'] ?? '',
      lastUpdated: DateTime.now(), // TODO: Use actual lastUpdated from API
      statusMessage: link['notes'] ?? 'No status available',
      nextCheckIn: DateTime.now().add(
        const Duration(days: 1),
      ), // TODO: Use actual check-in date
      mood: moodSnapshot?.label ?? _unknownMoodLabel,
      moodEmoji: moodSnapshot?.emoji ?? _unknownMoodEmoji,
      isUrgent: false, // TODO: Determine urgency based on patient status
      messageCount:
          (patientUserId != null && (unreadByUserId[patientUserId] ?? false))
              ? 1
              : 0,
    );
  }

  Future<Map<int, _MoodSnapshot>> _loadLatestMoodByPatientUserId(
    List<Map<String, dynamic>> rows,
  ) async {
    final userIds = rows
        .map(
          (row) => _safeInt(
            (row['link'] as Map<String, dynamic>?)?['patientUserId'],
          ),
        )
        .whereType<int>()
        .toSet()
        .toList();

    if (userIds.isEmpty) {
      return const {};
    }

    final results = await Future.wait(
      userIds.map((userId) async {
        try {
          final moods = await ApiService.getMoodHistory(userId);
          final latest = moods.isNotEmpty && moods.first is Map<String, dynamic>
              ? moods.first as Map<String, dynamic>
              : const <String, dynamic>{};

          final score = _safeInt(latest['score']) ?? 0;
          final label = _firstNonEmpty([
            latest['label'],
            _moodLabelFromScore(score),
          ]);

          return MapEntry(
            userId,
            _MoodSnapshot(label: label, emoji: _moodEmojiFromLabel(label)),
          );
        } catch (_) {
          return null;
        }
      }),
    );

    final map = <int, _MoodSnapshot>{};
    for (final entry in results) {
      if (entry != null) {
        map[entry.key] = entry.value;
      }
    }
    return map;
  }

  int? _safeInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  String _moodLabelFromScore(int score) {
    if (score >= 8) return 'Excellent';
    if (score >= 6) return 'Good';
    if (score >= 4) return 'Fair';
    if (score >= 1) return 'Poor';
    return _unknownMoodLabel;
  }

  String _moodEmojiFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('excellent') || l.contains('great')) return '😄';
    if (l.contains('good') || l.contains('happy')) return '🙂';
    if (l.contains('fair') || l.contains('neutral')) return '😐';
    if (l.contains('poor') || l.contains('sad')) return '😟';
    return _unknownMoodEmoji;
  }

  /// Fetches the inbox for [userId] and returns a map of peerId → hasUnread.
  Future<Map<int, bool>> _loadInboxUnreadByUserId(int userId) async {
    try {
      final data = await ApiService.getInbox(userId);
      final result = <int, bool>{};
      for (final entry in data) {
        if (entry is Map<String, dynamic>) {
          final peerId = (entry['peerId'] as num?)?.toInt();
          final hasUnread = entry['hasUnread'] as bool? ?? false;
          if (peerId != null) {
            result[peerId] = hasUnread;
          }
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Handles search text changes and filters the patient list.
  ///
  /// Filters patients based on the search query using multiple matching strategies:
  /// - Exact substring matching in full name
  /// - Prefix matching on first and last names
  /// - Fuzzy matching for typo tolerance
  ///
  /// Updates the filtered patient list and triggers a rebuild.
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredPatients = _allPatients;
      });
    } else {
      final results = _allPatients.where((patient) {
        final fullName = patient.fullName.toLowerCase();
        final firstName = patient.firstName.toLowerCase();
        final lastName = patient.lastName.toLowerCase();

        // Check if query matches any part of the name
        return fullName.contains(query) ||
            firstName.startsWith(query) ||
            lastName.startsWith(query) ||
            _fuzzyMatch(query, fullName);
      }).toList();

      setState(() {
        _filteredPatients = results;
      });
    }
  }

  /// Performs fuzzy matching to handle search typos.
  ///
  /// Compares characters position by position and allows for a limited
  /// number of differences based on the query length. Shorter queries
  /// allow fewer differences to maintain search relevance.
  ///
  /// Parameters:
  /// * [query] - The search query string (lowercase)
  /// * [target] - The target string to match against (lowercase)
  ///
  /// Returns:
  /// * bool - True if the strings match within the allowed difference threshold
  bool _fuzzyMatch(String query, String target) {
    if (query.length <= 2) return false;

    // Allow for 1-2 character differences depending on length
    int allowedDifferences = query.length <= 4 ? 1 : 2;
    int differences = 0;

    for (int i = 0; i < query.length && i < target.length; i++) {
      if (query[i] != target[i]) {
        differences++;
        if (differences > allowedDifferences) {
          return false;
        }
      }
    }

    return differences <= allowedDifferences;
  }

  /// Returns the count of patients requiring urgent attention.
  ///
  /// Counts patients where the isUrgent flag is true.
  ///
  /// Returns:
  /// * int - Number of urgent cases
  int get urgentCasesCount => _allPatients.where((p) => p.isUrgent).length;

  /// Returns the count of patients with normal status.
  ///
  /// Counts patients where the isUrgent flag is false.
  ///
  /// Returns:
  /// * int - Number of normal status cases
  int get normalCasesCount => _allPatients.where((p) => !p.isUrgent).length;

  /// Handles the add patient button press.
  ///
  /// Opens a dialog or navigates to a screen where caregivers can add existing
  /// patients to their care list. This is for linking already registered patients.
  Future<void> _onAddPatient() async {
    final emailController = TextEditingController();
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Existing Patient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the email address of the patient you want to add to your care list.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'Patient Email',
                hintText: 'patient@example.com',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add Patient'),
          ),
        ],
      ),
    );

    if (result != true || emailController.text.trim().isEmpty) {
      emailController.dispose();
      return;
    }

    final patientEmail = emailController.text.trim();
    emailController.dispose();

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      if (userProvider.user?.caregiverId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Caregiver ID not found'),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final response = await ApiService.addExistingPatientToCaregiver(
        caregiverId: userProvider.user!.caregiverId!,
        patientEmail: patientEmail,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Patient successfully added'),
            backgroundColor: theme.colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Reload the patient list
        await _loadPatients();
      } else if (response.statusCode == 202) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Invitation sent to patient'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Patient already linked'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add patient: ${response.statusCode}'),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding patient: $e'),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Handles the register patient button press.
  ///
  /// Opens a dialog or navigates to a screen where caregivers can register
  /// new patients who don't have accounts yet. This creates a new patient account.
  Future<void> _onRegisterPatient() async {
    final theme = Theme.of(context);

    // Open the registration page as a modal, preconfigured for a Patient
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.95,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const RegistrationPage(
            initialRole: 'Patient',
            lockRole: true,
            skipEmailVerification: true,
          ),
        );
      },
    );

    // If registration was submitted, show a confirmation message
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Patient should receive a registration email.'),
          backgroundColor: theme.colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );

      // Optionally refresh the list after closing the modal
      await _loadPatients();
    }
  }

  /// Builds the main UI for the caregiver patient list screen.
  ///
  /// Creates a scaffold with:
  /// - App header
  /// - Statistics cards showing urgent and normal cases
  /// - Search bar with filter options
  /// - Patient list with pull-to-refresh functionality
  /// - Loading states and empty state handling
  ///
  /// Parameters:
  /// * [context] - The build context
  ///
  /// Returns:
  /// * Widget - The complete patient list screen UI
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: DefaultAppHeader(),
      body: RefreshIndicator(
        onRefresh: _loadPatients,
        child: Column(
          children: [
            // Stats Cards
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      urgentCasesCount.toString(),
                      'Urgent Cases',
                      Colors.red,
                      theme,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      normalCasesCount.toString(),
                      'Normal Status',
                      Colors.green,
                      theme,
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar with Add Patient Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Enter patient name...',
                        prefixIcon: Icon(
                          Icons.search,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                },
                                icon: Icon(
                                  Icons.clear,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.tune,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _onAddPatient,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _onRegisterPatient,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Register'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: theme.colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Patient List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : _filteredPatients.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No patients found',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredPatients.length,
                          itemBuilder: (context, index) {
                            final patient = _filteredPatients[index];
                            return PatientCard(
                              patient: patient,
                              onMessageTap: () {
                                final peerUserId = patient.patientUserId;
                                if (peerUserId == null || peerUserId <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to open chat for this patient.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatRoomScreen(
                                      peerUserId: peerUserId,
                                      peerName: patient.fullName,
                                    ),
                                  ),
                                );
                              },
                              onInviteTap: patient.linkId == null
                                  ? null
                                  : () {
                                      context.push(
                                        '/care-circle/${patient.linkId}/invite',
                                      );
                                    },
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PatientDetailsPage(
                                      patientId: patient.id,
                                      isCaregiver: true, // or patient: patient
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a statistics card widget.
  ///
  /// Creates a card displaying a count and label with appropriate styling.
  /// Used for showing urgent cases and normal status counts.
  ///
  /// Parameters:
  /// * [count] - The numerical value to display
  /// * [label] - The descriptive label for the statistic
  /// * [color] - The color to use for the count text
  /// * [theme] - The app theme data for consistent styling
  ///
  /// Returns:
  /// * Widget - A styled card containing the statistic
  Widget _buildStatCard(
    String count,
    String label,
    Color color,
    ThemeData theme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodSnapshot {
  final String label;
  final String emoji;

  const _MoodSnapshot({required this.label, required this.emoji});
}
