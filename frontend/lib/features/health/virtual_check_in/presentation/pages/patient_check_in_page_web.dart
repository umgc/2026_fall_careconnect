import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_detail_page.dart';
import 'package:care_connect_app/features/health/virtual_check_in/services/checkin_api.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/checkin_service.dart';

class PatientVirtualCheckIn extends StatefulWidget {
  const PatientVirtualCheckIn({super.key});

  @override
  State<PatientVirtualCheckIn> createState() => _PatientVirtualCheckInState();
}

class _PatientVirtualCheckInState extends State<PatientVirtualCheckIn> {
  bool _isLoading = true;
  String? _error;
  int? _activeCheckInId;
  List<BackendQuestionDto> _assignedQuestions = const [];

  @override
  void initState() {
    super.initState();
    _loadAssignedQuestionnaire();
  }

  Future<void> _loadAssignedQuestionnaire() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        setState(() {
          _error = 'No user session found. Please sign in again.';
          _isLoading = false;
        });
        return;
      }

      final candidateIds = <int>{
        if (user.patientId != null) user.patientId!,
        user.id,
      };

      List<CheckInSummary> checkIns = const [];
      for (final id in candidateIds) {
        final found = await CheckinService.fetchCheckInsForPatient(
          id.toString(),
        );
        if (found.isNotEmpty) {
          checkIns = found;
          break;
        }
      }

      if (checkIns.isEmpty) {
        setState(() {
          _error = 'No check-in questionnaire has been assigned yet.';
          _isLoading = false;
        });
        return;
      }

      final unsubmitted = checkIns.where((c) => c.submittedAt == null).toList();
      if (unsubmitted.isEmpty) {
        setState(() {
          _error = 'All assigned check-ins have already been completed. '
              'No pending check-ins to answer.';
          _isLoading = false;
        });
        return;
      }

      final latestCheckInId = unsubmitted.first.checkInId;
      final api = CheckInApi(getBackendBaseUrl());
      try {
        final questions = await api.getQuestions(latestCheckInId.toString());
        if (!mounted) return;
        setState(() {
          _activeCheckInId = latestCheckInId;
          _assignedQuestions = questions;
          _error = questions.isEmpty
              ? 'This check-in has no questions configured.'
              : null;
          _isLoading = false;
        });
      } finally {
        api.close();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load questionnaire: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _error == null && _activeCheckInId != null && _assignedQuestions.isNotEmpty) {
      return PatientCheckInDetailPage(
        checkInId: _activeCheckInId!,
        questions: _assignedQuestions,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Virtual Check-In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned Check-In Questionnaire',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (_activeCheckInId != null) ...[
                        const SizedBox(height: 4),
                        Text('Check-in #$_activeCheckInId'),
                      ],
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        Text(_error!, style: const TextStyle(color: Colors.red))
                      else
                        ..._assignedQuestions.map((q) {
                          final requiredLabel = q.required
                              ? 'Required'
                              : 'Optional';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(
                                  child: Text(
                                    '${q.prompt} ($requiredLabel, ${q.type.name})',
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      Text(
                        'Camera recording flow is only available on mobile apps.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
