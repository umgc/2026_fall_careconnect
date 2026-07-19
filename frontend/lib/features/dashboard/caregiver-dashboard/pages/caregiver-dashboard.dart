import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/careteam-performace-card.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/recent-patient-activity-widget.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/services/invoice_service.dart';
import 'package:care_connect_app/features/invoices/widgets/invoice_overview_card.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/patient-stat-card.dart';

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
            onPressed: () {
              final double sheetHeight =
                  MediaQuery.of(context).size.height * 0.75;
              showModalBottomSheet(
                isScrollControlled: true,
                context: context,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width > 768
                      ? 600
                      : double.infinity,
                ),
                builder: (context) => SizedBox(
                  height: sheetHeight,
                  child: AIChat(
                    role: 'caregiver',
                    isModal: true,
                    patientId: user?.patientId,
                    userId: user?.id,
                    mode: AiChatMode.groundedRecords,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
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
