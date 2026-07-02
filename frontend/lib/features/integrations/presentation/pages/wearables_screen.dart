import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:fitbitter/fitbitter.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';

import 'add_devices_screen.dart';

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

class HealthData {
  final String type;
  final double value;
  final String unit;
  final DateTime date;
  final String source;
  final bool isPlaceholder;
  final String supportStatus;
  final String? placeholderReason;

  HealthData({
    required this.type,
    required this.value,
    required this.unit,
    required this.date,
    required this.source,
    this.isPlaceholder = false,
    this.supportStatus = 'Persisted Mapping',
    this.placeholderReason,
  });
}

class SemesterMetricDefinition {
  final String key;
  final String type;
  final String unit;
  final bool mappedToPersistedEntity;
  final bool availableFromCurrentSource;
  final String note;

  const SemesterMetricDefinition({
    required this.key,
    required this.type,
    required this.unit,
    required this.mappedToPersistedEntity,
    required this.availableFromCurrentSource,
    required this.note,
  });
}

class WearablesScreen extends StatefulWidget {
  const WearablesScreen({super.key});

  @override
  State<WearablesScreen> createState() => _WearablesScreenState();
}

class _WearablesScreenState extends State<WearablesScreen> {
  List<ConnectedDevice> connectedDevices = [];
  Map<String, HealthData> latestHealthData = {};
  bool isLoadingData = false;
  final FlutterSecureStorage _secureStorage =
      const FlutterSecureStorage(webOptions: WebOptions.defaultOptions);

  static const Map<String, List<SemesterMetricDefinition>>
      _semesterSourceMetricMatrix = {
    'fitbit': [
      SemesterMetricDefinition(
        key: 'steps',
        type: 'Steps',
        unit: 'steps',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(STEPS).',
      ),
      SemesterMetricDefinition(
        key: 'calories',
        type: 'Activity (Calories)',
        unit: 'cal',
        mappedToPersistedEntity: false,
        availableFromCurrentSource: true,
        note: 'UI demo only; activity persistence is a future story.',
      ),
      SemesterMetricDefinition(
        key: 'heart_rate',
        type: 'Heart Rate',
        unit: 'bpm',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: Fitbit heart-rate sync not wired this semester.',
      ),
      SemesterMetricDefinition(
        key: 'spo2',
        type: 'SpO2',
        unit: '%',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: source/API mapping not wired this semester.',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_systolic',
        type: 'Blood Pressure (Systolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: source/API mapping not wired this semester.',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_diastolic',
        type: 'Blood Pressure (Diastolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: source/API mapping not wired this semester.',
      ),
    ],
    'apple_health': [
      SemesterMetricDefinition(
        key: 'steps',
        type: 'Steps',
        unit: 'steps',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(STEPS).',
      ),
      SemesterMetricDefinition(
        key: 'heart_rate',
        type: 'Heart Rate',
        unit: 'bpm',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(HEART_RATE).',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_systolic',
        type: 'Blood Pressure (Systolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(BLOOD_PRESSURE_SYS).',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_diastolic',
        type: 'Blood Pressure (Diastolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(BLOOD_PRESSURE_DIA).',
      ),
      SemesterMetricDefinition(
        key: 'calories',
        type: 'Activity (Calories)',
        unit: 'cal',
        mappedToPersistedEntity: false,
        availableFromCurrentSource: true,
        note: 'UI demo only; activity persistence is a future story.',
      ),
      SemesterMetricDefinition(
        key: 'spo2',
        type: 'SpO2',
        unit: '%',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: not collected from this source in app flow.',
      ),
      SemesterMetricDefinition(
        key: 'blood_glucose',
        type: 'Blood Glucose',
        unit: 'mg/dL',
        mappedToPersistedEntity: false,
        availableFromCurrentSource: false,
        note: 'Outside semester scope; shown as placeholder only.',
      ),
    ],
    'google_fit': [
      SemesterMetricDefinition(
        key: 'steps',
        type: 'Steps',
        unit: 'steps',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(STEPS).',
      ),
      SemesterMetricDefinition(
        key: 'heart_rate',
        type: 'Heart Rate',
        unit: 'bpm',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(HEART_RATE).',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_systolic',
        type: 'Blood Pressure (Systolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(BLOOD_PRESSURE_SYS).',
      ),
      SemesterMetricDefinition(
        key: 'blood_pressure_diastolic',
        type: 'Blood Pressure (Diastolic)',
        unit: 'mmHg',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: true,
        note: 'Mapped to wearable_metric(BLOOD_PRESSURE_DIA).',
      ),
      SemesterMetricDefinition(
        key: 'calories',
        type: 'Activity (Calories)',
        unit: 'cal',
        mappedToPersistedEntity: false,
        availableFromCurrentSource: true,
        note: 'UI demo only; activity persistence is a future story.',
      ),
      SemesterMetricDefinition(
        key: 'spo2',
        type: 'SpO2',
        unit: '%',
        mappedToPersistedEntity: true,
        availableFromCurrentSource: false,
        note: 'Placeholder: not collected from this source in app flow.',
      ),
      SemesterMetricDefinition(
        key: 'blood_glucose',
        type: 'Blood Glucose',
        unit: 'mg/dL',
        mappedToPersistedEntity: false,
        availableFromCurrentSource: false,
        note: 'Outside semester scope; shown as placeholder only.',
      ),
    ],
  };

