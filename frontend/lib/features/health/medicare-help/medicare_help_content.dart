import 'package:flutter/material.dart';

import 'package:care_connect_app/l10n/app_localizations.dart';

/// Plain-language Medicare help (WBS 6.4.33).
///
/// Text only: these widgets show guidance and the SRS error messages, and hold
/// no API, OAuth, mapping or persistence logic. The Medicare screens (6.2.40,
/// 6.2.42) can drop in a single [MedicareHelpCard], the whole
/// [MedicareHelpList], or look up an error message with
/// [medicareErrorMessage].
enum MedicareHelpTopic {
  connect,
  consent,
  reconcile,
  disconnect,
  empty,
  errors
}

/// Heading and body text for one help topic.
({String title, String body}) medicareHelpText(
  AppLocalizations l10n,
  MedicareHelpTopic topic,
) {
  switch (topic) {
    case MedicareHelpTopic.connect:
      return (
        title: l10n.medicarehelp_connectTitle,
        body: l10n.medicarehelp_connectBody,
      );
    case MedicareHelpTopic.consent:
      return (
        title: l10n.medicarehelp_consentTitle,
        body: l10n.medicarehelp_consentBody,
      );
    case MedicareHelpTopic.reconcile:
      return (
        title: l10n.medicarehelp_reconcileTitle,
        body: l10n.medicarehelp_reconcileBody,
      );
    case MedicareHelpTopic.disconnect:
      return (
        title: l10n.medicarehelp_disconnectTitle,
        body: l10n.medicarehelp_disconnectBody,
      );
    case MedicareHelpTopic.empty:
      return (
        title: l10n.medicarehelp_emptyTitle,
        body: l10n.medicarehelp_emptyBody,
      );
    case MedicareHelpTopic.errors:
      return (
        title: l10n.medicarehelp_errorsTitle,
        body: l10n.medicarehelp_errorsBody,
      );
  }
}

/// The SRS section 8.6 message for a Medicare error code such as
/// `ERR-MCR-01`, or null for a code that isn't one of ERR-MCR-01 to 05.
String? medicareErrorMessage(AppLocalizations l10n, String code) {
  switch (code) {
    case 'ERR-MCR-01':
      return l10n.medicarehelp_errMcr01;
    case 'ERR-MCR-02':
      return l10n.medicarehelp_errMcr02;
    case 'ERR-MCR-03':
      return l10n.medicarehelp_errMcr03;
    case 'ERR-MCR-04':
      return l10n.medicarehelp_errMcr04;
    case 'ERR-MCR-05':
      return l10n.medicarehelp_errMcr05;
  }
  return null;
}

/// One help topic: a heading (announced as a heading by screen readers) and
/// its body text. Uses theme text styles so it follows the app's text size
/// and contrast settings.
class MedicareHelpCard extends StatelessWidget {
  const MedicareHelpCard({super.key, required this.topic});

  final MedicareHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final text = medicareHelpText(AppLocalizations.of(context)!, topic);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              header: true,
              child: Text(text.title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Text(text.body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Every help topic under a "Help with Medicare" heading, for a help screen or
/// bottom sheet.
class MedicareHelpList extends StatelessWidget {
  const MedicareHelpList({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text(
            l10n.medicarehelp_title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        for (final topic in MedicareHelpTopic.values)
          MedicareHelpCard(topic: topic),
      ],
    );
  }
}
