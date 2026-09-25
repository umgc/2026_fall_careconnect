import 'package:flutter/material.dart';
import '../models/health_record.dart';
import '../services/medicare_data_service.dart';

class HealthDataScreen extends StatefulWidget {
  const HealthDataScreen({super.key});

  @override
  State<HealthDataScreen> createState() => _HealthDataScreenState();
}

class _HealthDataScreenState extends State<HealthDataScreen> {
  // Text colours meet WCAG 2.1 AA (4.5:1) on the page and on their own
  // 12% tints; the lighter originals (00A7C8, 6B7280, 10B981, F59E0B) did not.
  static const _teal = Color(0xFF006B80);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _green = Color(0xFF047857);
  static const _border = Color(0xFFE5E7EB);
  static const _warning = Color(0xFFF59E0B);

  bool _loading = true;
  bool _synthetic = false;
  List<HealthRecord> _medicare = [];
  String _searchQuery = '';
  final Set<RecordType> _selectedTypes = {};
  String _selectedDateRange = 'any';
  bool _sortNewestFirst = true;
  final TextEditingController _searchController = TextEditingController();

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _selectedTypes.clear();
      _selectedDateRange = 'any';
      _sortNewestFirst = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await MedicareDataService().fetchRecords();
      if (!mounted) return;
      setState(() {
        _medicare = result.records;
        _synthetic = result.synthetic;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HealthRecord> get _samples => [
        HealthRecord.single(
          id: 'epic-med-1',
          source: RecordSource.epic,
          type: RecordType.medication,
          title: 'Lisinopril 10 mg',
          status: 'Active',
          details: const [
            RecordDetail('Route', 'Oral'),
            RecordDetail('Prescriber', 'Dr. Sarah Mitchell'),
          ],
        ),
        HealthRecord.single(
          id: 'cerner-appt-1',
          source: RecordSource.cerner,
          type: RecordType.appointment,
          title: 'Primary Care Follow-Up',
          date: DateTime(2026, 9, 15),
          details: const [
            RecordDetail('Time', '10:30 AM'),
            RecordDetail('Provider', 'Dr. Sarah Mitchell'),
          ],
        ),
        HealthRecord.single(
          id: 'athena-visit-1',
          source: RecordSource.athena,
          type: RecordType.clinicalRecord,
          title: 'Annual Wellness Visit',
          date: DateTime(2026, 8, 22),
          details: const [RecordDetail('Provider', 'Dr. James Carter')],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final allRecords = [..._medicare, ..._samples];

    final records = allRecords.where((record) {
      final matchesType =
          _selectedTypes.isEmpty || _selectedTypes.contains(record.type);

      if (!matchesType) {
        return false;
      }

      if (_selectedDateRange != 'any') {
        if (record.date == null) {
          return false;
        }

        final now = DateTime.now();
        late DateTime cutoffDate;

        switch (_selectedDateRange) {
          case '3months':
            cutoffDate = DateTime(now.year, now.month - 3, now.day);
            break;
          case '6months':
            cutoffDate = DateTime(now.year, now.month - 6, now.day);
            break;
          case '1year':
            cutoffDate = DateTime(now.year - 1, now.month, now.day);
            break;
          case '2years':
            cutoffDate = DateTime(now.year - 2, now.month, now.day);
            break;
          default:
            cutoffDate = DateTime(1900);
        }

        if (record.date!.isBefore(cutoffDate)) {
          return false;
        }
      }

      if (_searchQuery.trim().isEmpty) {
        return true;
      }

      final query = _searchQuery.trim().toLowerCase();

      final searchableText = [
        record.title,
        record.type.label,
        record.status ?? '',
        ...record.sources.map((source) => source.label),
        ...record.details.map((detail) => detail.label),
        ...record.details.map((detail) => detail.value),
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList()
      ..sort((a, b) {
        // Keep records without a timeline date at the bottom.
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;

        return _sortNewestFirst
            ? b.date!.compareTo(a.date!)
            : a.date!.compareTo(b.date!);
      });

    final hasActiveFilters = _searchQuery.trim().isNotEmpty ||
        _selectedTypes.isNotEmpty ||
        _selectedDateRange != 'any' ||
        !_sortNewestFirst;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Data'),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _teal),
                  SizedBox(height: 16),
                  Text('Loading your health data…',
                      style: TextStyle(color: _muted)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_synthetic) _syntheticBanner(),
                const Text(
                  'View your health information from connected sources.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search health data',
                    hintText: 'Search visits, medications, providers...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Record Type',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _recordTypeChip(
                      label: 'All',
                      type: null,
                    ),
                    _recordTypeChip(
                      label: 'Medications',
                      type: RecordType.medication,
                    ),
                    _recordTypeChip(
                      label: 'Conditions',
                      type: RecordType.condition,
                    ),
                    _recordTypeChip(
                      label: 'Allergies',
                      type: RecordType.allergy,
                    ),
                    _recordTypeChip(
                      label: 'Appointments',
                      type: RecordType.appointment,
                    ),
                    _recordTypeChip(
                      label: 'Clinical Records',
                      type: RecordType.clinicalRecord,
                    ),
                    _recordTypeChip(
                      label: 'Claims',
                      type: RecordType.claimService,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 600;

                    Widget dateFilter() {
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedDateRange,
                        decoration: InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'any',
                            child: Text('Any time'),
                          ),
                          DropdownMenuItem(
                            value: '3months',
                            child: Text('Past 3 months'),
                          ),
                          DropdownMenuItem(
                            value: '6months',
                            child: Text('Past 6 months'),
                          ),
                          DropdownMenuItem(
                            value: '1year',
                            child: Text('Past year'),
                          ),
                          DropdownMenuItem(
                            value: '2years',
                            child: Text('Past 2 years'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;

                          setState(() {
                            _selectedDateRange = value;
                          });
                        },
                      );
                    }

                    Widget sortFilter() {
                      return DropdownButtonFormField<bool>(
                        initialValue: _sortNewestFirst,
                        decoration: InputDecoration(
                          labelText: 'Sort',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text('Newest first'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Oldest first'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;

                          setState(() {
                            _sortNewestFirst = value;
                          });
                        },
                      );
                    }

                    if (isNarrow) {
                      return Column(
                        children: [
                          dateFilter(),
                          const SizedBox(height: 12),
                          sortFilter(),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: dateFilter()),
                        const SizedBox(width: 12),
                        Expanded(child: sortFilter()),
                      ],
                    );
                  },
                ),
                if (hasActiveFilters) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Clear filters'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoColumns = constraints.maxWidth >= 900;

                    final healthRecords = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Health Records',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${records.length} ${records.length == 1 ? 'record' : 'records'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (records.isEmpty)
                          _emptyResults()
                        else
                          ..._buildTimeline(records),
                      ],
                    );

                    // Narrow layouts remain a single column.
                    if (!useTwoColumns) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          healthRecords,
                          const SizedBox(height: 24),
                          _connectedSourcesCard(allRecords),
                        ],
                      );
                    }

                    // Desktop/tablet landscape layout based on the Figma design.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _connectedSourcesCard(allRecords),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: healthRecords,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _recordTypeChip({
    required String label,
    required RecordType? type,
  }) {
    final selected =
        type == null ? _selectedTypes.isEmpty : _selectedTypes.contains(type);

    return FilterChip(
      label: Text(label),
      selected: selected,
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.primary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      showCheckmark: selected,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      onSelected: (_) {
        setState(() {
          if (type == null) {
            _selectedTypes.clear();
            return;
          }

          if (_selectedTypes.contains(type)) {
            _selectedTypes.remove(type);
          } else {
            _selectedTypes.add(type);
          }

          const displayedTypes = {
            RecordType.medication,
            RecordType.condition,
            RecordType.allergy,
            RecordType.appointment,
            RecordType.clinicalRecord,
            RecordType.claimService,
          };

          if (_selectedTypes.containsAll(displayedTypes)) {
            _selectedTypes.clear();
          }
        });
      },
    );
  }

