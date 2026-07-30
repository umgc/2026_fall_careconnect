import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../widgets/patient_notes_widget.dart';
import '../../../../providers/user_provider.dart';

class PatientMedicalNotesPage extends StatelessWidget {
  final int patientId;
  final String patientName;

  const PatientMedicalNotesPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    final isCaregiver =
        user?.role.toUpperCase() == 'CAREGIVER' ||
        user?.role.toUpperCase() == 'FAMILY_LINK' ||
        user?.role.toUpperCase() == 'ADMIN';

    return Scaffold(
      appBar: AppBar(
        title: Text('$patientName - ${t.ptmednotes_medNotes}'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      drawer: const CommonDrawer(currentRoute: '/medical-notes'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with patient info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        patientName.isNotEmpty
                            ? patientName[0].toUpperCase()
                            : 'P',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${t.ptmednotes_ptID}: $patientId',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (isCaregiver)
                      Chip(
                        label: Text(t.ptmednotes_caregiverView),
                        backgroundColor: Colors.green.shade100,
                        labelStyle: TextStyle(color: Colors.green.shade800),
                      )
                    else
                      Chip(
                        label: Text(t.ptmednotes_ptView),
                        backgroundColor: Colors.blue.shade100,
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Medical notes widget
            Expanded(
              child: SingleChildScrollView(
                child: PatientNotesWidget(
                  patientId: patientId,
                  patientName: patientName,
                  isReadOnly:
                      false, // Both patients and caregivers can manage notes
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
