import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/api_service_offline.dart';
import '../../../../services/auth_token_manager.dart';
import '../../../dashboard/models/patient_model.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../widgets/evv_month_calendar_view.dart';
import '../widgets/evv_week_calendar_view.dart';
import '../widgets/evv_day_schedule_view.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

enum _SchedulePerspective { caregiver, patient }

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduledVisit> _scheduledVisits = [];
  List<ScheduledVisit> _upcomingVisits = [];
  bool _isLoading = false;
  String _viewMode = 'list'; // 'list', 'month', 'week', 'day'
  DateTime _selectedDate = clock.now();
  Map<String, int> _summaryData = {
    'overdue': 0,
    'ready': 0,
    'upcoming': 0,
    'totalToday': 0,
  };

  // Internal pool used to compute summary consistently with UI
  List<ScheduledVisit> _summaryPool = [];

  // Perspective and filter state
  _SchedulePerspective _perspective = _SchedulePerspective.caregiver;
  bool _filtersExpanded = false;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  int? _filterPatientId;
  String? _filterServiceType;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final isPatient =
        (userProvider.user?.role.toUpperCase() ?? '') == 'PATIENT';
    _perspective = isPatient
        ? _SchedulePerspective.patient
        : _SchedulePerspective.caregiver;
    _loadScheduledVisits();
    _loadUpcomingVisits();
    _loadAndSetSummaryData();
  }

  Future<void> _refreshAllData() async {
    print('🔄 Refreshing all schedule data...');
    await Future.wait([
      _loadScheduledVisits(),
      _loadUpcomingVisits(),
      _loadAndSetSummaryData(),
    ]);
    print('✅ Data refresh complete');
  }

  Future<void> _loadAndSetSummaryData() async {
    final data = await _loadSummaryDataClientSide();
    setState(() {
      _summaryData = data;
    });
  }

  Future<void> _loadScheduledVisits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final isPatient =
          (userProvider.user?.role.toUpperCase() ?? '') == 'PATIENT';

      final headers = await AuthTokenManager.getAuthHeaders();
      final baseUrl = ApiConstants.baseUrl;

      // Fetch a range from the past 7 days up to today so we can include recent overdue items
      final now = clock.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final startStr = DateFormat('yyyy-MM-dd').format(weekAgo);
      final endStr = DateFormat('yyyy-MM-dd').format(now);

      final Uri url;
      if (isPatient) {
        final patientId = userProvider.user?.patientId ?? 0;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/patient/$patientId/range?startDate=$startStr&endDate=$endStr',
        );
      } else {
        final caregiverId = userProvider.user?.caregiverId ?? 1;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/caregiver/$caregiverId/range?startDate=$startStr&endDate=$endStr',
        );
      }

      print('🔍 Fetching scheduled visits (week range) from: $url');
      final response =
          await ApiServiceOffline.httpClient.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final all = data.map((json) => ScheduledVisit.fromJson(json)).toList();

        // Keep today's visits and overdue (within past 7 days) that are still Scheduled
        final today = DateTime(now.year, now.month, now.day);
        final startWindow = now.subtract(const Duration(days: 7));
        final visits = all.where((v) {
          final dt = v.scheduledTime;
          final isToday = dt.year == today.year &&
              dt.month == today.month &&
              dt.day == today.day;
          final isOverdueWithinWeek = dt.isBefore(now) &&
              dt.isAfter(startWindow) &&
              v.status == 'Scheduled';
          return isToday || isOverdueWithinWeek;
        }).toList()
          ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

        setState(() {
          _scheduledVisits = visits;
          _isLoading = false;
        });
      } else {
        throw Exception(
          'Failed to load scheduled visits: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error loading scheduled visits: $e');
      setState(() {
        _scheduledVisits = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUpcomingVisits() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final isPatient =
          (userProvider.user?.role.toUpperCase() ?? '') == 'PATIENT';

      final headers = await AuthTokenManager.getAuthHeaders();
      final baseUrl = ApiConstants.baseUrl;

      // Get date range: tomorrow to 30 days out
      final tomorrow = clock.now().add(const Duration(days: 1));
      final endDate = clock.now().add(const Duration(days: 30));

      final startDateStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      final Uri url;
      if (isPatient) {
        final patientId = userProvider.user?.patientId ?? 0;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/patient/$patientId/range?startDate=$startDateStr&endDate=$endDateStr',
        );
      } else {
        final caregiverId = userProvider.user?.caregiverId ?? 1;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/caregiver/$caregiverId/range?startDate=$startDateStr&endDate=$endDateStr',
        );
      }

      final response =
          await ApiServiceOffline.httpClient.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final visits =
            data.map((json) => ScheduledVisit.fromJson(json)).toList();

        // Sort by date and time
        visits.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

        setState(() {
          _upcomingVisits = visits;
        });
      } else {
        throw Exception(
          'Failed to load upcoming visits: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error loading upcoming visits: $e');
      setState(() {
        _upcomingVisits = [];
      });
    }
  }

  Future<Map<String, int>> _loadSummaryDataClientSide() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final isPatient =
          (userProvider.user?.role.toUpperCase() ?? '') == 'PATIENT';
      final headers = await AuthTokenManager.getAuthHeaders();
      final baseUrl = ApiConstants.baseUrl;

      final now = clock.now();
      final start = now.subtract(const Duration(days: 7));
      final end = now.add(const Duration(days: 30));
      final startStr = DateFormat('yyyy-MM-dd').format(start);
      final endStr = DateFormat('yyyy-MM-dd').format(end);

      final Uri url;
      if (isPatient) {
        final patientId = userProvider.user?.patientId ?? 0;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/patient/$patientId/range?startDate=$startStr&endDate=$endStr',
        );
      } else {
        final caregiverId = userProvider.user?.caregiverId ?? 1;
        url = Uri.parse(
          '${baseUrl}scheduled-visits/caregiver/$caregiverId/range?startDate=$startStr&endDate=$endStr',
        );
      }

      final response =
          await ApiServiceOffline.httpClient.get(url, headers: headers);
      if (response.statusCode != 200) {
        throw Exception('summary range fetch failed');
      }
      final List<dynamic> data = jsonDecode(response.body);
      _summaryPool = data.map((json) => ScheduledVisit.fromJson(json)).toList();

      int overdue = 0, ready = 0, upcoming = 0, totalToday = 0;
      for (final v in _summaryPool) {
        if (v.status != 'Scheduled') continue; // only pending visits
        final dt = v.scheduledTime;
        final isToday =
            dt.year == now.year && dt.month == now.month && dt.day == now.day;
        if (isToday) totalToday++;
        final diffMinutes = dt.difference(now).inMinutes;
        if (diffMinutes < 0) {
          overdue++;
        } else if (diffMinutes <= 30) {
          ready++;
        } else {
          upcoming++;
        }
      }
      return {
        'overdue': overdue,
        'ready': ready,
        'upcoming': upcoming,
        'totalToday': totalToday,
      };
    } catch (e) {
      print('Error computing summary client-side: $e');
      return _summaryData;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.evvScheduleTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllData,
            tooltip: AppLocalizations.of(context)!.evvScheduleRefresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPerspectiveToggle(context),
                _buildHeader(context),
                _buildFilterBar(context),
                if (_perspective == _SchedulePerspective.caregiver)
                  _buildViewModeSelector(context),
                Expanded(child: _buildViewContent(context)),
              ],
            ),
    );
  }

  Widget _buildViewModeSelector(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildViewModeButton(AppLocalizations.of(context)!.evvScheduleList, 'list', Icons.list, context),
            const SizedBox(width: 8),
            _buildViewModeButton(
              AppLocalizations.of(context)!.evvScheduleMonth,
              'month',
              Icons.calendar_month,
              context,
            ),
            const SizedBox(width: 8),
            _buildViewModeButton(AppLocalizations.of(context)!.evvScheduleWeek, 'week', Icons.view_week, context),
            const SizedBox(width: 8),
            _buildViewModeButton(AppLocalizations.of(context)!.evvScheduleDay, 'day', Icons.view_day, context),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeButton(
    String label,
    String mode,
    IconData icon,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSelected = _viewMode == mode;

    return FilterChip(
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _viewMode = mode;
          _selectedDate = clock.now();
        });
      },
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 4), Text(label)],
      ),
      backgroundColor: Colors.transparent,
      selectedColor: cs.primaryContainer,
      side: BorderSide(color: isSelected ? cs.primary : theme.dividerColor),
    );
  }

  String _localizedVisitStatus(String status) {
    final t = AppLocalizations.of(context)!;
    switch (status) {
      case 'Scheduled': return t.evvScheduleStatusScheduled;
      case 'In Progress': return t.evvScheduleStatusInProgress;
      case 'Completed': return t.evvScheduleStatusCompleted;
      case 'Cancelled': return t.evvScheduleStatusCancelled;
      default: return status;
    }
  }

  // ─── Filter helpers ────────────────────────────────────────────────────────

  bool get _hasActiveFilters =>
      _filterStartDate != null ||
      _filterEndDate != null ||
      _filterPatientId != null ||
      (_filterServiceType != null && _filterServiceType!.isNotEmpty) ||
      (_filterStatus != null && _filterStatus!.isNotEmpty);

  List<ScheduledVisit> _getFilteredVisits(List<ScheduledVisit> source) {
    return source.where((v) {
      if (_filterStartDate != null) {
        final start = DateTime(
          _filterStartDate!.year,
          _filterStartDate!.month,
          _filterStartDate!.day,
        );
        if (v.scheduledTime.isBefore(start)) return false;
      }
      if (_filterEndDate != null) {
        final end = DateTime(
          _filterEndDate!.year,
          _filterEndDate!.month,
          _filterEndDate!.day,
          23,
          59,
          59,
        );
        if (v.scheduledTime.isAfter(end)) return false;
      }
      if (_filterPatientId != null && v.patientId != _filterPatientId) {
        return false;
      }
      if (_filterServiceType != null &&
          _filterServiceType!.isNotEmpty &&
          v.serviceType != _filterServiceType) {
        return false;
      }
      if (_filterStatus != null &&
          _filterStatus!.isNotEmpty &&
          v.status != _filterStatus) {
        return false;
      }
      return true;
    }).toList();
  }

  // ─── Perspective toggle ────────────────────────────────────────────────────

  Widget _buildPerspectiveToggle(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_SchedulePerspective>(
              segments: [
                ButtonSegment(
                  value: _SchedulePerspective.caregiver,
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: Text(AppLocalizations.of(context)!.evvScheduleCaregiverView),
                ),
                ButtonSegment(
                  value: _SchedulePerspective.patient,
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(AppLocalizations.of(context)!.evvSchedulePatientView),
                ),
              ],
              selected: {_perspective},
              onSelectionChanged: (Set<_SchedulePerspective> sel) {
                setState(() => _perspective = sel.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.comfortable,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Badge(
            isLabelVisible: _hasActiveFilters,
            child: IconButton(
              tooltip: _filtersExpanded
                  ? AppLocalizations.of(context)!.evvScheduleHideFilters
                  : AppLocalizations.of(context)!.evvScheduleShowFilters,
              icon: Icon(
                _filtersExpanded ? Icons.filter_list_off : Icons.filter_list,
                color: _hasActiveFilters ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: () =>
                  setState(() => _filtersExpanded = !_filtersExpanded),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter bar ────────────────────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context) {
    if (!_filtersExpanded) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFormat = Localizations.localeOf(context).languageCode == 'es'
        ? DateFormat.yMMMd('es')
        : DateFormat('MMM d, yyyy');

    // Collect unique patients from loaded visits for the dropdown
    final allVisits = [..._scheduledVisits, ..._upcomingVisits];
    final patientMap = <int, String>{};
    for (final v in allVisits) {
      patientMap[v.patientId] = v.patientName;
    }

    const serviceTypes = [
      'Personal Care',
      'Medication Management',
      'Meal Preparation',
      'Light Housekeeping',
      'Companionship',
      'Transportation',
      'Respite Care',
      'Physical Therapy',
      'Occupational Therapy',
      'Skilled Nursing',
    ];

    const statuses = ['Scheduled', 'In Progress', 'Completed', 'Cancelled'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1 — Date range
          Row(
            children: [
              Expanded(
                child: _buildDateFilterField(
                  label: AppLocalizations.of(context)!.evvScheduleFrom,
                  value: _filterStartDate != null
                      ? dateFormat.format(_filterStartDate!)
                      : null,
                  icon: Icons.calendar_today_outlined,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _filterStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _filterStartDate = d);
                  },
                  onClear: _filterStartDate != null
                      ? () => setState(() => _filterStartDate = null)
                      : null,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateFilterField(
                  label: AppLocalizations.of(context)!.evvScheduleTo,
                  value: _filterEndDate != null
                      ? dateFormat.format(_filterEndDate!)
                      : null,
                  icon: Icons.event_outlined,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _filterEndDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _filterEndDate = d);
                  },
                  onClear: _filterEndDate != null
                      ? () => setState(() => _filterEndDate = null)
                      : null,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2 — Patient + Service Type
          Row(
            children: [
              Expanded(
                child: _buildDropdownFilter<int>(
                  label: AppLocalizations.of(context)!.evvSchedulePatient,
                  value: _filterPatientId,
                  icon: Icons.person_outline,
                  items: patientMap.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterPatientId = v),
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownFilter<String>(
                  label: AppLocalizations.of(context)!.evvScheduleServiceType,
                  value: _filterServiceType,
                  icon: Icons.medical_services_outlined,
                  items: serviceTypes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterServiceType = v),
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 3 — Status + Clear all
          Row(
            children: [
              Expanded(
                child: _buildDropdownFilter<String>(
                  label: AppLocalizations.of(context)!.evvScheduleStatus,
                  value: _filterStatus,
                  icon: Icons.flag_outlined,
                  items: statuses
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(_localizedVisitStatus(s))),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _filterStatus = v),
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _hasActiveFilters
                      ? () => setState(() {
                            _filterStartDate = null;
                            _filterEndDate = null;
                            _filterPatientId = null;
                            _filterServiceType = null;
                            _filterStatus = null;
                          })
                      : null,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(AppLocalizations.of(context)!.evvScheduleClearFilters),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: cs.error,
                    side: BorderSide(
                      color: _hasActiveFilters ? cs.error : theme.dividerColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterField({
    required String label,
    required String? value,
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback? onClear,
    required ThemeData theme,
  }) {
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClear,
                  padding: EdgeInsets.zero,
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: cs.surface,
        ),
        child: Text(
          value ?? AppLocalizations.of(context)!.evvScheduleAny,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: value != null ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownFilter<T>({
    required String label,
    required T? value,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required ThemeData theme,
  }) {
    final cs = theme.colorScheme;

    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: cs.surface,
      ),
      hint: Text(AppLocalizations.of(context)!.evvScheduleAny, style: TextStyle(color: cs.onSurfaceVariant)),
      items: [
        DropdownMenuItem<T>(
          value: null,
          child: Text(AppLocalizations.of(context)!.evvScheduleAny, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        ...items,
      ],
      onChanged: onChanged,
    );
  }

  // ─── Patient-centric view ──────────────────────────────────────────────────

  Widget _buildPatientCentricView(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final allFiltered = _getFilteredVisits(
      [..._scheduledVisits, ..._upcomingVisits],
    );

    // Group by patientId
    final Map<int, List<ScheduledVisit>> byPatient = {};
    for (final v in allFiltered) {
      byPatient.putIfAbsent(v.patientId, () => []).add(v);
    }

    // Sort each patient's list chronologically
    for (final list in byPatient.values) {
      list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    }

    // Sort patients by earliest visit
    final sortedPatients = byPatient.entries.toList()
      ..sort(
        (a, b) =>
            a.value.first.scheduledTime.compareTo(b.value.first.scheduledTime),
      );

    if (sortedPatients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.evvScheduleBatchNoMatchingVisits,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.evvScheduleBatchAdjustFilters,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '${AppLocalizations.of(context)!.evvSchedulePatientCount(sortedPatients.length)} · '
              '${AppLocalizations.of(context)!.evvScheduleVisitCount(allFiltered.length)}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ...sortedPatients.map((e) => _buildPatientCard(e.value, theme)),
        ],
      ),
    );
  }

  Widget _buildPatientCard(List<ScheduledVisit> visits, ThemeData theme) {
    final cs = theme.colorScheme;
    final patient = visits.first;

    final scheduled = visits.where((v) => v.status == 'Scheduled').length;
    final inProgress = visits.where((v) => v.status == 'In Progress').length;
    final completed = visits.where((v) => v.status == 'Completed').length;
    final cancelled = visits.where((v) => v.status == 'Cancelled').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.4),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primary,
                  child: Text(
                    patient.patientName.isNotEmpty
                        ? patient.patientName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.patientName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (scheduled > 0)
                            _buildStatusPill(
                              '$scheduled ${_localizedVisitStatus('Scheduled')}',
                              cs.primary,
                              cs.onPrimary,
                            ),
                          if (inProgress > 0)
                            _buildStatusPill(
                              '$inProgress ${_localizedVisitStatus('In Progress')}',
                              Colors.orange,
                              Colors.white,
                            ),
                          if (completed > 0)
                            _buildStatusPill(
                              '$completed ${_localizedVisitStatus('Completed')}',
                              Colors.green,
                              Colors.white,
                            ),
                          if (cancelled > 0)
                            _buildStatusPill(
                              '$cancelled ${_localizedVisitStatus('Cancelled')}',
                              cs.error,
                              cs.onError,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Visit rows
          ...visits.asMap().entries.map((entry) {
            final isLast = entry.key == visits.length - 1;
            return _buildPatientVisitRow(entry.value, isLast, theme);
          }),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPatientVisitRow(
    ScheduledVisit visit,
    bool isLast,
    ThemeData theme,
  ) {
    final cs = theme.colorScheme;
    final statusColor = _getStatusColor(visit.status);
    final locale = Localizations.localeOf(context).languageCode;
    final timeStr = locale == 'es'
        ? '${DateFormat.MMMd('es').format(visit.scheduledTime)} · ${DateFormat('HH:mm').format(visit.scheduledTime)}'
        : DateFormat('MMM d · HH:mm').format(visit.scheduledTime);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withOpacity(0.5),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.serviceType,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.5)),
            ),
            child: Text(
              _localizedVisitStatus(visit.status),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Main view content dispatcher ─────────────────────────────────────────

  Widget _buildViewContent(BuildContext context) {
    // Patient-centric perspective — ignore calendar view mode
    if (_perspective == _SchedulePerspective.patient) {
      return _buildPatientCentricView(context);
    }

    // Caregiver perspective — apply filters and route to selected view mode
    final allVisits = _getFilteredVisits(
      [..._scheduledVisits, ..._upcomingVisits],
    );

    switch (_viewMode) {
      case 'month':
        return SingleChildScrollView(
          child: EVVMonthCalendarView(
            visits: allVisits,
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() => _selectedDate = date);
            },
            onVisitTap: _handleVisitTap,
            onScheduleNew: _scheduleNewVisit,
          ),
        );
      case 'week':
        return SingleChildScrollView(
          child: EVVWeekCalendarView(
            visits: allVisits,
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() => _selectedDate = date);
            },
            onVisitTap: _handleVisitTap,
          ),
        );
      case 'day':
        return EVVDayScheduleView(
          visits: allVisits,
          selectedDate: _selectedDate,
          onDateSelected: (date) {
            setState(() => _selectedDate = date);
          },
          onVisitTap: _handleVisitTap,
        );
      case 'list':
      default:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildSummaryCards(context),
              const SizedBox(height: 24),
              _buildTodaysVisitsSection(),
              const SizedBox(height: 32),
              _buildUpcomingVisitsSection(),
              const SizedBox(height: 24),
            ],
          ),
        );
    }
  }

  void _handleVisitTap(ScheduledVisit visit) {
    // Open visit details or edit dialog
    showDialog(
      context: context,
      builder: (context) => _buildVisitDetailsDialog(visit),
    );
  }

  Widget _buildVisitDetailsDialog(ScheduledVisit visit) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(visit.patientName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('${AppLocalizations.of(context)!.evvScheduleServiceType}:', visit.serviceType, theme),
          const SizedBox(height: 12),
          _buildDetailRow(
            '${AppLocalizations.of(context)!.evvScheduleInfoDateTime}:',
            '${DateFormat('MMM d, yyyy').format(visit.scheduledTime)} at ${visit.scheduledTime.hour.toString().padLeft(2, '0')}:${visit.scheduledTime.minute.toString().padLeft(2, '0')}',
            theme,
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            '${AppLocalizations.of(context)!.evvScheduleDuration}:',
            '${visit.duration.inMinutes} minutes',
            theme,
          ),
          const SizedBox(height: 12),
          _buildDetailRow('${AppLocalizations.of(context)!.evvScheduleFormPriority}:', visit.priority, theme),
          const SizedBox(height: 12),
          _buildDetailRow('${AppLocalizations.of(context)!.evvScheduleStatus}:', _localizedVisitStatus(visit.status), theme),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.evvScheduleClose),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.evvScheduleManage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _scheduleNewVisit,
            icon: const Icon(Icons.add, size: 18),
            label: Text(AppLocalizations.of(context)!.evvScheduleNewVisit),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          // Give tiles more vertical room on narrow screens
          final crossAxisCount = isNarrow ? 2 : 4;
          final aspect = isNarrow ? 2.0 : 2.6;

          return GridView.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: aspect,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildSummaryCard(
                context: context,
                title: AppLocalizations.of(context)!.evvScheduleBatchOverdue,
                count: _summaryData['overdue'].toString(),
                icon: Icons.error_outline,
                iconColor: cs.error,
                iconBackgroundColor: cs.errorContainer.withOpacity(0.6),
              ),
              _buildSummaryCard(
                context: context,
                title: AppLocalizations.of(context)!.evvScheduleBatchReady,
                count: _summaryData['ready'].toString(),
                icon: Icons.play_arrow,
                iconColor: cs.tertiary,
                iconBackgroundColor: cs.tertiaryContainer.withOpacity(0.6),
              ),
              _buildSummaryCard(
                context: context,
                title: AppLocalizations.of(context)!.evvScheduleBatchUpcoming,
                count: _summaryData['upcoming'].toString(),
                icon: Icons.access_time,
                iconColor: cs.primary,
                iconBackgroundColor: cs.primaryContainer.withOpacity(0.6),
              ),
              _buildSummaryCard(
                context: context,
                title: AppLocalizations.of(context)!.evvScheduleBatchTotalToday,
                count: _summaryData['totalToday'].toString(),
                icon: Icons.calendar_today,
                iconColor: cs.secondary,
                iconBackgroundColor: cs.secondaryContainer.withOpacity(0.6),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required String title,
    required String count,
    required IconData icon,
    required Color iconColor,
    required Color iconBackgroundColor,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Cap text scale so accessibility settings do not overflow these compact tiles
    final cappedScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.2);

    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(cappedScale)),
      child: Container(
        // Allow it to grow if needed, but ensure a comfortable minimum
        constraints: const BoxConstraints(minHeight: 98),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Slightly smaller than headlineSmall to avoid overflow on dense UIs
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaysVisitsSection() {
    final theme = Theme.of(context);

    // Apply active filters then keep only pending scheduled visits
    final activeVisits = _getFilteredVisits(_scheduledVisits)
        .where((visit) => visit.status == 'Scheduled')
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.evvScheduleBatchTodayVisits,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          activeVisits.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: activeVisits.map((visit) {
                    return _buildTodayVisitCard(visit);
                  }).toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available,
              size: 64,
              color: cs.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.evvScheduleBatchNoToday,
              style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.evvCalendarScheduleHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getVisitStatus(ScheduledVisit visit) {
    if (visit.status != 'Scheduled') {
      return 'completed';
    }

    // Compare full date-times, as the summary counts do: the list also holds
    // still-Scheduled visits from earlier days, which are overdue whatever
    // their clock time.
    final diffMinutes = visit.scheduledTime.difference(clock.now()).inMinutes;

    if (diffMinutes < 0) {
      return 'overdue';
    } else if (diffMinutes <= 30) {
      return 'ready';
    } else {
      return 'upcoming';
    }
  }

  Widget _buildTodayVisitCard(ScheduledVisit visit) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _getVisitStatus(visit);

    Color backgroundColor;
    Color borderColor;
    Color statusBadgeColor;
    String statusText;
    String buttonText;
    IconData buttonIcon;

    if (status == 'overdue') {
      backgroundColor = cs.errorContainer.withOpacity(0.35);
      borderColor = cs.error;
      statusBadgeColor = cs.error;
      statusText = AppLocalizations.of(context)!.evvScheduleBatchOverdue;
      buttonText = AppLocalizations.of(context)!.evvScheduleBatchStartOverdue;
      buttonIcon = Icons.play_arrow;
    } else if (status == 'ready') {
      backgroundColor = cs.primaryContainer.withOpacity(0.35);
      borderColor = cs.primary;
      statusBadgeColor = cs.primary;
      statusText = AppLocalizations.of(context)!.evvScheduleBatchReady;
      buttonText = AppLocalizations.of(context)!.evvScheduleStartVisit;
      buttonIcon = Icons.play_arrow;
    } else {
      backgroundColor = cs.surface;
      borderColor = theme.dividerColor;
      statusBadgeColor = cs.outline;
      statusText = AppLocalizations.of(context)!.evvScheduleBatchUpcoming;
      buttonText = AppLocalizations.of(context)!.evvScheduleViewDetails;
      buttonIcon = Icons.info_outline;
    }

    final timeStr =
        '${visit.scheduledTime.hour.toString().padLeft(2, '0')}:${visit.scheduledTime.minute.toString().padLeft(2, '0')}';
    final durationHours = visit.duration.inHours;
    final durationMinutes = visit.duration.inMinutes.remainder(60);
    final durationStr = durationHours > 0
        ? '${durationHours}h ${durationMinutes}m'
        : '${durationMinutes}m';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: cs.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    visit.patientName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                if (status == 'overdue')
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.priority_high,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusBadgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              visit.serviceType,
              style: TextStyle(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.evvScheduleBatchScheduledTime,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.evvScheduleBatchEstimatedDuration,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
                Text(
                  durationStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (status == 'overdue' || status == 'ready') {
                    final encodedServiceType = Uri.encodeComponent(
                      visit.serviceType,
                    );
                    context.push(
                      '/evv/checkin-location?patientId=${visit.patientId}&serviceType=$encodedServiceType&scheduledVisitId=${visit.id}',
                    );
                  } else {
                    _viewVisitDetails(visit);
                  }
                },
                icon: Icon(buttonIcon, size: 18),
                label: Text(buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: status == 'overdue' ? cs.error : cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Scheduled':
        return Colors.blue;
      case 'In Progress':
        return Colors.orange;
      case 'Completed':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildUpcomingVisitsSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filteredUpcoming = _getFilteredVisits(_upcomingVisits);
    if (filteredUpcoming.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group visits by date
    final Map<String, List<ScheduledVisit>> groupedVisits = {};
    for (var visit in filteredUpcoming) {
      final dateKey = DateFormat('yyyy-MM-dd').format(visit.scheduledTime);
      groupedVisits.putIfAbsent(dateKey, () => []).add(visit);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (theme.brightness == Brightness.light)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.evvScheduleBatchUpcomingVisits,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            ...groupedVisits.entries.map((entry) {
              final dateStr = entry.key;
              final visits = entry.value;
              final date = DateTime.parse(dateStr);
              final formattedDate = (Localizations.localeOf(context).languageCode == 'es'
                  ? DateFormat.MMMMEEEEd('es')
                  : DateFormat('EEEE, MMMM d')).format(date);

              return _buildDateGroup(formattedDate, visits);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDateGroup(String dateLabel, List<ScheduledVisit> visits) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 16),
          child: Text(
            dateLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ),
        ...visits.asMap().entries.map((entry) {
          final index = entry.key;
          final visit = entry.value;
          final isLast = index == visits.length - 1;

          return _buildUpcomingVisitEntry(visit, isLast);
        }),
      ],
    );
  }

  Widget _buildUpcomingVisitEntry(ScheduledVisit visit, bool isLast) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final timeStr =
        '${visit.scheduledTime.hour.toString().padLeft(2, '0')}:${visit.scheduledTime.minute.toString().padLeft(2, '0')}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 4,
          child: Column(
            children: [
              Container(
                width: 4,
                height: isLast ? 60 : 80,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: isLast
                      ? const BorderRadius.only(
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primaryContainer, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              visit.patientName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          '${visit.serviceType} at $timeStr',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.evvScheduleBatchUpcoming.toLowerCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _scheduleNewVisit() {
    showDialog(
      context: context,
      builder: (context) => _ScheduleVisitDialog(
        onScheduled: () {
          _loadScheduledVisits();
          _loadUpcomingVisits();
          _loadAndSetSummaryData();
        },
      ),
    );
  }

  void _viewVisitDetails(ScheduledVisit visit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.evvScheduleDetailsTitle(visit.patientName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              AppLocalizations.of(context)!.evvScheduleServiceType,
              visit.serviceType,
              Theme.of(context),
            ),
            _buildDetailRow(
              AppLocalizations.of(context)!.evvScheduleTime,
              '${visit.scheduledTime.hour}:${visit.scheduledTime.minute.toString().padLeft(2, '0')}',
              Theme.of(context),
            ),
            _buildDetailRow(
              AppLocalizations.of(context)!.evvScheduleDuration,
              '${visit.duration.inHours}h ${visit.duration.inMinutes.remainder(60)}m',
              Theme.of(context),
            ),
            _buildDetailRow(AppLocalizations.of(context)!.evvScheduleStatus, _localizedVisitStatus(visit.status), Theme.of(context)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.evvScheduleClose),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/evv/select-patient');
            },
            child: Text(AppLocalizations.of(context)!.evvScheduleStartVisit),
          ),
        ],
      ),
    );
  }
}

// Schedule Visit Dialog
class _ScheduleVisitDialog extends StatefulWidget {
  final VoidCallback onScheduled;

  const _ScheduleVisitDialog({required this.onScheduled});

  @override
  State<_ScheduleVisitDialog> createState() => _ScheduleVisitDialogState();
}

class _ScheduleVisitDialogState extends State<_ScheduleVisitDialog> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  Patient? _selectedPatient;
  String? _selectedServiceType;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  int _duration = 60;
  String _priority = 'Normal';
  final TextEditingController _notesController = TextEditingController();

  // Data
  List<Patient> _patients = [];
  bool _isLoading = false;
  bool _isSubmitting = false;

  final List<String> _serviceTypes = [
    'Personal Care',
    'Medication Management',
    'Meal Preparation',
    'Light Housekeeping',
    'Companionship',
    'Transportation',
    'Respite Care',
    'Physical Therapy',
    'Occupational Therapy',
    'Skilled Nursing',
  ];

  final List<String> _priorities = ['Normal', 'High', 'Urgent'];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiverId = userProvider.user?.caregiverId ?? 1;

      final headers = await AuthTokenManager.getAuthHeaders();
      final baseUrl = ApiConstants.baseUrl;
      final url = Uri.parse('${baseUrl}caregivers/$caregiverId/patients');

      final response =
          await ApiServiceOffline.httpClient.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _patients = data.map((json) => Patient.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load patients');
      }
    } catch (e) {
      print('Error loading patients: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading patients: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _scheduleVisit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.evvScheduleFormSelectPatientError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedServiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.evvScheduleFormSelectServiceError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.evvScheduleFormSelectTimeError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final caregiverId = userProvider.user?.caregiverId ?? 1;

      final headers = await AuthTokenManager.getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final baseUrl = ApiConstants.baseUrl;
      final url = Uri.parse(
        '${baseUrl}scheduled-visits/caregiver/$caregiverId',
      );

      // Build request body
      final requestBody = {
        'patientId': _selectedPatient!.id,
        'serviceType': _selectedServiceType,
        'scheduledDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'scheduledTime':
            '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00',
        'durationMinutes': _duration,
        'priority': _priority,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
      };

      print('📤 Scheduling visit: $requestBody');

      final response = await ApiServiceOffline.httpClient.post(
        url,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.evvScheduleFormSuccess),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
          widget.onScheduled();
        }
      } else if (response.statusCode == 400) {
        // Handle conflict errors
        String errorMessage = 'Unable to schedule this visit';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData.containsKey('error')) {
            errorMessage = errorData['error'];
          }
        } catch (e) {
          // If JSON parsing fails, use the response body
          errorMessage = response.body;
        }
        throw Exception(errorMessage);
      } else {
        throw Exception('Unable to schedule this visit. Please try again.');
      }
    } catch (e) {
      print('Error scheduling visit: $e');
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        _showConflictDialog(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showConflictDialog(String errorMessage) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: cs.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.evvScheduleConflictTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.3),
                  border: Border.all(color: cs.error.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  errorMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  border: Border.all(color: cs.primary.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: cs.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.evvScheduleConflictAdvice,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.evvScheduleConflictSteps,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.evvScheduleConflictTryAgain,
              style: TextStyle(color: cs.primary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Reset the form to allow user to try again
              setState(() {
                _selectedTime = null;
              });
            },
            icon: const Icon(Icons.edit_calendar),
            label: Text(AppLocalizations.of(context)!.evvScheduleConflictModify),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.evvScheduleNewVisit,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Patient dropdown
                      _buildLabel(AppLocalizations.of(context)!.evvScheduleFormPatientRequired),
                      const SizedBox(height: 8),
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : DropdownButtonFormField<Patient>(
                              initialValue: _selectedPatient,
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.evvScheduleFormSelectPatient,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              items: _patients.map((patient) {
                                return DropdownMenuItem<Patient>(
                                  value: patient,
                                  child: Text(
                                    '${patient.firstName} ${patient.lastName}',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedPatient = value;
                                });
                              },
                            ),
                      const SizedBox(height: 16),

                      // Service Type dropdown
                      _buildLabel(AppLocalizations.of(context)!.evvScheduleFormServiceRequired),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedServiceType,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.evvScheduleFormSelectService,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: _serviceTypes.map((type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedServiceType = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Date and Time row
                      Row(
                        children: [
                          // Date picker
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel(AppLocalizations.of(context)!.evvScheduleFormDateRequired),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _selectDate(context),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: Text(
                                      (Localizations.localeOf(context).languageCode == 'es'
                                          ? DateFormat.yMd('es')
                                          : DateFormat('MM/dd/yyyy'))
                                          .format(_selectedDate),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Time picker
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel(AppLocalizations.of(context)!.evvScheduleFormTimeRequired),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _selectTime(context),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: Text(
                                      _selectedTime != null
                                          ? _selectedTime!.format(context)
                                          : '--:-- --',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Duration and Priority row
                      Row(
                        children: [
                          // Duration
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel(AppLocalizations.of(context)!.evvScheduleFormDurationMinutes),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: theme.dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove),
                                        onPressed: _duration > 15
                                            ? () {
                                                setState(() {
                                                  _duration = (_duration - 15)
                                                      .clamp(15, 480);
                                                });
                                              }
                                            : null,
                                        padding: const EdgeInsets.all(8),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            _duration.toString(),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: theme
                                                  .textTheme.bodyLarge?.color,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        onPressed: _duration < 480
                                            ? () {
                                                setState(() {
                                                  _duration = (_duration + 15)
                                                      .clamp(15, 480);
                                                });
                                              }
                                            : null,
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Priority
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel(AppLocalizations.of(context)!.evvScheduleFormPriority),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _priority,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: _priorities.map((priority) {
                                    return DropdownMenuItem<String>(
                                      value: priority,
                                      child: Text(priority),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _priority = value!;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      _buildLabel(AppLocalizations.of(context)!.evvScheduleFormNotes),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.evvScheduleFormNotesHint,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isSubmitting ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(AppLocalizations.of(context)!.evvScheduleFormCancel),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _scheduleVisit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(AppLocalizations.of(context)!.evvScheduleFormSubmit),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }
}

// Model class for scheduled visits
class ScheduledVisit {
  final int id;
  final int patientId;
  final String patientName;
  final String serviceType;
  final DateTime scheduledTime;
  final Duration duration;
  final String status;
  final String priority;

  ScheduledVisit({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.serviceType,
    required this.scheduledTime,
    required this.duration,
    required this.status,
    required this.priority,
  });

  factory ScheduledVisit.fromJson(Map<String, dynamic> json) {
    // Parse date and time from the response
    final dateStr = json['scheduledDate'] as String;
    final timeStr = json['scheduledTime'] as String;

    // Parse date (format: yyyy-MM-dd)
    final dateParts = dateStr.split('-');
    final year = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final day = int.parse(dateParts[2]);

    // Parse time (format: HH:mm:ss or HH:mm)
    final timeParts = timeStr.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    final scheduledDateTime = DateTime(year, month, day, hour, minute);
    final durationMinutes = json['durationMinutes'] as int;

    return ScheduledVisit(
      id: json['id'] as int,
      patientId: json['patientId'] as int,
      patientName: json['patientName'] as String,
      serviceType: json['serviceType'] as String,
      scheduledTime: scheduledDateTime,
      duration: Duration(minutes: durationMinutes),
      status: json['status'] as String,
      priority: json['priority'] as String? ?? 'Normal',
    );
  }
}
