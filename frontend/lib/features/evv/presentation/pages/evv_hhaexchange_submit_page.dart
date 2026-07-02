import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../services/evv_service.dart';
import '../../../../widgets/app_bar_helper.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../utils/file_handler_web_stub.dart'
    if (dart.library.html) '../../../../utils/file_handler_web.dart';

/// Allows a caregiver to review their APPROVED EVV visit records and
/// manually trigger submission to HHAExchange
/// (POST https://implementation.hhaexchange.com/api/v2/visits).
class EvvHhaExchangeSubmitPage extends StatefulWidget {
  const EvvHhaExchangeSubmitPage({super.key});

  @override
  State<EvvHhaExchangeSubmitPage> createState() =>
      _EvvHhaExchangeSubmitPageState();
}

class _EvvHhaExchangeSubmitPageState extends State<EvvHhaExchangeSubmitPage> {
  final EvvService _evvService = EvvService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<EvvRecord> _eligible = [];
  final Set<int> _selected = {};
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadEligible();
  }

  @override
  void dispose() {
    _evvService.dispose();
    super.dispose();
  }

  Future<void> _loadEligible() async {
    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });
    try {
      final records = await _evvService.getHhaExchangeEligibleRecords();
      if (!mounted) return;
      setState(() {
        _eligible = records;
        _selected.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading records: $e')),
      );
    }
  }

  Future<void> _submitSelected() async {
    if (_selected.isEmpty) return;
    setState(() {
      _isSubmitting = true;
      _resultMessage = null;
    });

    final ids = _selected.toList();

    // Step 1: Download the payload JSON before attempting submission.
    try {
      debugPrint('[HHAExchange] Starting payload fetch for ${ids.length} records');
      setState(() {
        _resultMessage = 'Fetching payload for download...';
        _resultSuccess = true; // Show as success while fetching
      });
      final payloadJson = await _evvService.getHhaExchangePayload(ids);
      debugPrint('[HHAExchange] Payload fetched successfully, length: ${payloadJson.length}');
      await _downloadPayloadFile(payloadJson, ids);
      setState(() {
        _resultMessage = 'Payload downloaded. Submitting to HHAExchange...';
        _resultSuccess = true;
      });
    } catch (e) {
      // Non-fatal – log the issue but proceed with submission attempt.
      debugPrint('[HHAExchange] Could not fetch payload for download: $e');
      setState(() {
        _resultMessage = 'Warning: Could not download payload ($e). Continuing with submission...';
        _resultSuccess = false;
      });
      // Wait a moment to show the warning
      await Future.delayed(const Duration(seconds: 3));
    }

    // Step 2: Submit to HHAExchange.
    try {
      final result = await _evvService.submitToHhaExchange(ids);
      if (!mounted) return;
      final count = result['submitted'] ?? ids.length;
      setState(() {
        _isSubmitting = false;
        _resultSuccess = true;
        _resultMessage =
            '$count visit(s) successfully submitted to HHAExchange.';
        _selected.clear();
      });
      // Refresh the list so submitted records no longer appear as APPROVED-pending
      await _loadEligible();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _resultSuccess = false;
        _resultMessage = 'Submission failed: $e';
      });
    }
  }

  /// Triggers a browser download of [payloadJson] as a timestamped JSON file.
  Future<void> _downloadPayloadFile(String payloadJson, List<int> ids) async {
    try {
      debugPrint('[HHAExchange] Starting payload download for ${ids.length} records');

      // Show download started notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading HHAExchange payload...')),
        );
      }

      // Pretty-print the JSON for readability.
      final pretty = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(payloadJson));
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filename = 'hhaexchange_payload_$ts.json';

      debugPrint('[HHAExchange] Creating file with filename: $filename');

      // Convert JSON string to bytes
      final bytes = utf8.encode(pretty) as Uint8List;

      // Use the proper web file handler
      final fileHandler = WebFileHandler();
      await fileHandler.downloadFile(filename, bytes, 'application/json');

      debugPrint('[HHAExchange] Payload download completed successfully');

      // Show download completed notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payload downloaded as $filename')),
        );
      }
    } catch (e) {
      debugPrint('[HHAExchange] Payload download failed: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download payload: $e')),
        );
      }
    }
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value == true) {
        _selected.addAll(_eligible.map((r) => r.id));
      } else {
        _selected.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allSelected =
        _eligible.isNotEmpty && _selected.length == _eligible.length;

    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/evv/hhaexchange-submit'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Submit to HHAExchange',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadEligible,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info banner ──────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: scheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: scheme.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select APPROVED visits to send to the Virginia HHAExchange '
                    'aggregator (https://implementation.hhaexchange.com/api/v2/visits). '
                    'Only VA-state records are forwarded.',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // ── Result banner ────────────────────────────────────────────────
          if (_resultMessage != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              color: _resultSuccess ? Colors.green.shade100 : Colors.red.shade100,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _resultSuccess ? Icons.check_circle : Icons.error,
                    color: _resultSuccess
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resultMessage!,
                      style: TextStyle(
                        color: _resultSuccess
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Select-all row ───────────────────────────────────────────────
          if (!_isLoading && _eligible.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: allSelected
                        ? true
                        : _selected.isEmpty
                            ? false
                            : null,
                    onChanged: _toggleAll,
                  ),
                  Text(
                    allSelected
                        ? 'Deselect all'
                        : 'Select all (${_eligible.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    Text(
                      '${_selected.length} selected',
                      style: TextStyle(color: scheme.primary),
                    ),
                ],
              ),
            ),

          // ── Record list ──────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _eligible.isEmpty
                    ? _EmptyState(onRefresh: _loadEligible)
                    : RefreshIndicator(
                        onRefresh: _loadEligible,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: _eligible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, i) {
                            final rec = _eligible[i];
                            final checked = _selected.contains(rec.id);
                            return _RecordTile(
                              record: rec,
                              checked: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(rec.id);
                                  } else {
                                    _selected.remove(rec.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      // ── Submit FAB ───────────────────────────────────────────────────────
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSubmitting ? null : _submitSelected,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                _isSubmitting
                    ? 'Submitting…'
                    : 'Submit ${_selected.length} Visit(s)',
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record tile
// ─────────────────────────────────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.record,
    required this.checked,
    required this.onChanged,
  });

  final EvvRecord record;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final patientName = record.patient != null
        ? '${record.patient!.firstName} ${record.patient!.lastName}'
        : record.individualName;

    final dateStr =
        '${record.dateOfService.year}-${record.dateOfService.month.toString().padLeft(2, '0')}'
        '-${record.dateOfService.day.toString().padLeft(2, '0')}';
    final timeIn =
        '${record.timeIn.hour.toString().padLeft(2, '0')}:${record.timeIn.minute.toString().padLeft(2, '0')}';
    final timeOut =
        '${record.timeOut.hour.toString().padLeft(2, '0')}:${record.timeOut.minute.toString().padLeft(2, '0')}';

    return Card(
      color: checked ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: checked
            ? BorderSide(color: scheme.primary, width: 1.5)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: CheckboxListTile(
        value: checked,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          patientName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${record.serviceType}  •  $dateStr'),
            Text(
              'Check-in: $timeIn  →  Check-out: $timeOut  |  State: ${record.stateCode}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        secondary: Chip(
          label: Text(record.status,
              style: const TextStyle(fontSize: 11, color: Colors.white)),
          backgroundColor: Colors.green.shade600,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'No eligible visits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'All approved visits have already been submitted,\nor there are no approved visits yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
