import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/evv_service.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../widgets/app_bar_helper.dart';
import 'evv_hhaexchange_submit_page.dart';
import 'evv_record_review.dart';
import 'evv_visit_history.dart';
import 'evv_corrections.dart';
import 'evv_offline_sync.dart';
import 'patient_selection_page.dart';

class EvvDashboard extends StatefulWidget {
  const EvvDashboard({super.key, this.service});

  final EvvService? service;

  @override
  State<EvvDashboard> createState() => _EvvDashboardState();
}

class _EvvDashboardState extends State<EvvDashboard>
    with TickerProviderStateMixin {
  late final EvvService _evvService = widget.service ?? EvvService();
  bool _isLoading = true;
  List<EvvOfflineQueue> _offlineQueue = [];
  int _pendingApprovals = 0;
  int _pendingCorrections = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user?.role == 'ADMIN' || user?.role == 'SUPERVISOR') {
        final pendingApprovals = await _evvService.getPendingEorApprovals();
        final pendingCorrections = await _evvService.getPendingCorrections();
        _pendingApprovals = pendingApprovals.length;
        _pendingCorrections = pendingCorrections.length;
      }

      final offlineQueue = await _evvService.getOfflineQueue();

      if (!mounted) return;
      setState(() {
        _offlineQueue = offlineQueue;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.evvDashLoadError(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = context.watch<UserProvider>().user;
    final isAdmin = user?.role == 'ADMIN';
    final isSupervisor = user?.role == 'SUPERVISOR';
    final isCaregiver = user?.role == 'CAREGIVER';
    final isPatient = user?.role == 'PATIENT';

    if (_isLoading) {
      return Scaffold(
        drawer: const CommonDrawer(currentRoute: '/evv/dashboard'),
        appBar: AppBarHelper.createAppBar(context, title: AppLocalizations.of(context)!.evvDashTitle),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/evv/dashboard'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: AppLocalizations.of(context)!.evvDashTitle,
        additionalActions: [
          if (_offlineQueue.isNotEmpty)
            IconButton(
              icon: Badge.count(
                count: _offlineQueue.length,
                child: const Icon(Icons.sync),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const EvvOfflineSyncPage()),
                );
              },
              tooltip: AppLocalizations.of(context)!.evvDashOfflineSync,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QuickStats(
                offlineCount: _offlineQueue.length,
                pendingApprovals:
                    (isAdmin || isSupervisor) ? _pendingApprovals : null,
                pendingCorrections:
                    (isAdmin || isSupervisor) ? _pendingCorrections : null,
              ),
              const SizedBox(height: 16),
              _MainActions(
                isAdmin: isAdmin,
                isSupervisor: isSupervisor,
                isCaregiver: isCaregiver,
                isPatient: isPatient,
              ),
              const SizedBox(height: 16),
              if (isAdmin || isSupervisor) ...[
                _PendingItems(
                  pendingApprovals: _pendingApprovals,
                  pendingCorrections: _pendingCorrections,
                  onOpenCorrections: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const EvvCorrectionsPage()),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (_offlineQueue.isNotEmpty) ...[
                _OfflineQueueStatus(
                  count: _offlineQueue.length,
                  onSync: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const EvvOfflineSyncPage()),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              _RecentActivity(),
            ],
          ),
        ),
      ),
      floatingActionButton: isCaregiver
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const PatientSelectionPage()),
                );
              },
              icon: const Icon(Icons.play_circle),
              label: Text(AppLocalizations.of(context)!.evvDashStartVisit),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      backgroundColor: scheme.surfaceContainerLowest,
    );
  }

  @override
  void dispose() {
    _evvService.dispose();
    super.dispose();
  }
}

/* ========== Quick Stats ========== */

