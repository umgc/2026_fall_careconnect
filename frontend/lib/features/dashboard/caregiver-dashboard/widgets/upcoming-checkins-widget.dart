import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';

// ---------------------------------------------------------------------------
// Lightweight local model — mirrors the fields returned by the scheduled-visits
// endpoint, parsed the same way as ScheduledVisit in schedule_page.dart.
// ---------------------------------------------------------------------------
class _UpcomingVisit {
  final int id;
  final int patientId;
  final String patientName;
  final String serviceType;
  final DateTime scheduledTime;
  final int durationMinutes;
  final String status;
  final String priority;

  _UpcomingVisit({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.serviceType,
    required this.scheduledTime,
    required this.durationMinutes,
    required this.status,
    required this.priority,
  });

  factory _UpcomingVisit.fromJson(Map<String, dynamic> json) {
    final dateStr = json['scheduledDate'] as String;
    final timeStr = json['scheduledTime'] as String;

    final dateParts = dateStr.split('-');
    final year = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final day = int.parse(dateParts[2]);

    final timeParts = timeStr.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    return _UpcomingVisit(
      id: json['id'] as int,
      patientId: json['patientId'] as int,
      patientName: json['patientName'] as String,
      serviceType: json['serviceType'] as String,
      scheduledTime: DateTime(year, month, day, hour, minute),
      durationMinutes: json['durationMinutes'] as int,
      status: json['status'] as String,
      priority: json['priority'] as String? ?? 'Normal',
    );
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------
class UpcomingCheckins extends StatefulWidget {
  const UpcomingCheckins({super.key});

  @override
  State<UpcomingCheckins> createState() => _UpcomingCheckinsState();
}

class _UpcomingCheckinsState extends State<UpcomingCheckins> {
  List<_UpcomingVisit> _visits = [];
  bool _loading = true;
  String? _error;

  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _fetchVisits();
  }

  Future<void> _fetchVisits() async {
    final t = AppLocalizations.of(context)!;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiverId = userProvider.user?.caregiverId;

      if (caregiverId == null) {
        setState(() {
          _error = t.upcomingcheckinwidget_missingCaregiverSession;
          _loading = false;
        });
        return;
      }

      final headers = await AuthTokenManager.getAuthHeaders();
      final url = Uri.parse(
        '${ApiConstants.baseUrl}scheduled-visits/caregiver/$caregiverId/upcoming',
      );

      final response = await ApiServiceOffline.httpClient.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        setState(() {
          _visits = data
              .map((e) => _UpcomingVisit.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = '${t.upcomingcheckinwidget_failedToLoadVisits} (${response.statusCode}).';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = t.upcomingcheckinwidget_failedToLoadCheckIns;
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    final t = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final visitDay = DateTime(dt.year, dt.month, dt.day);
    final diff = visitDay.difference(today).inDays;

    final timeLabel = DateFormat('h:mm a').format(dt);
    if (diff == 0) return '${t.upcomingcheckinwidget_todayAt} $timeLabel';
    if (diff == 1) return '${t.upcomingcheckinwidget_tomorrowAt} $timeLabel';
    return '${DateFormat('MMM d').format(dt)} ${t.upcomingcheckinwidget_at} $timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.blue[600], size: 20),
              const SizedBox(width: 8),
              Text(
                t.upcomingcheckinwidget_upcomingCheckInTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null || _visits.isEmpty)
            Center(
              child: Text(
                _error ?? t.upcomingcheckinwidget_noCheckIns,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            )
          else
            ..._visits.map(
              (visit) => _PatientCheckInItem(
                name: visit.patientName,
                date: _formatDate(visit.scheduledTime),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => context.push('/tasks'),
              child: Text(
                t.upcomingcheckinwidget_viewAllPatients,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Center(
            child: ElevatedButton(
              onPressed: () => context.push('/evv/select-patient'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, size: 20),
                  SizedBox(width: 8),
                  Text(
                    t.upcomingcheckinwidget_startEVSession,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientCheckInItem extends StatelessWidget {
  final String name;
  final String date;

  const _PatientCheckInItem({required this.name, required this.date});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () {}, child: Text(t.upcomingcheckinwidget_view)),
        ],
      ),
    );
  }
}
