import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/features/emergency_qr/qr_screen.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';

/// Dashboard App header
class DashboardAppHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final String userName;
  final String? timezone;
  final String? profileImageUrl;
  final String role;

  const DashboardAppHeader({
    super.key,
    required this.userName,
    required this.role,
    this.timezone,
    this.profileImageUrl = "",
  });

  @override
  Size get preferredSize {
    // Calculate the height based on content
    return const Size.fromHeight(210); // This will be overridden
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final DateTime time = DateTime.now();
    final String timeZone = time.timeZoneName;
    // Helper function to ensure two-digit formatting
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    // Format the datetime manually
    String formattedTime =
        '${twoDigits(time.month)}/${twoDigits(time.day)}/${time.year} ${twoDigits(time.hour)}:${twoDigits(time.minute)}';

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: preferredSize.height,
      flexibleSpace: Container(
        height: preferredSize.height,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(25),
            bottomRight: Radius.circular(25),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row with logo and icons
                SizedBox(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo section
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 35,
                              height: 35,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.local_hospital,
                                color: theme.colorScheme.onPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "CARECONNECT",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Right icons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Emergency QR Icon
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                final userProvider = Provider.of<UserProvider>(context, listen: false);
                                final patient = userProvider.patientModel;
                                final user = userProvider.user;

                                if (patient != null && user != null) {
                                  // Parse date of birth
                                  DateTime dobDate;
                                  try {
                                    dobDate = DateTime.parse(patient.dob);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(t.appheaderwidget_invalidDOB),
                                      ),
                                    );
                                    return;
                                  }

                                  // Calculate accurate age
                                  final now = DateTime.now();
                                  int age = now.year - dobDate.year;
                                  if (now.month < dobDate.month || (now.month == dobDate.month && now.day < dobDate.day)) {
                                    age--;
                                  }

                                  // Create emergency ID from patient ID
                                  final emergencyId = 'VIAL${user.patientId ?? user.id}';

                                  final emergencyInfo = EmergencyInfo(
                                    firstName: patient.firstName,
                                    lastName: patient.lastName,
                                    bloodType: '', // Will be filled from backend
                                    dob: dobDate,
                                    age: age,
                                    gender: patient.gender,
                                    id: emergencyId,
                                    allergiesCritical: [], // Will be loaded from backend
                                    contacts: [],
                                    secureToken: user.token,
                                  );

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => QrScreen(
                                        payload: emergencyInfo.qrPayload(),
                                        emergencyId: emergencyId,
                                        patientId: user.patientId ?? user.id,
                                      ),
                                    ),
                                  );
                                } else {
                                  // Show error if no patient data available
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(t.appheaderwidget_missingPtData),
                                    ),
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.local_hospital,
                                color: Colors.red,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Settings Icon
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsPage(),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.settings_outlined,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Profile and welcome section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile avatar with online indicator
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundImage: profileImageUrl!.isNotEmpty
                              ? NetworkImage(profileImageUrl!)
                              : null,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: profileImageUrl!.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 30,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.cardColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 15),

                    // Welcome text section
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${t.appheaderwidget_welcomeBack} $userName",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "$formattedTime $timeZone",
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role == "PATIENT"
                                ? t.appheaderwidget_greetingPt
                                : t.appheaderwidget_greetingNonPt,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
