import 'package:care_connect_app/features/dashboard/patient_dashboard/pages/patient_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../features/profile/presentation/pages/profile_settings_page.dart';
import '../../features/social/presentation/pages/chat_inbox_screen.dart';
import '../../screens/patient_reports.dart';

class PatientHomeTab extends StatelessWidget {
  const PatientHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userId = userProvider.user?.id;

    return PatientDashboard(userId: userId);
  }
}

class PatientHealthTab extends StatelessWidget {
  const PatientHealthTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.health_and_safety,
              size: 80,
              color: Color(0xFF14366E),
            ),
            SizedBox(height: 16),
            Text(
              'Health Tracking',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14366E),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Monitor your health metrics, medications, and wellness goals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PatientMessagesTab extends StatelessWidget {
  const PatientMessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Messages'),
          backgroundColor: const Color(0xFF14366E),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Please log in to view messages'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: const Color(0xFF14366E),
        foregroundColor: Colors.white,
      ),
      body: const ChatInboxScreen(),
    );
  }
}

class PatientProfileTab extends StatelessWidget {
  const PatientProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProfileSettingsPage();
  }
}

class PatientReportsTab extends StatelessWidget {
  const PatientReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PatientReportsScreen();
  }
}