  // Fitbit configuration
  static const String fitbitClientId = '23QG9C';
  static const String fitbitClientSecret = 'c77f0a7a3839a9307674b893fae14934';

  @override
  void initState() {
    super.initState();
    _loadConnectedDevices();
    _fetchLatestHealthData();
  }

  Future<void> _loadConnectedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesString = prefs.getString('connected_devices');

      if (devicesString != null) {
        final List<dynamic> devicesJson = jsonDecode(devicesString);
        setState(() {
          connectedDevices = devicesJson
              .map((json) => ConnectedDevice.fromJson(json))
              .where((device) => device.isActive)
              .toList();
        });
        print('✓ Loaded ${connectedDevices.length} connected devices');
      }
    } catch (e) {
      print('✗ Failed to load devices: $e');
    }
  }

  Future<void> _fetchLatestHealthData() async {
    if (connectedDevices.isEmpty) return;

    setState(() {
      isLoadingData = true;
    });

    try {
      DateTime now = DateTime.now();
      DateTime yesterday = now.subtract(const Duration(days: 1));

      // Fetch Fitbit data
      await _fetchFitbitData(yesterday, now);

      // Fetch Google Health/Apple Health data
      await _fetchGoogleAppleHealthData(yesterday, now);

      print('✓ Fetched health data: ${latestHealthData.length} metrics');
    } catch (e) {
      print('✗ Error fetching health data: $e');
    } finally {
      setState(() {
        isLoadingData = false;
      });
    }
  }

  Future<void> _fetchFitbitData(DateTime startTime, DateTime endTime) async {
    bool hasFitbitDevice =
        connectedDevices.any((device) => device.platform == 'fitbit');
    if (!hasFitbitDevice) return;

    try {
      String? accessToken =
          await _secureStorage.read(key: 'fitbit_access_token');
      String? userID = await _secureStorage.read(key: 'fitbit_user_id');

      if (accessToken == null) {
        _setDefaultFitbitData();
        return;
      }

      userID ??= '-';

      FitbitCredentials fitbitCredentials = FitbitCredentials(
        userID: userID,
        fitbitAccessToken: accessToken,
        fitbitRefreshToken: '',
      );

      DateTime today = DateTime.now();

      // Fetch Steps
      await _fetchFitbitSteps(fitbitCredentials, today);

      // Fetch Calories
      await _fetchFitbitCalories(fitbitCredentials, today);
    } catch (e) {
      _setDefaultFitbitData();
    }
  }

  Future<void> _fetchFitbitSteps(
      FitbitCredentials credentials, DateTime date) async {
    try {
      FitbitActivityTimeseriesDataManager stepsManager =
          FitbitActivityTimeseriesDataManager(
        clientID: fitbitClientId,
        clientSecret: fitbitClientSecret,
      );

      final stepsData = await stepsManager
          .fetch(FitbitActivityTimeseriesAPIURL.dayWithResource(
        date: date,
        resource: Resource.steps,
        fitbitCredentials: credentials,
      ));

      List<dynamic> dataList = stepsData;
      if (dataList.isNotEmpty) {
        var latestData = dataList.last;
        double finalValue = _extractFitbitValue(latestData);
        DateTime dataDate = _extractFitbitDate(latestData);

        setState(() {
          latestHealthData['steps'] = _healthDataFromDefinition(
            key: 'steps',
            source: 'Fitbit',
            value: finalValue,
            date: dataDate,
          );
        });
      }
    } catch (e) {
      _setDefaultValue('steps', 'Fitbit',
          reason: 'No Fitbit steps data available.');
    }
  }

  Future<void> _fetchFitbitCalories(
      FitbitCredentials credentials, DateTime date) async {
    try {
      FitbitActivityTimeseriesDataManager caloriesManager =
          FitbitActivityTimeseriesDataManager(
        clientID: fitbitClientId,
        clientSecret: fitbitClientSecret,
      );

      final caloriesData = await caloriesManager
          .fetch(FitbitActivityTimeseriesAPIURL.dayWithResource(
        date: date,
        resource: Resource.calories,
        fitbitCredentials: credentials,
      ));

      List<dynamic> dataList = caloriesData;
      if (dataList.isNotEmpty) {
        var latestData = dataList.last;
        double finalValue = _extractFitbitValue(latestData);
        DateTime dataDate = _extractFitbitDate(latestData);

        setState(() {
          latestHealthData['calories'] = _healthDataFromDefinition(
            key: 'calories',
            source: 'Fitbit',
            value: finalValue,
            date: dataDate,
          );
        });
      }
    } catch (e) {
      _setDefaultValue('calories', 'Fitbit',
          reason: 'Activity is demo-only this semester.');
    }
  }

  double _extractFitbitValue(dynamic data) {
    dynamic value = 0;
    if (data is FitbitActivityTimeseriesData) {
      value = data.value;
    } else if (data is Map) {
      value = data['value'] ?? 0;
    }

    try {
      if (value is String) {
        return double.parse(value);
      } else if (value is num) {
        return value.toDouble();
      }
    } catch (e) {
      return 0;
    }
    return 0;
  }

  DateTime _extractFitbitDate(dynamic data) {
    if (data is FitbitActivityTimeseriesData) {
      return data.dateOfMonitoring ?? DateTime.now();
    } else if (data is Map && data['dateTime'] != null) {
      try {
        return DateTime.parse(data['dateTime']);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  String _sourceLabelForPlatform(String platform) {
    switch (platform) {
      case 'fitbit':
        return 'Fitbit';
      case 'apple_health':
        return 'Apple Health';
      case 'google_fit':
      default:
        return 'Health Connect';
    }
  }

  SemesterMetricDefinition? _metricDefinitionFor(String source, String key) {
    final platform = source == 'Apple Health'
        ? 'apple_health'
        : source == 'Fitbit'
            ? 'fitbit'
            : 'google_fit';
    final sourceMetrics = _semesterSourceMetricMatrix[platform] ?? const [];
    for (final metric in sourceMetrics) {
      if (metric.key == key) {
        return metric;
      }
    }
    return null;
  }

  String _supportStatusFor(
      SemesterMetricDefinition? definition, bool isPlaceholder) {
    if (definition == null) {
      return isPlaceholder ? 'Placeholder' : 'Persisted Mapping';
    }
    if (isPlaceholder || !definition.availableFromCurrentSource) {
      return 'Placeholder';
    }
    return definition.mappedToPersistedEntity ? 'Persisted Mapping' : 'UI Only';
  }

  HealthData _healthDataFromDefinition({
    required String key,
    required String source,
    required double value,
    required DateTime date,
    bool isPlaceholder = false,
    String? placeholderReason,
  }) {
    final definition = _metricDefinitionFor(source, key);
    return HealthData(
      type: definition?.type ?? key,
      value: value,
      unit: definition?.unit ?? '',
      date: date,
      source: source,
      isPlaceholder: isPlaceholder,
      supportStatus: _supportStatusFor(definition, isPlaceholder),
      placeholderReason:
          placeholderReason ?? (isPlaceholder ? definition?.note : null),
    );
  }

  void _setDefaultValue(String key, String source, {String? reason}) {
    setState(() {
      latestHealthData[key] = _healthDataFromDefinition(
        key: key,
        source: source,
        value: 0,
        date: DateTime.now(),
        isPlaceholder: true,
        placeholderReason: reason,
      );
    });
  }

  void _setDefaultFitbitData() {
    _setDefaultValue('steps', 'Fitbit',
        reason: 'No Fitbit steps data available.');
    _setDefaultValue('calories', 'Fitbit',
        reason: 'Activity is demo-only this semester.');
    _setDefaultValue('heart_rate', 'Fitbit',
        reason: 'Fitbit heart-rate sync is a placeholder this semester.');
  }

  Future<void> _fetchGoogleAppleHealthData(
      DateTime startTime, DateTime endTime) async {
    bool hasHealthDevice = connectedDevices.any((device) =>
        device.platform == 'google_fit' || device.platform == 'apple_health');

    if (!hasHealthDevice) return;

    try {
      Health health = Health();
      await health.configure();

      String source =
          connectedDevices.any((device) => device.platform == 'apple_health')
              ? 'Apple Health'
              : 'Health Connect';

      List<HealthDataType> types = [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
        HealthDataType.BLOOD_GLUCOSE,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      ];

      // Fetch all health data types at once
      List<HealthDataPoint> allHealthData = await health.getHealthDataFromTypes(
        startTime: startTime,
        endTime: endTime,
        types: types,
      );

      // Process each type of health data
      await _processHealthDataByType(allHealthData, source);
    } catch (e) {
      print('⚠ Health data fetch failed: $e');
      _setDefaultHealthData();
    }
  }

  Future<void> _processHealthDataByType(
      List<HealthDataPoint> allHealthData, String source) async {
    // Group data by type
    Map<HealthDataType, List<HealthDataPoint>> groupedData = {};
    for (var point in allHealthData) {
      if (!groupedData.containsKey(point.type)) {
        groupedData[point.type] = [];
      }
      groupedData[point.type]!.add(point);
    }

    // Process Steps
    if (groupedData.containsKey(HealthDataType.STEPS)) {
      int totalSteps = groupedData[HealthDataType.STEPS]!
          .fold(0, (sum, point) => sum + (point.value as num).toInt());

      setState(() {
        latestHealthData['steps'] = _healthDataFromDefinition(
          key: 'steps',
          source: source,
          value: totalSteps.toDouble(),
          date: DateTime.now(),
        );
      });
    }

    // Process Calories (Active Energy Burned)
    if (groupedData.containsKey(HealthDataType.ACTIVE_ENERGY_BURNED)) {
      double totalCalories = groupedData[HealthDataType.ACTIVE_ENERGY_BURNED]!
          .fold(0.0, (sum, point) => sum + (point.value as num).toDouble());

      setState(() {
        latestHealthData['calories'] = _healthDataFromDefinition(
          key: 'calories',
          source: source,
          value: totalCalories,
          date: DateTime.now(),
        );
      });
    }

    // Process Heart Rate (get latest reading)
    if (groupedData.containsKey(HealthDataType.HEART_RATE)) {
      var heartRateData = groupedData[HealthDataType.HEART_RATE]!;
      if (heartRateData.isNotEmpty) {
        // Get the most recent heart rate reading
        heartRateData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        var latestHR = heartRateData.first;

        setState(() {
          latestHealthData['heart_rate'] = _healthDataFromDefinition(
            key: 'heart_rate',
            source: source,
            value: (latestHR.value as num).toDouble(),
            date: latestHR.dateFrom,
          );
        });
      }
    }

    // Process Blood Glucose (get latest reading)
    if (groupedData.containsKey(HealthDataType.BLOOD_GLUCOSE)) {
      var glucoseData = groupedData[HealthDataType.BLOOD_GLUCOSE]!;
      if (glucoseData.isNotEmpty) {
        glucoseData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        var latestGlucose = glucoseData.first;

        setState(() {
          latestHealthData['blood_glucose'] = _healthDataFromDefinition(
            key: 'blood_glucose',
            source: source,
            value: (latestGlucose.value as num).toDouble(),
            date: latestGlucose.dateFrom,
            isPlaceholder: true,
            placeholderReason:
                'Blood glucose is outside semester scope for persisted metrics.',
          );
        });
      }
    }

    // Process Blood Pressure Diastolic (get latest reading)
    if (groupedData.containsKey(HealthDataType.BLOOD_PRESSURE_DIASTOLIC)) {
      var diastolicData = groupedData[HealthDataType.BLOOD_PRESSURE_DIASTOLIC]!;
      if (diastolicData.isNotEmpty) {
        diastolicData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        var latestDiastolic = diastolicData.first;

        setState(() {
          latestHealthData['blood_pressure_diastolic'] =
              _healthDataFromDefinition(
            key: 'blood_pressure_diastolic',
            source: source,
            value: (latestDiastolic.value as num).toDouble(),
            date: latestDiastolic.dateFrom,
          );
        });
      }
    }

    // Process Blood Pressure Systolic (get latest reading)
    if (groupedData.containsKey(HealthDataType.BLOOD_PRESSURE_SYSTOLIC)) {
      var systolicData = groupedData[HealthDataType.BLOOD_PRESSURE_SYSTOLIC]!;
      if (systolicData.isNotEmpty) {
        systolicData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
        var latestSystolic = systolicData.first;

        setState(() {
          latestHealthData['blood_pressure_systolic'] =
              _healthDataFromDefinition(
            key: 'blood_pressure_systolic',
            source: source,
            value: (latestSystolic.value as num).toDouble(),
            date: latestSystolic.dateFrom,
          );
        });
      }
    }

    // Set default values for any missing data
    _setDefaultHealthData(source);
  }

  void _setDefaultHealthData([String? source]) {
    String defaultSource = source ??
        (connectedDevices.any((device) => device.platform == 'apple_health')
            ? 'Apple Health'
            : 'Health Connect');

    final platform =
        defaultSource == 'Apple Health' ? 'apple_health' : 'google_fit';
    final defaultMetrics = _semesterSourceMetricMatrix[platform] ?? const [];

    for (final metric in defaultMetrics) {
      if (!latestHealthData.containsKey(metric.key)) {
        _setDefaultValue(metric.key, defaultSource, reason: metric.note);
      }
    }
  }

  // Get appropriate icon for health data type
  IconData _getHealthDataIcon(String type) {
    switch (type.toLowerCase()) {
      case 'steps':
        return Icons.directions_walk;
      case 'calories':
        return Icons.local_fire_department;
      case 'heart rate':
        return Icons.favorite;
      case 'blood glucose':
        return Icons.water_drop;
      case 'blood pressure (diastolic)':
      case 'blood pressure (systolic)':
        return Icons.monitor_heart;
      case 'body fat percentage':
        return Icons.accessibility;
      default:
        return Icons.health_and_safety;
    }
  }

  // Get appropriate color for health data type
  Color _getHealthDataColor(String type) {
    switch (type.toLowerCase()) {
      case 'steps':
        return Colors.blue;
      case 'calories':
        return Colors.orange;
      case 'heart rate':
        return Colors.red;
      case 'blood glucose':
        return Colors.purple;
      case 'blood pressure (diastolic)':
      case 'blood pressure (systolic)':
        return Colors.indigo;
      case 'body fat percentage':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _refreshData() async {
    await _loadConnectedDevices();
    await _fetchLatestHealthData();
  }

  Future<void> _removeDevice(ConnectedDevice device) async {
    try {
      bool? shouldRemove = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Remove Device'),
            content: Text('Are you sure you want to remove ${device.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child:
                    const Text('Remove', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (shouldRemove == true) {
        setState(() {
          connectedDevices.removeWhere((d) => d.id == device.id);
        });

        await _saveConnectedDevicesToStorage();
        await _secureStorage.delete(key: '${device.platform}_access_token');

        if (connectedDevices.isEmpty ||
            !connectedDevices.any((d) =>
                d.platform == 'google_fit' ||
                d.platform == 'apple_health' ||
                d.platform == 'fitbit')) {
          setState(() {
            latestHealthData.clear();
          });
        } else {
          await _fetchLatestHealthData();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device.name} has been removed'),
              backgroundColor: Colors.green,
            ),
          );
        }

        print('✓ Removed device: ${device.name}');
      }
    } catch (e) {
      print('✗ Failed to remove device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveConnectedDevicesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final devicesJson =
          connectedDevices.map((device) => device.toJson()).toList();
      await prefs.setString('connected_devices', jsonEncode(devicesJson));
      print('✓ Saved ${connectedDevices.length} connected devices');
    } catch (e) {
      print('✗ Failed to save devices: $e');
    }
  }

  List<Widget> get supportedDeviceWidgets {
    List<Map<String, dynamic>> devices = [
      {
        'icon': Icons.fitness_center,
        'name': 'Fitbit',
        'color': Colors.green,
      },
    ];

    if (!kIsWeb && Platform.isIOS) {
      devices.add({
        'icon': Icons.favorite,
        'name': 'Apple Health',
        'color': Colors.red,
      });
    }

    if (!kIsWeb && Platform.isAndroid) {
      devices.add({
        'icon': Icons.directions_run,
        'name': 'Google Fit',
        'color': Colors.blue,
      });
    }

    return devices
        .map((device) => _buildSupportedDevice(
              icon: device['icon'],
              name: device['name'],
              color: device['color'],
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/wearables'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Wearables',
        centerTitle: true,
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _navigateToAddDevice,
          ),
        ],
      ),
      body: connectedDevices.isEmpty
          ? _buildEmptyState()
          : _buildConnectedDevicesView(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.watch,
              size: 60,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Wearables Connected',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect wearable devices to track your patient\'s health data in real-time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                _navigateToAddDevice();
              },
              icon: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                'Add Your First Device',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Supported Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 20,
                    children: supportedDeviceWidgets,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedDevice({
    required IconData icon,
    required String name,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildConnectedDevicesView() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connected Devices',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${connectedDevices.length} device${connectedDevices.length == 1 ? '' : 's'} connected',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _navigateToAddDevice,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Device'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSemesterScopeCard(),
            const SizedBox(height: 20),
            if (latestHealthData.isNotEmpty) ...[
              const Text(
                'Latest Health Data',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),
              if (isLoadingData)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                _buildHealthDataCards(),
              const SizedBox(height: 20),
            ],
            const Text(
              'Your Devices',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 12),
            ...connectedDevices.map((device) => _buildDeviceCard(device)),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterScopeCard() {
    final connectedPlatforms = connectedDevices.map((d) => d.platform).toSet();
    final visiblePlatforms = connectedPlatforms.isEmpty
        ? {
            'fitbit',
            if (!kIsWeb && Platform.isIOS) 'apple_health',
            if (!kIsWeb && Platform.isAndroid) 'google_fit'
          }
        : connectedPlatforms;

    final rows = <Widget>[];
    for (final platform in visiblePlatforms) {
      final metrics = _semesterSourceMetricMatrix[platform] ?? const [];
      final sourceLabel = _sourceLabelForPlatform(platform);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sourceLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: metrics.map((metric) {
                  final bool isPlaceholder =
                      !metric.availableFromCurrentSource ||
                          !metric.mappedToPersistedEntity;
                  final Color chipColor =
                      isPlaceholder ? Colors.orange : Colors.green;
                  final String status = metric.mappedToPersistedEntity &&
                          metric.availableFromCurrentSource
                      ? 'Persisted'
                      : 'Placeholder';
                  return Chip(
                    label: Text('${metric.type} ($status)'),
                    backgroundColor: chipColor.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: isPlaceholder
                          ? Colors.orange.shade900
                          : Colors.green.shade900,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Semester Metric Scope',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Persisted = mapped to backend entities. Placeholder = UI-only demo or not wired this semester.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _buildHealthDataCards() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Health Metrics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  children: latestHealthData.values
                      .map((data) => _buildHealthDataItem(data))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthDataItem(HealthData data) {
    IconData dataIcon = _getHealthDataIcon(data.type);
    Color dataColor = _getHealthDataColor(data.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: dataColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              dataIcon,
              color: dataColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        data.type,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color:
                            _getSourceColor(data.source).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.source,
                        style: TextStyle(
                          fontSize: 9,
                          color: _getSourceColor(data.source),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: data.isPlaceholder
                            ? Colors.orange.withValues(alpha: 0.12)
                            : Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data.supportStatus,
                        style: TextStyle(
                          fontSize: 9,
                          color: data.isPlaceholder
                              ? Colors.orange.shade900
                              : Colors.green.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Updated: ${_formatDate(data.date)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data.isPlaceholder
                    ? '---'
                    : _formatHealthValue(data.value, data.type),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              Text(
                data.isPlaceholder ? data.supportStatus : data.unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              if (data.isPlaceholder && data.placeholderReason != null)
                SizedBox(
                  width: 140,
                  child: Text(
                    data.placeholderReason!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatHealthValue(double value, String type) {
    if (type.toLowerCase().contains('percentage')) {
      return value.toStringAsFixed(1);
    } else if (type.toLowerCase().contains('glucose') ||
        type.toLowerCase().contains('pressure')) {
      return value.toStringAsFixed(0);
    } else {
      return value.toInt().toString();
    }
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 'Fitbit':
        return Colors.green;
      case 'Apple Health':
        return Colors.red;
      case 'Health Connect':
      default:
        return Colors.blue;
    }
  }

  Widget _buildDeviceCard(ConnectedDevice device) {
    IconData deviceIcon;
    Color deviceColor;

    switch (device.platform) {
      case 'google_fit':
        deviceIcon = Icons.directions_run;
        deviceColor = Colors.blue;
        break;
      case 'apple_health':
        deviceIcon = Icons.favorite;
        deviceColor = Colors.red;
        break;
      case 'fitbit':
        deviceIcon = Icons.fitness_center;
        deviceColor = Colors.green;
        break;
      default:
        deviceIcon = Icons.watch;
        deviceColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: deviceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                deviceIcon,
                color: deviceColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connected ${_formatDate(device.connectedAt)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${device.permissions.length} permission${device.permissions.length == 1 ? '' : 's'} granted',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _removeDevice(device),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  void _navigateToAddDevice() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddDeviceScreen(),
      ),
    );

    if (result == true) {
      await _refreshData();
    }
  }
}
