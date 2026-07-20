import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/services/checkin_service.dart';

/// CheckIn Model
class CheckIn {
  final DateTime date;
  final String status;
  final String emoji;

  CheckIn({required this.date, required this.status, required this.emoji});

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      date: DateTime.parse(json['date']),
      status: json['status'] ?? '',
      emoji: json['emoji'] ?? '',
    );
  }

}

/// Recent CheckIns Widget
class RecentCheckInsWidget extends StatelessWidget {

  /// Call this from the patient side when the user checks in.
  static Future<bool> performCheckIn({
    required String patientId,
    required String caregiverId,
  }) async {
    return await CheckinService.addCheckin(patientId, caregiverId);
  }

  // Static counter to track all check-ins for caregiver dashboard linkage
  static int totalCheckIns = 0;

  /// This method updates the count whenever new check-ins are received
  static void updateCheckInCount(List<CheckIn> latestCheckIns) {
    totalCheckIns = latestCheckIns.length;
  }

  final List<CheckIn> checkIns;

  const RecentCheckInsWidget({super.key, required this.checkIns});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    
    // Update the counter each time this widget rebuilds
    RecentCheckInsWidget.updateCheckInCount(checkIns);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart,
                color: theme.colorScheme.tertiary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                t.recentcheckinwidget_widgetTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          
          // Add Check-In button for patient
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              label: Text(
                t.recentcheckinwidget_openCheckInButton,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: () {
                context.push('/virtual-checkin');
              },
            ),
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 16),
          ...checkIns
              .take(3)
              .map(
                (checkIn) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(checkIn.emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 16),
                      Text(
                        _formatDate(checkIn.date, t),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _translateMood(checkIn.status, t),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

String _translateMood(String status, AppLocalizations t){
  switch(status){
    case('Sad'):
      return t.recentcheckinwidget_moodSad;
    case('Down'):
      return t.recentcheckinwidget_moodDown;
    case('Okay'):
      return t.recentcheckinwidget_moodOkay;
    case('Happy'):
      return t.recentcheckinwidget_moodHappy;
    case('Great'):
      return t.recentcheckinwidget_moodGreat;
    case('Excellent'):
      return t.recentcheckinwidget_moodExcellent;
    default:
      return status;
  }
}

  /// Formats the date into a more readable format
  String _formatDate(DateTime date, AppLocalizations t) {
    final months = [
      t.recentcheckinwidget_janShort,
      t.recentcheckinwidget_febShort,
      t.recentcheckinwidget_marShort,
      t.recentcheckinwidget_aprShort,
      t.recentcheckinwidget_mayShort,
      t.recentcheckinwidget_junShort,
      t.recentcheckinwidget_julShort,
      t.recentcheckinwidget_augShort,
      t.recentcheckinwidget_sepShort,
      t.recentcheckinwidget_octShort,
      t.recentcheckinwidget_novShort,
      t.recentcheckinwidget_decShort,
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
