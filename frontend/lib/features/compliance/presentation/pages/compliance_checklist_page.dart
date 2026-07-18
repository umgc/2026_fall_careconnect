import 'package:flutter/material.dart';
import 'package:care_connect_app/services/document_compliance_service.dart';

/// Required-document checklist for one subject (an employee being onboarded
/// or a care circle). Shows the status of every required document, lets
/// coordinators transition statuses with a mandatory reason, and exposes the
/// full audit trail of who changed what, when and why.
class ComplianceChecklistPage extends StatefulWidget {
  /// 'EMPLOYEE' or 'CARE_CIRCLE'.
  final String subjectType;
  final int subjectId;
  final String? subjectName;

  /// Whether the current user may transition statuses (coordinators only).
  final bool canEdit;

  const ComplianceChecklistPage({
    super.key,
    required this.subjectType,
    required this.subjectId,
    this.subjectName,
    this.canEdit = false,
  });

  @override
  State<ComplianceChecklistPage> createState() =>
      _ComplianceChecklistPageState();
}

class _ComplianceChecklistPageState extends State<ComplianceChecklistPage> {
  DocumentChecklist? _checklist;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  Future<void> _loadChecklist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final checklist = await DocumentComplianceService.getChecklist(
        widget.subjectType,
        widget.subjectId,
      );
      if (!mounted) return;
      setState(() {
        _checklist = checklist;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETE':
        return Colors.green;
      case 'IN_PROGRESS':
        return Colors.orange;
      case 'REJECTED':
        return Colors.red;
      case 'MISSING':
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'COMPLETE':
        return Icons.check_circle;
      case 'IN_PROGRESS':
        return Icons.hourglass_top;
      case 'REJECTED':
        return Icons.cancel;
      case 'MISSING':
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Future<void> _showChangeStatusDialog(ChecklistItem item) async {
    String selectedStatus = item.status;
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(
                'Update ${DocumentComplianceService.prettify(item.documentType)}',
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: DocumentComplianceService.statuses
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                    DocumentComplianceService.prettify(s)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedStatus = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Reason (required)',
                        hintText: 'Why is this status changing?',
                      ),
                      maxLines: 2,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'A reason is required for the audit trail'
                              : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      await DocumentComplianceService.updateStatus(
        subjectType: widget.subjectType,
        subjectId: widget.subjectId,
        documentType: item.documentType,
        status: selectedStatus,
        reason: reasonController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated')),
      );
      _loadChecklist();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showHistory(ChecklistItem? item) async {
    List<StatusHistoryEntry> history;
    try {
      history = await DocumentComplianceService.getHistory(
        widget.subjectType,
        widget.subjectId,
        documentType: item?.documentType,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load history: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (sheetContext, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    item != null
                        ? '${DocumentComplianceService.prettify(item.documentType)} history'
                        : 'Status change history',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? const Center(child: Text('No status changes recorded yet'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: history.length,
                          itemBuilder: (listContext, index) {
                            final entry = history[index];
                            final from = entry.previousStatus != null
                                ? DocumentComplianceService.prettify(
                                    entry.previousStatus!)
                                : 'Untracked';
                            final to = DocumentComplianceService.prettify(
                                entry.newStatus);
                            return ListTile(
                              leading: Icon(
                                _statusIcon(entry.newStatus),
                                color: _statusColor(entry.newStatus),
                              ),
                              title: Text(
                                '${DocumentComplianceService.prettify(entry.documentType)}: $from → $to',
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Reason: ${entry.reason}'),
                                  Text(
                                    'By ${entry.changedByName ?? 'user #${entry.changedBy}'}'
                                    '${entry.changedAt != null ? ' on ${_formatDate(entry.changedAt!)}' : ''}',
                                    style: Theme.of(listContext)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.subjectName ?? _checklist?.subjectName ?? 'Checklist';
    return Scaffold(
      appBar: AppBar(
        title: Text('$title - Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Status change history',
            onPressed: () => _showHistory(null),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChecklist,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Could not load checklist:\n$_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadChecklist,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildChecklist(),
    );
  }

  Widget _buildChecklist() {
    final checklist = _checklist!;
    return RefreshIndicator(
      onRefresh: _loadChecklist,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(checklist),
          const SizedBox(height: 16),
          ...checklist.items.map(_buildItemCard),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(DocumentChecklist checklist) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              checklist.subjectType == 'EMPLOYEE'
                  ? 'Employee onboarding documents'
                  : 'Care circle documents',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: checklist.requiredCount == 0
                  ? 0
                  : checklist.completeCount / checklist.requiredCount,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${checklist.completeCount} of ${checklist.requiredCount} required documents complete '
              '(${checklist.percentComplete}%)',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _countChip('Missing', checklist.missingCount, Colors.grey),
                _countChip(
                    'In progress', checklist.inProgressCount, Colors.orange),
                _countChip('Complete', checklist.completeCount, Colors.green),
                _countChip('Rejected', checklist.rejectedCount, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Chip(
      label: Text('$label: $count'),
      backgroundColor: color.withOpacity(0.15),
      side: BorderSide(color: color.withOpacity(0.4)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildItemCard(ChecklistItem item) {
    final color = _statusColor(item.status);
    final evidence = <String>[];
    if (item.fileCount > 0) {
      evidence.add(
          '${item.fileCount} uploaded file${item.fileCount == 1 ? '' : 's'}');
    }
    if (item.hasStructuredEntry) {
      evidence.add('digitized record');
    }
    if (evidence.isEmpty) {
      evidence.add('No documents on file');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_statusIcon(item.status), color: color, size: 32),
        title: Text(DocumentComplianceService.prettify(item.documentType)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(evidence.join(' · ')),
            if (item.latestFilename != null)
              Text(
                'Latest: ${item.latestFilename}',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            if (item.notes != null && item.notes!.isNotEmpty)
              Text(
                'Note: ${item.notes}',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(
                DocumentComplianceService.prettify(item.status),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              backgroundColor: color.withOpacity(0.12),
              visualDensity: VisualDensity.compact,
            ),
            if (widget.canEdit)
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'change') {
                    _showChangeStatusDialog(item);
                  } else if (action == 'history') {
                    _showHistory(item);
                  }
                },
                itemBuilder: (menuContext) => const [
                  PopupMenuItem(
                      value: 'change', child: Text('Change status...')),
                  PopupMenuItem(value: 'history', child: Text('View history')),
                ],
              ),
          ],
        ),
        onTap: widget.canEdit ? () => _showChangeStatusDialog(item) : null,
      ),
    );
  }
}
