// caregiver_medicare_tab.dart
//
// The Medicare tab on a caregiver's patient page (WBS 6.2.58, FR-MCR-16/17).
// It reads that patient's coverage and visits with ?patientId=. Only the
// patient can connect or disconnect Medicare, so the one action here is Retry.

import 'package:flutter/material.dart';

import '../../health_data/models/health_record.dart';
import '../../health_data/pages/health_event_details_screen.dart';
import '../../health_data/services/medicare_data_service.dart';

class CaregiverMedicareTab extends StatefulWidget {
  /// The `patient.id` the caregiver is viewing, not a user id.
  final int patientId;
  final String patientName;

  const CaregiverMedicareTab({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<CaregiverMedicareTab> createState() => _CaregiverMedicareTabState();
}

class _CaregiverMedicareTabState extends State<CaregiverMedicareTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  MedicareFetchResult _result =
      const MedicareFetchResult(records: [], complete: false);

  // The spinner replaces the list while Retry reads again, which takes keyboard
  // focus away; these give it back to Retry, or to the result (DEF-MCR-34).
  final FocusNode _retryFocus = FocusNode(debugLabel: 'Medicare Retry');
  final FocusNode _contentFocus =
      FocusNode(debugLabel: 'Medicare tab content', skipTraversal: true);

  // Keep the result while the caregiver moves between tabs.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final hadFocus = _retryFocus.hasFocus;
    setState(() => _loading = true);
    MedicareFetchResult result =
        const MedicareFetchResult(records: [], complete: false);
    try {
      result =
          await MedicareDataService().fetchRecords(patientId: widget.patientId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // A node keeps its context after its button is gone; check it is
        // still mounted, i.e. this read failed again and Retry is back.
        (_retryFocus.context?.mounted == true ? _retryFocus : _contentFocus)
            .requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Loading Medicare records',
        ),
      );
    }

    final problem = _result.problem;
    // The API answers "not shared" and "not connected" the same way on
    // purpose (FR-MCR-17), so a caregiver sees one message for both.
    if (problem == MedicareReadProblem.notLinked) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _anchor(),
          _notice(
            Icons.lock_outline,
            '${widget.patientName} hasn\'t shared this with you.',
          ),
        ],
      );
    }

    if (problem == MedicareReadProblem.forbidden) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _anchor(),
          _notice(
            Icons.lock_outline,
            'Medicare data isn\'t available for this patient yet.',
          ),
        ],
      );
    }

    final records = _result.records;
    final coverage =
        records.where((r) => r.type != RecordType.claimService).toList();
    final visits =
        records.where((r) => r.type == RecordType.claimService).toList()
          ..sort((a, b) {
            if (a.date == null && b.date == null) return 0;
            if (a.date == null) return 1;
            if (b.date == null) return -1;
            return b.date!.compareTo(a.date!);
          });

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _anchor(),
        if (_result.synthetic)
          _notice(
            Icons.warning_amber_rounded,
            'Demo data: showing synthetic Medicare records, not a live account.',
          ),
        if (problem == MedicareReadProblem.linkExpired)
          _notice(
            Icons.link_off,
            'This patient\'s Medicare connection has expired. They need to '
            'connect it again before you can see current records.',
          )
        else if (!_result.complete)
          _notice(
            Icons.cloud_off_outlined,
            'We couldn\'t reach Medicare right now.',
            action: OutlinedButton.icon(
              focusNode: _retryFocus,
              style: OutlinedButton.styleFrom(foregroundColor: _accent()),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        if (_result.complete && records.isEmpty)
          _notice(Icons.info_outline, 'No Medicare records found.'),
        if (coverage.isNotEmpty) ...[
          _heading('Coverage'),
          ...coverage.map(_recordTile),
        ],
        if (visits.isNotEmpty) ...[
          _heading('Visits and claims'),
          ...visits.map(_recordTile),
        ],
      ],
    );
  }

  // The light theme's primary (00A7C8) is 2.85:1 as text on white, so use the
  // same darker teal as Health Data there; the dark theme's primary is fine.
  Color _accent() => Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.primary
      : const Color(0xFF006B80);

  // Where focus goes after a reload that removed Retry; Tab moves on from it.
  Widget _anchor() =>
      Focus(focusNode: _contentFocus, child: const SizedBox.shrink());

  Widget _notice(IconData icon, String text, {Widget? action}) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                        fontSize: 14, color: cs.onSurface, height: 1.4),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _recordTile(HealthRecord r) {
    final subtitle = [
      if (r.date != null) _formatDate(r.date!),
      if (r.status != null) r.status!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        minVerticalPadding: 12,
        title: Text(r.title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HealthEventDetailsScreen(record: r),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
