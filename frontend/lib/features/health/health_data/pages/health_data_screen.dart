import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/epic_service.dart';
import '../../../../services/oracle_health_service.dart';
import '../models/health_record.dart';
import '../models/patient_demographics.dart';
import '../services/medicare_data_service.dart';
import '../services/ehr_data_service.dart';
import '../services/identity_conflict_service.dart';
import '../services/athena_connect_service.dart';
import '../services/athena_data_service.dart';
import '../services/record_choice_store.dart';
import '../services/record_reconciler.dart';
import '../widgets/athena_connect_tile.dart';
import '../widgets/record_conflict_dialog.dart';
import '../../../../widgets/epic_connect_tile.dart';

import 'health_event_details_screen.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? lookupAppLocalizations(const Locale('en'));

class HealthDataScreen extends StatefulWidget {
  final int? patientId;

  const HealthDataScreen({
    super.key,
    this.patientId,
  });

  @override
  State<HealthDataScreen> createState() => _HealthDataScreenState();
}

class _HealthDataScreenState extends State<HealthDataScreen> {
  // Text colours meet WCAG 2.1 AA (4.5:1) on the page and on their own
  // 12% tints; the lighter originals (00A7C8, 6B7280, 10B981, F59E0B) did not.
  static const _teal = Color(0xFF006B80);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  // Darker green for text on the tinted status chip: 4.22:1 -> 5.89:1.
  static const _greenText = Color(0xFF065F46);
  static const _warning = Color(0xFFF59E0B);
  // Confirmation remains hidden until it is backed by real patient data.
  static const bool _showConfirmationSection = false;
  static const bool _showConnectedProvidersSection = true;

  // The app's light-theme primary (00A7C8) is 2.85:1 as text on white, so text
  // that would use it uses _teal instead; the dark theme's primary is fine.
  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primary
          : _teal;

  Color _onAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.onPrimary
          : Colors.white;

  // _muted is for light surfaces; on the dark page use the theme's own.
  Color _mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : _muted;

  bool _loading = true;
  bool _synthetic = false;
  bool _medicareUnreachable = false;
  bool? _epicConnected;
  bool? _oracleHealthConnected;
  MedicareReadProblem? _medicareProblem;
  bool _ehrUnavailable = false;
  bool _medicareEmpty = false;
  List<HealthRecord> _ehr = [];
  List<HealthRecord> _medicare = [];
  List<HealthRecord> _athena = [];
  AthenaReadProblem? _athenaProblem;

  /// Every source's records with duplicates merged (Epic preferred).
  List<HealthRecord> _records = [];

  /// Records whose providers disagree and the patient hasn't decided.
  List<RecordConflict> _conflicts = [];
  Map<String, String> _choices = {};

  /// Conflicts the automatic review has already opened for, by storage key.
  /// While this screen is open, each one pops up by itself once: a conflict
  /// that appears after a reload (connecting athenahealth, confirming the
  /// date of birth) pops up too, but one the patient put off with "Decide
  /// later" stays in the banner instead of asking again.
  final Set<String> _autoReviewed = {};
  final RecordChoiceStore _choiceStore = RecordChoiceStore();
  PatientDemographics? _patientDemographics;

  /// Epic and athenahealth disagree on the date of birth and the patient
  /// hasn't confirmed which is right yet.
  bool _dobNeedsConfirmation = false;
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

  // TODO: Use the patient-confirmed DOB once the DOB confirmation flow
  // is connected to the unified health data screen.
  String _formatBirthDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMMd(locale).format(date);
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
    // Each source loads on its own, so one failing never hides the others.
    final ehrService = EhrDataService();

