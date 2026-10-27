import 'package:flutter/material.dart';

import '../models/health_record.dart';
import '../services/ehr_resource_mapper.dart';
import '../services/record_reconciler.dart';

/// What the patient decided about a conflicting record (WBS 6.2.41: confirm,
/// separate or defer). Closing the dialog is "decide later".
class RecordConflictDecision {
  /// The version confirmed as correct, when one was.
  final HealthRecord? chosen;

  /// The versions are different records: show each separately.
  final bool keepBoth;

  const RecordConflictDecision.choose(HealthRecord this.chosen)
      : keepBoth = false;
  const RecordConflictDecision.keepBoth()
      : chosen = null,
        keepBoth = true;
}

/// Shows a record that several providers reported, for the patient to
/// resolve (WBS 6.2.41: confirm, separate or defer):
/// - [RecordConflictKind.differs]: pick the correct version or keep both.
/// - [RecordConflictKind.possibleDuplicate]: confirm it's one record or keep
///   both.
///
/// WBS 6.2.41 requires flagged records to be "presented with source and
/// provenance context", so each version names its source and when it was
/// last updated.
///
/// Returns null for "Decide later".
Future<RecordConflictDecision?> showRecordConflictDialog(
  BuildContext context,
  RecordConflict conflict, {
  int index = 1,
  int total = 1,
}) {
  return showDialog<RecordConflictDecision>(
    context: context,
    builder: (ctx) => _RecordConflictDialog(
        conflict: conflict, index: index, total: total),
  );
}

class _RecordConflictDialog extends StatelessWidget {
  const _RecordConflictDialog(
      {required this.conflict, required this.index, required this.total});

  final RecordConflict conflict;
  final int index;
  final int total;

  static const _teal = Color(0xFF006B80);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _changed = Color(0xFFFEF3C7);

  String get _title => switch (conflict.kind) {
        RecordConflictKind.differs => 'Which is correct?',
        RecordConflictKind.possibleDuplicate => 'Is this the same record?',
      };

  String get _intro => switch (conflict.kind) {
        RecordConflictKind.differs =>
          'Your providers have different details for what looks like the '
              'same record. Choose the version that\'s correct, or keep both '
              'if they\'re different records. Nothing is deleted.',
        RecordConflictKind.possibleDuplicate =>
          'Your providers both have this record with the same details, so '
              'Health Data shows it once. If they\'re different records, keep '
              'both. Nothing is deleted.',
      };

  @override
  Widget build(BuildContext context) {
    final versions = conflict.versions;
    final rows = _rows(versions);
    final textButton = TextButton.styleFrom(
        foregroundColor: _teal, minimumSize: const Size(48, 48));
    return AlertDialog(
      // Drawn for a white surface in both themes (WCAG 1.4.3).
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      titleTextStyle: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w600, color: _text),
      title: Text(total > 1 ? '$_title ($index of $total)' : _title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _intro,
                style: const TextStyle(fontSize: 15, height: 1.4, color: _text),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < versions.length; i++) ...[
                _versionCard(context, i, versions[i], rows),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: textButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Decide later'),
        ),
        TextButton(
          style: textButton,
          onPressed: () => Navigator.of(context)
              .pop(const RecordConflictDecision.keepBoth()),
          child: const Text('Keep both'),
        ),
        if (conflict.kind == RecordConflictKind.possibleDuplicate)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            onPressed: () => Navigator.of(context)
                .pop(RecordConflictDecision.choose(versions.first)),
            child: const Text('Same record'),
          ),
      ],
    );
  }

  Widget _versionCard(BuildContext context, int i, HealthRecord v,
      List<(String, List<String>)> rows) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Version ${i + 1}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: _text)),
          const SizedBox(height: 2),
          Text(_provenance(v),
              style: const TextStyle(fontSize: 13, color: _muted)),
          const SizedBox(height: 8),
          for (final (label, values) in rows)
            _field(label, values[i], differs: values.toSet().length > 1),
          if (conflict.kind == RecordConflictKind.differs) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () =>
                  Navigator.of(context).pop(RecordConflictDecision.choose(v)),
              child: Text('Use version ${i + 1}'),
            ),
          ),
          ],
        ],
      ),
    );
  }

  /// "From Epic, updated Oct 14, 2026".
  static String _provenance(HealthRecord v) {
    final updated = v.details
        .where((d) => d.label == EhrResourceMapper.lastUpdatedLabel)
        .firstOrNull
        ?.value;
    return 'From ${v.primarySource.label}'
        '${updated == null ? '' : ', updated $updated'}';
  }

  Widget _field(String label, String value, {required bool differs}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: differs
          ? BoxDecoration(
              color: _changed, borderRadius: BorderRadius.circular(6))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _muted)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 14, color: _text)),
          ),
          if (differs)
            Semantics(
              label: 'Different',
              child: const Icon(Icons.compare_arrows, size: 16, color: _muted),
            ),
        ],
      ),
    );
  }

  /// Label plus each version's value, for the fields worth comparing.
  static List<(String, List<String>)> _rows(List<HealthRecord> versions) {
    final rows = <(String, List<String>)>[
      ('Record', versions.map((v) => v.title).toList()),
      ('Status', versions.map((v) => v.status ?? '').toList()),
      ('Date',
          versions.map((v) => v.date == null ? '' : _date(v.date!)).toList()),
    ];
    final labels = <String>{
      for (final v in versions)
        for (final d in v.details)
          // Retrieval time is provenance, shown under each version instead.
          if (d.label != EhrResourceMapper.lastUpdatedLabel) d.label,
    };
    for (final label in labels) {
      rows.add((
        label,
        versions
            .map((v) =>
                v.details.where((d) => d.label == label).firstOrNull?.value ??
                '')
            .toList(),
      ));
    }
    return rows;
  }

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
