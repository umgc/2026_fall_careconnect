import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/features/dashboard/presentation/sosscreen.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/informed_delivery/informed_delivery_screen.dart';
import 'package:care_connect_app/shared/widgets/more_features_bottom_drawer.dart';
import 'package:flutter/material.dart';

/// Widget for the More bottom drawer navigation item
class PatientMoreFeaturesBottomDrawerWidget extends StatelessWidget {
  const PatientMoreFeaturesBottomDrawerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final List<FeatureItem> features = [
      FeatureItem(
        icon: Icons.sos,
        iconColor: Colors.red,
        title: 'SOS',
        subtitle: 'Informing Caregiver of emergency',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Emergency Assistance',
              builder: (context) => const SosScreen()),
          );
        },
      ),
      FeatureItem(
        icon: Icons.medication,
        iconColor: Colors.blue,
        title: 'Medication Tracker',
        subtitle: 'Track your medications and schedules',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Medication Tracker',
              builder: (context) => const MedicationsTrackerPage(),
            ),
          );
        },
      ),
      FeatureItem(
        icon: Icons.calendar_month_outlined,
        iconColor: Colors.blue,
        title: 'Calendar Assistant',
        subtitle: 'Manage your Calendar Assistant Settings',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Calendar',
              builder: (context) => const CalendarAssistantScreen(),
            ),
          );
        },
      ),
      FeatureItem(
        icon: Icons.mail,
        iconColor: Colors.blue,
        title: 'Informed Delivery',
        subtitle: 'View your Infomred Deliver digest',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Informed Delivery',
              builder: (context) => const InformedDeliveryScreen(),
            ),
          );
        },
      ),
      FeatureItem(
        icon: Icons.health_and_safety,
        iconColor: Colors.blue,
        title: 'Virtual Check-In',
        subtitle: 'Virtual Check-In',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Virtual Check-In',
              builder: (context) => const PatientVirtualCheckIn(),
            ),
          );
        },
      ),
    ];

    return MoreFeaturesBottomDrawer(features: features);
  }
}
