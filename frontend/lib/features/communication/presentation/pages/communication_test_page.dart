import 'package:flutter/material.dart';
import '../../../../widgets/communication_widget.dart';

class CommunicationTestPage extends StatelessWidget {
  const CommunicationTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication Test'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Communication Features Test',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Test video calls, audio calls, SMS, and messaging functionality. '
                      'All features now work on web, iOS, and Android.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Test Case 1: Caregiver to Patient
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Test Case 1: Caregiver → Patient',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const CommunicationWidget(
                      currentUserId: 'caregiver_001',
                      currentUserName: 'Dr. Sarah Johnson',
                      targetUserId: 'patient_001',
                      targetUserName: 'John Smith',
                      targetPhoneNumber: '+1234567890',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test Case 2: Patient to Caregiver
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Test Case 2: Patient → Caregiver',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const CommunicationWidget(
                      currentUserId: 'patient_002',
                      currentUserName: 'Mary Wilson',
                      targetUserId: 'caregiver_002',
                      targetUserName: 'Dr. Michael Brown',
                      targetPhoneNumber: '+1987654321',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test Case 3: Emergency Contact
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Test Case 3: Emergency Contact',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                      ),
                    ),
                    const CommunicationWidget(
                      currentUserId: 'patient_003',
                      currentUserName: 'Emergency Patient',
                      targetUserId: 'emergency_contact',
                      targetUserName: 'Emergency Services',
                      targetPhoneNumber: '+1911',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Platform Information
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Platform Support',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildPlatformInfo(
                      '📱 iOS',
                      'Full support for video calls, audio calls, SMS, and messaging',
                    ),
                    _buildPlatformInfo(
                      '🤖 Android',
                      'Full support for video calls, audio calls, SMS, and messaging',
                    ),
                    _buildPlatformInfo(
                      '🌐 Web',
                      'Video calls, audio calls, messaging, and SMS (opens default email client as fallback)',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformInfo(String platform, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(platform, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }
}
