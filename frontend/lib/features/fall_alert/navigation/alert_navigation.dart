import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fall_alert.dart';
import '../pages/alert_details_page.dart';

class AlertNavigation {
  static void navigateFromPayload(
    BuildContext context,
    Map<String, String> payload,
  ) {
    final alert = FallAlert.fromPayload(payload);

    // Read role from your provider
    final userProvider = context.read<UserProvider>();
    final isPatient = userProvider.isPatient;

    if (isPatient) {
      // Patient view: show the fall prompt with countdown and actions
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: PatientFallPromptPage.routeName),
          builder: (_) => PatientFallPromptPage(
            autoCallSeconds: 30,
            emergencyNumber: '911', // make region aware later
            emergencyContactName: alert.emergencyContactName,
            emergencyContactPhone: alert.emergencyContactPhone,

            onAcknowledgeOk: () async {
              // TODO: mark alert as acknowledged for this patient
            },
            onEscalate: () async {
              // TODO: log or notify caregiver that emergency call started
            },
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: AlertDetailsPage.routeName),
          builder: (_) => AlertDetailsPage(alert: alert),
        ),
      );
    }
  }
}
