import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Header card for Patient Details.
/// Shows avatar, name/age/sex, optional vitals row (compact, under Allergies),
/// diagnoses chips, allergy pills, and call/video action buttons.
class PatientHeaderCard extends StatelessWidget {
  final String fullName;
  final String mrn;
  final int age;
  final String sex;

  // Mood (for the small block on the right)
  final String currentMoodLabel;
  final String currentMoodEmoji;

  // Optional vitals (if any is provided, the vitals bar will render)
  final int? heartRateBpm; // e.g. 72
  final int? bpSystolic; // e.g. 120
  final int? bpDiastolic; // e.g. 80
  final int? oxygenPercent; // e.g. 98
  final double? temperatureF; // e.g. 98.6

  final List<String> diagnoses;
  final List<String> allergies;

  /// NEW: numbers to dial for "Emergency Contacts" conference flow.
  final List<String> emergencyPhones;

  /// NEW: optional callbacks so callers can override button behavior.
  final VoidCallback? onStartVideoCall;
  final VoidCallback? onCallEmergencyContacts;

  const PatientHeaderCard({
    super.key,
    required this.fullName,
    required this.mrn,
    required this.age,
    required this.sex,
    required this.currentMoodLabel,
    required this.currentMoodEmoji,
    required this.diagnoses,
    required this.allergies,
    this.heartRateBpm,
    this.bpSystolic,
    this.bpDiastolic,
    this.oxygenPercent,
    this.temperatureF,
    this.emergencyPhones = const [],
    this.onStartVideoCall,
    this.onCallEmergencyContacts,
  });

  bool get _hasAnyVitals =>
      heartRateBpm != null ||
      (bpSystolic != null && bpDiastolic != null) ||
      oxygenPercent != null ||
      temperatureF != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 430;

    final borderColor = cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─────────────── Header Row ───────────────
          if (isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: cs.primary.withValues(alpha: .12),
                      child: Text(
                        (fullName.isNotEmpty ? fullName[0] : '?').toUpperCase(),
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Age $age • $sex',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: cs.onSurface.withValues(alpha: .7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _CallActions(
                  emergencyPhones: emergencyPhones,
                  onStartVideoCall: onStartVideoCall,
                  onCallEmergencyContacts: onCallEmergencyContacts,
                  compact: true,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Last Check-in: Today, 10:30 AM',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withValues(alpha: .75),
                      ),
                    ),
                    Text(
                      'Current Mood: $currentMoodEmoji $currentMoodLabel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT — avatar + name/age/sex
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: cs.primary.withValues(alpha: .12),
                        child: Text(
                          (fullName.isNotEmpty ? fullName[0] : '?')
                              .toUpperCase(),
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Age $age • $sex',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 16,
                                color: cs.onSurface.withValues(alpha: .7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // RIGHT — actions + right-side meta
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _CallActions(
                            emergencyPhones: emergencyPhones,
                            onStartVideoCall: onStartVideoCall,
                            onCallEmergencyContacts: onCallEmergencyContacts,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Last Check-in: Today, 10:30 AM',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface.withValues(alpha: .75),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Current Mood: $currentMoodEmoji $currentMoodLabel',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 2),

          // ─────────────── Diagnoses ───────────────
          if (diagnoses.isNotEmpty) ...[
            Text(
              'Primary Diagnoses',
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: diagnoses.map((d) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    d,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // ─────────────── Allergies ───────────────
          if (allergies.isNotEmpty) ...[
            Text(
              'Allergies',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allergies.map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    a,
                    style: TextStyle(
                      color: cs.onError,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: .2,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // ─────────────── Full-width compact vitals row (UNDER Allergies) ───────────────
          if (_hasAnyVitals) ...[
            const SizedBox(height: 10),
            _VitalsBarFullWidth(
              heartRateBpm: heartRateBpm,
              bpSystolic: bpSystolic,
              bpDiastolic: bpDiastolic,
              oxygenPercent: oxygenPercent,
              temperatureF: temperatureF,
            ),
          ],
        ],
      ),
    );
  }
}

/// ——— Action Buttons (top-right) ———
/// Adds real behavior:
/// • Start Video Call → navigates to a simple video-call screen stub (or uses provided callback)
/// • Emergency Contacts → conference-style flow (or uses provided callback)
class _CallActions extends StatelessWidget {
  const _CallActions({
    required this.emergencyPhones,
    this.onStartVideoCall,
    this.onCallEmergencyContacts,
    this.compact = false,
  });

  final List<String> emergencyPhones;
  final VoidCallback? onStartVideoCall;
  final VoidCallback? onCallEmergencyContacts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Future<void> dialNumber(String number) async {
      final uri = Uri(scheme: 'tel', path: number);
      final ok = await launchUrl(uri);
      if (!ok) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch dialer for $number')),
        );
      }
    }

    Future<void> callEmergencyConference() async {
      if (emergencyPhones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No emergency contacts configured')),
        );
        return;
      }

      // Dial the first contact
      await dialNumber(emergencyPhones.first);

      // If a second contact exists, guide the user to merge calls and dial the second
      if (emergencyPhones.length >= 2) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 4),
            content: Text(
              'In your Phone app, tap “Add Call”. We’ll then dial the next contact so you can Merge.',
            ),
          ),
        );

