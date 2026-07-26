import 'package:care_connect_app/features/ai_hitl/presentation/hitl_queue_page.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/invoices/screens/dashboard/invoice_dashboard_page.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/shared/widgets/more_features_bottom_drawer.dart';
import 'package:care_connect_app/utils/permission_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/notetaker/presentation/notetaker_search.dart';

/// Widget for the More bottom drawer navigation item
class CaregiverMoreFeaturesBottomDrawerWidget extends StatelessWidget {
  const CaregiverMoreFeaturesBottomDrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final role =
        Provider.of<UserProvider>(context, listen: false).user?.role ?? '';
    final List<FeatureItem> features = [
      FeatureItem(
        icon: Icons.calendar_month_outlined,
        iconColor: Colors.blue,
        title: 'Calendar Assistant',
        subtitle: 'Manage your Calendar Assistant Settings',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CalendarAssistantScreen(),
            ),
          );
        },
      ),
      FeatureItem(
        icon: Icons.payments,
        iconColor: Colors.blue,
        title: 'Invoice Assistant',
        subtitle: 'Manage your medical invoices.',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const InvoiceDashboardPage(),
            ),
          );
        },
      ),
      FeatureItem(
        icon: Icons.note_alt,
        iconColor: Colors.blue,
        title: 'Medical Notetaker',
        subtitle: 'View Notetaker Notes',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotetakerSearchPage(),
            ),
          );
        },
      ),
      if (PermissionHelper.hasPermission(role, 'REVIEW_AI_HOLDS'))
        FeatureItem(
          icon: Icons.fact_check_outlined,
          iconColor: Colors.blue,
          title: 'AI review queue',
          subtitle: 'Release or reject held Ask AI answers',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const HitlQueuePage(),
              ),
            );
          },
        ),
      FeatureItem(
        icon: Icons.settings,
        iconColor: Colors.blue,
        title: 'Settings',
        subtitle: 'Manage application settings.',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          );
        },
      ),
    ];

    return MoreFeaturesBottomDrawer(features: features);
  }
}
