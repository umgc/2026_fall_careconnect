import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_service.dart' as auth_service;
import 'package:care_connect_app/services/user_role_storage_service.dart';
import 'package:care_connect_app/services/google_health/google_health_api_service.dart';
import 'package:care_connect_app/services/google_health/google_health_auth_service.dart';
import 'package:care_connect_app/services/google_health/google_health_config.dart';
import 'package:care_connect_app/config/env_constant.dart';

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

class _IngestReading {
  final String metric;
  final double metricValue;
  final DateTime recordedAt;
  final String source;

  _IngestReading({
    required this.metric,
    required this.metricValue,
    required this.recordedAt,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'metricValue': metricValue,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'source': source,
      };
}

class WearablesScreen extends StatefulWidget {
  final String? googleHealthStatus;
  final String? googleHealthError;

  const WearablesScreen({
    super.key,
    this.googleHealthStatus,
    this.googleHealthError,
  });

  @override
  State<WearablesScreen> createState() => _WearablesScreenState();
}

class _WearablesScreenState extends State<WearablesScreen> {
  List<ConnectedDevice> connectedDevices = [];
  Map<String, HealthData> latestHealthData = {};
  bool isLoadingData = false;
  bool hasSyncError = false;
  String? syncStatusMessage;
  int _lastCollectedCount = 0;
  int _lastAcceptedCount = 0;
  int _lastRejectedCount = 0;
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

  // Fitbit now connects through Google Health OAuth (not legacy Fitbit Web API).
  GoogleHealthAuthService? _googleHealthAuth;
  GoogleHealthApiService? _googleHealthApi;

  GoogleHealthAuthService? _tryGoogleAuth() {
    if (!GoogleHealthConfig.isEnvironmentConfigured) return null;
    return _googleHealthAuth ??= GoogleHealthAuthService();
  }

  GoogleHealthApiService? _tryGoogleApi() {
    final auth = _tryGoogleAuth();
    if (auth == null) return null;
    return _googleHealthApi ??= GoogleHealthApiService(authService: auth);
  }

  @override
  void initState() {
    super.initState();
    _initializeWearables();
  }

  Future<void> _initializeWearables() async {
    await _loadConnectedDevices();
    await _handleGoogleHealthReturnParams();
    await _fetchLatestHealthData();
  }

