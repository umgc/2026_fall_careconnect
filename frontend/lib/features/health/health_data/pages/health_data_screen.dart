import 'package:flutter/material.dart';
import '../models/health_record.dart';
import '../models/patient_demographics.dart';
import '../services/medicare_data_service.dart';
import '../services/ehr_data_service.dart';

import 'health_event_details_screen.dart';

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
  static const _warning = Color(0xFFF59E0B);
  // Hidden until these sections are backed by real patient data.
  static const bool _showConfirmationSection = false;
  static const bool _showConnectedProvidersSection = false;

  bool _loading = true;
  bool _synthetic = false;
  List<HealthRecord> _ehr = [];
  List<HealthRecord> _medicare = [];
  PatientDemographics? _patientDemographics;
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

  String _formatBirthDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$month/$day/${date.year}';
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
      final ehrService = EhrDataService();
      final ehrRecords = await ehrService.fetchRecords();
      final patientDemographics = await ehrService.fetchPatientDemographics();
      final medicareResult = await MedicareDataService().fetchRecords();

      if (!mounted) return;

      setState(() {
        _ehr = ehrRecords;
        _medicare = medicareResult.records;
        _patientDemographics = patientDemographics;
        _synthetic = medicareResult.synthetic;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allRecords = [..._ehr, ..._medicare];

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
                  'One searchable health history from all of your connected healthcare providers.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search your health history',
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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

                    final sidebar = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_patientDemographics != null)
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Patient Information',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Name',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _patientDemographics?.name ??
                                                  'Not available',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Date of Birth',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _patientDemographics?.birthDate !=
                                                      null
                                                  ? _formatBirthDate(
                                                      _patientDemographics!
                                                          .birthDate!)
                                                  : 'Not available',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Gender',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _patientDemographics?.gender == null
                                        ? 'Not available'
                                        : '${_patientDemographics!.gender![0].toUpperCase()}${_patientDemographics!.gender!.substring(1)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_showConfirmationSection) ...[
                          const SizedBox(height: 16),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color:
                                        Theme.of(context).colorScheme.tertiary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '2 items need your confirmation',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'A newly connected provider has different information for you.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {},
                                    child: const Text('Review'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (_showConnectedProvidersSection) ...[
                          const SizedBox(height: 16),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connected Providers',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add a Provider'),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _providerCard(
                                    name: 'Mercy Medical Center',
                                    location: 'Baltimore, MD',
                                  ),
                                  const SizedBox(height: 10),
                                  _providerCard(
                                    name: 'Main Street Primary Care',
                                    location: 'Baltimore, MD',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );

                    final healthHistory = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Your health history',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              '${records.length} events',
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
                        const SizedBox(height: 16),
                        Text(
                          'Health Information',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
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
                              label: 'Visits',
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
                        if (records.isEmpty)
                          _emptyResults()
                        else
                          ..._buildTimeline(records),
                      ],
                    );

                    if (!useTwoColumns) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sidebar,
                          const SizedBox(height: 24),
                          healthHistory,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: sidebar,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: healthHistory,
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

    return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 48,
        ),
        child: FilterChip(
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
        ));
  }

  Widget _providerCard({
    required String name,
    required String location,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  location,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
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
          : 'Health information without a date';

      if (group != currentGroup) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 12),
            child: Row(
              children: [
                Text(
                  group,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Divider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.type.label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const Spacer(),
                  if (r.status != null) _statusChip(r.status!),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                r.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (r.date != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Date',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(r.date!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              ...r.details.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => HealthEventDetailsScreen(
                        record: r,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        'View details',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
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
              fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
    );
  }
}
