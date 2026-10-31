import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../../../../services/evv_service.dart';

class EvvOfflineSyncPage extends StatefulWidget {
  const EvvOfflineSyncPage({super.key});

  @override
  State<EvvOfflineSyncPage> createState() => _EvvOfflineSyncPageState();
}

class _EvvOfflineSyncPageState extends State<EvvOfflineSyncPage> {
  final EvvService _evvService = EvvService();
  bool _isLoading = true;
  bool _isSyncing = false;
  List<EvvOfflineQueue> _offlineQueue = [];

  @override
  void initState() {
    super.initState();
    _loadOfflineData();
  }

  Future<void> _loadOfflineData() async {
    try {
      final queue = await _evvService.getOfflineQueue();

      setState(() {
        _offlineQueue = queue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading offline data: $e')),
        );
      }
    }
  }

  Future<void> _syncOfflineData() async {
    setState(() => _isSyncing = true);
    try {
      await _evvService.syncOfflineData();
      await _loadOfflineData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.evvOfflineSyncDone),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing offline data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.evvOfflineTitle),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOfflineData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Sync Status Overview
                Card(
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cloud_sync, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.evvOfflineSyncStatus,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatusGrid(context),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSyncing ? null : _syncOfflineData,
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync),
                            label: Text(_isSyncing
                                ? AppLocalizations.of(context)!.evvOfflineSyncingDots
                                : AppLocalizations.of(context)!.evvOfflineSyncAll),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Offline Queue List
                Expanded(
                  child: _offlineQueue.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_done,
                                  size: 56, color: Colors.green),
                              const SizedBox(height: 10),
                              Text(AppLocalizations.of(context)!.evvOfflineAllSynced,
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey)),
                              const SizedBox(height: 6),
                              Text(AppLocalizations.of(context)!.evvOfflineNoRecords,
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _offlineQueue.length,
                          itemBuilder: (context, index) {
                            final item = _offlineQueue[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0.5,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      _getStatusColor(item.syncStatus),
                                  child: Icon(_getStatusIcon(item.syncStatus),
                                      color: Colors.white),
                                ),
                                title: Text(
                                  '${item.operationType} ${AppLocalizations.of(context)!.evvOfflineRecord} #${item.recordId}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${AppLocalizations.of(context)!.evvOfflineCaregiverId}: ${item.caregiverId}'),
                                    Text(
                                        '${AppLocalizations.of(context)!.evvOfflineQueued}: ${_formatDateTime(item.queuedAt)}'),
                                    if (item.lastSyncAttempt != null)
                                      Text(
                                          '${AppLocalizations.of(context)!.evvOfflineLastAttempt}: ${_formatDateTime(item.lastSyncAttempt!)}'),
                                    if (item.syncAttempts > 0)
                                      Text('${AppLocalizations.of(context)!.evvOfflineAttempts}: ${item.syncAttempts}'),
                                    if (item.lastError != null)
                                      Text('${AppLocalizations.of(context)!.evvOfflineError}: ${item.lastError}',
                                          style: const TextStyle(
                                              color: Colors.red)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _pill(item.syncStatus,
                                            _getStatusColor(item.syncStatus)),
                                        const SizedBox(width: 8),
                                        _pill(_getPriorityText(item.priority),
                                            _getPriorityColor(item.priority)),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'retry' &&
                                        item.syncStatus == 'FAILED') {
                                      _retrySync(item);
                                    } else if (value == 'details') {
                                      _showItemDetails(item);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'details',
                                      child: Row(
                                        children: [
                                          Icon(Icons.info, size: 20),
                                          SizedBox(width: 8),
                                          Text(AppLocalizations.of(context)!.evvOfflineDetails),
                                        ],
                                      ),
                                    ),
                                    if (item.syncStatus == 'FAILED')
                                      PopupMenuItem(
                                        value: 'retry',
                                        child: Row(
                                          children: [
                                            Icon(Icons.refresh,
                                                size: 20, color: Colors.blue),
                                            SizedBox(width: 8),
                                            Text(AppLocalizations.of(context)!.evvOfflineRetry,
                                                style: TextStyle(
                                                    color: Colors.blue)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // Responsive grid that keeps all four tiles same size and height
  Widget _buildStatusGrid(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pendingCount =
        _offlineQueue.where((i) => i.syncStatus == 'PENDING').length.toString();
    final syncingCount =
        _offlineQueue.where((i) => i.syncStatus == 'SYNCING').length.toString();
    final syncedCount =
        _offlineQueue.where((i) => i.syncStatus == 'SYNCED').length.toString();
    final failedCount =
        _offlineQueue.where((i) => i.syncStatus == 'FAILED').length.toString();

    final tiles = [
      _StatusTileData(
        title: AppLocalizations.of(context)!.evvOfflinePending,
        count: pendingCount,
        icon: Icons.pending,
        color: Colors.orange,
      ),
      _StatusTileData(
        title: AppLocalizations.of(context)!.evvOfflineSyncing,
        count: syncingCount,
        icon: Icons.sync,
        color: cs.primary,
      ),
      _StatusTileData(
        title: AppLocalizations.of(context)!.evvOfflineSynced,
        count: syncedCount,
        icon: Icons.check_circle,
        color: Colors.green,
      ),
      _StatusTileData(
        title: AppLocalizations.of(context)!.evvOfflineFailed,
        count: failedCount,
        icon: Icons.error,
        color: cs.error,
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final isWide = c.maxWidth >= 720;
      final crossAxisCount = isWide ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tiles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          // Aspect ratio keeps heights equal and prevents vertical text wrap
          childAspectRatio: 1.6,
        ),
        itemBuilder: (context, index) {
          final t = tiles[index];
          return _buildStatusCard(t.title, t.count, t.icon, t.color);
        },
      );
    });
  }

  Widget _buildStatusCard(
      String title, String count, IconData icon, Color color) {
    final border = color.withOpacity(0.28);
    final bg = color.withOpacity(0.08);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      // Fixed min height so all tiles match when grid stretches
      constraints: const BoxConstraints(minHeight: 84),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              count,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }

  void _retrySync(EvvOfflineQueue item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.evvOfflineRetryPlaceholder),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _showItemDetails(EvvOfflineQueue item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.evvOfflineDetailTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineRecordId, item.recordId.toString()),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineOperation, item.operationType),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineCaregiverId, item.caregiverId.toString()),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineDeviceId, item.deviceId ?? 'N/A'),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineQueuedAt, _formatDateTime(item.queuedAt)),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineSyncStatus, _localizedStatus(item.syncStatus)),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflineSyncAttempts, item.syncAttempts.toString()),
              if (item.lastSyncAttempt != null)
                _buildDetailRow(AppLocalizations.of(context)!.evvOfflineLastSyncAttempt,
                    _formatDateTime(item.lastSyncAttempt!)),
              if (item.lastError != null)
                _buildDetailRow(AppLocalizations.of(context)!.evvOfflineLastError, item.lastError!),
              _buildDetailRow(AppLocalizations.of(context)!.evvOfflinePriority, _getPriorityText(item.priority)),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.evvOfflineRecordData,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Text(item.recordData.toString(),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.evvOfflineClose)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.orange;
      case 'SYNCING':
        return Theme.of(context).colorScheme.primary;
      case 'SYNCED':
        return Colors.green;
      case 'FAILED':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'PENDING':
        return Icons.pending;
      case 'SYNCING':
        return Icons.sync;
      case 'SYNCED':
        return Icons.check_circle;
      case 'FAILED':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.grey;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _localizedStatus(String status) {
    final t = AppLocalizations.of(context)!;
    switch (status) {
      case 'PENDING': return t.evvOfflinePending;
      case 'SYNCING': return t.evvOfflineSyncing;
      case 'SYNCED': return t.evvOfflineSynced;
      case 'FAILED': return t.evvOfflineFailed;
      default: return status;
    }
  }

  String _getPriorityText(int priority) {
    switch (priority) {
      case 1:
        return 'Normal';
      case 2:
        return AppLocalizations.of(context)!.evvOfflineHigh;
      case 3:
        return AppLocalizations.of(context)!.evvOfflineUrgent;
      default:
        return 'Normal';
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _evvService.dispose();
    super.dispose();
  }
}

class _StatusTileData {
  final String title;
  final String count;
  final IconData icon;
  final Color color;
  _StatusTileData({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });
}
