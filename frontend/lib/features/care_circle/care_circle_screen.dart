import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Care Circle hub — lists linked caregivers (patient) or patients (caregiver)
/// and exposes invite / share actions that were previously route-only.
class CareCircleScreen extends StatefulWidget {
  const CareCircleScreen({super.key});

  @override
  State<CareCircleScreen> createState() => _CareCircleScreenState();
}

class _CareCircleScreenState extends State<CareCircleScreen> {
  static const int _softMemberCap = 3;

  bool _loading = true;
  String? _error;
  List<_CircleMember> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        setState(() {
          _members = const [];
          _loading = false;
          _error = 'Sign in to view your Care Circle.';
        });
        return;
      }

      final role = user.role.toUpperCase();
      if (role == 'PATIENT') {
        final links = await ApiService.getPatientLinkedCaregiverLinks(user.id);
        if (!mounted) return;
        setState(() {
          _members = links.map(_memberFromPatientLink).toList();
          _loading = false;
        });
        return;
      }

      if (role == 'CAREGIVER' || role == 'ADMIN' || role == 'FAMILY_LINK') {
        final caregiverId = user.caregiverId;
        if (caregiverId == null || caregiverId <= 0) {
          setState(() {
            _members = const [];
            _loading = false;
            _error = 'No caregiver profile is linked to this account.';
          });
          return;
        }

        final response = await ApiService.getCaregiverPatients(caregiverId);
        if (!mounted) return;
        if (response.statusCode != 200) {
          setState(() {
            _members = const [];
            _loading = false;
            _error = 'Could not load Care Circle (${response.statusCode}).';
          });
          return;
        }

        final decoded = jsonDecode(response.body);
        final rows = decoded is List
            ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
            : <Map<String, dynamic>>[];

        setState(() {
          _members = rows.map(_memberFromCaregiverPatientRow).toList();
          _loading = false;
        });
        return;
      }

      setState(() {
        _members = const [];
        _loading = false;
        _error = 'Care Circle is available for patients and caregivers.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong loading your Care Circle.';
      });
    }
  }

  _CircleMember _memberFromPatientLink(Map<String, dynamic> link) {
    final linkId = _toInt(link['id'] ?? link['linkId']);
    final name = (link['caregiverName'] ?? link['name'] ?? 'Caregiver')
        .toString()
        .trim();
    final email = (link['caregiverEmail'] ?? link['email'] ?? '').toString();
    final status = (link['status'] ?? (link['isActive'] == true ? 'ACTIVE' : ''))
        .toString();
    return _CircleMember(
      linkId: linkId,
      title: name.isEmpty ? 'Caregiver' : name,
      subtitle: email,
      status: status.isEmpty ? 'UNKNOWN' : status,
      patientRecordId: null,
      isActive: link['isActive'] == true || status.toUpperCase() == 'ACTIVE',
    );
  }

  _CircleMember _memberFromCaregiverPatientRow(Map<String, dynamic> row) {
    final patient = (row['patient'] as Map?)?.cast<String, dynamic>() ?? {};
    final link = (row['link'] as Map?)?.cast<String, dynamic>() ?? {};
    final first = (patient['firstName'] ?? '').toString();
    final last = (patient['lastName'] ?? '').toString();
    final name = '$first $last'.trim();
    final email = (patient['email'] ?? link['patientEmail'] ?? '').toString();
    final status = (link['status'] ?? '').toString();
    return _CircleMember(
      linkId: _toInt(link['id'] ?? link['linkId']),
      title: name.isEmpty ? 'Patient' : name,
      subtitle: email,
      status: status.isEmpty ? 'UNKNOWN' : status,
      patientRecordId: patient['id']?.toString(),
      isActive: link['isActive'] == true || status.toUpperCase() == 'ACTIVE',
    );
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _invite(int linkId) async {
    await context.push('/care-circle/$linkId/invite');
  }

  Future<void> _suspend(int linkId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend link?'),
        content: const Text(
          'This member will temporarily lose Care Circle access until reactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final response = await ApiService.suspendCaregiverPatientLink(linkId);
    if (!mounted) return;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link suspended.')),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not suspend link (${response.statusCode}).')),
      );
    }
  }

  Future<void> _reactivate(int linkId) async {
    final response = await ApiService.reactivateCaregiverPatientLink(linkId);
    if (!mounted) return;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link reactivated.')),
      );
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reactivate link (${response.statusCode}).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<UserProvider>().user;
    final role = user?.role.toUpperCase() ?? '';
    final isPatient = role == 'PATIENT';
    final isCaregiverSide =
        role == 'CAREGIVER' || role == 'ADMIN' || role == 'FAMILY_LINK';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care Circle'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                    isPatient
                        ? 'People who help manage your care'
                        : 'Patients linked to you',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPatient
                        ? 'Invite helpers with a shared profile link, or manage caregivers already linked to you. Soft limit: $_softMemberCap caregivers.'
                        : 'Invite someone into an existing link with a QR code, or add a patient to grow your circle.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: ListTile(
                        leading: Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        title: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_members.isEmpty && _error == null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No members yet',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isPatient
                                  ? 'Share your limited profile so a caregiver can connect, or ask them to add you from their patient list.'
                                  : 'Add an existing patient by email, or open Invite on a linked patient once they are in your list.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ..._members.map((m) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Icon(
                                  isPatient
                                      ? Icons.health_and_safety_outlined
                                      : Icons.person_outline,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              title: Text(m.title),
                              subtitle: Text(
                                [
                                  if (m.subtitle.isNotEmpty) m.subtitle,
                                  m.status,
                                ].join(' · '),
                              ),
                              trailing: Chip(
                                label: Text(m.isActive ? 'Active' : m.status),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (isCaregiverSide && m.linkId != null)
                                  FilledButton.tonalIcon(
                                    onPressed: () => _invite(m.linkId!),
                                    icon: const Icon(Icons.qr_code_2, size: 18),
                                    label: const Text('Invite QR'),
                                  ),
                                if (isCaregiverSide &&
                                    m.patientRecordId != null &&
                                    m.patientRecordId!.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PatientDetailsPage(
                                            patientId: m.patientRecordId!,
                                            isCaregiver: true,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chevron_right),
                                    label: const Text('Open patient'),
                                  ),
                                if (m.linkId != null && m.isActive)
                                  TextButton(
                                    onPressed: () => _suspend(m.linkId!),
                                    child: const Text('Suspend'),
                                  ),
                                if (m.linkId != null && !m.isActive)
                                  TextButton(
                                    onPressed: () => _reactivate(m.linkId!),
                                    child: const Text('Reactivate'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (isPatient) ...[
                    FilledButton.icon(
                      onPressed: () => context.push('/profile/share'),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share limited profile'),
                    ),
                  ],
                  if (isCaregiverSide) ...[
                    FilledButton.icon(
                      onPressed: () => context.push('/add-patient'),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add patient'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/dashboard?tab=patients'),
                      icon: const Icon(Icons.list_alt),
                      label: const Text('Open patient list'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CircleMember {
  final int? linkId;
  final String title;
  final String subtitle;
  final String status;
  final String? patientRecordId;
  final bool isActive;

  const _CircleMember({
    required this.linkId,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.patientRecordId,
    required this.isActive,
  });
}