    bool? epicConnected;
    try {
      final epicStatus = await EpicService.status();
      epicConnected = epicStatus['connected'] == true;
    } catch (_) {}
    bool? oracleHealthConnected;
    try {
      final oracleStatus = await OracleHealthService.status();
      oracleHealthConnected = oracleStatus.connected;
    } catch (_) {}
    List<HealthRecord>? ehrRecords;
    try {
      ehrRecords = await ehrService.tryFetchRecords(
        patientId: widget.patientId,
      );
    } catch (_) {}
    PatientDemographics? demographics;
    var dobNeedsConfirmation = false;
    Map<String, PatientDemographics?> bySource = const {};
    try {
      bySource = await ehrService.fetchDemographicsBySource();
      demographics = EhrDataService.mergeDemographics(bySource);
    } catch (_) {}
    // Separate, so a date-of-birth check that fails still shows the card.
    try {
      final resolved = await _resolveBirthDate(demographics, bySource);
      demographics = resolved.$1;
      dobNeedsConfirmation = resolved.$2;
    } catch (_) {}
    MedicareFetchResult medicare =
        const MedicareFetchResult(records: [], complete: false);
    try {
      medicare = await MedicareDataService().fetchRecords();
    } catch (_) {}
    AthenaFetchResult athena = const AthenaFetchResult(
        records: [], complete: false, problem: AthenaReadProblem.unreachable);
    try {
      athena = await AthenaDataService().fetchRecords();
    } catch (_) {}
    athena = await _explainAthenaFailure(athena);
    final choices = await _choiceStore.load();

