import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:care_connect_app/services/document_compliance_service.dart';
import 'compliance_checklist_page.dart';

/// Coordinator dashboard for Document Completion and Compliance Tracking.
///
/// The Overview tab lists every employee and care circle with their
/// required-document progress so onboarding blockers stand out; the Missing
/// Forms tab is a filterable, exportable report of outstanding documents.
class ComplianceDashboardPage extends StatefulWidget {
  const ComplianceDashboardPage({super.key});

  @override
  State<ComplianceDashboardPage> createState() =>
      _ComplianceDashboardPageState();
}

class _ComplianceDashboardPageState extends State<ComplianceDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Overview tab state
  List<ComplianceSummary> _summaries = [];
  bool _isLoadingSummaries = true;
  String? _summaryError;
  String _subjectTypeFilter = 'ALL'; // ALL | EMPLOYEE | CARE_CIRCLE
  bool _blockedOnly = false;

  // Missing forms tab state
  List<MissingDocument> _missing = [];
  bool _isLoadingMissing = true;
  String? _missingError;
  String _missingSubjectFilter = 'ALL';
  String _missingDocumentFilter = 'ALL';

  static const Map<String, String> _subjectFilterLabels = {
    'ALL': 'All',
    'EMPLOYEE': 'Employees',
    'CARE_CIRCLE': 'Care circles',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSummaries();
    _loadMissing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSummaries() async {
    setState(() {
      _isLoadingSummaries = true;
      _summaryError = null;
    });
    try {
      final summaries = await DocumentComplianceService.getDashboard(
        subjectType: _subjectTypeFilter == 'ALL' ? null : _subjectTypeFilter,
      );
      if (!mounted) return;
      setState(() {
        _summaries = summaries;
        _isLoadingSummaries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.toString();
        _isLoadingSummaries = false;
      });
    }
  }

  Future<void> _loadMissing() async {
    setState(() {
      _isLoadingMissing = true;
      _missingError = null;
    });
    try {
      final missing = await DocumentComplianceService.getMissing(
        subjectType:
            _missingSubjectFilter == 'ALL' ? null : _missingSubjectFilter,
        documentType:
            _missingDocumentFilter == 'ALL' ? null : _missingDocumentFilter,
      );
      if (!mounted) return;
      setState(() {
        _missing = missing;
        _isLoadingMissing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _missingError = e.toString();
        _isLoadingMissing = false;
      });
    }
  }

  Future<void> _exportMissing() async {
    try {
      final csv = await DocumentComplianceService.exportMissingCsv(
        subjectType:
            _missingSubjectFilter == 'ALL' ? null : _missingSubjectFilter,
        documentType:
            _missingDocumentFilter == 'ALL' ? null : _missingDocumentFilter,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Missing documents export (CSV)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy CSV'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csv));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV copied to clipboard')),
                  );
                }
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openChecklist(String subjectType, int subjectId, String subjectName) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (routeContext) => ComplianceChecklistPage(
              subjectType: subjectType,
              subjectId: subjectId,
              subjectName: subjectName,
              canEdit: true,
            ),
          ),
        )
        .then((_) {
      // Statuses may have changed while drilled in.
      _loadSummaries();
      _loadMissing();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Compliance'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.report_problem), text: 'Missing Forms'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadSummaries();
              _loadMissing();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOverviewTab(), _buildMissingTab()],
      ),
    );
  }

  // ==================== OVERVIEW TAB ====================

  Widget _buildOverviewTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _subjectFilterLabels.entries.map((entry) {
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: _subjectTypeFilter == entry.key,
                      onSelected: (_) {
                        setState(() => _subjectTypeFilter = entry.key);
                        _loadSummaries();
                      },
                    );
                  }).toList(),
                ),
              ),
              FilterChip(
                label: const Text('Blocked only'),
                selected: _blockedOnly,
                onSelected: (value) => setState(() => _blockedOnly = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingSummaries
              ? const Center(child: CircularProgressIndicator())
              : _summaryError != null
                  ? _buildError(_summaryError!, _loadSummaries)
                  : _buildSummaryList(),
        ),
      ],
    );
  }

  Widget _buildSummaryList() {
    final rows =
        _blockedOnly ? _summaries.where((s) => s.blocked).toList() : _summaries;
    if (rows.isEmpty) {
      return const Center(child: Text('No subjects to show'));
    }
    return RefreshIndicator(
      onRefresh: _loadSummaries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (listContext, index) => _buildSummaryCard(rows[index]),
      ),
    );
  }

  Widget _buildSummaryCard(ComplianceSummary summary) {
    final isEmployee = summary.subjectType == 'EMPLOYEE';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openChecklist(
            summary.subjectType, summary.subjectId, summary.subjectName),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEmployee ? Icons.badge : Icons.family_restroom,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.subjectName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (summary.blocked)
                    Chip(
                      label: const Text('Blocked'),
                      backgroundColor: Colors.red.withOpacity(0.12),
                      labelStyle: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isEmployee ? 'Employee' : 'Care circle',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: summary.requiredCount == 0
                    ? 0
                    : summary.completeCount / summary.requiredCount,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                '${summary.completeCount}/${summary.requiredCount} complete'
                '${summary.missingCount > 0 ? ' · ${summary.missingCount} missing' : ''}'
                '${summary.inProgressCount > 0 ? ' · ${summary.inProgressCount} in progress' : ''}'
                '${summary.rejectedCount > 0 ? ' · ${summary.rejectedCount} rejected' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== MISSING FORMS TAB ====================

  Widget _buildMissingTab() {
    final documentTypes = <String>{'ALL', ..._missing.map((m) => m.documentType)};
    if (_missingDocumentFilter != 'ALL' &&
        !documentTypes.contains(_missingDocumentFilter)) {
      documentTypes.add(_missingDocumentFilter);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _missingSubjectFilter,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    isDense: true,
                  ),
                  items: _subjectFilterLabels.entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _missingSubjectFilter = value);
                      _loadMissing();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _missingDocumentFilter,
                  decoration: const InputDecoration(
                    labelText: 'Document type',
                    isDense: true,
                  ),
                  items: documentTypes
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type == 'ALL'
                                  ? 'All'
                                  : DocumentComplianceService.prettify(type),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _missingDocumentFilter = value);
                      _loadMissing();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export as CSV',
                onPressed: _exportMissing,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingMissing
              ? const Center(child: CircularProgressIndicator())
              : _missingError != null
                  ? _buildError(_missingError!, _loadMissing)
                  : _buildMissingList(),
        ),
      ],
    );
  }

  Widget _buildMissingList() {
    if (_missing.isEmpty) {
      return const Center(
        child: Text('No missing or rejected required forms 🎉'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMissing,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _missing.length,
        itemBuilder: (listContext, index) {
          final row = _missing[index];
          final rejected = row.status == 'REJECTED';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                rejected ? Icons.cancel : Icons.warning_amber,
                color: rejected ? Colors.red : Colors.orange,
              ),
              title:
                  Text(DocumentComplianceService.prettify(row.documentType)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.subjectName} · '
                    '${row.subjectType == 'EMPLOYEE' ? 'Employee' : 'Care circle'}',
                  ),
                  if (row.notes != null && row.notes!.isNotEmpty)
                    Text(
                      'Note: ${row.notes}',
                      style: Theme.of(listContext).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: Chip(
                label: Text(
                  DocumentComplianceService.prettify(row.status),
                  style: TextStyle(
                    color: rejected ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor:
                    (rejected ? Colors.red : Colors.orange).withOpacity(0.12),
                visualDensity: VisualDensity.compact,
              ),
              onTap: () => _openChecklist(
                  row.subjectType, row.subjectId, row.subjectName),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError(String error, Future<void> Function() retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Something went wrong:\n$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
