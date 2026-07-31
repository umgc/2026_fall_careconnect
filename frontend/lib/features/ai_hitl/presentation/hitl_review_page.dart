import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter/material.dart';

/// Clinician review screen: edit/release or reject a held Ask AI answer.
class HitlReviewPage extends StatefulWidget {
  const HitlReviewPage({
    super.key,
    required this.heldItemId,
    this.api,
  });

  final String heldItemId;
  final HitlApiService? api;

  @override
  State<HitlReviewPage> createState() => _HitlReviewPageState();
}

class _HitlReviewPageState extends State<HitlReviewPage> {
  late final HitlApiService _api;
  late Future<HitlDetail> _future;
  final _answerController = TextEditingController();
  final _notesController = TextEditingController();
  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? HitlApiService.instance;
    _future = _loadDetail();
  }

  Future<HitlDetail> _loadDetail() async {
    final detail = await _api.fetchDetail(widget.heldItemId);
    if (mounted) {
      _answerController.text = detail.draftAnswer ?? '';
    }
    return detail;
  }

  @override
  void dispose() {
    _answerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadDetail();
      _actionError = null;
    });
    await _future;
  }

  Future<void> _release(HitlDetail detail) async {
    final edited = _answerController.text.trim();
    if (detail.requiresEditedAnswer &&
        (edited.isEmpty || edited == (detail.draftAnswer ?? '').trim())) {
      setState(() {
        _actionError =
            'Unsupported-claim holds require an edited answer before release.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final String? editedAnswer =
          edited.isEmpty || edited == (detail.draftAnswer ?? '').trim()
              ? null
              : edited;
      await _api.release(
        widget.heldItemId,
        editedAnswer: editedAnswer,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Reject held answer'),
          content: TextField(
            key: const Key('hitl-reject-reason'),
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('hitl-reject-confirm'),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await _api.reject(
        widget.heldItemId,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = error.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review held answer'),
      ),
      body: FutureBuilder<HitlDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load held item.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final detail = snapshot.data!;
          final pending = detail.isPending;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Patient ${detail.patientId}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('Status: ${detail.status} · ${detail.deliveryStatus}'),
              if (detail.triggerCodes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Triggers: ${detail.triggerCodes.join(', ')}'),
              ],
              const SizedBox(height: 16),
              Text('Original question', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(detail.queryText?.trim().isNotEmpty == true
                  ? detail.queryText!
                  : '(no query text)'),
              const SizedBox(height: 16),
              Text(
                pending ? 'Answer to release' : 'Draft answer',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('hitl-edited-answer'),
                controller: _answerController,
                enabled: pending && !_busy,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  helperText: detail.requiresEditedAnswer
                      ? 'Unsupported claim: edit the answer before release.'
                      : 'Leave unchanged to release the draft as-is.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('hitl-review-notes'),
                controller: _notesController,
                enabled: pending && !_busy,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Reviewer notes (optional)',
                ),
              ),
              if (_actionError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _actionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              if (pending)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('hitl-reject-button'),
                        onPressed: _busy ? null : _reject,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('hitl-release-button'),
                        onPressed: _busy ? null : () => _release(detail),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Release'),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  detail.finalAnswer?.isNotEmpty == true
                      ? 'Final answer: ${detail.finalAnswer}'
                      : 'This hold is no longer pending.',
                ),
            ],
          );
        },
      ),
    );
  }
}
