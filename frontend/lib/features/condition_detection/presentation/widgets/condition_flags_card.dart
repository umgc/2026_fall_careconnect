import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../../config/theme/app_theme.dart';
import '../../models/condition_flags.dart';

/// Post-call AI condition screening: one section per model with its status, and the
/// mandatory "not a diagnosis" disclaimer. Never shown to patients — the host screen gates
/// it and the backend refuses patients regardless.
///
/// Results arrive asynchronously; in-progress models tell the user to pull to refresh.
class ConditionFlagsCard extends StatelessWidget {
  /// `null` means the request failed.
  final ConditionFlagsResult? result;

  const ConditionFlagsCard({super.key, required this.result});

  static const String voiceModelId = 'kintsugi-dam-3.1';
  static const String transcriptModelId = 'bedrock-transcript-screen-v1';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final data = result;
    return Card(
      key: const Key('conditionFlagsCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.conditionFlags_title,
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Disclaimer(text: l10n.conditionFlags_disclaimer),
            const SizedBox(height: 12),
            if (data == null)
              Text(l10n.conditionFlags_loadError,
                  style: theme.textTheme.bodyMedium)
            else
              for (final run in data.runs) ...[
                _ModelSection(run: run),
                if (run != data.runs.last) const Divider(height: 24),
              ],
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  final String text;

  const _Disclaimer({required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? AppTheme.warningDarkTheme : AppTheme.warning;
    final fg = dark ? AppTheme.warningDarkTheme : const Color(0xFF92400E);
    return Semantics(
      label: AppLocalizations.of(context)!.disclaimerLabel,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: dark ? 0.15 : 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.40)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 16, color: fg, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelSection extends StatelessWidget {
  final ConditionModelRun run;

  const _ModelSection({required this.run});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_modelName(l10n, run),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (run.isInProgress)
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.conditionFlags_statusProcessing)),
            ],
          )
        else if (run.status == 'COMPLETE')
          for (final flag in run.flags) _FlagRow(flag: flag)
        else if (run.status == 'SKIPPED')
          Text(_skipText(l10n, run.skipReason),
              style: theme.textTheme.bodyMedium)
        else
          Text(l10n.conditionFlags_statusFailed,
              style: theme.textTheme.bodyMedium),
      ],
    );
  }

  static String _modelName(AppLocalizations l10n, ConditionModelRun run) {
    switch (run.modelId) {
      case ConditionFlagsCard.voiceModelId:
        return l10n.conditionFlags_modelVoice;
      case ConditionFlagsCard.transcriptModelId:
        return l10n.conditionFlags_modelTranscript;
      default:
        return run.displayName.isNotEmpty ? run.displayName : run.modelId;
    }
  }

  static String _skipText(AppLocalizations l10n, String? reason) {
    switch (reason) {
      case 'CALL_TOO_SHORT':
        return l10n.conditionFlags_skipCallTooShort;
      case 'NO_RECORDING':
        return l10n.conditionFlags_skipNoRecording;
      case 'NO_PATIENT_AUDIO':
        return l10n.conditionFlags_skipNoPatientAudio;
      case 'INSUFFICIENT_SPEECH':
        return l10n.conditionFlags_skipInsufficientSpeech;
      case 'AUDIO_EXPIRED':
        return l10n.conditionFlags_skipAudioExpired;
      case 'TRANSCRIPT_UNAVAILABLE':
        return l10n.conditionFlags_skipTranscriptUnavailable;
      case 'TRANSCRIPT_TIMEOUT':
        return l10n.conditionFlags_skipTranscriptTimeout;
      case 'PATIENT_SPEAKER_UNIDENTIFIED':
        return l10n.conditionFlags_skipPatientSpeakerUnidentified;
      case 'MODEL_UNAVAILABLE':
        return l10n.conditionFlags_skipModelUnavailable;
      default:
        return l10n.conditionFlags_skipUnknown;
    }
  }
}

class _FlagRow extends StatelessWidget {
  final ConditionFlagItem flag;

  const _FlagRow({required this.flag});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final condition = _conditionName(l10n, flag.condition);
    final severity = _severityName(l10n, flag.severityLabel);
    final color = _severityColor(theme, flag.severityLevel);
    final evidence = flag.evidenceSummary;
    return Semantics(
      label: evidence == null || evidence.isEmpty
          ? '$condition: $severity'
          : '$condition: $severity. $evidence',
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(condition, style: theme.textTheme.bodyLarge)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        flag.severityLevel == 0
                            ? Icons.check_circle_outline
                            : Icons.flag_outlined,
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 4),
                      Text(severity,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: color)),
                    ],
                  ),
                ),
              ],
            ),
            if (evidence != null && evidence.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(evidence, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  static Color _severityColor(ThemeData theme, int level) {
    final dark = theme.brightness == Brightness.dark;
    switch (level) {
      case 0:
        return theme.colorScheme.onSurfaceVariant;
      case 1:
        return dark ? AppTheme.warningDarkTheme : const Color(0xFF92400E);
      default:
        return theme.colorScheme.error;
    }
  }

  static String _conditionName(AppLocalizations l10n, String condition) {
    switch (condition) {
      case 'DEPRESSION':
        return l10n.conditionFlags_conditionDepression;
      case 'ANXIETY':
        return l10n.conditionFlags_conditionAnxiety;
      case 'PTSD':
        return l10n.conditionFlags_conditionPtsd;
      case 'BIPOLAR':
        return l10n.conditionFlags_conditionBipolar;
      default:
        return condition;
    }
  }

  static String _severityName(AppLocalizations l10n, String label) {
    switch (label) {
      case 'NONE':
        return l10n.conditionFlags_severityNone;
      case 'LOW':
        return l10n.conditionFlags_severityLow;
      case 'MILD':
        return l10n.conditionFlags_severityMild;
      case 'MILD_TO_MODERATE':
        return l10n.conditionFlags_severityMildToModerate;
      case 'MODERATE':
        return l10n.conditionFlags_severityModerate;
      case 'SEVERE':
        return l10n.conditionFlags_severitySevere;
      case 'HIGH':
        return l10n.conditionFlags_severityHigh;
      default:
        return label;
    }
  }
}
