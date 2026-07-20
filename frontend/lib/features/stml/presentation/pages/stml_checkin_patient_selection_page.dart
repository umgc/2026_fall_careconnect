import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../dashboard/models/patient_model.dart';

/// Entry point for STML-3: caregivers pick which patient's check-in prep
/// view to open, since a caregiver may have several care recipients.
class StmlCheckInPatientSelectionPage extends StatefulWidget {
  const StmlCheckInPatientSelectionPage({super.key});

  @override
  State<StmlCheckInPatientSelectionPage> createState() =>
      _StmlCheckInPatientSelectionPageState();
}

class _StmlCheckInPatientSelectionPageState
    extends State<StmlCheckInPatientSelectionPage> {
  List<Patient> _patients = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = context.read<UserProvider>().user;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final caregiverId = user.caregiverId ?? user.id;
      final response = await ApiService.getCaregiverPatients(caregiverId);

      if (response.statusCode != 200) {
        throw Exception('Failed to load patients: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body);
      final patients = <Patient>[];
      for (final json in data) {
        try {
          final raw = json is Map && json['patient'] != null
              ? json['patient']
              : json;
          patients.add(Patient.fromJson(Map<String, dynamic>.from(raw as Map)));
        } catch (_) {
          // Skip malformed entries rather than failing the whole list.
        }
      }
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundSecondary,
      appBar: AppBar(
        title: const Text('Select a patient'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadPatients, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_patients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            "You don't have any patients assigned to you yet.",
            textAlign: TextAlign.center,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _patients.length,
      itemBuilder: (context, index) {
        final patient = _patients[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              '${patient.firstName} ${patient.lastName}',
              style: const TextStyle(fontSize: 18),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/stml/checkin/${patient.id}'),
          ),
        );
      },
    );
  }
}
