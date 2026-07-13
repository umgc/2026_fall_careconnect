import 'dart:io';
import 'dart:convert';
import 'package:care_connect_app/config/env_constant.dart';
import 'package:fitbitter/fitbitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
 

class ConnectedDevice {
  final String id;
  final String platform;
  final String name;
  final DateTime connectedAt;
  final List<String> permissions;
  final bool isActive;

  ConnectedDevice({
    required this.id,
    required this.platform,
    required this.name,
    required this.connectedAt,
    required this.permissions,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'name': name,
    'connectedAt': connectedAt.toIso8601String(),
    'permissions': permissions,
    'isActive': isActive,
  };

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) =>
      ConnectedDevice(
        id: json['id'],
        platform: json['platform'],
        name: json['name'],
        connectedAt: DateTime.parse(json['connectedAt']),
        permissions: List<String>.from(json['permissions']),
        isActive: json['isActive'] ?? true,
      );
}

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  int currentStep = 0;
  String? selectedPlatform;
  bool isConnecting = false;
  bool isConnected = false;
  String? errorMessage;

  // Device storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(webOptions: WebOptions.defaultOptions);
  List<ConnectedDevice> _connectedDevices = [];

  // Fitbit configuration (optional at runtime; show graceful message if missing)
  final String? fitbitClientId = _resolveFitbitClientId();
  final String? fitbitClientSecret = _resolveFitbitClientSecret();
  static const String redirectUri = 'care-connect://add-device';

  static String? _resolveFitbitClientId() {
    try {
      return getFitbitClientId();
    } catch (_) {
      return null;
    }
  }

  static String? _resolveFitbitClientSecret() {
    try {
      return getFitbitClientSecret();
    } catch (_) {
      return null;
    }
  }

  // Platform-specific health platforms
  List<Map<String, dynamic>> get healthPlatforms {
    List<Map<String, dynamic>> platforms = [
      {
        'id': 'fitbit',
        'name': 'Fitbit',
        'description': 'Connect your Fitbit device to track steps and calories',
        'icon': Icons.fitness_center,
        'color': Colors.green,
        'features': ['Steps', 'Calories'],
      },
    ];

    // Add Apple Health only for iOS
    if (!kIsWeb && Platform.isIOS) {
      platforms.add({
        'id': 'apple_health',
        'name': 'Apple Health',
        'description': 'Sync health data from Apple Health app',
        'icon': Icons.favorite,
        'color': Colors.red,
        'features': [
          'Steps',
          'Calories',
          'Heart Rate',
          'Blood Glucose',
          'Blood Pressure (Diastolic)',
          'Blood Pressure (Systolic)'
        ],
      });
    }

    // Add Google Fit only for Android
    if (!kIsWeb && Platform.isAndroid) {
      platforms.add({
        'id': 'google_fit',
        'name': 'Health Connect',
        'description': 'Connect to Health Connect for health tracking',
        'icon': Icons.directions_run,
        'color': Colors.blue,
        'features': [
          'Steps',
          'Calories',
          'Heart Rate',
          'Blood Glucose',
          'Blood Pressure (Diastolic)',
          'Blood Pressure (Systolic)'
        ],
      });
    }

    return platforms;
  }

  @override
  void initState() {
    super.initState();
    _loadConnectedDevices();
  }

  // Device Management Methods
  Future<void> _loadConnectedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesString = prefs.getString('connected_devices');

      if (devicesString != null) {
        final List<dynamic> devicesJson = jsonDecode(devicesString);
        _connectedDevices = devicesJson
            .map((json) => ConnectedDevice.fromJson(json))
            .toList();
        print('Loaded ${_connectedDevices.length} connected devices');
      }
    } catch (e) {
      print('Failed to load devices: $e');
      _connectedDevices = [];
    }
  }

  Future<void> _saveConnectedDevicesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesJson = _connectedDevices
          .map((device) => device.toJson())
          .toList();
      await prefs.setString('connected_devices', jsonEncode(devicesJson));
      print('Saved ${_connectedDevices.length} connected devices');
    } catch (e) {
      print('Failed to save devices: $e');
    }
  }

  Future<void> _storeAccessToken(String platform, String token) async {
    try {
      await _secureStorage.write(key: '${platform}_access_token', value: token);
      print('Stored $platform access token securely');
    } catch (e) {
      print('Failed to store access token: $e');
    }
  }

  // New method to store Fitbit userID
  Future<void> _storeFitbitUserID(String userID) async {
    try {
      await _secureStorage.write(key: 'fitbit_user_id', value: userID);
      print('Stored Fitbit userID securely: $userID');
    } catch (e) {
      print('Failed to store Fitbit userID: $e');
    }
  }

  Future<void> _storeConnectedDevice(
      String platform,
      List<String> permissions,
      ) async {
    try {
      final device = ConnectedDevice(
        id: '${platform}_${DateTime.now().millisecondsSinceEpoch}',
        platform: platform,
        name: _getPlatformDisplayName(platform),
        connectedAt: DateTime.now(),
        permissions: permissions,
      );

      _connectedDevices.add(device);
      await _saveConnectedDevicesToStorage();

      print('Device added: ${device.name}');
    } catch (e) {
      print('Failed to store device: $e');
    }
  }

  String _getPlatformDisplayName(String platform) {
    switch (platform) {
      case 'google_fit':
        return 'Health Connect';
      case 'apple_health':
        return 'Apple Health';
      case 'fitbit':
        return 'Fitbit';
      default:
        return platform.toUpperCase();
    }
  }

  bool _isPlatformConnected(String platform) {
    return _connectedDevices.any(
          (device) => device.platform == platform && device.isActive,
    );
  }

  Future<void> _fetchAndLogHealthData(
      Health health,
      List<HealthDataType> types,
      ) async {
    try {
      DateTime now = DateTime.now();
      DateTime lastWeek = now.subtract(const Duration(days: 7));

      List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
        startTime: lastWeek,
        endTime: now,
        types: types,
      );

      print('Successfully fetched ${healthData.length} health data points');

      Map<HealthDataType, int> summary = {};
      for (var point in healthData) {
        summary[point.type] = (summary[point.type] ?? 0) + 1;
      }

      summary.forEach((type, count) {
        print('  - ${type.toString()}: $count data points');
      });
    } catch (e) {
      print('Data fetch failed (connection still OK): $e');
    }
  }

  // Auto-start connection when platform is selected
  void _selectPlatformAndConnect(String platformId) async {
    if (_isPlatformConnected(platformId)) {
      return; // Already connected, do nothing
    }

    setState(() {
      selectedPlatform = platformId;
      currentStep = 1;
      isConnecting = true;
      errorMessage = null;
    });

    if (platformId == 'fitbit' &&
        (fitbitClientId == null || fitbitClientSecret == null)) {
      setState(() {
        isConnecting = false;
        errorMessage =
            'Fitbit is not configured. Set FITBIT_CLIENT_ID and FITBIT_CLIENT_SECRET in --dart-define to connect Fitbit.';
      });
      return;
    }

    // Start connection process immediately
    try {
      if (platformId == 'fitbit') {
        await _connectToFitbitReal();
      } else if (platformId == 'apple_health') {
        await _connectToAppleHealthReal();
      } else if (platformId == 'google_fit') {
        await _connectToGoogleFitReal();
      }
    } catch (e) {
      print('Connection error: $e');
      setState(() {
        isConnecting = false;
        errorMessage =
        'Failed to connect to ${_getPlatformDisplayName(platformId)}. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Add Health Platform',
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Progress Indicator
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Select', currentStep >= 0),
                _buildStepLine(currentStep >= 1),
                _buildStepIndicator(1, 'Connect', currentStep >= 1),
                _buildStepLine(currentStep >= 2),
                _buildStepIndicator(2, 'Complete', currentStep >= 2),
              ],
            ),
          ),

          // Content Area
          Expanded(child: _buildStepContent()),

          // Bottom Action Button (only show for step 1 and certain states)
          if (currentStep == 1 &&
              !isConnecting &&
              !isConnected &&
              errorMessage != null)
            _buildBottomButton(),
          if (currentStep == 1 && isConnected) _buildBottomButton(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppTheme.primary : Colors.grey[300],
            border: Border.all(
              color: isActive ? AppTheme.primary : Colors.grey[400]!,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? AppTheme.primary : Colors.grey[600],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 30),
        color: isActive ? AppTheme.primary : Colors.grey[300],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (currentStep) {
      case 0:
        return _buildSelectPlatformStep();
      case 1:
        return _buildConnectStep();
      case 2:
        return _buildCompleteStep();
      default:
        return _buildSelectPlatformStep();
    }
  }

  Widget _buildSelectPlatformStep() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Health Platform',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select which health platform you\'d like to connect for health monitoring.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: healthPlatforms.map((platform) {
                  final isAlreadyConnected = _isPlatformConnected(
                    platform['id'],
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isAlreadyConnected
                            ? AppTheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      onTap: isAlreadyConnected
                          ? null
                          : () {
                        _selectPlatformAndConnect(platform['id']);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: (platform['color'] as Color).withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    platform['icon'] as IconData,
                                    color: platform['color'] as Color,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            platform['name'] as String,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isAlreadyConnected) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius: BorderRadius.circular(
                                                  12,
                                                ),
                                              ),
                                              child: const Text(
                                                'Connected',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        platform['description'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isAlreadyConnected)
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Features list
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Health Metrics:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: (platform['features'] as List<String>).map((feature) =>
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (platform['color'] as Color).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            feature,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: platform['color'] as Color,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        )
                                    ).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectStep() {
    final selectedPlatformData = healthPlatforms.firstWhere(
          (platform) => platform['id'] == selectedPlatform,
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          const Text(
            'Connect to Platform',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 24),

          // Platform Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: (selectedPlatformData['color'] as Color)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      selectedPlatformData['icon'] as IconData,
                      color: selectedPlatformData['color'] as Color,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedPlatformData['name'] as String,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedPlatformData['description'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Connection Status
          if (isConnecting)
            Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Connecting to ${selectedPlatformData['name']}...',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please complete authorization in the permission dialog',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            )
          else if (isConnected)
            Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Connected to ${selectedPlatformData['name']}!',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Device has been added to your connected devices',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            )
          else if (errorMessage != null)
              Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error, color: Colors.red, size: 30),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Connection Failed',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        errorMessage = null;
                      });
                    },
                    style: AppTheme.primaryButtonStyle,
                    child: const Text(
                      'Try Again',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    final selectedPlatformData = healthPlatforms.firstWhere(
          (platform) => platform['id'] == selectedPlatform,
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          const SizedBox(height: 8),

          // Success Animation
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 60,
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            'Successfully Connected!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            '${selectedPlatformData['name']} has been connected and added to your devices.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 32),

          // Data Sync Info
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.sync, color: Colors.indigo),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Health Monitoring Active',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Now tracking: ${(selectedPlatformData['features'] as List<String>).join(', ')}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
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

          const SizedBox(height: 20),

          // Action Buttons
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      true,
                    ); // Return true to indicate a device was added
                  },
                  style: AppTheme.primaryButtonStyle.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  child: const Text(
                    'Back to Dashboard',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    // Reset and add another device
                    setState(() {
                      currentStep = 0;
                      selectedPlatform = null;
                      isConnecting = false;
                      isConnected = false;
                      errorMessage = null; // Reset error message as well
                    });
                  },
                  style: AppTheme.textButtonStyle,
                  child: Text(
                    'Add Another Platform',
                    style: TextStyle(color: AppTheme.primary, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _getButtonAction(),
          style: AppTheme.primaryButtonStyle.copyWith(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          child: Text(
            _getButtonText(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    if (currentStep == 1) {
      if (isConnected) return 'Continue';
      if (errorMessage != null) return 'Try Again';
    }
    return 'Continue';
  }

  VoidCallback? _getButtonAction() {
    if (currentStep == 1) {
      if (isConnected) {
        return () {
          setState(() {
            currentStep = 2;
          });
        };
      }
      if (errorMessage != null) {
        return () {
          setState(() {
            isConnecting = true;
            errorMessage = null;
          });

          // Retry connection
          if (selectedPlatform == 'fitbit') {
            _connectToFitbitReal();
          } else if (selectedPlatform == 'apple_health') {
            _connectToAppleHealthReal();
          } else if (selectedPlatform == 'google_fit') {
            _connectToGoogleFitReal();
          }
        };
      }
    }
    return null;
  }

  Future<void> _connectToFitbitReal() async {
    try {
      if (fitbitClientId == null || fitbitClientSecret == null) {
        throw Exception(
          'Fitbit is not configured. Missing FITBIT_CLIENT_ID/FITBIT_CLIENT_SECRET.',
        );
      }

      FitbitCredentials? fitbitCredentials = await FitbitConnector.authorize(
        clientID: fitbitClientId!,
        clientSecret: fitbitClientSecret!,
        redirectUri: redirectUri,
        callbackUrlScheme: 'care-connect',
      );

      if (fitbitCredentials != null) {

        String accessToken = fitbitCredentials.fitbitAccessToken;
        String userID = fitbitCredentials.userID; // Get the userID

        if (accessToken.isNotEmpty && userID.isNotEmpty) {
          print('Valid access token and userID received');

          // Store both access token and userID
          await _storeAccessToken('fitbit', accessToken);
          await _storeFitbitUserID(userID);

          List<String> permissions = [
            'steps',
            'calories'
          ];

          await _storeConnectedDevice('fitbit', permissions);

          setState(() {
            isConnecting = false;
            isConnected = true;
          });

          print('Fitbit connected successfully');
        } else {
          print('Access token or userID is empty');
          throw Exception(
            'Failed to get access token or userID - one or both are empty',
          );
        }
      } else {
        throw Exception('Authorization was cancelled or failed');
      }
    } catch (e) {

      setState(() {
        isConnecting = false;
        errorMessage = 'Failed to connect to Fitbit: ${e.toString()}';
      });
    }
  }

  Future<void> _connectToAppleHealthReal() async {
    try {
      print('Starting Apple Health connection...');

      if (_isPlatformConnected('apple_health')) {
        setState(() {
          errorMessage = 'Apple Health is already connected to this account.';
          isConnecting = false;
        });
        return;
      }

      setState(() {
        isConnecting = true;
        errorMessage = null;
      });

      // Keep authorization scope aligned with the persisted metrics we ingest.
      final List<HealthDataType> requiredTypes = [
        HealthDataType.STEPS,
        HealthDataType.HEART_RATE,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      ];

      bool requested = await Health().requestAuthorization(
        requiredTypes,
        permissions: requiredTypes.map((type) => HealthDataAccess.READ).toList(),
      );

      if (requested) {
        final hasPermissions = await Health().hasPermissions(requiredTypes) ?? false;
        if (!hasPermissions) {
          // iOS can report false here even after an auth success callback.
          // Continue and let actual sync determine whether data access works.
          print(
            '⚠ Apple Health reported partial/unknown permissions after authorization; proceeding with connection.',
          );
        }

        await _storeAccessToken(
          'apple_health',
          'apple_health_authorized_${DateTime.now().millisecondsSinceEpoch}',
        );

        List<String> grantedPermissions = [
          'steps',
          'heart_rate',
          'blood_pressure_diastolic',
          'blood_pressure_systolic'
        ];

        await _storeConnectedDevice('apple_health', grantedPermissions);

        setState(() {
          isConnecting = false;
          isConnected = true;
        });

        print(
            'Apple Health connected successfully with ${grantedPermissions.length} required permissions');
      } else {
        throw Exception(
          'Apple Health permission was denied. Please allow access in the Apple Health prompt or Settings > Health > Data Access & Devices.',
        );
      }
    } catch (e) {
      print('Apple Health connection error: $e');
      setState(() {
        isConnecting = false;
        errorMessage = 'Failed to connect to Apple Health: ${e.toString()}';
      });
    }
  }

  Future<void> _connectToGoogleFitReal() async {
    try {
      if (_isPlatformConnected('google_fit')) {
        setState(() {
          errorMessage = 'Health Connect is already connected to this account.';
          isConnecting = false;
        });
        return;
      }

      print('Starting Health Connect connection...');
      final health = Health();

      setState(() {
        isConnecting = true;
        errorMessage = null;
      });

      // Configure health
      await health.configure();
      print('Health configured successfully');

      List<HealthDataType> types = [
        HealthDataType.STEPS,
        HealthDataType.HEART_RATE,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      ];

      // Request authorization
      print('Requesting health permissions for ${types.length} data types...');
      bool requested = await health.requestAuthorization(
        types,
        permissions: types.map((type) => HealthDataAccess.READ).toList(),
      );

      if (requested) {
        print('Authorization requested successfully!');

        // Verify permissions were actually granted
        bool hasPermissions = await health.hasPermissions(types) ?? false;

        if (hasPermissions) {
          // Store access token and device info
          await _storeAccessToken(
            'google_fit',
            'health_connect_authorized_${DateTime.now().millisecondsSinceEpoch}',
          );

          List<String> grantedPermissions = [
            'steps',
            'heart_rate',
            'blood_pressure_diastolic',
            'blood_pressure_systolic'
          ];

          await _storeConnectedDevice('google_fit', grantedPermissions);

          // Test the connection by fetching recent data
          await _fetchAndLogHealthData(health, types);

          setState(() {
            isConnecting = false;
            isConnected = true;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Health Connect successfully connected with ${grantedPermissions.length} permissions!'),
                backgroundColor: Colors.green,
              ),
            );
          }

          print('Health Connect connected successfully with ${grantedPermissions.length} permissions');
        } else {
          throw Exception('Health permission were not granted');
        }
      } else {
        throw Exception('Health authorization was denied');
      }
    } catch (e) {
      print('Google Fit connection error: $e');
      setState(() {
        isConnecting = false;
        errorMessage = 'Connection failed: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
