import 'dart:convert';

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/careteam-performace-card.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/recent-patient-activity-widget.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/services/invoice_service.dart';
import 'package:care_connect_app/features/invoices/widgets/invoice_overview_card.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/patient-stat-card.dart';

class _LinkedActivePatient {
  final int patientId;
  final String displayName;

  const _LinkedActivePatient({
    required this.patientId,
    required this.displayName,
  });
}

class CaregiverDashboard extends StatelessWidget {
  const CaregiverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    return Scaffold(
      appBar: DashboardAppHeader(
        userName: user?.name ?? '',
        role: user?.role ?? '',
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Statistics Cards
              const PatientStatisticsCards(),
              const SizedBox(height: 20),

              // Upcoming Check-ins
              const UpcomingCheckins(),
              const SizedBox(height: 20),

              // Recent Patient Activity
              const RecentPatientActivity(),
              const SizedBox(height: 20),

              // Care Team Performance
              const CareTeamPerformance(),
              // Invoice overview
              const SizedBox(height: 20),
              InvoiceOverviewCard(
                getUnpaidCount: () => _fetchUnpaidInvoiceCount(context),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'chat_fab',
            backgroundColor: Theme.of(context).primaryColor,
            child: Icon(
              Icons.chat_bubble_outline,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () => _openGroundedAskAi(context),
          ),
        ],
      ),
    );
  }

  /// Caregiver Ask AI requires an explicit selection from currently linked
  /// active patients. Never infer mutable [UserSession.patientId].
  Future<void> _openGroundedAskAi(BuildContext context) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final caregiverId = user?.caregiverId;
    if (caregiverId == null || caregiverId <= 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No caregiver profile is linked to this account.'),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<_LinkedActivePatient> patients = const [];
    String? loadError;
    try {
      patients = await _loadLinkedActivePatients(caregiverId);
    } catch (e) {
      loadError = 'Unable to load linked patients.';
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (loadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadError)),
      );
      return;
    }
    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No currently linked active patients found.'),
        ),
      );
      return;
    }

    final selected = await showDialog<_LinkedActivePatient>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('caregiver-ask-ai-patient-picker'),
        title: const Text('Select a patient'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              return ListTile(
                key: Key('caregiver-ask-ai-patient-${patient.patientId}'),
                title: Text(patient.displayName),
                onTap: () => Navigator.of(dialogContext).pop(patient),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (!context.mounted || selected == null) return;

    final double sheetHeight = MediaQuery.of(context).size.height * 0.75;
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxWidth:
            MediaQuery.of(context).size.width > 768 ? 600 : double.infinity,
      ),
      builder: (sheetContext) => SizedBox(
        height: sheetHeight,
        child: AIChat(
          key: ValueKey(
            'ai-chat-${AiChatMode.groundedRecords.name}-${selected.patientId}',
          ),
          role: 'caregiver',
          isModal: true,
          patientId: selected.patientId,
          userId: user?.id,
          mode: AiChatMode.groundedRecords,
        ),
      ),
    );
  }

  Future<List<_LinkedActivePatient>> _loadLinkedActivePatients(
    int caregiverId,
  ) async {
    final response = await ApiService.getCaregiverPatients(caregiverId);
    if (response.statusCode != 200) {
      throw Exception('Failed to load patients (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected caregiver patient payload');
    }

    final patients = <_LinkedActivePatient>[];
    final seen = <int>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final link = map['link'];
      final patient = map['patient'];
      final linkMap = link is Map
          ? Map<String, dynamic>.from(link)
          : const <String, dynamic>{};
      final patientMap = patient is Map
          ? Map<String, dynamic>.from(patient)
          : const <String, dynamic>{};

      final status = (linkMap['status'] ?? 'ACTIVE').toString().toUpperCase();
      final isActiveFlag = linkMap['isActive'];
      final isActive = isActiveFlag is bool ? isActiveFlag : status == 'ACTIVE';
      if (!isActive || status != 'ACTIVE') continue;

      final patientId = _asInt(patientMap['id']);
      if (patientId == null || patientId <= 0 || seen.contains(patientId)) {
        continue;
      }
      seen.add(patientId);

      final firstName = (patientMap['firstName'] ?? '').toString().trim();
      final lastName = (patientMap['lastName'] ?? '').toString().trim();
      final fallbackName = (linkMap['patientName'] ?? '').toString().trim();
      final displayName = [firstName, lastName]
          .where((part) => part.isNotEmpty)
          .join(' ')
          .trim();

      patients.add(_LinkedActivePatient(
        patientId: patientId,
        displayName: displayName.isNotEmpty
            ? displayName
            : (fallbackName.isNotEmpty ? fallbackName : 'Patient $patientId'),
      ));
    }
    return patients;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<int> _fetchUnpaidInvoiceCount(BuildContext context) async {
    final unpaidStatuses = <PaymentStatus>{
      PaymentStatus.pending,
      PaymentStatus.overdue,
      PaymentStatus.pendingInsurance,
      PaymentStatus.sent,
      PaymentStatus.partialPayment,
      PaymentStatus.rejectedInsurance,
    };

    final invoices = await InvoiceService.instance.fetchInvoices(
      status: unpaidStatuses,
      pageSize: 200, // adjust if needed
    );

    return invoices.length;
  }
}
