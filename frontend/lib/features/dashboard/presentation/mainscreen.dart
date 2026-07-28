import 'package:care_connect_app/l10n/app_localizations.dart';

import '../../dashboard/presentation/sosscreen.dart';
import 'package:flutter/material.dart';
import 'cancelscreen.dart';
import '../../../../config/theme/app_theme.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  _EmergencyScreenState createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  @override
  void initState() {
    super.initState();
    // Schedule dialog after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEmergencyDialog();
    });
  }

  void _showEmergencyDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;
    final t = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Icon(
                Icons.error,
                color: AppTheme.error,
                size: isLargeScreen ? 28 : 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.mainscreen_emergencySOS,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: isLargeScreen ? 22 : 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: SizedBox(
          width: isLargeScreen ? 400 : 300,
          child: Text(
            t.mainscreen_areYouSure,
            style: TextStyle(
              fontSize: isLargeScreen ? 16 : 14,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CancelScreen()),
              );
            },
            style: AppTheme.textButtonStyle,
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SosScreen()),
              );
            },
            style: AppTheme.textButtonStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(AppTheme.error),
            ),
            child: Text(
              t.mainscreen_sendSOS,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("CareConnect"),
        centerTitle: true,
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
        elevation: 2,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            padding: EdgeInsets.all(isLargeScreen ? 32 : 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emergency,
                  size: isLargeScreen ? 100 : 60,
                  color: AppTheme.error,
                ),
                SizedBox(height: isLargeScreen ? 32 : 16),
                Text(
                  t.mainscreen_sosLoaded,
                  style: isLargeScreen
                      ? theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        )
                      : theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isLargeScreen ? 16 : 8),
                Text(
                  t.mainscreen_sosAuto,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
