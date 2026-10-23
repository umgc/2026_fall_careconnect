import 'package:flutter/material.dart';
import '../../../../services/evv_service.dart';

class EvvCorrectionsPage extends StatefulWidget {
  const EvvCorrectionsPage({super.key});

  @override
  State<EvvCorrectionsPage> createState() => _EvvCorrectionsPageState();
}

class _EvvCorrectionsPageState extends State<EvvCorrectionsPage>
    with TickerProviderStateMixin {
  final EvvService _evvService = EvvService();
  bool _isLoading = true;
  List<EvvCorrection> _pendingCorrections = [];
  List<EvvRecord> _pendingEorApprovals = [];
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final corrections = await _evvService.getPendingCorrections();
      final approvals = await _evvService.getPendingEorApprovals();

      setState(() {
        _pendingCorrections = corrections;
        _pendingEorApprovals = approvals;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _approveCorrection(
      EvvCorrection correction, String? comment) async {
    try {
      await _evvService.approveCorrection(
        correctionId: correction.id,
        comment: comment,
      );

      setState(() {
        _pendingCorrections.remove(correction);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Correction approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving correction: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _approveEor(EvvRecord record, String? comment) async {
    try {
      await _evvService.approveEor(
        recordId: record.id,
        comment: comment,
      );

      setState(() {
        _pendingEorApprovals.remove(record);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EOR approval completed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving EOR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCorrectionApprovalDialog(EvvCorrection correction) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Correction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correction Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              _buildCorrectionDetails(correction),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: 'Approval Comment (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveCorrection(correction, commentController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showEorApprovalDialog(EvvRecord record) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve EOR'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              _buildRecordDetails(record),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: 'Approval Comment (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveEor(record, commentController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectionDetails(EvvCorrection correction) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Reason Code', correction.reasonCode),
            _buildDetailRow('Explanation', correction.explanation),
            _buildDetailRow('Corrected By', correction.correctedBy.toString()),
            _buildDetailRow(
                'Corrected At', _formatDateTime(correction.correctedAt)),
            const SizedBox(height: 8),
            const Text(
              'Changes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...correction.originalValues.entries.map((entry) {
              final originalValue = entry.value?.toString() ?? 'N/A';
              final correctedValue =
                  correction.correctedValues[entry.key]?.toString() ?? 'N/A';

              if (originalValue != correctedValue) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${entry.key}:',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From: $originalValue',
                              style: const TextStyle(color: Colors.red),
                            ),
                            Text(
                              'To: $correctedValue',
                              style: const TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordDetails(EvvRecord record) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Service Type', record.serviceType),
            _buildDetailRow('Individual', record.individualName),
            _buildDetailRow('Date', _formatDate(record.dateOfService)),
            _buildDetailRow('Time In', _formatTime(record.timeIn)),
            _buildDetailRow('Time Out', _formatTime(record.timeOut)),
            _buildDetailRow('State', record.stateCode),
            _buildDetailRow('Status', record.status),
            _buildDetailRow('MA Number', record.patient?.maNumber ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EVV Corrections & Approvals'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: TabController(
              length: 2, vsync: this, initialIndex: _selectedTabIndex),
          onTap: (index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 8),
                  Text('Corrections (${_pendingCorrections.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.approval),
                  const SizedBox(width: 8),
                  Text('EOR Approvals (${_pendingEorApprovals.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: TabController(
                  length: 2, vsync: this, initialIndex: _selectedTabIndex),
              children: [
                // Corrections Tab
                _pendingCorrections.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No pending corrections',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'All corrections have been reviewed',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pendingCorrections.length,
                        itemBuilder: (context, index) {
                          final correction = _pendingCorrections[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.red,
                                child:
                                    const Icon(Icons.edit, color: Colors.white),
                              ),
                              title: Text(
                                'Correction for ${correction.originalRecord.individualName}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Reason: ${correction.reasonCode}'),
                                  Text(
                                      'Service: ${correction.originalRecord.serviceType}'),
                                  Text(
                                      'Date: ${_formatDate(correction.originalRecord.dateOfService)}'),
                                  Text(
                                      'Corrected: ${_formatDateTime(correction.correctedAt)}'),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () =>
                                  _showCorrectionApprovalDialog(correction),
                            ),
                          );
                        },
                      ),

                // EOR Approvals Tab
                _pendingEorApprovals.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.approval_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No pending EOR approvals',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'All EOR approvals are complete',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pendingEorApprovals.length,
                        itemBuilder: (context, index) {
                          final record = _pendingEorApprovals[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: const Icon(Icons.approval,
                                    color: Colors.white),
                              ),
                              title: Text(
                                record.individualName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${record.serviceType} - ${_formatDate(record.dateOfService)}'),
                                  Text(
                                      '${_formatTime(record.timeIn)} - ${_formatTime(record.timeOut)}'),
                                  Text('State: ${record.stateCode}'),
                                  Text(
                                      'Created: ${_formatDateTime(record.createdAt)}'),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () => _showEorApprovalDialog(record),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
  }

  @override
  void dispose() {
    _evvService.dispose();
    super.dispose();
  }
}
