import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Primary Care Provider Widget
class PrimaryCareProviderWidget extends StatelessWidget {
  final String providerName;
  final String specialty;
  final String organization;
  final String phone;
  final String email;
  final DateTime? nextAppointment;
  final String? appointmentType;
  final VoidCallback? onContactProvider;

  const PrimaryCareProviderWidget({
    super.key,
    required this.providerName,
    required this.specialty,
    required this.organization,
    required this.phone,
    required this.email,
    this.nextAppointment,
    this.appointmentType,
    this.onContactProvider,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
          Text(
            t.pcpwidget_pcpTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  providerName.split(' ').map((e) => e[0]).take(2).join(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      specialty,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      organization,
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
          const SizedBox(height: 20),
          Text(
            t.signup_accountContactInfo,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            phone,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            email,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (nextAppointment != null) ...[
            const SizedBox(height: 20),
            Text(
              t.pcpwidget_nextAppointment,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _formatAppointmentDate(nextAppointment!, t),
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              _formatAppointmentTime(nextAppointment!) +
                  (appointmentType != null ? ' - $appointmentType' : ''),
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContactProvider,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                t.pcpwidget_contactProvider,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats the appointment date into a more readable format
  String _formatAppointmentDate(DateTime date, AppLocalizations t) {
    final months = [
      t.pcpwidget_janLong,
      t.pcpwidget_febLong,
      t.pcpwidget_marLong,
      t.pcpwidget_aprLong,
      t.pcpwidget_mayLong,
      t.pcpwidget_junLong,
      t.pcpwidget_julLong,
      t.pcpwidget_augLong,
      t.pcpwidget_sepLong,
      t.pcpwidget_octLong,
      t.pcpwidget_novLong,
      t.pcpwidget_decLong,
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Formats the appointment time into a more readable format
  String _formatAppointmentTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $amPm';
  }
}
