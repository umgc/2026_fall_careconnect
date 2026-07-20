import 'dart:convert';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/services/patient_medication_reminder_service.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/offline_notification_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/primary_care_provider_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/recent_checkin_widget.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/communication_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../services/evv_service.dart';
import '../../../../services/api_service_offline.dart';
import 'package:http/http.dart' as http;

import '../../../../../utils/call_integration_helper.dart';
import '../../../../../widgets/ai_chat_improved.dart';

class PatientDashboard extends StatefulWidget {
  final int? userId;

  const PatientDashboard({super.key, this.userId});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {

  // Patient data
  Map<String, dynamic>? patient;
  List<Map<String, dynamic>> caregivers = [];
  List<Map<String, dynamic>> familyMembers = [];

  // Loading states
  bool loading = true;
  bool isLoading = false;
  String? error;

  // Dashboard specific data
  List<CheckIn> recentCheckIns = [];
  List<MedicationReminderItem> medicationReminders = [];
  Map<String, dynamic>? primaryCareProvider;
  Map<String, dynamic>? _callableCaregiver;
  List<Map<String, dynamic>> _linkedCaregiverLinks = [];
  bool _providerVideoCallsEnabled = true;
  String? _providerCallPolicyMessage;

  // Mood tracking
  int currentMoodScore = 0;
  String currentMoodLabel = '';
  List<String> moodTags = [];

  // Notifications state
  bool _callNotificationInitialized = false;
  bool _isOffline = false;
  DateTime? _lastSynced;
  List<AlertNotification> activeAlerts = [];

  // Alert dismissal tracking
  Set<String> dismissedAlertIds = {};
  final PatientMedicationReminderService _medicationReminderService =
      PatientMedicationReminderService();

  // EVV sections state
  final EvvService _evvService = EvvService();
  List<EvvRecord> _pastEvvVisits = [];
  List<Map<String, dynamic>> _upcomingEvvAppointments = [];
  bool _loadingEvv = false;

  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadDashboardData();
    _callNotificationInitialized = true;
    _checkConnectivity();
    _loadRecentMoodData();
    _loadMedicationReminders();
    _loadLinkedCaregiversForCalling();
    _loadPrimaryCareProvider();
    _loadEvvSections();
  }

  /// Check connectivity status
  Future<void> _checkConnectivity() async {
    // Implement actual connectivity checking
    // For now, using mock data
    setState(() {
      _isOffline = false; // Set based on actual connectivity
      _lastSynced = DateTime.now().subtract(const Duration(hours: 2));
    });
  }

  /// Load all dashboard data
  Future<void> _loadDashboardData() async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final int? id = user?.id;

      if (id == null) {
        setState(() {
          error = t.ptdashboard_userNotLoggedIn;
          loading = false;
        });
        return;
      }

      await _loadMedicationReminders();
      final alerts = await _buildAlerts(id);