  Future<void> _handleGoogleHealthReturnParams() async {
    final error = widget.googleHealthError;
    final status = widget.googleHealthStatus;
    if (error == null && status == null) return;
    if (!mounted) return;

    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Health connection failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (status == 'connected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fitbit connected via Google Health'),
          backgroundColor: Colors.green,
        ),
      );
    }
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

      // Tokens live on the backend for both web and native (Option A).
      await _syncBackendGoogleHealthConnection(prefs);
    } catch (e) {
      print('✗ Failed to load devices: $e');
    }
  }

  Future<void> _syncBackendGoogleHealthConnection(
    SharedPreferences prefs,
  ) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final response = await http.get(
        Uri.parse(
            '${getBackendBaseUrl()}/v1/api/wearables/google-health/status'),
        headers: authHeaders,
      );
      if (response.statusCode != 200) {
        return;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final connected = payload['connected'] == true;
      const devicePrefix = 'google_health_';
      final hasAnyFitbit =
          connectedDevices.any((device) => device.platform == 'fitbit');

      bool changed = false;
      if (connected && !hasAnyFitbit) {
        connectedDevices.add(
          ConnectedDevice(
            id: '${devicePrefix}${DateTime.now().millisecondsSinceEpoch}',
            platform: 'fitbit',
            name: 'Fitbit (Google Health)',
            connectedAt: DateTime.now(),
            permissions: const [
              'steps',
              'heart_rate',
              'sleep',
              'activity',
            ],
          ),
        );
        changed = true;
      } else if (!connected) {
        final before = connectedDevices.length;
        connectedDevices.removeWhere((device) => device.platform == 'fitbit');
        changed = connectedDevices.length != before;
      }

      if (changed) {
        setState(() {});
        final devicesJson =
            connectedDevices.map((device) => device.toJson()).toList();
        await prefs.setString('connected_devices', jsonEncode(devicesJson));
      }
    } catch (_) {
      // Status sync is best-effort and should not block screen rendering.
    }
  }

  Future<void> _fetchLatestHealthData() async {
    if (connectedDevices.isEmpty) return;

    setState(() {
      isLoadingData = true;
      hasSyncError = false;
      syncStatusMessage = null;
      _lastCollectedCount = 0;
      _lastAcceptedCount = 0;
      _lastRejectedCount = 0;
    });

    try {
      final patientId = await _resolvePatientId();
      if (patientId == null) {
        setState(() {
          latestHealthData.clear();
          hasSyncError = false;
          syncStatusMessage =
              'Select a patient first (Analytics patient dropdown), then tap refresh.';
        });
        return;
      }

      DateTime now = DateTime.now();
      // Use a wider window so recently-added manual Apple Health samples
      // are not excluded by timestamp granularity differences.
      DateTime recentWindowStart = now.subtract(const Duration(days: 7));

      final readings = <_IngestReading>[];
      await _collectFitbitReadings(readings, recentWindowStart, now);
      await _collectGoogleAppleReadings(readings, recentWindowStart, now);
      setState(() {
        _lastCollectedCount = readings.length;
      });

      final acceptedReadings =
          await _ingestReadings(patientId: patientId, readings: readings);
      final hasPersistedData =
          await _loadPersistedReadings(patientId: patientId);
      // Always merge freshly accepted readings so STEPS (wearable_metric-only)
      // still appear even when vital_sample rows already exist.
      if (acceptedReadings.isNotEmpty) {
        _mergeAcceptedIngestionSnapshot(acceptedReadings);
      } else if (!hasPersistedData && readings.isEmpty) {
        setState(() {
          syncStatusMessage =
              'No Google Health / Fitbit samples were collected in the last 7 days. '
              'Debug: collected=$_lastCollectedCount accepted=$_lastAcceptedCount rejected=$_lastRejectedCount';
        });
      }
    } catch (e) {
      setState(() {
        hasSyncError = true;
        syncStatusMessage = 'Failed to synchronize wearable data: $e';
      });
      print('✗ Error syncing wearable health data: $e');
    } finally {
      setState(() {
        isLoadingData = false;
      });
    }
  }

  Future<int?> _resolvePatientId() async {
    final selectedPatientId =
        await UserRoleStorageService.instance.getPatientId();
    if (selectedPatientId != null) {
      return selectedPatientId;
    }

    final session = await auth_service.AuthService.getCurrentUser();
    if (session == null) return null;

    if (session.patientId != null) {
      return session.patientId;
    }

    if (session.isCaregiver && session.caregiverId != null) {
      return await _resolveSingleLinkedPatientId(session.caregiverId!);
    }

    return null;
  }

  Future<int?> _resolveSingleLinkedPatientId(int caregiverId) async {
    try {
      final response = await ApiService.getCaregiverPatients(caregiverId);
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return null;
      }

      final linkedPatientIds = decoded
          .map<int?>((item) {
            if (item is! Map<String, dynamic>) return null;
            final patient = item['patient'];
            if (patient is! Map<String, dynamic>) return null;
            final patientId = patient['id'];
            if (patientId is int) return patientId;
            if (patientId is String) return int.tryParse(patientId);
            return null;
          })
          .whereType<int>()
          .toSet()
          .toList();

      // Auto-select only when unambiguous.
      if (linkedPatientIds.length == 1) {
        final autoResolved = linkedPatientIds.first;
        await UserRoleStorageService.instance.updatePatientId(autoResolved);
        return autoResolved;
      }
    } catch (_) {
      // Ignore and fall back to explicit patient selection guidance.
    }
    return null;
  }

  Future<void> _collectFitbitReadings(
    List<_IngestReading> readings,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final hasFitbitDevice =
        connectedDevices.any((device) => device.platform == 'fitbit');
    if (!hasFitbitDevice) return;

    // Prefer backend-proxied Google Health (tokens stored server-side).
    final startIso = startTime.toUtc().toIso8601String();
    final endIso = endTime.toUtc().toIso8601String();
    var added = 0;

    added += await _appendGoogleHealthDataType(
      readings: readings,
      dataType: 'steps',
      defaultMetric: 'STEPS',
      filter:
          'steps.interval.start_time >= "$startIso" AND steps.interval.start_time < "$endIso"',
      fallbackRecordedAt: endTime,
      windowStart: startTime,
      windowEnd: endTime,
    );
    added += await _appendGoogleHealthDataType(
      readings: readings,
      dataType: 'heart-rate',
      defaultMetric: 'HEART_RATE',
      filter:
          'heartRate.interval.start_time >= "$startIso" AND heartRate.interval.start_time < "$endIso"',
      fallbackRecordedAt: endTime,
      windowStart: startTime,
      windowEnd: endTime,
    );

    if (added > 0) return;

    // Optional local AppAuth fallback if dart-defines are configured.
    final auth = _tryGoogleAuth();
    final api = _tryGoogleApi();
    if (auth != null && api != null && await auth.isConnected()) {
      try {
        final heartRate = await api.fetchHeartRate(pageSize: 100);
        for (final point in _extractGoogleHealthPoints(heartRate)) {
          final value = point.value;
          if (value == null || value <= 0) continue;
          readings.add(
            _IngestReading(
              metric: point.metric ?? 'HEART_RATE',
              metricValue: value,
              recordedAt: point.recordedAt ?? endTime,
              source: 'fitbit',
            ),
          );
        }

        final steps = await api.fetchSteps(pageSize: 100);
        for (final point in _extractGoogleHealthPoints(steps)) {
          final value = point.value;
          if (value == null || value <= 0) continue;
          readings.add(
            _IngestReading(
              metric: point.metric ?? 'STEPS',
              metricValue: value,
              recordedAt: point.recordedAt ?? endTime,
              source: 'fitbit',
            ),
          );
        }
        return;
      } catch (e) {
        print('⚠ Local Google Health Fitbit reading collection failed: $e');
      }
    }

    print(
      '⚠ No Google Health steps/heart-rate points returned for Fitbit. '
      'Reconnect Fitbit after granting activity + health-metrics scopes.',
    );
  }

  Future<int> _appendGoogleHealthDataType({
    required List<_IngestReading> readings,
    required String dataType,
    required String defaultMetric,
    required String filter,
    required DateTime fallbackRecordedAt,
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    var added = await _fetchGoogleHealthDataType(
      readings: readings,
      dataType: dataType,
      defaultMetric: defaultMetric,
      filter: filter,
      fallbackRecordedAt: fallbackRecordedAt,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
    // Some Google Health responses reject/ignore filters; retry unfiltered
    // and keep only points inside the local sync window.
    if (added == 0) {
      added = await _fetchGoogleHealthDataType(
        readings: readings,
        dataType: dataType,
        defaultMetric: defaultMetric,
        filter: null,
        fallbackRecordedAt: fallbackRecordedAt,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
    }
    return added;
  }

  Future<int> _fetchGoogleHealthDataType({
    required List<_IngestReading> readings,
    required String dataType,
    required String defaultMetric,
    required String? filter,
    required DateTime fallbackRecordedAt,
    DateTime? windowStart,
    DateTime? windowEnd,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final query = <String, String>{'pageSize': '100'};
      if (filter != null && filter.isNotEmpty) {
        query['filter'] = filter;
      }
      final uri = Uri.parse(
        '${getBackendBaseUrl()}/v1/api/wearables/google-health/data-types/$dataType/data-points',
      ).replace(queryParameters: query);
      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode != 200) {
        print(
          '⚠ Google Health $dataType fetch failed '
          '(${response.statusCode}): ${response.body}',
        );
        return 0;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final nested = payload['data'];
      final map =
          nested is Map ? Map<String, dynamic>.from(nested) : payload;
      var added = 0;
      for (final point in _extractGoogleHealthPoints(map)) {
        final value = point.value;
        if (value == null || value <= 0) continue;
        final recordedAt = point.recordedAt ?? fallbackRecordedAt;
        if (windowStart != null && recordedAt.isBefore(windowStart)) continue;
        if (windowEnd != null && recordedAt.isAfter(windowEnd)) continue;
        readings.add(
          _IngestReading(
            metric: point.metric ?? defaultMetric,
            metricValue: value,
            recordedAt: recordedAt,
            source: 'fitbit',
          ),
        );
        added++;
      }
      return added;
    } catch (e) {
      print('⚠ Backend Google Health $dataType fetch failed: $e');
      return 0;
    }
  }

  List<({double? value, DateTime? recordedAt, String? metric})>
      _extractGoogleHealthPoints(
    Map<String, dynamic> payload,
  ) {
    final rawPoints = payload['dataPoints'] ?? payload['data'];
    if (rawPoints is! List) return const [];

    final results = <({double? value, DateTime? recordedAt, String? metric})>[];
    for (final item in rawPoints) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      double? value;
      String? metric;
      final heartRate = map['heartRate'] ?? map['heart_rate'];
      if (heartRate is Map) {
        final bpm = heartRate['bpm'] ?? heartRate['value'];
        if (bpm != null) {
          value = double.tryParse(bpm.toString());
          metric = 'HEART_RATE';
        }
      }
      final steps = map['steps'];
      if (value == null && steps is Map) {
        final count = steps['count'] ?? steps['value'];
        if (count != null) {
          value = double.tryParse(count.toString());
          metric = 'STEPS';
        }
      }
      if (value == null) {
        final bpm = _deepFindFirstNumber(map, const ['bpm']);
        if (bpm != null) {
          value = bpm;
          metric = 'HEART_RATE';
        }
      }
      if (value == null) {
        final count = _deepFindFirstNumber(map, const ['count']);
        if (count != null) {
          value = count;
          metric = 'STEPS';
        }
      }
      value ??= _deepFindFirstNumber(map, const [
        'value',
        'numericValue',
      ]);

      DateTime? recordedAt;
      final nestedInterval = heartRate is Map
          ? heartRate['interval']
          : (steps is Map ? steps['interval'] : null);
      final interval = map['interval'] ?? nestedInterval;
      final startTime = map['startTime']?.toString() ??
          map['start_time']?.toString() ??
          (interval is Map
              ? (interval['startTime'] ?? interval['start_time'])?.toString()
              : null);
      if (startTime != null) {
        recordedAt = DateTime.tryParse(startTime)?.toLocal();
      }

      results.add((value: value, recordedAt: recordedAt, metric: metric));
    }
    return results;
  }

  double? _deepFindFirstNumber(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) {
        final parsed = double.tryParse(map[key].toString());
        if (parsed != null) return parsed;
      }
    }
    for (final value in map.values) {
      if (value is Map) {
        final nested =
            _deepFindFirstNumber(Map<String, dynamic>.from(value), keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<void> _collectHealthReadingsFromPlugin({
    required List<_IngestReading> readings,
    required DateTime startTime,
    required DateTime endTime,
    required String source,
  }) async {
    try {
      final health = Health();
      await health.configure();

      final List<HealthDataType> types = [
        HealthDataType.STEPS,
        HealthDataType.HEART_RATE,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      ];

      final bool hasReadAccess = await health.requestAuthorization(
        types,
        permissions: types.map((type) => HealthDataAccess.READ).toList(),
      );
      if (!hasReadAccess) {
        return;
      }

      final List<HealthDataPoint> allHealthData =
          await health.getHealthDataFromTypes(
        startTime: startTime,
        endTime: endTime,
        types: types,
      );

      for (final point in allHealthData) {
        final mappedMetric = _mapHealthTypeToBackendMetric(point.type);
        if (mappedMetric == null) continue;
        final value = _safeHealthValue(point.value);
        if (value == null || value <= 0) continue;
        readings.add(
          _IngestReading(
            metric: mappedMetric,
            metricValue: value,
            recordedAt: point.dateFrom,
            source: source,
          ),
        );
      }
    } catch (e) {
      print('⚠ Plugin health fallback collection failed for $source: $e');
    }
  }

  Future<void> _collectGoogleAppleReadings(
    List<_IngestReading> readings,
    DateTime startTime,
    DateTime endTime,
  ) async {
    bool hasHealthDevice = connectedDevices.any((device) =>
        device.platform == 'google_fit' || device.platform == 'apple_health');

    if (!hasHealthDevice) return;

    try {
      Health health = Health();
      await health.configure();

      final source =
          connectedDevices.any((device) => device.platform == 'apple_health')
              ? 'apple_health'
              : 'google_fit';

      List<HealthDataType> types = [
        HealthDataType.STEPS,
        HealthDataType.HEART_RATE,
        HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      ];

      // Re-check authorization before reading; on iOS this can avoid silent empty reads.
      final bool hasReadAccess = await health.requestAuthorization(
        types,
        permissions: types.map((type) => HealthDataAccess.READ).toList(),
      );
      if (!hasReadAccess) {
        setState(() {
          syncStatusMessage =
              'Apple Health access was denied. Enable Steps/Heart Rate/Blood Pressure in Health app.';
        });
        return;
      }

      List<HealthDataPoint> allHealthData = await health.getHealthDataFromTypes(
        startTime: startTime,
        endTime: endTime,
        types: types,
      );

      int collectedCount = 0;

      for (final point in allHealthData) {
        final mappedMetric = _mapHealthTypeToBackendMetric(point.type);
        if (mappedMetric == null) continue;
        final value = _safeHealthValue(point.value);
        if (value == null || value <= 0) continue;
        collectedCount++;
        readings.add(
          _IngestReading(
            metric: mappedMetric,
            metricValue: value,
            recordedAt: point.dateFrom,
            source: source,
          ),
        );
      }

      if (allHealthData.isEmpty) {
        setState(() {
          syncStatusMessage =
              'Connected to Apple Health, but no matching data found in the last 7 days.';
        });
      } else if (collectedCount == 0) {
        setState(() {
          syncStatusMessage =
              'Apple Health data was found but could not be mapped to sync metrics.';
        });
      }
    } catch (e) {
      print('⚠ Health data collection failed: $e');
    }
  }

  String? _mapHealthTypeToBackendMetric(HealthDataType type) {
    switch (type) {
      case HealthDataType.STEPS:
        return 'STEPS';
      case HealthDataType.HEART_RATE:
        return 'HEART_RATE';
      case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
        return 'BLOOD_PRESSURE_DIA';
      case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
        return 'BLOOD_PRESSURE_SYS';
      default:
        return null;
    }
  }

  double? _safeHealthValue(HealthValue value) {
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    final asString = value.toString();
    final direct = double.tryParse(asString);
    if (direct != null) return direct;
    final numericMatch = RegExp(r'[-+]?\d*\.?\d+').firstMatch(asString);
    if (numericMatch != null) {
      return double.tryParse(numericMatch.group(0)!);
    }
    return null;
  }

  Future<List<_IngestReading>> _ingestReadings({
    required int patientId,
    required List<_IngestReading> readings,
  }) async {
    if (readings.isEmpty) {
      setState(() {
        _lastAcceptedCount = 0;
        _lastRejectedCount = 0;
      });
      return const [];
    }

    final authHeaders = await ApiService.getAuthHeaders();
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}analytics/vitals/ingest'),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'patientId': patientId,
        'source': 'wearables_screen',
        'readings':
            readings.take(500).map((reading) => reading.toJson()).toList(),
      }),
    );

    if (response.statusCode == 201 ||
        response.statusCode == 200 ||
        response.statusCode == 207) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      int accepted =
          ((data?['acceptedCount'] ?? body['acceptedCount'] ?? 0) as num)
              .toInt();
      int rejected =
          ((data?['rejectedCount'] ?? body['rejectedCount'] ?? 0) as num)
              .toInt();
      final acceptedReadings = _parseAcceptedIngestionReadings(data);
      if (accepted == 0 && acceptedReadings.isNotEmpty) {
        accepted = acceptedReadings.length;
      }
      setState(() {
        _lastAcceptedCount = accepted;
        _lastRejectedCount = rejected;
      });

      if (rejected > 0) {
        setState(() {
          syncStatusMessage =
              'Synced $accepted readings, but $rejected were rejected.';
        });
      }
      return acceptedReadings;
    }

    final errorBody = response.body.length > 200
        ? '${response.body.substring(0, 200)}...'
        : response.body;
    throw Exception(
      'Wearable ingest failed (${response.statusCode}) body=$errorBody',
    );
  }

  List<_IngestReading> _parseAcceptedIngestionReadings(
    Map<String, dynamic>? data,
  ) {
    final acceptedRaw = data?['acceptedReadings'];
    if (acceptedRaw is! List) return const [];

    return acceptedRaw
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final metric = entry['metric']?.toString();
          final value = (entry['metricValue'] as num?)?.toDouble();
          final recordedAt =
              DateTime.tryParse(entry['recordedAt']?.toString() ?? '');
          final source = entry['source']?.toString() ?? 'wearable';

          if (metric == null || value == null || recordedAt == null) {
            return null;
          }
          return _IngestReading(
            metric: metric,
            metricValue: value,
            recordedAt: recordedAt,
            source: source,
          );
        })
        .whereType<_IngestReading>()
        .toList();
  }

  Future<bool> _loadPersistedReadings({required int patientId}) async {
    final authHeaders = await ApiService.getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}analytics/vitals?patientId=$patientId&days=30',
      ),
      headers: authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load persisted vitals (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> data = (decoded['data'] as List<dynamic>? ?? []);

    if (data.isEmpty) {
      setState(() {
        hasSyncError = false;
        latestHealthData = {};
        syncStatusMessage = 'No synced wearable data found yet. '
            'Debug: collected=$_lastCollectedCount accepted=$_lastAcceptedCount rejected=$_lastRejectedCount';
      });
      return false;
    }

    final vitals = data.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final aTs = DateTime.tryParse(a['timestamp']?.toString() ?? '');
        final bTs = DateTime.tryParse(b['timestamp']?.toString() ?? '');
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

    final persisted = <String, HealthData>{};

    for (final vital in vitals) {
      final timestamp = DateTime.tryParse(vital['timestamp']?.toString() ?? '');
      if (timestamp == null) continue;

      final heartRate = (vital['heartRate'] as num?)?.toDouble() ?? 0.0;
      final spo2 = (vital['spo2'] as num?)?.toDouble() ?? 0.0;
      final systolic = (vital['systolic'] as num?)?.toDouble() ?? 0.0;
      final diastolic = (vital['diastolic'] as num?)?.toDouble() ?? 0.0;
      final weight = (vital['weight'] as num?)?.toDouble() ?? 0.0;

      if (heartRate > 0 && !persisted.containsKey('heart_rate')) {
        persisted['heart_rate'] = _healthDataFromDefinition(
          key: 'heart_rate',
          source: 'CareConnect Backend',
          value: heartRate,
          date: timestamp,
        );
      }
      if (spo2 > 0 && !persisted.containsKey('spo2')) {
        persisted['spo2'] = _healthDataFromDefinition(
          key: 'spo2',
          source: 'CareConnect Backend',
          value: spo2,
          date: timestamp,
        );
      }
      if (systolic > 0 && !persisted.containsKey('blood_pressure_systolic')) {
        persisted['blood_pressure_systolic'] = _healthDataFromDefinition(
          key: 'blood_pressure_systolic',
          source: 'CareConnect Backend',
          value: systolic,
          date: timestamp,
        );
      }
      if (diastolic > 0 && !persisted.containsKey('blood_pressure_diastolic')) {
        persisted['blood_pressure_diastolic'] = _healthDataFromDefinition(
          key: 'blood_pressure_diastolic',
          source: 'CareConnect Backend',
          value: diastolic,
          date: timestamp,
        );
      }
      if (weight > 0 && !persisted.containsKey('weight')) {
        persisted['weight'] = _healthDataFromDefinition(
          key: 'weight',
          source: 'CareConnect Backend',
          value: weight,
          date: timestamp,
        );
      }
      final steps = (vital['steps'] as num?)?.toDouble() ?? 0.0;
      if (steps > 0 && !persisted.containsKey('steps')) {
        persisted['steps'] = _healthDataFromDefinition(
          key: 'steps',
          source: 'CareConnect Backend',
          value: steps,
          date: timestamp,
        );
      }
    }

    setState(() {
      hasSyncError = false;
      latestHealthData = persisted;
      if (persisted.isEmpty) {
        syncStatusMessage =
            'No persisted wearable vitals available in this range. '
            'Debug: collected=$_lastCollectedCount accepted=$_lastAcceptedCount rejected=$_lastRejectedCount';
      } else if (syncStatusMessage == null) {
        syncStatusMessage = null;
      }
    });
    return persisted.isNotEmpty;
  }

  void _mergeAcceptedIngestionSnapshot(List<_IngestReading> acceptedReadings) {
    final snapshot = Map<String, HealthData>.from(latestHealthData);
    for (final reading in acceptedReadings) {
      final metricKey = _uiMetricKeyForBackendMetric(reading.metric);
      if (metricKey == null) continue;
      final existing = snapshot[metricKey];
      if (existing != null && existing.date.isAfter(reading.recordedAt)) {
        continue;
      }
      snapshot[metricKey] = _healthDataFromDefinition(
        key: metricKey,
        source: 'Fitbit (Google Health)',
        value: reading.metricValue,
        date: reading.recordedAt,
      );
    }

    if (snapshot.isNotEmpty) {
      setState(() {
        hasSyncError = false;
        latestHealthData = snapshot;
        syncStatusMessage =
            'Synced $_lastAcceptedCount Fitbit/Google Health reading(s)'
            '${_lastRejectedCount > 0 ? ', $_lastRejectedCount rejected' : ''}.';
      });
    }
  }

  void _applyAcceptedIngestionSnapshot(List<_IngestReading> acceptedReadings) {
    _mergeAcceptedIngestionSnapshot(acceptedReadings);
  }

  String? _uiMetricKeyForBackendMetric(String backendMetric) {
    switch (backendMetric.toUpperCase()) {
      case 'STEPS':
        return 'steps';
      case 'HEART_RATE':
        return 'heart_rate';
      case 'SPO2':
        return 'spo2';
      case 'BLOOD_PRESSURE_SYS':
        return 'blood_pressure_systolic';
      case 'BLOOD_PRESSURE_DIA':
        return 'blood_pressure_diastolic';
      case 'WEIGHT':
        return 'weight';
      default:
        return null;
    }
  }

  Future<void> _fetchFitbitData(DateTime startTime, DateTime endTime) async {
    final hasFitbitDevice =
        connectedDevices.any((device) => device.platform == 'fitbit');
    if (!hasFitbitDevice) return;

    final preview = <_IngestReading>[];
    await _collectFitbitReadings(preview, startTime, endTime);
    if (preview.isEmpty) {
      _setDefaultFitbitData();
      return;
    }

    final hrPoints =
        preview.where((r) => r.metric.toUpperCase() == 'HEART_RATE');
    final stepPoints =
        preview.where((r) => r.metric.toUpperCase() == 'STEPS');

    if (hrPoints.isNotEmpty) {
      final point = hrPoints.last;
      setState(() {
        latestHealthData['heart_rate'] = _healthDataFromDefinition(
          key: 'heart_rate',
          source: 'Fitbit',
          value: point.metricValue,
          date: point.recordedAt,
        );
      });
    } else {
      _setDefaultValue('heart_rate', 'Fitbit',
          reason: 'No Google Health heart-rate data available.');
    }

    if (stepPoints.isNotEmpty) {
      final point = stepPoints.last;
      setState(() {
        latestHealthData['steps'] = _healthDataFromDefinition(
          key: 'steps',
          source: 'Fitbit',
          value: point.metricValue,
          date: point.recordedAt,
        );
      });
    } else {
      _setDefaultValue('steps', 'Fitbit',
          reason: 'No Google Health steps data available.');
    }
  }

  String _sourceLabelForPlatform(String platform) {
    switch (platform) {
      case 'fitbit':
        return 'Fitbit';
      case 'apple_health':
        return 'Apple Health';
      case 'google_fit':
      case 'careconnect backend':
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

        if (device.platform == 'fitbit') {
          await _secureStorage.delete(key: 'fitbit_user_id');
          try {
            final auth = _tryGoogleAuth();
            await auth?.disconnect();
          } catch (_) {}
          try {
            final authHeaders = await ApiService.getAuthHeaders();
            await http.delete(
              Uri.parse(
                '${getBackendBaseUrl()}/v1/api/wearables/google-health/disconnect',
              ),
              headers: authHeaders,
            );
          } catch (_) {
            // Backend disconnect is best-effort for web-linked sessions.
          }
        }

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
            _buildConnectedDevicesHeader(),
            const SizedBox(height: 20),
            if (isLoadingData ||
                latestHealthData.isNotEmpty ||
                syncStatusMessage != null) ...[
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
              else if (hasSyncError)
                _buildSyncStateCard(
                  icon: Icons.sync_problem,
                  color: Colors.red,
                  title: 'Synchronization failed',
                  subtitle: syncStatusMessage ??
                      'We could not synchronize wearable readings.',
                )
              else if (latestHealthData.isEmpty)
                _buildSyncStateCard(
                  icon: Icons.inbox_outlined,
                  color: Colors.blueGrey,
                  title: 'No synced data yet',
                  subtitle: syncStatusMessage ??
                      'Connect a wearable and run sync to view persisted vitals.',
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

  Widget _buildConnectedDevicesHeader() {
    final subtitle =
        '${connectedDevices.length} device${connectedDevices.length == 1 ? '' : 's'} connected';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 430;
        if (isCompact) {
          return Column(
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
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _navigateToAddDevice,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Device'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          );
        }

        return Row(
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
                  subtitle,
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
        );
      },
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

  Widget _buildSyncStateCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
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
                Text(
                  data.type,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
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
                const SizedBox(height: 2),
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
