import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/profile_service.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:care_connect_app/services/auth_service.dart';

class SmartDevicesPage extends StatefulWidget {
  const SmartDevicesPage({super.key});

  @override
  State<SmartDevicesPage> createState() => _SmartDevicesPageState();
}

class _SmartDevicesPageState extends State<SmartDevicesPage> {
  bool? isAlexaLinked;
  bool isLoading = true;
  String? error;
  String? role;

  // Sample URLs for skill stores
  final String alexaSkillUrl =
      'https://skills-store.amazon.com/deeplink/tvt/1cc43d50136bee48a3039cf55775ec0a64a967d5685df997fae9a2fe719a20a7d8e108ed6f4d7bfedb9ce283ddbdf81ed9f6289f17e311266b534cbb311f0bf69ee09a1c8d5d376364359852b0ba8ba7edecc29327df49ac547b52edb016973e1c7b73c96251be9c74dc48e68ba321e6';
  final String googleActionUrl =
      'https://assistant.google.com/services/invoke/uid/000000d139bbc4d4';

  @override
  void initState() {
    super.initState();
    _checkAlexaStatus();
  }

  Future<void> _checkAlexaStatus() async {
    try {
      setState(() => isLoading = true);

      final profile = await ProfileService.getCurrentUserProfile();
      if (!mounted) return;

      if (profile == null) {
        setState(() {
          error = AppLocalizations.of(context)!.smartDevicesProfileUnavailable;
          isLoading = false;
        });
        return;
      }

      // Extract role from nested user object
      final userObj = profile['user'];
      role = (userObj != null ? userObj['role'] : null)
              ?.toString()
              .trim()
              .toUpperCase() ??
          '';

      debugPrint("DEBUG: Extracted role: '$role'");

      // Extract Alexa status directly from profile (using alexaLinked field)
      isAlexaLinked = profile['alexaLinked'] ?? false;
      debugPrint("DEBUG: Alexa linked status from profile: $isAlexaLinked");

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = AppLocalizations.of(context)!
            .smartDevicesErrorOccurred(e.toString());
        isLoading = false;
      });
    }
  }

  Future<void> _linkAlexaAccount() async {
    debugPrint("Opening Alexa linking flow...");
    _showEnablementDialog('Alexa', alexaSkillUrl);
  }

  Future<void> _unlinkAlexaAccount() async {
    setState(() => isLoading = true);
    try {
      final l10n = AppLocalizations.of(context)!;
      final result = await AuthService.unlinkAlexaAccount(l10n);
      if (!mounted) return;

      if (result['isSuccess'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .authservice_alexaUnlinkedSuccess)),
        );
        setState(() {
          isAlexaLinked = false;
          isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result['message'] ??
                  AppLocalizations.of(context)!
                      .authservice_alexaUnlinkedFailed)),
        );
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .smartDevicesUnlinkError(e.toString()))),
      );
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Scaffold(
        drawer: const CommonDrawer(currentRoute: '/smart-devices'),
        appBar: AppBarHelper.createAppBar(
          context,
          title: AppLocalizations.of(context)!.smartDevices,
          centerTitle: true,
        ),
        body: Center(
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final isPatient = role == 'PATIENT';

    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/smart-devices'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: AppLocalizations.of(context)!.smartDevices,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header Section with Icon and Description
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.devices,
                size: 60,
                color: Theme.of(context).primaryColor,
              ),
            ),

            const SizedBox(height: 24),

            Text(
              AppLocalizations.of(context)!.smartDevicesIntegrationTitle,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              AppLocalizations.of(context)!.smartDevicesIntro,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
            ),

            const SizedBox(height: 32),

            // Privacy Policy footer
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(
                    'https://www.freeprivacypolicy.com/live/9a586bf1-2869-40aa-993a-c8f80200209c');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .smartDevicesPrivacyOpenFailed)),
                  );
                }
              },
              child: Text(
                AppLocalizations.of(context)!.smartDevicesPrivacyPolicy,
                style: TextStyle(
                  color: Colors.blue.shade700,
                  decoration: TextDecoration.underline,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Two-Column Layout for Alexa and Google
            LayoutBuilder(
              builder: (context, constraints) {
                // Use column layout for phone screens (< 600px width)
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      _buildAlexaPlatformCard(context, isPatient),
                      const SizedBox(height: 16),
                      _buildGooglePlatformCard(context, isPatient),
                    ],
                  );
                } else {
                  // Use row layout for tablets/desktop
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: _buildAlexaPlatformCard(context, isPatient)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildGooglePlatformCard(context, isPatient)),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlexaPlatformCard(BuildContext context, bool isPatient) {
    final devices = [
      _DeviceInfo(
          icon: Icons.speaker,
          name: AppLocalizations.of(context)!.smartDevicesEchoDevices,
          available: true),
      _DeviceInfo(
          icon: Icons.lightbulb,
          name: AppLocalizations.of(context)!.smartDevicesSmartLights,
          available: false),
      _DeviceInfo(
          icon: Icons.thermostat,
          name: AppLocalizations.of(context)!.smartDevicesThermostats,
          available: false),
      _DeviceInfo(
          icon: Icons.lock,
          name: AppLocalizations.of(context)!.smartDevicesSmartLocks,
          available: false),
      _DeviceInfo(
          icon: Icons.outlet,
          name: AppLocalizations.of(context)!.smartDevicesSmartPlugs,
          available: false),
      _DeviceInfo(
          icon: Icons.sensor_door,
          name: AppLocalizations.of(context)!.smartDevicesSensors,
          available: false),
    ];

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Platform Header
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, color: Colors.blue, size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Amazon Alexa',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 20),

            // Status indicator for patients
            if (isPatient) ...[
              Icon(
                isAlexaLinked == true ? Icons.link : Icons.link_off,
                color: isAlexaLinked == true ? Colors.green : Colors.grey,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                isAlexaLinked == true
                    ? AppLocalizations.of(context)!.smartDevicesAlexaLinked
                    : AppLocalizations.of(context)!.smartDevicesAlexaNotLinked,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Device List
            ...devices.map((device) => _buildDeviceItem(
                  icon: device.icon,
                  name: device.name,
                  available: device.available,
                  color: Colors.blue,
                )),

            const SizedBox(height: 20),

            // Message for non-patients
            if (!isPatient) ...[
              Text(
                AppLocalizations.of(context)!.smartDevicesAlexaPatientOnly,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isPatient
                    ? (isAlexaLinked == true
                        ? _unlinkAlexaAccount
                        : _linkAlexaAccount)
                    : null,
                icon: Icon(isPatient && isAlexaLinked == true
                    ? Icons.refresh
                    : Icons.add),
                label: Text(
                  isPatient
                      ? (isAlexaLinked == true
                          ? AppLocalizations.of(context)!
                              .smartDevicesDisableAlexa
                          : AppLocalizations.of(context)!
                              .smartDevicesEnableAlexa)
                      : AppLocalizations.of(context)!
                          .smartDevicesCaregiversComingSoon,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPatient
                      ? (isAlexaLinked == true ? Colors.red : Colors.blue)
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGooglePlatformCard(BuildContext context, bool isPatient) {
    final devices = [
      _DeviceInfo(
          icon: Icons.home,
          name: AppLocalizations.of(context)!.smartDevicesNestHubs,
          available: true),
      _DeviceInfo(
          icon: Icons.speaker,
          name: AppLocalizations.of(context)!.smartDevicesGoogleHome,
          available: true),
      _DeviceInfo(
          icon: Icons.lightbulb,
          name: AppLocalizations.of(context)!.smartDevicesSmartLights,
          available: false),
      _DeviceInfo(
          icon: Icons.thermostat,
          name: AppLocalizations.of(context)!.smartDevicesNestThermostat,
          available: false),
      _DeviceInfo(
          icon: Icons.doorbell,
          name: AppLocalizations.of(context)!.smartDevicesNestDoorbell,
          available: false),
      _DeviceInfo(
          icon: Icons.camera_alt,
          name: AppLocalizations.of(context)!.smartDevicesNestCameras,
          available: false),
    ];

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Platform Header
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.g_mobiledata_rounded,
                  color: Colors.red, size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Google Nest',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 20),

            // Device List
            ...devices.map((device) => _buildDeviceItem(
                  icon: device.icon,
                  name: device.name,
                  available: device.available,
                  color: Colors.red,
                )),

            const SizedBox(height: 20),

            // Message for all users (Google not available yet)
            Text(
              isPatient
                  ? AppLocalizations.of(context)!
                      .smartDevicesGoogleUnderDevelopment
                  : AppLocalizations.of(context)!.smartDevicesGooglePatientOnly,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),

            // Action Button (disabled for now)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.add),
                label: Text(AppLocalizations.of(context)!
                    .smartDevicesEnableGoogleComingSoon),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem({
    required IconData icon,
    required String name,
    required bool available,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: available
                  ? color.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: available ? color : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: available ? Colors.black87 : Colors.grey,
              ),
            ),
          ),
          if (!available)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                AppLocalizations.of(context)!.smartDevicesComingSoon,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEnablementDialog(String platform, String url) {
    final skillType = platform == 'Alexa' ? 'Skill' : 'Action';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!
              .smartDevicesEnablePlatform(platform, skillType)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!
                    .smartDevicesOpenStoreInstruction(platform, skillType),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.smartDevicesSampleUrlNote,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!
                          .smartDevicesOpeningStore(platform, skillType)),
                    ),
                  );
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!
                          .smartDevicesStoreOpenFailed),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: platform == 'Alexa' ? Colors.blue : Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(AppLocalizations.of(context)!
                  .smartDevicesOpenPlatformStore(platform)),
            ),
          ],
        );
      },
    );
  }
}

// Helper class for device info
class _DeviceInfo {
  final IconData icon;
  final String name;
  final bool available;

  _DeviceInfo({
    required this.icon,
    required this.name,
    required this.available,
  });
}