      if (!mounted) {
        return;
      }
      setState(() {
        activeAlerts = alerts;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = '${t.ptdashboard_errorLoadDash}: ${e.toString()}';
        loading = false;
      });
    }
  }

  Future<void> _loadEvvSections() async {
    setState(() => _loadingEvv = true);
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final patientId = user?.patientId;
      if (patientId == null) {
        setState(() => _loadingEvv = false);
        return;
      }
      final now = DateTime.now();
      // Use name-based filter to avoid backend SQL param typing issue
      String? patientName;
      try {
        final first = patient?['firstName'] ?? '';
        final last = patient?['lastName'] ?? '';
        final combined = ('$first $last').trim();
        patientName = combined.isNotEmpty ? combined : null;
      } catch (_) {}

      final result = await _evvService.searchRecords(
        EvvSearchRequest(
          patientName: patientName,
          page: 0,
          size: 200,
          sortBy: 'dateOfService',
          sortDirection: 'DESC',
        ),
      );
      _pastEvvVisits = result.content
          .where((r) => r.patient?.id == patientId)
          .toList();


      // Fetch scheduled visits directly for this patient
      try {
        final headers = await ApiService.getAuthHeaders();
        final startStr = DateTime(now.year, now.month, now.day)
            .toIso8601String()
            .split('T')[0];
        final endDate = now.add(const Duration(days: 30));
        final endStr = DateTime(endDate.year, endDate.month, endDate.day)
            .toIso8601String()
            .split('T')[0];

        final url = Uri.parse(
          '${ApiConstants.baseUrl}scheduled-visits/patient/$patientId/range?startDate=$startStr&endDate=$endStr',
        );
        final res = await ApiServiceOffline.httpClient.get(url, headers: headers);
        if (res.statusCode == 200) {
          final List<dynamic> data = jsonDecode(res.body);

          DateTime? parseWhen(Map<String, dynamic> m) {
            final v = m['scheduledTime'] ?? m['scheduled_time'] ?? m['time'];
            if (v is String) {
              if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(v)) {
                final d = (m['scheduledDate'] ?? m['scheduled_date']) as String?;
                if (d != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) {
                  return DateTime.tryParse('$d $v');
                }
              }
              final dt = DateTime.tryParse(v);
              if (dt != null) return dt;
            }
            if (v is int) {
              try { return DateTime.fromMillisecondsSinceEpoch(v); } catch (_) {}
            }
            final dateStr = (m['scheduledDate'] ?? m['scheduled_date']) as String?;
            final timeStr = (m['scheduledTime'] ?? m['scheduled_time']) as String?;
            if (dateStr != null && timeStr != null) {
              final date = DateTime.tryParse(dateStr);
              if (date != null) {
                final tp = timeStr.split(':');
                if (tp.length >= 2) {
                  final h = int.tryParse(tp[0]) ?? 0;
                  final min = int.tryParse(tp[1]) ?? 0;
                  return DateTime(date.year, date.month, date.day, h, min);
                }
              }
            }
            return null;
          }

          final Set<dynamic> seenIds = {};
          final List<Map<String, dynamic>> normalized = [];
          for (final raw in data.cast<Map<String, dynamic>>()) {
            final when = parseWhen(raw);
            if (when == null) continue;
            if (when.isBefore(DateTime.now())) continue;
            final id = raw['id'] ?? raw['visitId'] ?? raw['scheduledVisitId'];
            if (id != null && seenIds.contains(id)) continue;
            if (id != null) seenIds.add(id);
            final service = raw['serviceType'] ?? raw['service_type'] ?? raw['service'] ?? 'Service';
            normalized.add({
              'id': id,
              'serviceType': service,
              'scheduledTime': when.toIso8601String(),
            });
          }
          normalized.sort(
            (a, b) => DateTime.parse(a['scheduledTime']).compareTo(DateTime.parse(b['scheduledTime'])),
          );
          _upcomingEvvAppointments = normalized;
        }
      } catch (_) {
        _upcomingEvvAppointments = [];
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingEvv = false);
    }
  }

  /// Load recent mood data
  Future<void> _loadRecentMoodData() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final userId = user?.id;
      if (userId == null) {
        return;
      }

      final response = await ApiService.getMoodHistory(userId);
      final entries = response.whereType<Map<String, dynamic>>().map((entry) {
        final scoreRaw = entry['score'];
        final score = scoreRaw is int
            ? scoreRaw
            : int.tryParse(scoreRaw?.toString() ?? '') ?? 5;
        final label = (entry['label'] ?? '').toString().trim();
        final createdAt = DateTime.tryParse(
          (entry['createdAt'] ?? '').toString(),
        );
        return {
          'score': score,
          'label': label,
          'createdAt': createdAt ?? DateTime.now(),
        };
      }).toList();

      entries.sort(
        (a, b) =>
            (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime),
      );

      final latest = entries.isNotEmpty ? entries.first : null;
      final latestScore = (latest?['score'] as int?) ?? 0;
      final latestLabel = (latest?['label'] as String?)?.isNotEmpty == true
          ? latest!['label'] as String
          : _moodLabelFromScore(latestScore);

      setState(() {
        currentMoodScore = latestScore;
        currentMoodLabel = latestLabel;
        moodTags = _moodTagsFromLabel(latestLabel);
        recentCheckIns = entries.take(3).map((entry) {
          final score = entry['score'] as int;
          final label = entry['label'] as String;
          final normalizedLabel = label.isNotEmpty
              ? label
              : _moodLabelFromScore(score);
          return CheckIn(
            date: entry['createdAt'] as DateTime,
            status: normalizedLabel,
            emoji: _moodEmojiFromScore(score),
          );
        }).toList();
      });
    } catch (e) {
      print('Error loading mood data: $e');
    }
  }

  String _moodLabelFromScore(int score) {
    if (score >= 9) return 'Excellent';
    if (score >= 7) return 'Good';
    if (score >= 5) return 'Fair';
    if (score >= 1) return 'Poor';
    return 'Unknown';
  }

  String _moodEmojiFromScore(int score) {
    if (score >= 9) return '😄';
    if (score >= 7) return '🙂';
    if (score >= 5) return '😐';
    if (score >= 1) return '😟';
    return '😐';
  }

  List<String> _moodTagsFromLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('excellent') || l.contains('great')) {
      return const ['happy', 'calm', 'positive'];
    }
    if (l.contains('good')) {
      return const ['comfortable', 'stable', 'positive'];
    }
    if (l.contains('fair') || l.contains('neutral')) {
      return const ['neutral', 'watchful'];
    }
    if (l.contains('poor') || l.contains('sad')) {
      return const ['low', 'monitoring'];
    }
    return const ['no recent mood data'];
  }

  /// Load medication reminders
  Future<void> _loadMedicationReminders() async {
    try {
      final t = AppLocalizations.of(context)!;
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final next = await _medicationReminderService.loadReminders(
        patientId: user?.patientId,
        t: t,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        medicationReminders = next;
        activeAlerts = _withMedicationReminderAlert(
          activeAlerts,
          hasPendingUntaken: _hasPendingMedicationReminders(next),
        );
      });
    } catch (e) {
      print('Error loading medication reminders: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        medicationReminders = [];
        activeAlerts = _withMedicationReminderAlert(
          activeAlerts,
          hasPendingUntaken: false,
        );
      });
    }
  }

  /// Load primary care provider
  Future<void> _loadPrimaryCareProvider() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final patientId = user?.patientId;
      Map<String, dynamic>? provider;
      if (patientId != null) {
        final headers = await ApiService.getAuthHeaders();
        final providerRes = await http.get(
          Uri.parse('${ApiConstants.baseUrl}patients/$patientId/provider'),
          headers: headers,
        );

        if (providerRes.statusCode == 200) {
          final decoded = jsonDecode(providerRes.body);
          if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
            provider = decoded;
          }
        }
      }

      final fallback = _buildDefaultProvider();
      if (provider == null || provider.isEmpty) {
        provider = {
          ...fallback,
          'caregiverUserId':
              _toInt(_callableCaregiver?['caregiverUserId']) ??
              _toInt(fallback['caregiverUserId']),
        };
      } else {
        provider['caregiverUserId'] ??=
            _toInt(_callableCaregiver?['caregiverUserId']) ??
            _toInt(fallback['caregiverUserId']);
      }
      provider = _normalizeProvider(provider);

      if (mounted) {
        setState(() {
          primaryCareProvider = provider;
          _syncProviderCallingPolicy();
        });
      }
    } catch (e) {
      print('Error loading primary care provider: $e');
      if (mounted) {
        setState(() {
          primaryCareProvider = _normalizeProvider(_buildDefaultProvider());
          _syncProviderCallingPolicy();
        });
      }
    }
  }

  Future<void> _loadLinkedCaregiversForCalling() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final patientUserId = user?.id;
      if (patientUserId == null) {
        return;
      }

      final links = await ApiService.getPatientLinkedCaregiverLinks(
        patientUserId,
      );
      if (mounted) {
        setState(() {
          _linkedCaregiverLinks = links;
          _syncProviderCallingPolicy();
        });
      }
    } catch (e) {
      print('Error loading caregiver call policy: $e');
    }
  }

  Map<String, dynamic> _buildDefaultProvider() {
    return <String, dynamic>{
      'name': 'Dr. Sarah Mitchell, MD',
      'specialty': 'Internal Medicine',
      'organization': 'CareConnect Medical Group',
      'phone': '(555) 123-4567',
      'email': 'sarah.mitchell@careconnect.com',
      'nextAppointment': DateTime(2026, 4, 7, 20, 50),
      'appointmentType': '8:50 PM - Annual Checkup',
    };
  }

  Map<String, dynamic> _normalizeProvider(Map<String, dynamic> provider) {
    final normalized = Map<String, dynamic>.from(provider);
    final rawNextAppointment = normalized['nextAppointment'];
    if (rawNextAppointment != null && rawNextAppointment is! DateTime) {
      final parsed = DateTime.tryParse('$rawNextAppointment');
      normalized['nextAppointment'] = parsed ?? DateTime.now();
    }
    return normalized;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }

  String _normalizedText(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  String _normalizedPhone(dynamic value) {
    return (value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Strips common title prefixes (Dr., Mr., etc.) and credential suffixes
  /// (MD, RN, DO, etc.) so that "Dr. Sarah Mitchell, MD" matches "Sarah Mitchell".
  String _normalizedPersonName(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'\b(dr|mr|mrs|ms|prof|md|rn|do|np|pa|phd|dds|dvm|jd)\b\.?'),
          '',
        )
        .replaceAll(RegExp(r'[^a-z\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _toBool(dynamic value, {bool defaultValue = true}) {
    if (value is bool) return value;
    final raw = '$value'.trim().toLowerCase();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return defaultValue;
  }

  void _syncProviderCallingPolicy() {
    final t = AppLocalizations.of(context)!;
    // Wait until both data sources are loaded before resolving.
    // Prevents a flash of "calling disabled" when caregiver links arrive
    // before the primary care provider finishes loading.
    if (primaryCareProvider == null) return;

    if (_linkedCaregiverLinks.isEmpty) {
      _callableCaregiver = null;
      _providerVideoCallsEnabled = false;
      _providerCallPolicyMessage =
          t.ptdashboard_videoCallDisabledWithoutCaregiver;
      return;
    }

    final providerCaregiverUserId = _toInt(
      primaryCareProvider?['caregiverUserId'],
    );

    Map<String, dynamic>? selectedLink;
    if (providerCaregiverUserId != null) {
      for (final link in _linkedCaregiverLinks) {
        if (_toInt(link['caregiverUserId']) == providerCaregiverUserId) {
          selectedLink = link;
          break;
        }
      }
    }

    selectedLink ??= () {
      final providerEmail = _normalizedText(primaryCareProvider?['email']);
      if (providerEmail.isNotEmpty) {
        for (final link in _linkedCaregiverLinks) {
          final linkEmail = _normalizedText(
            link['caregiverEmail'] ?? link['email'],
          );
          if (linkEmail.isNotEmpty && linkEmail == providerEmail) {
            return link;
          }
        }
      }

      final providerPhone = _normalizedPhone(primaryCareProvider?['phone']);
      if (providerPhone.isNotEmpty) {
        for (final link in _linkedCaregiverLinks) {
          final linkPhone = _normalizedPhone(
            link['caregiverPhone'] ?? link['phone'],
          );
          if (linkPhone.isNotEmpty && linkPhone == providerPhone) {
            return link;
          }
        }
      }

      final providerName = _normalizedPersonName(primaryCareProvider?['name']);
      if (providerName.isNotEmpty) {
        for (final link in _linkedCaregiverLinks) {
          final linkName = _normalizedPersonName(
            link['caregiverName'] ?? link['name'],
          );
          if (linkName.isNotEmpty && linkName == providerName) {
            return link;
          }
        }
      }

      return null;
    }();

    if (selectedLink == null) {
      _callableCaregiver = null;
      _providerVideoCallsEnabled = false;
      _providerCallPolicyMessage =
          t.ptdashboard_videoCallDisabledWithoutProvider;
      return;
    }

    final normalizedCaregiverUserId = _toInt(selectedLink['caregiverUserId']);
    final enabled = _toBool(selectedLink['patientVideoCallsEnabled']);

    _callableCaregiver = {
      ...selectedLink,
      'caregiverUserId': normalizedCaregiverUserId,
    };
    if (primaryCareProvider != null && normalizedCaregiverUserId != null) {
      primaryCareProvider!['caregiverUserId'] = normalizedCaregiverUserId;
    }

    _providerVideoCallsEnabled = enabled;
    _providerCallPolicyMessage = enabled
        ? null
        : t.ptdashboard_videoCallDisabledByProvider;
  }

  int? _parseMoodScore(dynamic value) {
    if (value is int) {
      return value.clamp(1, 10);
    }
    if (value is num) {
      return value.round().clamp(1, 10);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed.clamp(1, 10);
      }
    }
    return null;
  }

  DateTime? _parseMoodDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  double? _averageMoodLast7Days(List<dynamic> moodHistory) {
    final nowUtc = DateTime.now().toUtc();
    final cutoffUtc = nowUtc.subtract(const Duration(days: 7));
    var total = 0;
    var count = 0;

    for (final row in moodHistory) {
      if (row is! Map) {
        continue;
      }

      final score = _parseMoodScore(row['score']);
      final date = _parseMoodDate(
        row['createdAt'] ?? row['date'] ?? row['timestamp'] ?? row['updatedAt'],
      );

      if (score == null || date == null) {
        continue;
      }

      final utcDate = date.toUtc();
      if (utcDate.isBefore(cutoffUtc)) {
        continue;
      }

      total += score;
      count += 1;
    }

    if (count == 0) {
      return null;
    }

    return total / count;
  }

  List<AlertNotification> _withMoodAlertForAverage(
    List<AlertNotification> existing,
    double? averageMood,
  ) {
    final t = AppLocalizations.of(context)!;
    final next = existing
        .where(
          (alert) =>
              !(alert.type == AlertType.important &&
                  alert.message == t.ptdashboard_moodScoreLow),
        )
        .toList();

    if (averageMood != null && averageMood <= 5.0) {
      next.insert(
        0,
        AlertNotification(
          type: AlertType.important,
          message: t.ptdashboard_moodScoreLow,
        ),
      );
    }

    return next;
  }

  bool _hasPendingMedicationReminders(List<MedicationReminderItem> reminders) {
    return _medicationReminderService.hasPendingUntaken(reminders);
  }

  bool _isPendingMedicationAlert(AlertNotification alert) {
    final t = AppLocalizations.of(context)!;
    return alert.type == AlertType.reminder &&
        alert.message == t.ptdashboard_medicationReminders;
  }

  String _alertId(AlertNotification alert) {
    final t = AppLocalizations.of(context)!;
    if (_isPendingMedicationAlert(alert)) {
      return t.ptdashboard_medPendingReminder;
    }
    return '${alert.type.name}:${alert.message}';
  }

  List<AlertNotification> _withMedicationReminderAlert(
    List<AlertNotification> existing, {
    required bool hasPendingUntaken,
  }) {
    final t = AppLocalizations.of(context)!;
    final next = existing
        .where((alert) => !_isPendingMedicationAlert(alert))
        .toList();

    if (!hasPendingUntaken) {
      dismissedAlertIds.remove(t.ptdashboard_medPendingReminder);
      return next;
    }

    next.add(
      AlertNotification(
        type: AlertType.reminder,
        message: t.ptdashboard_medicationReminders,
      ),
    );
    return next;
  }

  void _handleAverageMoodChanged(double averageMood) {
    if (!mounted) {
      return;
    }
    setState(() {
      activeAlerts = _withMoodAlertForAverage(activeAlerts, averageMood);
    });
  }

  /// Build alerts from real dashboard data only.
  Future<List<AlertNotification>> _buildAlerts(int userId) async {
    final moodHistory = await ApiService.getMoodHistory(userId);
    final averageMood = _averageMoodLast7Days(moodHistory);
    final moodAlerts = _withMoodAlertForAverage(<AlertNotification>[], averageMood);
    return _withMedicationReminderAlert(
      moodAlerts,
      hasPendingUntaken: _hasPendingMedicationReminders(medicationReminders),
    );
  }

  /// Load family members
  Future<void> _loadFamilyMembers() async {
    if (!isLoading) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      final userId = widget.userId ?? user?.id ?? 1;

      final response = await ApiService.getFamilyMembers(userId);

      if (mounted) {
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          setState(() {
            familyMembers = List<Map<String, dynamic>>.from(data);
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading family members: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }


  /// Handle medication action
  Future<void> _handleMedicationAction(int medicationId, bool taken) async {
    final t = AppLocalizations.of(context)!;
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final patientId = user?.patientId;
    if (patientId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.ptdashboard_unableToUpdateMeds),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final actionAt = DateTime.now().toUtc();
    if (taken) {
      _medicationReminderService.markTaken(
        medicationId: medicationId,
        takenAt: actionAt,
      );
    } else {
      _medicationReminderService.markMissed(medicationId: medicationId);
    }

    final response = taken
        ? await ApiService.markMedicationTaken(
            patientId,
            medicationId,
            takenAt: actionAt,
          )
        : await ApiService.clearMedicationTakenStatus(
            patientId,
            medicationId,
          );
    final queuedOffline = response.headers['x-offline-queued'] == 'true';
    final success = (response.statusCode >= 200 && response.statusCode < 300) ||
        queuedOffline;

    if (!success) {
      _medicationReminderService.clearLocalOverride(medicationId: medicationId);
    }

    if (mounted) {
      final snackBarTheme = Theme.of(context);
      late final SnackBar snackBar;
      if (success) {
        if (queuedOffline) {
          snackBar = SnackBar(
            content: Text(
              taken
                  ? t.ptdashboard_medsTakenUpdateQueued
                  : t.ptdashboard_medsMissedUpdateQueued,
            ),
            backgroundColor: snackBarTheme.colorScheme.tertiary,
            duration: const Duration(seconds: 2),
          );
        } else if (taken) {
          snackBar = SnackBar(
            content: Text(t.ptdashboard_medsMarkedTaken),
            backgroundColor: AppTheme.success,
            duration: Duration(seconds: 2),
          );
        } else {
          snackBar = SnackBar(
            content: Text(t.ptdashboard_medsMarkedMissed),
            backgroundColor: snackBarTheme.colorScheme.tertiary,
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        snackBar = SnackBar(
          content: Text(t.ptdashboard_unableToUpdateMedStatus),
          backgroundColor: snackBarTheme.colorScheme.error,
          duration: const Duration(seconds: 2),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }

    await _loadMedicationReminders();
  }

  /// Handle contacting provider
  void _handleContactProvider() {
    final t = AppLocalizations.of(context)!;
    // Show contact options
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.pcpwidget_contactProvider,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text(t.ptdashboard_call),
              subtitle: Text(primaryCareProvider?['phone'] ?? ''),
              onTap: () {
                Navigator.pop(context);
                final phone = primaryCareProvider?['phone'];
                if (phone != null) {
                  CommunicationService.makePhoneCall(phone, context);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.email),
              title: Text(t.resetpassword_emailTitle),
              subtitle: Text(primaryCareProvider?['email'] ?? ''),
              onTap: () async {
                Navigator.pop(context);
                final email = primaryCareProvider?['email'];
                if (email != null) {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: email,
                    queryParameters: {
                      'subject': t.ptdashboard_emailSubject,
                      'body':
                          '${t.ptdashboard_emailBody} ${primaryCareProvider?['name']?.split(' ')[1]},\n\n',
                    },
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_call),
              title: Text(t.ptdashboard_videoCall),
              subtitle: Text(
                _providerVideoCallsEnabled
                    ? t.ptdashboard_startVideoCallProvider
                    : (_providerCallPolicyMessage ??
                          t.ptdashboard_disabledVideoCallProvider),
              ),
              enabled: _providerVideoCallsEnabled,
              onTap: _providerVideoCallsEnabled
                  ? () async {
                Navigator.pop(context);

                if (primaryCareProvider == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(t.ptdashboard_providerInfoUnavailable),
                    ),
                  );
                  return;
                }

                final user = Provider.of<UserProvider>(
                  this.context,
                  listen: false,
                ).user;

                if (user == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(t.ptdashboard_notLoggedInCall),
                    ),
                  );
                  return;
                }

                final targetCaregiver = <String, dynamic>{
                  ...?primaryCareProvider,
                  ...?_callableCaregiver,
                  'id': _callableCaregiver?['caregiverUserId'] ??
                      primaryCareProvider?['caregiverUserId'],
                  'name': (_callableCaregiver?['caregiverName'] ??
                      primaryCareProvider?['name'] ??
                      '')
                    .toString(),
                  'firstName': (((_callableCaregiver?['caregiverName'] ??
                          primaryCareProvider?['name']) ??
                        '')
                          .toString()
                          .split(' ')
                          .isNotEmpty)
                    ? ((_callableCaregiver?['caregiverName'] ??
                            primaryCareProvider?['name']) ??
                          '')
                        .toString()
                        .split(' ')
                        .first
                      : '',
                  'lastName': (((_callableCaregiver?['caregiverName'] ??
                          primaryCareProvider?['name']) ??
                        '')
                          .toString()
                          .split(' ')
                          .length >
                      1)
                    ? ((_callableCaregiver?['caregiverName'] ??
                            primaryCareProvider?['name']) ??
                          '')
                          .toString()
                          .split(' ')
                          .skip(1)
                          .join(' ')
                      : '',
                };

                await CallIntegrationHelper.startVideoCallToCaregiver(
                  context: this.context,
                  currentUser: user,
                  targetCaregiver: targetCaregiver,
                  isVideoCall: true,
                );
              }
                  : () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _providerCallPolicyMessage ??
                                t.ptdashboard_videoCallDisabled,
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: DashboardAppHeader(
        userName: user?.name ?? '',
        role: user?.role ?? '',
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).primaryColor,
        child: Icon(
          Icons.chat_bubble_outline,
          color: theme.colorScheme.onPrimary,
        ),
        onPressed: () {
          final double sheetHeight = MediaQuery.of(context).size.height * 0.75;
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            constraints: BoxConstraints(
              maxWidth: isTablet ? 600 : double.infinity,
            ),
            builder: (context) => SizedBox(
              height: sheetHeight,
              child: AIChat(
                role: 'patient',
                isModal: true,
                patientId: user?.patientId, // Pass the actual patient ID
                userId: user?.id,
              ),
            ),
          );
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.ptdashboard_errorLoadDash,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(t.ptdashboard_retryButton),
                        onPressed: _loadDashboardData,
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _loadDashboardData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),

                          // Responsive layout for tablets
                          if (isTablet) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left Column
                                  Expanded(
                                    child: Column(
                                      children: [
                                        // Offline notification
                                        if (_isOffline)
                                          OfflineNotification(
                                            lastSynced: _lastSynced,
                                          ),

                                        // Alert notifications
                                        ...activeAlerts
                                            .where(
                                              (alert) =>
                                                  !dismissedAlertIds.contains(
                                                _alertId(alert),
                                              ),
                                            )
                                            .map(
                                              (alert) => AlertNotification(
                                                type: alert.type,
                                                message: alert.message,
                                                onDismiss: () {
                                                  setState(() {
                                                    dismissedAlertIds.add(
                                                      _alertId(alert),
                                                    );
                                                  });
                                                },
                                              ),
                                            ),

                                        // Current Mood
                                        CurrentMoodWidget(
                                          moodScore: currentMoodScore,
                                          moodLabel: currentMoodLabel,
                                          moodTags: moodTags,
                                          date: DateTime.now(),
                                          onAverageMoodChanged:
                                              _handleAverageMoodChanged,
                                        ),

                                        // Recent Check-ins
                                        if (recentCheckIns.isNotEmpty)
                                          RecentCheckInsWidget(
                                            checkIns: recentCheckIns,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Right Column
                                  Expanded(
                                    child: Column(
                                      children: [
                                        // Medication Reminders
                                        MedicationRemindersWidget(
                                          reminders: medicationReminders,
                                          onMarkTaken: (medicationId) {
                                            _handleMedicationAction(
                                              medicationId,
                                              true,
                                            );
                                          },
                                          onMarkMissed: (medicationId) {
                                            _handleMedicationAction(
                                              medicationId,
                                              false,
                                            );
                                          },
                                        ),

                                        // Upcoming EVV & Past EVV
                                        const SizedBox(height: 12),
                                        _buildUpcomingEvvSection(theme),
                                        const SizedBox(height: 12),
                                        _buildPastEvvSection(theme),

                                        // Primary Care Provider
                                        if (primaryCareProvider != null)
                                          PrimaryCareProviderWidget(
                                            providerName:
                                                primaryCareProvider!['name'],
                                            specialty: primaryCareProvider![
                                                'specialty'],
                                            organization: primaryCareProvider![
                                                'organization'],
                                            phone:
                                                primaryCareProvider!['phone'],
                                            email:
                                                primaryCareProvider!['email'],
                                            nextAppointment:
                                                primaryCareProvider![
                                                    'nextAppointment'],
                                            appointmentType:
                                                primaryCareProvider![
                                                    'appointmentType'],
                                            onContactProvider:
                                                _handleContactProvider,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Mobile layout (single column)
                            // Offline notification
                            if (_isOffline)
                              OfflineNotification(lastSynced: _lastSynced),

                            // Alert notifications
                            ...activeAlerts
                                .where(
                                  (alert) => !dismissedAlertIds.contains(
                                    _alertId(alert),
                                  ),
                                )
                                .map(
                                  (alert) => AlertNotification(
                                    type: alert.type,
                                    message: alert.message,
                                    onDismiss: () {
                                      setState(() {
                                        dismissedAlertIds.add(
                                          _alertId(alert),
                                        );
                                      });
                                    },
                                  ),
                                ),

                            // Current Mood Widget
                            CurrentMoodWidget(
                              moodScore: currentMoodScore,
                              moodLabel: currentMoodLabel,
                              moodTags: moodTags,
                              date: DateTime.now(),
                              onAverageMoodChanged: _handleAverageMoodChanged,
                            ),

                            // Recent Check-Ins
                            if (recentCheckIns.isNotEmpty)
                              RecentCheckInsWidget(checkIns: recentCheckIns),

                            // Medication Reminders
                            MedicationRemindersWidget(
                              reminders: medicationReminders,
                              onMarkTaken: (medicationId) {
                                _handleMedicationAction(medicationId, true);
                              },
                              onMarkMissed: (medicationId) {
                                _handleMedicationAction(medicationId, false);
                              },
                            ),

                            const SizedBox(height: 12),
                            _buildUpcomingEvvSection(theme),
                            const SizedBox(height: 12),
                            _buildPastEvvSection(theme),

                            // Primary Care Provider
                            if (primaryCareProvider != null)
                              PrimaryCareProviderWidget(
                                providerName: primaryCareProvider!['name'],
                                specialty: primaryCareProvider!['specialty'],
                                organization:
                                    primaryCareProvider!['organization'],
                                phone: primaryCareProvider!['phone'],
                                email: primaryCareProvider!['email'],
                                nextAppointment:
                                    primaryCareProvider!['nextAppointment'],
                                appointmentType:
                                    primaryCareProvider!['appointmentType'],
                                onContactProvider: _handleContactProvider,
                              ),
                          ],

                          // Emergency Actions
                          Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Column(
                              children: [
                                // SOS Emergency Button
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.sos),
                                  label: Text(t.ptdashboard_sosEmergency),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                    foregroundColor: theme.colorScheme.onError,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    CallIntegrationHelper.showSOSDialog(
                                      context: context,
                                      currentPatient: patient,
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                // Send SMS Notification Button
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.sms),
                                  label: Text(t.ptdashboard_sosSmsToCaregiver),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.primary,
                                    side: BorderSide(
                                      color: theme.colorScheme.primary,
                                    ),
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    final caregiver = caregivers.firstWhere(
                                      (c) =>
                                          c['phone'] != null &&
                                          c['phone'].toString().isNotEmpty,
                                      orElse: () => {},
                                    );

                                    if (caregiver.isNotEmpty && user != null) {
                                      _showSendMessageDialog(
                                        context,
                                        caregiver,
                                        user,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            t.ptdashboard_noCaregiverPhone,
                                          ),
                                          backgroundColor:
                                              theme.colorScheme.error,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 100), // Bottom padding for FAB
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final primaryColorLight = theme.primaryColorLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: primaryColorLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: primaryColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // SMS Dialog
  void _showSendMessageDialog(
    BuildContext context,
    Map<String, dynamic> caregiver,
    dynamic currentUser,
  ) {
    final t = AppLocalizations.of(context)!;
    final TextEditingController messageController = TextEditingController();
    final String name = '${caregiver['firstName']} ${caregiver['lastName']}';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${t.ptdashboard_sendMessageTo} $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: messageController,
                decoration: InputDecoration(
                  labelText: t.ptdashboard_message,
                  hintText: '${t.ptdashboard_messageLabel}...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                CallIntegrationHelper.sendSMSToCaregiver(
                  currentUser: currentUser,
                  targetCaregiver: caregiver,
                  message: messageController.text,
                );
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${t.ptdashboard_smsSent} $name')));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(t.ptdashboard_sendButton),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUpcomingEvvSection(ThemeData theme) {
    final t = AppLocalizations.of(context)!;
    if (_loadingEvv) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                t.ptdashboard_upcomingEVV,
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadEvvSections,
                icon: const Icon(Icons.refresh),
              ),

            ],
          ),
          const SizedBox(height: 8),
          if (_upcomingEvvAppointments.isEmpty)
            Text(t.ptdashboard_noUpcomingEVV)
          else
            ..._upcomingEvvAppointments.take(5).map((v) {
              final when =
                  DateTime.tryParse(v['scheduledTime'] ?? '') ?? DateTime.now();
              final service = v['serviceType'] ?? t.ptdashboard_service;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  service,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${when.month}/${when.day}/${when.year} • ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
                ),

              );
            }),
        ],
      ),
    );
  }

  Widget _buildPastEvvSection(ThemeData theme) {
    final t = AppLocalizations.of(context)!;
    if (_loadingEvv) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Text(t.ptdashboard_pastEVVs, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (_pastEvvVisits.isEmpty)
            Text(t.ptdashboard_NoPastEVVs)
          else
            ..._pastEvvVisits.take(10).map((r) {
              final date = r.dateOfService;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.check, color: Colors.white, size: 18),
                ),
                title: Text(
                  r.serviceType,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                subtitle: Text('${date.month}/${date.day}/${date.year}'),
              );
            }),
        ],
      ),
    );
  }
}