  Widget _connectedSourcesCard(List<HealthRecord> records) {
    final sourceCounts = <RecordSource, int>{
      for (final source in RecordSource.values)
        source:
            records.where((record) => record.sources.contains(source)).length,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connected Sources',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...RecordSource.values.map((source) {
              final count = sourceCounts[source] ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _sourceColor(source),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        source.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? 'record' : 'records'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _syntheticBanner() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: _warning,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Demo data: showing synthetic Medicare records, not a live account.',
                style: TextStyle(
                  color: _text,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _sourceColor(RecordSource s) {
    switch (s) {
      case RecordSource.epic:
        return const Color(0xFF1D4ED8);
      case RecordSource.cerner:
        return const Color(0xFF047857);
      case RecordSource.athena:
        return const Color(0xFF92400E);
      case RecordSource.medicare:
        return _teal;
    }
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

  String _formatMonthYear(DateTime date) {
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

    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _emptyResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No health records found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try changing your search or filters.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTimeline(List<HealthRecord> records) {
    final widgets = <Widget>[];
    String? currentGroup;

    for (final record in records) {
      final group = record.date != null
          ? _formatMonthYear(record.date!)
          : 'Other health information';

      if (group != currentGroup) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              group,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        );

        currentGroup = group;
      }

      widgets.add(_recordCard(record));
    }

    return widgets;
  }

  Widget _recordCard(HealthRecord r) {
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (r.status != null) ...[
                    const SizedBox(width: 8),
                    _statusChip(r.status!),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                r.type.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (r.date != null) ...[
                const SizedBox(height: 2),
                Text(
                  _formatDate(r.date!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              ...r.details.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${d.label}: ',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                          ),
                          TextSpan(
                            text: d.value,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 8),
              _sourceBadges(r),
            ],
          ),
        ));
  }

  Widget _sourceBadges(HealthRecord r) {
    if (!r.isMultiSource) {
      return Text(
        'Source: ${r.primarySource.label}',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      children: [
        if (r.isMultiSource)
          Container(
            margin: const EdgeInsets.only(right: 6, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Found in ${r.sources.length} sources',
                style: const TextStyle(
                    fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
          ),
        ...r.sources.map((s) {
          final c = _sourceColor(s);
          return Container(
            margin: const EdgeInsets.only(right: 6, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.withValues(alpha: 0.4)),
            ),
            child: Text(s.badge,
                style: TextStyle(
                    fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          );
        }),
      ],
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status,
          style: const TextStyle(
              fontSize: 11,
              color: _green,
              fontWeight: FontWeight.w600)),
    );
  }
}