        await Future.delayed(const Duration(seconds: 3));
        await dialNumber(emergencyPhones[1]);
      }
    }

    final startButton = OutlinedButton.icon(
      onPressed: onStartVideoCall ??
          () {
            Navigator.of(context).push(
              TitledMaterialPageRoute(
                title: 'Video Call',
                builder: (_) => const _VideoCallScreen()),
            );
          },
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: Icon(Icons.videocam, color: cs.onSurface),
      label: Text(
        'Start Video Call',
        style: theme.textTheme.labelLarge?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final emergencyButton = ElevatedButton.icon(
      onPressed: onCallEmergencyContacts ?? callEmergencyConference,
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      icon: const Icon(Icons.phone),
      label: Text(
        'Emergency Contacts',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onPrimary,
        ),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          startButton,
          const SizedBox(height: 8),
          emergencyButton,
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 8,
      children: [startButton, emergencyButton],
    );
  }
}

/// A tiny stub screen to represent a video call session.
/// (Replace with your real implementation later.)
class _VideoCallScreen extends StatelessWidget {
  const _VideoCallScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Call'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          'Video call in progress…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

/// Full-width vitals row: each item expands to reach the end of the card.
class _VitalsBarFullWidth extends StatelessWidget {
  final int? heartRateBpm;
  final int? bpSystolic;
  final int? bpDiastolic;
  final int? oxygenPercent;
  final double? temperatureF;

  const _VitalsBarFullWidth({
    required this.heartRateBpm,
    required this.bpSystolic,
    required this.bpDiastolic,
    required this.oxygenPercent,
    required this.temperatureF,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];

    if (heartRateBpm != null) {
      tiles.add(
        _VitalBox(
          icon: Icons.favorite_outline,
          iconColor: Colors.redAccent,
          title: 'Heart Rate',
          value: '${heartRateBpm!} bpm',
        ),
      );
    }
    if (bpSystolic != null && bpDiastolic != null) {
      tiles.add(
        _VitalBox(
          icon: Icons.show_chart,
          iconColor: Colors.blueAccent,
          title: 'Blood Pressure',
          value: '$bpSystolic/$bpDiastolic mmHg',
        ),
      );
    }
    if (oxygenPercent != null) {
      tiles.add(
        _VitalBox(
          icon: Icons.air,
          iconColor: Colors.cyan[600] ?? Colors.cyan,
          title: 'Oxygen',
          value: '${oxygenPercent!} %',
        ),
      );
    }
    if (temperatureF != null) {
      tiles.add(
        _VitalBox(
          icon: Icons.thermostat,
          iconColor: Colors.deepOrange,
          title: 'Temperature',
          value: '${temperatureF!.toStringAsFixed(1)} °F',
        ),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    // Put them in a Row and let each one expand evenly.
    return Row(
      children: [
        for (int i = 0; i < tiles.length; i++) ...[
          Expanded(child: tiles[i]),
          if (i != tiles.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

/// A longer, compact vital box that expands in the row.
class _VitalBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _VitalBox({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      // Compact, but grows if needed to avoid overflow stripes
      constraints: const BoxConstraints(minHeight: 88),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: .75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
