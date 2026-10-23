import 'package:flutter/material.dart';
import '../../../../services/evv_service.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../widgets/app_bar_helper.dart';
import '../../../dashboard/models/patient_model.dart';

class EvvVisitHistoryPage extends StatefulWidget {
  const EvvVisitHistoryPage({super.key});

  @override
  State<EvvVisitHistoryPage> createState() => _EvvVisitHistoryPageState();
}

class _EvvVisitHistoryPageState extends State<EvvVisitHistoryPage> {
  final EvvService _evvService = EvvService();
  final _searchFormKey = GlobalKey<FormState>();

  // Search form controllers
  final _patientNameController = TextEditingController();
  final _serviceTypeController = TextEditingController();
  final _caregiverIdController = TextEditingController();

  // Search parameters
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedStateCode = '';
  String _selectedStatus = '';

  bool _isLoading = false;
  EvvSearchResult? _searchResult;
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  Future<void> _performSearch({bool resetPage = true}) async {
    if (resetPage) {
      _currentPage = 0;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = EvvSearchRequest(
        patientName: _patientNameController.text.trim().isEmpty
            ? null
            : _patientNameController.text.trim(),
        serviceType: _serviceTypeController.text.trim().isEmpty
            ? null
            : _serviceTypeController.text.trim(),
        caregiverId: _caregiverIdController.text.trim().isEmpty
            ? null
            : int.tryParse(_caregiverIdController.text.trim()),
        startDate: _startDate,
        endDate: _endDate,
        stateCode: _selectedStateCode.isEmpty ? null : _selectedStateCode,
        status: _selectedStatus.isEmpty ? null : _selectedStatus,
        page: _currentPage,
        size: _pageSize,
        sortBy: 'createdAt',
        sortDirection: 'DESC',
      );

      final result = await _evvService.searchRecords(request);

      setState(() {
        _searchResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_searchResult == null || _searchResult!.last) return;

    _currentPage++;
    await _performSearch(resetPage: false);
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _patientNameController.clear();
      _serviceTypeController.clear();
      _caregiverIdController.clear();
      _startDate = null;
      _endDate = null;
      _selectedStateCode = '';
      _selectedStatus = '';
    });
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/evv/visit-history'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'EVV Visit History',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearFilters,
            tooltip: 'Clear Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Filters
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _searchFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Search Filters',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _performSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // First row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _patientNameController,
                            decoration: const InputDecoration(
                              labelText: 'Patient Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _serviceTypeController,
                            decoration: const InputDecoration(
                              labelText: 'Service Type',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.medical_services),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Second row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _caregiverIdController,
                            decoration: const InputDecoration(
                              labelText: 'Caregiver ID',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.badge),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: _selectDateRange,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.date_range,
                                      color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _startDate != null && _endDate != null
                                          ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                                          : 'Select Date Range',
                                      style: TextStyle(
                                        color: _startDate != null
                                            ? Colors.black
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Third row
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedStateCode.isEmpty
                                ? null
                                : _selectedStateCode,
                            decoration: const InputDecoration(
                              labelText: 'State',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: '', child: Text('All States')),
                              ...EvvService.stateCodes.map((code) {
                                String stateName = '';
                                switch (code) {
                                  case 'MD':
                                    stateName = 'Maryland';
                                    break;
                                  case 'DC':
                                    stateName = 'DC';
                                    break;
                                  case 'VA':
                                    stateName = 'Virginia';
                                    break;
                                }
                                return DropdownMenuItem(
                                  value: code,
                                  child: Text('$code - $stateName'),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedStateCode = value ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedStatus.isEmpty
                                ? null
                                : _selectedStatus,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: '', child: Text('All Statuses')),
                              DropdownMenuItem(
                                  value: 'UNDER_REVIEW',
                                  child: Text('Under Review')),
                              DropdownMenuItem(
                                  value: 'APPROVED', child: Text('Approved')),
                              DropdownMenuItem(
                                  value: 'REJECTED', child: Text('Rejected')),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedStatus = value ?? '';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResult == null || _searchResult!.content.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No records found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Try adjusting your search filters',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Results header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Text(
                                  'Found ${_searchResult!.totalElements} records',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                const Spacer(),
                                Text(
                                  'Page ${_currentPage + 1} of ${_searchResult!.totalPages}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),

                          // Records list
                          Expanded(
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _searchResult!.content.length +
                                  (_searchResult!.last ? 0 : 1),
                              itemBuilder: (context, index) {
                                if (index == _searchResult!.content.length) {
                                  // Load more button
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: ElevatedButton(
                                        onPressed: _loadMore,
                                        child: const Text('Load More'),
                                      ),
                                    ),
                                  );
                                }

                                final record = _searchResult!.content[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          _getStatusColor(record.status),
                                      child: Icon(
                                        _getStatusIcon(record.status),
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      record.individualName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${record.serviceType} - ${_formatDate(record.dateOfService)}'),
                                        Text(
                                            '${_formatTime(record.timeIn)} - ${_formatTime(record.timeOut)}'),
                                        Text(
                                            'MA: ${record.patient?.maNumber ?? 'N/A'}'),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(
                                                        record.status)
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                record.status,
                                                style: TextStyle(
                                                  color: _getStatusColor(
                                                      record.status),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                record.stateCode,
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            if (record.isOffline) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'OFFLINE',
                                                  style: TextStyle(
                                                    color: Colors.orange,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing:
                                        const Icon(Icons.arrow_forward_ios),
                                    onTap: () => _showRecordDetails(record),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  void _showRecordDetails(EvvRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Service Type', record.serviceType),
              _buildDetailRow('Individual', record.individualName),
              _buildDetailRow('Caregiver ID', record.caregiverId.toString()),
              _buildDetailRow('Date', _formatDate(record.dateOfService)),
              _buildDetailRow('Time In', _formatTime(record.timeIn)),
              _buildDetailRow('Time Out', _formatTime(record.timeOut)),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              // Check-in location
              _buildLocationSection(
                'Check-In Location',
                record.checkinLocationSource,
                record.checkinLocationLat,
                record.checkinLocationLng,
                record.patient,
              ),
              const SizedBox(height: 8),
              // Check-out location
              _buildLocationSection(
                'Check-Out Location',
                record.checkoutLocationSource,
                record.checkoutLocationLat,
                record.checkoutLocationLng,
                record.patient,
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              _buildDetailRow('State', record.stateCode),
              _buildDetailRow('Status', record.status),
              _buildDetailRow('MA Number', record.patient?.maNumber ?? 'N/A'),
              _buildDetailRow('Created', _formatDateTime(record.createdAt)),
              _buildDetailRow('Updated', _formatDateTime(record.updatedAt)),
              if (record.isOffline) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('This record was created offline'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
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

  Widget _buildLocationSection(
    String title,
    String? locationSource,
    double? latitude,
    double? longitude,
    Patient? patient,
  ) {
    String locationDisplay;
    Color iconColor;
    IconData iconData;

    if (locationSource == null || locationSource.isEmpty) {
      locationDisplay = 'Not recorded';
      iconColor = Colors.grey;
      iconData = Icons.help_outline;
    } else if (locationSource == 'GPS') {
      if (latitude != null && longitude != null) {
        locationDisplay =
            'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
        iconColor = Colors.blue;
        iconData = Icons.gps_fixed;
      } else {
        locationDisplay = 'GPS (coordinates not available)';
        iconColor = Colors.orange;
        iconData = Icons.gps_off;
      }
    } else if (locationSource == 'PATIENT_ADDRESS') {
      if (patient?.address != null) {
        final addr = patient!.address!;
        final parts = <String>[];
        if (addr.line1?.isNotEmpty == true) parts.add(addr.line1!);
        if (addr.line2?.isNotEmpty == true) parts.add(addr.line2!);
        if (addr.city?.isNotEmpty == true) parts.add(addr.city!);
        if (addr.state?.isNotEmpty == true) parts.add(addr.state!);
        if (addr.zip?.isNotEmpty == true) parts.add(addr.zip!);
        locationDisplay =
            parts.isNotEmpty ? parts.join(', ') : 'Address not available';
        iconColor = Colors.green;
        iconData = Icons.home;
      } else {
        locationDisplay = 'Patient Address (not available)';
        iconColor = Colors.orange;
        iconData = Icons.home_outlined;
      }
    } else {
      locationDisplay = locationSource;
      iconColor = Colors.grey;
      iconData = Icons.location_on;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(iconData, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                locationSource ?? 'Unknown',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            locationDisplay,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'UNDER_REVIEW':
        return Colors.orange;
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'UNDER_REVIEW':
        return Icons.pending;
      case 'APPROVED':
        return Icons.check_circle;
      case 'REJECTED':
        return Icons.cancel;
      default:
        return Icons.help;
    }
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
    _patientNameController.dispose();
    _serviceTypeController.dispose();
    _caregiverIdController.dispose();
    _evvService.dispose();
    super.dispose();
  }
}