class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.offlineCount,
    this.pendingApprovals,
    this.pendingCorrections,
  });

  final int offlineCount;
  final int? pendingApprovals;
  final int? pendingCorrections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final items = <_StatSpec>[
      _StatSpec(
        title: AppLocalizations.of(context)!.evvDashOfflineRecords,
        value: '$offlineCount',
        icon: Icons.cloud_off,
        tone: _Tone
            .warning, // maps to scheme.tertiary or scheme.secondaryContainer as background
      ),
      if (pendingApprovals != null)
        _StatSpec(
          title: AppLocalizations.of(context)!.evvDashPendingApprovals,
          value: '${pendingApprovals!}',
          icon: Icons.approval,
          tone: _Tone.info, // maps to scheme.primary
        ),
      if (pendingCorrections != null)
        _StatSpec(
          title: AppLocalizations.of(context)!.evvDashPendingCorrections,
          value: '${pendingCorrections!}',
          icon: Icons.edit,
          tone: _Tone.error, // maps to scheme.error
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SectionHeader(
                title: AppLocalizations.of(context)!.evvDashQuickStats, icon: Icons.dashboard_outlined),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items
                      .map((s) => SizedBox(
                            width: isWide
                                ? (constraints.maxWidth -
                                        12 * (items.length - 1)) /
                                    items.length
                                : (constraints.maxWidth),
                            child: _StatCard(spec: s, scheme: scheme),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { info, warning, error, neutral }

class _StatSpec {
  const _StatSpec({
    required this.title,
    required this.value,
    required this.icon,
    this.tone = _Tone.neutral,
  });

  final String title;
  final String value;
  final IconData icon;
  final _Tone tone;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.spec, required this.scheme});

  final _StatSpec spec;
  final ColorScheme scheme;

  Color _fg(_Tone t) {
    switch (t) {
      case _Tone.info:
        return scheme.onPrimaryContainer;
      case _Tone.warning:
        return scheme.onTertiaryContainer;
      case _Tone.error:
        return scheme.onErrorContainer;
      case _Tone.neutral:
        return scheme.onSecondaryContainer;
    }
  }

  Color _bg(_Tone t) {
    switch (t) {
      case _Tone.info:
        return scheme.primaryContainer;
      case _Tone.warning:
        return scheme.tertiaryContainer;
      case _Tone.error:
        return scheme.errorContainer;
      case _Tone.neutral:
        return scheme.secondaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _fg(spec.tone);
    final background = _bg(spec.tone);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background.withOpacity(0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, color: foreground),
          const SizedBox(height: 8),
          Text(
            spec.value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            spec.title,
            style: TextStyle(fontSize: 12, color: foreground.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/* ========== Main Actions ========== */

class _MainActions extends StatelessWidget {
  const _MainActions({
    required this.isAdmin,
    required this.isSupervisor,
    required this.isCaregiver,
    required this.isPatient,
  });

  final bool isAdmin;
  final bool isSupervisor;
  final bool isCaregiver;
  final bool isPatient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final actions = <_ActionSpec>[
      if (isCaregiver)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashStartVisit,
          icon: Icons.play_circle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PatientSelectionPage()),
          ),
        ),
      if (isCaregiver)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashReviewRecords,
          icon: Icons.rate_review,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EvvRecordReviewPage()),
          ),
        ),
      if (isCaregiver || isSupervisor || isAdmin)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashSubmitHha,
          icon: Icons.upload_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EvvHhaExchangeSubmitPage()),
          ),
        ),
      if (isAdmin || isSupervisor || isPatient)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashVisitHistory,
          icon: Icons.history,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EvvVisitHistoryPage()),
          ),
        ),
      if (isAdmin || isSupervisor)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashManageCorrections,
          icon: Icons.edit_note,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EvvCorrectionsPage()),
          ),
        ),
      if (isAdmin || isSupervisor || isCaregiver || isPatient)
        _ActionSpec(
          title: AppLocalizations.of(context)!.evvDashVisitSchedules,
          icon: Icons.schedule,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SchedulePage()),
          ),
        ),
      _ActionSpec(
        title: AppLocalizations.of(context)!.evvDashOfflineSync,
        icon: Icons.sync,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EvvOfflineSyncPage()),
        ),
      ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _SectionHeader(
                title: AppLocalizations.of(context)!.evvDashMainActions, icon: Icons.grid_view_rounded),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final crossAxisCount = maxWidth >= 900
                    ? 4
                    : maxWidth >= 680
                        ? 3
                        : maxWidth >= 420
                            ? 2
                            : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 72,
                  ),
                  itemCount: actions.length,
                  itemBuilder: (context, i) {
                    final a = actions[i];
                    return _ActionCard(spec: a, scheme: scheme);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.spec, required this.scheme});

  final _ActionSpec spec;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: spec.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(spec.icon, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  spec.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ========== Pending Items ========== */

class _PendingItems extends StatelessWidget {
  const _PendingItems({
    required this.pendingApprovals,
    required this.pendingCorrections,
    required this.onOpenCorrections,
  });

  final int pendingApprovals;
  final int pendingCorrections;
  final VoidCallback onOpenCorrections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SectionHeader(
                title: AppLocalizations.of(context)!.evvDashPendingItems, icon: Icons.pending_actions_outlined),
            const SizedBox(height: 8),
            if (pendingApprovals > 0)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.approval, color: scheme.onPrimaryContainer),
                ),
                title: Text(AppLocalizations.of(context)!.evvDashEorApprovals),
                subtitle: Text(AppLocalizations.of(context)!.evvDashPendingCount(pendingApprovals)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Implement navigation when approvals screen exists
                },
              ),
            if (pendingCorrections > 0)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.errorContainer,
                  child: Icon(Icons.edit, color: scheme.onErrorContainer),
                ),
                title: Text(AppLocalizations.of(context)!.evvDashCorrections),
                subtitle: Text(AppLocalizations.of(context)!.evvDashPendingCount(pendingCorrections)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: onOpenCorrections,
              ),
            if (pendingApprovals == 0 && pendingCorrections == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  AppLocalizations.of(context)!.evvDashNoPendingItems,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ========== Offline Queue ========== */

class _OfflineQueueStatus extends StatelessWidget {
  const _OfflineQueueStatus({required this.count, required this.onSync});

  final int count;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SectionHeader(title: AppLocalizations.of(context)!.evvDashOfflineQueue, icon: Icons.cloud_off),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.evvDashWaitingCount(count),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onSync,
                  icon: const Icon(Icons.sync),
                  label: Text(AppLocalizations.of(context)!.evvDashSyncNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ========== Recent Activity ========== */

class _RecentActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SectionHeader(
                title: AppLocalizations.of(context)!.evvDashRecentActivities,
                icon: Icons.auto_awesome_motion_outlined),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context)!.evvDashNoRecentActivity,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ========== Shared bits ========== */

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title, style: textStyle),
      ],
    );
  }
}