    if (!mounted) return;
    setState(() {
      _epicConnected = epicConnected;
      _oracleHealthConnected = oracleHealthConnected;
      _choices = choices;
      _ehr = (ehrRecords ?? []).where((record) {
        if (athena.complete &&
            record.sources.contains(RecordSource.athena)) {
          return false;
        }
        if (medicare.complete &&
            record.sources.contains(RecordSource.medicare)) {
          return false;
        }
        return true;
      }).toList();
      _ehrUnavailable = ehrRecords == null;
      _medicareProblem = medicare.problem;
      _medicare = medicare.records;
      _patientDemographics = demographics;
      _dobNeedsConfirmation = dobNeedsConfirmation;
      _synthetic = medicare.synthetic;
      _medicareUnreachable = !medicare.complete;
      _medicareEmpty = medicare.complete && medicare.records.isEmpty;
      _athena = athena.records;
      _athenaProblem = athena.problem;
      _reconcile();
      _loading = false;
    });
    // Only records whose details differ pop up by themselves, and each only
    // once while this screen is open (see [_autoReviewed]); possible
    // duplicates wait in the banner.
    final fresh = [
      for (final c in _conflicts)
        if (c.kind == RecordConflictKind.differs &&
            !_autoReviewed.contains(c.storageKey))
          c,
    ];
    if (fresh.isNotEmpty) {
      _autoReviewed.addAll(fresh.map((c) => c.storageKey));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reviewConflicts(only: fresh);
      });
    }
  }

  /// A failed athena read is only "unreachable" for a patient who is
  /// connected. A server with athena turned off can't even say 404: its
  /// catch-all error handler answers 500 for the missing route. So ask the
  /// status, and read anything but "connected" as not connected, as Epic's
  /// tile does.
  Future<AthenaFetchResult> _explainAthenaFailure(AthenaFetchResult r) async {
    if (r.problem != AthenaReadProblem.unreachable) return r;
    AthenaStatus? status;
    try {
      status = await AthenaConnectService.instance.status();
    } catch (_) {}
    if (status != null && status.connected) return r;
    return AthenaFetchResult(
      records: r.records,
      complete: false,
      problem: status != null && !status.shown
          ? AthenaReadProblem.hidden
          : AthenaReadProblem.notConnected,
    );
  }

  /// When Epic and athenahealth disagree on the date of birth, the patient
  /// confirms which is right through the DOB confirmation flow
  /// (FR-XSRC-10…15) instead of Epic's silently winning. Until they choose,
  /// the current (Epic) date stays shown and the screen asks them to confirm.
  /// Returns the demographics to show and whether a confirmation is pending.
  Future<(PatientDemographics?, bool)> _resolveBirthDate(
      PatientDemographics? merged,
      Map<String, PatientDemographics?> bySource) async {
    // By name: a source that isn't fetched is simply null.
    final current = bySource['EPIC']?.birthDate;
    final incoming = bySource['ATHENAHEALTH']?.birthDate;
    if (merged == null ||
        current == null ||
        incoming == null ||
        DateUtils.isSameDay(current, incoming)) {
      return (merged, false);
    }
    final chosen = await IdentityConflictService.reportDobDisagreement(
      current: current,
      currentSource: RecordSource.epic.label,
      incoming: incoming,
      incomingSource: RecordSource.athena.label,
    );
    return chosen == null
        ? (merged, true)
        : (merged.withBirthDate(chosen), false);
  }

  Future<void> _confirmDob() async {
    await GoRouter.of(context).push('/dob-confirm');
    // The patient may have chosen a date there.
    if (mounted) _load();
  }

  void _reconcile() {
    final result = RecordReconciler.reconcile(
        [..._ehr, ..._medicare, ..._athena],
        choices: _choices);
    _records = result.records;
    _conflicts = result.unresolved;
  }

  /// Goes through each flagged record in turn. "Decide later" stops and
  /// leaves the rest flagged (WBS 6.2.41). [only] is the automatic review
  /// on load, which asks only about the new records whose details differ;
  /// the banner's Review goes through every flagged record.
  Future<void> _reviewConflicts({List<RecordConflict>? only}) async {
    final pending = List.of(only ?? _conflicts);
    for (var i = 0; i < pending.length; i++) {
      final conflict = pending[i];
      final decision = await showRecordConflictDialog(context, conflict,
          index: i + 1, total: pending.length);
      if (!mounted) return;
      final versions = conflict.versions.map(RecordConflict.versionId).toList();
      if (decision == null) {
        await _choiceStore.logDecision(RecordDecisionEntry(
            at: DateTime.now(), decision: 'deferred', versions: versions));
        break;
      }
      final encoded = decision.keepBoth
          ? RecordReconciler.encodeKeepBoth(conflict)
          : RecordReconciler.encodeChoice(conflict, decision.chosen!);
      _choices = {..._choices, conflict.storageKey: encoded};
      await _choiceStore.save(conflict.storageKey, encoded);
      await _choiceStore.logDecision(RecordDecisionEntry(
        at: DateTime.now(),
        decision: decision.keepBoth ? 'keep_both' : 'confirmed',
        versions: versions,
        chosen: decision.chosen == null
            ? null
            : RecordConflict.versionId(decision.chosen!),
      ));
      if (!mounted) return;
      setState(_reconcile);
    }
  }

  /// One line for every kind of flagged record.
  String _conflictSummary() {
    int count(RecordConflictKind k) =>
        _conflicts.where((c) => c.kind == k).length;
    String plural(int n, String one, String many) => n == 1 ? one : many;
    final differs = count(RecordConflictKind.differs);
    final duplicates = count(RecordConflictKind.possibleDuplicate);
    return [
      if (differs > 0)
        '$differs ${plural(differs, 'record has', 'records have')} '
            'different details from your providers.',
      if (duplicates > 0)
        '$duplicates possible duplicate '
            '${plural(duplicates, 'record was', 'records were')} combined.',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final allRecords = _records;

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
        title: Text(l10n.healthDataTitle),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _teal),
                  const SizedBox(height: 16),
                  Text(l10n.healthDataLoading,
                      style: TextStyle(color: _mutedText(context))),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_synthetic) _syntheticBanner(),
                if (_medicareProblem == MedicareReadProblem.linkExpired)
                  _noticeBanner(
                    Icons.link_off,
                    // SRS ERR-MCR-05 (FR-MCR-09, AC-MCR-09-1), exact wording.
                    l10n.healthDataMedicareExpired,
                    action: _connectMedicareButton(),
                  ),
                // Normal not-connected status is now shown in Connected Sources.
                // Keep this banner available in case UI/UX decides to restore it.
                // else if (_medicareProblem == MedicareReadProblem.notLinked)
                //   _noticeBanner(
                //     Icons.link_off,
                //     'Medicare isn\'t connected yet.',
                //     action: _connectMedicareButton(),
                //   )
                if (_medicareUnreachable &&
                    _medicareProblem != MedicareReadProblem.notLinked &&
                    _medicareProblem != MedicareReadProblem.linkExpired)
                  _noticeBanner(
                    Icons.cloud_off_outlined,
                    // SRS ERR-MCR-03 (FR-MCR-24, AC-MCR-24-2), exact wording.
                    l10n.healthDataMedicareUpdateUnavailable,
                    warning: true,
                  ),
                // Normal athenahealth not-connected status is now shown in Connected Sources.
                // Keep this banner available in case UI/UX decides to restore it.
                // if (_athenaProblem == AthenaReadProblem.notConnected &&
                //     _mayConnectAthena())
                //   _noticeBanner(
                //     Icons.link_off,
                //     'athenahealth isn\'t connected yet.',
                //     // Consent and connect happen right here, then the screen
                //     // reloads with the new records.
                //     action: AthenaConnectTile(
                //       buttonOnly: true,
                //       onChanged: () {
                //         if (mounted) _load();
                //       },
                //     ),
                //   ),
                if (_athenaProblem == AthenaReadProblem.unreachable)
                  _noticeBanner(
                    Icons.cloud_off_outlined,
                    'We couldn\'t load records from your other providers. Showing what we could.',
                    warning: true,
                  ),
                if (_ehrUnavailable)
                  _noticeBanner(
                    Icons.cloud_off_outlined,
                    'We couldn\'t load records from your connected health sources. Showing what we could.',
                    warning: true,
                  ),

                // Normal connected status is now shown in Connected Sources.
                // Keep this banner available in case UI/UX decides to restore it.
                // else
                //   _noticeBanner(
                //     Icons.check_circle_outline,
                //     'Connected to Oracle Health. Your Oracle Health records are included in your health history.',
                //   ),

                // Normal connected status is now shown in Connected Sources.
                // Keep this banner available in case UI/UX decides to restore it.
                // else
                //   _noticeBanner(
                //     Icons.check_circle_outline,
                //     'Connected to Oracle Health. Your Oracle Health records are included in your health history.',
                //   ),
                if (_dobNeedsConfirmation)
                  _noticeBanner(
                    Icons.cake_outlined,
                    'Your providers have different dates of birth for you. '
                    'Please confirm which is correct.',
                    action: TextButton(
                      onPressed: _confirmDob,
                      style: TextButton.styleFrom(
                        foregroundColor: _accent(context),
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                if (_conflicts.isNotEmpty)
                  _noticeBanner(
                    Icons.compare_arrows,
                    _conflictSummary(),
                    action: TextButton(
                      onPressed: () => _reviewConflicts(),
                      style: TextButton.styleFrom(
                        foregroundColor: _teal,
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Review'),
                    ),
                  ),
                if (_medicareEmpty)
                  _noticeBanner(
                    Icons.info_outline,
                    // SRS AC-MCR-28-1 (FR-MCR-28).
                    l10n.healthDataMedicareNoRecords,
                  ),
                Text(
                  l10n.healthDataHistoryDescription,
                  style: TextStyle(color: _mutedText(context)),
                ),
                if (_showManageMedicare())
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _manageMedicare,
                      style: TextButton.styleFrom(
                          foregroundColor: _accent(context),
                          minimumSize: const Size(48, 48)),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Manage Medicare connection'),
                    ),
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
                          l10n.search,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: l10n.healthDataSearchHistory,
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
                      label: Text(l10n.healthDataClearFilters),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Only reserve the left column when something is in it;
                    // an empty one pushed the records off-centre.
                    final hasSidebar = _patientDemographics != null ||
                        _showConfirmationSection ||
                        _showConnectedProvidersSection;
                    final useTwoColumns =
                        hasSidebar && constraints.maxWidth >= 900;

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
                                    l10n.healthDataPatientInformation,
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
                                              l10n.healthDataName,
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
                                                  l10n.healthDataNotAvailable,
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
                                              l10n.healthDataDateOfBirth,
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
                                                      context,
                                                      _patientDemographics!
                                                          .birthDate!,
                                                    )
                                                  : l10n.healthDataNotAvailable,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (_dobNeedsConfirmation)
                                              Text(
                                                'Needs your confirmation',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          _mutedText(context),
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    l10n.healthDataGender,
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
                                        ? l10n.healthDataNotAvailable
                                        : _localizedGender(
                                            _patientDemographics!.gender!),
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
                                    style: TextButton.styleFrom(
                                      foregroundColor: _accent(context),
                                      minimumSize: const Size(48, 48),
                                    ),
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
                                    'Connected Sources',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  _providerCard(
                                    name: 'Epic (MyChart)',
                                    status: _epicConnected == null
                                        ? 'Status unavailable'
                                        : _epicConnected!
                                            ? 'Connected'
                                            : 'Not connected',
                                    connected: _epicConnected == true,
                                    action: _epicConnected == null
                                        ? TextButton(
                                            onPressed: _load,
                                            style: TextButton.styleFrom(
                                              foregroundColor: _accent(context),
                                              minimumSize: const Size(48, 48),
                                            ),
                                            child: const Text('Retry'),
                                          )
                                        : _epicConnected == false
                                            ? EpicConnectTile(
                                                buttonOnly: true,
                                                onChanged: () {
                                                  if (mounted) _load();
                                                },
                                              )
                                            : null,
                                  ),
                                  const Divider(height: 1),
                                  _providerCard(
                                    name: 'Oracle Health',
                                    status: _oracleHealthConnected == null
                                        ? 'Status unavailable'
                                        : _oracleHealthConnected!
                                            ? 'Connected'
                                            : 'Not connected',
                                    connected: _oracleHealthConnected == true,
                                    action: _oracleHealthConnected == null
                                        ? TextButton(
                                            onPressed: _load,
                                            style: TextButton.styleFrom(
                                              foregroundColor: _accent(context),
                                              minimumSize: const Size(48, 48),
                                            ),
                                            child: const Text('Retry'),
                                          )
                                        : _oracleHealthConnected == false
                                            ? TextButton(
                                                onPressed: () async {
                                                  try {
                                                    await OracleHealthService
                                                        .connect();
                                                    if (mounted) {
                                                      await _load();
                                                    }
                                                  } catch (_) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Unable to start Oracle Health connection.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      _accent(context),
                                                  minimumSize:
                                                      const Size(48, 48),
                                                ),
                                                child: const Text('Connect'),
                                              )
                                            : null,
                                  ),
                                  const Divider(height: 1),
                                  _providerCard(
                                    name: 'Athena Health',
                                    status: _athenaProblem ==
                                            AthenaReadProblem.notConnected
                                        ? 'Not connected'
                                        : _athenaProblem ==
                                                AthenaReadProblem.unreachable
                                            ? 'Status unavailable'
                                            : _athenaProblem ==
                                                    AthenaReadProblem.hidden
                                                ? 'Unavailable'
                                                : 'Connected',
                                    connected: _athenaProblem == null,
                                    action: _athenaProblem ==
                                            AthenaReadProblem.unreachable
                                        ? TextButton(
                                            onPressed: _load,
                                            style: TextButton.styleFrom(
                                              foregroundColor: _accent(context),
                                              minimumSize: const Size(48, 48),
                                            ),
                                            child: const Text('Retry'),
                                          )
                                        : _athenaProblem ==
                                                    AthenaReadProblem
                                                        .notConnected &&
                                                _mayConnectAthena()
                                            ? AthenaConnectTile(
                                                buttonOnly: true,
                                                onChanged: () {
                                                  if (mounted) _load();
                                                },
                                              )
                                            : null,
                                  ),
                                  const Divider(height: 1),
                                  _providerCard(
                                    name: 'Medicare',
                                    status: _medicareProblem ==
                                            MedicareReadProblem.notLinked
                                        ? 'Not connected'
                                        : _medicareProblem ==
                                                MedicareReadProblem.linkExpired
                                            ? 'Connection expired'
                                            : _medicareUnreachable
                                                ? 'Status unavailable'
                                                : 'Connected',
                                    connected: _medicareProblem == null &&
                                        !_medicareUnreachable,
                                    action: _medicareUnreachable &&
                                            _medicareProblem !=
                                                MedicareReadProblem.notLinked &&
                                            _medicareProblem !=
                                                MedicareReadProblem.linkExpired
                                        ? TextButton(
                                            onPressed: _load,
                                            style: TextButton.styleFrom(
                                              foregroundColor: _accent(context),
                                              minimumSize: const Size(48, 48),
                                            ),
                                            child: const Text('Retry'),
                                          )
                                        : _medicareProblem ==
                                                MedicareReadProblem.linkExpired
                                            ? TextButton(
                                                onPressed: () =>
                                                    GoRouter.of(context).push(
                                                        '/medicare-connect'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      _accent(context),
                                                  minimumSize:
                                                      const Size(48, 48),
                                                ),
                                                child: const Text('Reconnect'),
                                              )
                                            : _medicareProblem ==
                                                    MedicareReadProblem
                                                        .notLinked
                                                ? _connectMedicareButton()
                                                : null,
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
                              l10n.healthDataYourHistory,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              l10n.healthDataEventCount(records.length),
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
                          l10n.healthDataInformation,
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
                              label: l10n.healthDataFilterAll,
                              type: null,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterMedications,
                              type: RecordType.medication,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterConditions,
                              type: RecordType.condition,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterAllergies,
                              type: RecordType.allergy,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterVisits,
                              type: RecordType.appointment,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterClinicalRecords,
                              type: RecordType.clinicalRecord,
                            ),
                            _recordTypeChip(
                              label: l10n.healthDataFilterClaims,
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
                          if (hasSidebar) ...[
                            sidebar,
                            const SizedBox(height: 24),
                          ],
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
          selectedColor: _accent(context),
          labelStyle: TextStyle(
            color: selected ? _onAccent(context) : _accent(context),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: _accent(context),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          showCheckmark: selected,
          checkmarkColor: _onAccent(context),
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
    required String status,
    required bool connected,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            connected ? Icons.check_circle_outline : Icons.link_off,
            size: 20,
            color: connected
                ? _greenText
                : Theme.of(context).colorScheme.onSurfaceVariant,
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
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }

  Widget _connectMedicareButton() {
    return TextButton(
      onPressed: () => GoRouter.of(context).push('/medicare-connect'),
      style: TextButton.styleFrom(
        foregroundColor: _accent(context),
        minimumSize: const Size(48, 48),
      ),
      child: const Text('Connect'),
    );
  }

  /// A connected patient had no way back to the Medicare page (status,
  /// sharing, Disconnect) without typing /#/medicare-connect. Hidden when the
  /// banners above already offer Connect (not linked, link expired) and for
  /// callers who may not use Medicare here (403).
  bool _showManageMedicare() =>
      _mayConnectAthena() &&
      _medicareProblem != MedicareReadProblem.notLinked &&
      _medicareProblem != MedicareReadProblem.linkExpired &&
      _medicareProblem != MedicareReadProblem.forbidden;

  /// Opens the Medicare page, then reloads: the patient may have disconnected.
  Future<void> _manageMedicare() async {
    await GoRouter.of(context).push('/medicare-connect');
    if (mounted) _load();
  }

  /// athenahealth is patients only. With athena off the server answers 404
  /// to everyone, so the role decides; without a signed-in user to ask (as
  /// in widget tests) the server's answer stands.
  bool _mayConnectAthena() {
    try {
      final role = Provider.of<UserProvider>(context, listen: false).user?.role;
      return role == null || role.toLowerCase() == 'patient';
    } on ProviderNotFoundException {
      return true;
    }
  }

  Widget _noticeBanner(
    IconData icon,
    String text, {
    Widget? action,
    bool warning = false,
  }) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFFFBEB) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: warning ? const Color(0xFFD97706) : const Color(0xFFD1D5DB),
            width: warning ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 20,
                color:
                    warning ? const Color(0xFF92400E) : const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                  height: 1.4,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _syntheticBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
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

  String _formatDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMMd(locale).format(date);
  }

  String _formatMonthYear(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMM(locale).format(date);
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
              _l10n(context).healthDataNoRecords,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _l10n(context).healthDataChangeSearchFilters,
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
          ? _formatMonthYear(context, record.date!)
          : _l10n(context).healthDataNoDate;

      if (group != currentGroup) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 12),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    group,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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

  String _localizedRecordType(RecordType type) {
    final l10n = _l10n(context);

    switch (type) {
      case RecordType.medication:
        return l10n.healthDataRecordTypeMedication;
      case RecordType.condition:
        return l10n.healthDataRecordTypeCondition;
      case RecordType.allergy:
        return l10n.healthDataRecordTypeAllergy;
      case RecordType.appointment:
        return l10n.healthDataRecordTypeVisit;
      case RecordType.clinicalRecord:
        return l10n.healthDataRecordTypeClinicalRecord;
      case RecordType.claimService:
        return l10n.healthDataRecordTypeClaimService;
      default:
        return l10n.healthDataRecordTypeRecord;
    }
  }

  Widget _recordCard(HealthRecord r) {
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
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
                      _localizedRecordType(r.type).toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
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
                  _l10n(context).healthDataDate,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(context, r.date!),
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
                    TitledMaterialPageRoute<void>(
                      title: 'Health Event Details',
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
                      Expanded(
                        child: Text(
                          _l10n(context).healthDataViewDetails,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: _accent(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: _accent(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  String _localizedGender(String gender) {
    final l10n = _l10n(context);

    switch (gender.toLowerCase()) {
      case 'female':
        return l10n.healthDataGenderFemale;
      case 'male':
        return l10n.healthDataGenderMale;
      default:
        return gender;
    }
  }

  String _localizedStatus(String status) {
    final l10n = _l10n(context);

    switch (status.toLowerCase()) {
      case 'active':
        return l10n.healthDataStatusActive;
      default:
        return status;
    }
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_localizedStatus(status),
          style: const TextStyle(
              fontSize: 11, color: _greenText, fontWeight: FontWeight.w600)),
    );
  }
}
