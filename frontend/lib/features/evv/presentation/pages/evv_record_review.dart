import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/evv_service.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../widgets/app_bar_helper.dart';
import '../../../dashboard/models/patient_model.dart';

class EvvRecordReviewPage extends StatefulWidget {
  const EvvRecordReviewPage({super.key});

  @override
  State<EvvRecordReviewPage> createState() => _EvvRecordReviewPageState();
}

class _EvvRecordReviewPageState extends State<EvvRecordReviewPage> {
  final EvvService _evvService = EvvService();
  bool _isLoading = true;
  List<EvvRecord> _allRecords = [];
  List<EvvRecord> _filteredRecords = [];
  String _selectedStatusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadAllRecords();
  }

  Future<void> _loadAllRecords() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) return;

      // Search all records without status filter
      final request = EvvSearchRequest(
        page: 0,
        size: 1000,
        sortBy: 'createdAt',
        sortDirection: 'DESC',
      );

      final result = await _evvService.searchRecords(request);

      setState(() {
        _allRecords = result.content;
        _filteredRecords = result.content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading records: $e')),
        );
      }
    }
  }

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatusFilter = status;
      if (status == 'ALL') {
        _filteredRecords = _allRecords;
      } else {
        _filteredRecords =
            _allRecords.where((record) => record.status == status).toList();
      }
    });
  }

  String _uniqueFileName(String base) {
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    final rand =
        math.Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${base}_${ts}_$rand.edi';
  }

  Future<void> _reviewRecord(
      EvvRecord record, bool approve, String? comment) async {
    try {
      await _evvService.reviewRecord(
        recordId: record.id,
        approve: approve,
        comment: comment,
      );

      // Reload all records to reflect the status change
      await _loadAllRecords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Record approved' : 'Record rejected'),
            backgroundColor: approve ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reviewing record: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportEDI(EvvRecord record) async {
    try {
      final ediContent = _generateEDIContent(record);
      final bytes = utf8.encode(ediContent);

      if (kIsWeb) {
        // Web: trigger a file download using a Blob and hidden anchor
        final blob = html.Blob([bytes], 'text/plain');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = _uniqueFileName('evv_record_${record.id}');
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile/Desktop: save to Downloads and open
        final fileName = _uniqueFileName('evv_record_${record.id}');
        String? downloadsPath;
        try {
          // Android common downloads directory
          downloadsPath = '/storage/emulated/0/Download';
          final downloadsDir = Directory(downloadsPath);
          if (!await downloadsDir.exists()) {
            // Fallback to app external storage
            final ext = await getExternalStorageDirectory();
            downloadsPath = ext?.path;
          }
          final savePath = '$downloadsPath/$fileName';
          final file = File(savePath);
          await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

          // Try open the file
          await OpenFilex.open(savePath);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved to: $savePath')),
            );
          }
        } catch (saveErr) {
          // Fallback: write to temp and share
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/$fileName';
          await File(tempPath)
              .writeAsBytes(Uint8List.fromList(bytes), flush: true);
          final xfile = XFile(tempPath, mimeType: 'text/plain', name: fileName);
          await Share.shareXFiles([xfile], text: 'EVV EDI export');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EDI document exported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _generateEDIContent(EvvRecord record) {
    final patientId = record.patient?.id ?? record.id;
    final maNumber = record.patient?.maNumber ??
        'SUBSCR${patientId.toString().padLeft(5, '0')}';

    final now = DateTime.now();
    final isaDate =
        '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final isaTime =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final gsDate =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final gsTime =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    final serviceDate =
        '${record.dateOfService.year}${record.dateOfService.month.toString().padLeft(2, '0')}${record.dateOfService.day.toString().padLeft(2, '0')}';

    String patientDob = '19700101';
    if (record.patient?.dob != null && record.patient!.dob.isNotEmpty) {
      try {
        final dobDate = DateTime.parse(record.patient!.dob);
        patientDob =
            '${dobDate.year}${dobDate.month.toString().padLeft(2, '0')}${dobDate.day.toString().padLeft(2, '0')}';
      } catch (e) {
        patientDob = '19700101';
      }
    }

    final gender = (record.patient?.gender?.toUpperCase() == 'MALE' ||
            record.patient?.gender?.toUpperCase() == 'M')
        ? 'M'
        : 'F';

    final claimId =
        '$patientId${record.dateOfService.millisecondsSinceEpoch.toString().substring(0, 10)}';
    final evvId = 'EVV-$claimId';

    final duration = record.timeOut.difference(record.timeIn).inMinutes;
    final units = ((duration / 15).ceil()).toString();
    final totalCharge = (30.0 * (duration / 15).ceil()).toStringAsFixed(2);

    final patientName = record.individualName.split(' ');
    final lastName =
        patientName.length > 1 ? patientName.last : record.individualName;
    final firstName = patientName.length > 1 ? patientName.first : '';

    final addressLine1 = record.patient?.address?.line1 ?? '123 Main St';
    final city = record.patient?.address?.city ?? 'Richmond';
    final state = record.patient?.address?.state ?? record.stateCode;
    final zip = record.patient?.address?.zip ?? '23220';

    final controlNumber =
        now.millisecondsSinceEpoch.toString().substring(3, 12);

    final ediContent =
        '''ISA*00*          *00*          *ZZ*SUBMIT123      *ZZ*987654321      *$isaDate*$isaTime*^*00501*$controlNumber*0*P*:~
GS*HC*SUBMIT123*987654321*$gsDate*$gsTime*$controlNumber*X*005010X222A1~
ST*837*0001*005010X222A1~
BHT*0019*00*$claimId*$gsDate*$gsTime*CH~
NM1*41*2*Your Agency Name*****46*SUBMIT123~
PER*IC*Billing Contact*TE*5551234567~
NM1*40*2*ANTHEM*****46*987654321~
HL*1**20*1~
PRV*BI*PXC*251E00000X~
NM1*85*2*Your Agency Name*****XX*1234567893~
N3*123 Care Street~
N4*Richmond*VA*23220~
REF*EI*123456789~
HL*2*1*22*0~
SBR*P*18**MC*****MC~
NM1*IL*1*$lastName*$firstName****MI*$maNumber~
N3*$addressLine1~
N4*$city*$state*$zip~
DMG*D8*$patientDob*$gender~
NM1*PR*2*ANTHEM*****PI*00123~
CLM*$claimId*$totalCharge***12:B:1**A*Y*Y~
DTP*434*RD8*$serviceDate-$serviceDate~
REF*D9*AUTH12345~
REF*F8*$evvId~
HI*BK:I10~
NM1*82*1*Worker*Alice****XX*1098765432~
PRV*PE*PXC*3747P1801X~
LX*1~
SV1*HC:T1019*$totalCharge*UN*$units***1~
DTP*472*D8*$serviceDate~
SE*31*0001~
GE*1*$controlNumber~
IEA*1*$controlNumber~
''';

    return ediContent;
  }

  void _showReviewDialog(EvvRecord record) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review EVV Record'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRecordDetails(record),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: 'Review Comment (Optional)',
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
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _exportEDI(record);
            },
            icon: const Icon(Icons.download),
            label: const Text('Export EDI'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reviewRecord(record, false, commentController.text.trim());
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reviewRecord(record, true, commentController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
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
            Text(
              'Record Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Service Type', record.serviceType),
            _buildDetailRow('Individual', record.individualName),
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
            if (record.isOffline)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
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
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/evv/review-records'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'All EVV Records (${_filteredRecords.length})',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllRecords,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Filter by Status:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStatusFilter,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'ALL', child: Text('All Statuses')),
                      DropdownMenuItem(
                          value: 'UNDER_REVIEW', child: Text('Under Review')),
                      DropdownMenuItem(
                          value: 'APPROVED', child: Text('Approved')),
                      DropdownMenuItem(
                          value: 'REJECTED', child: Text('Rejected')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _filterByStatus(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Records List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.rate_review_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _allRecords.isEmpty
                                  ? 'No records found'
                                  : 'No records match this filter',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _allRecords.isEmpty
                                  ? 'Start creating EVV records to see them here'
                                  : 'Try selecting a different status filter',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredRecords.length,
                        itemBuilder: (context, index) {
                          final record = _filteredRecords[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(record.status),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${record.serviceType} - ${_formatDate(record.dateOfService)}'),
                                  Text(
                                      '${_formatTime(record.timeIn)} - ${_formatTime(record.timeOut)}'),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(record.status)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          record.status,
                                          style: TextStyle(
                                            color:
                                                _getStatusColor(record.status),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.2),
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
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.orange.withOpacity(0.2),
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
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () => _showReviewDialog(record),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
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

  @override
  void dispose() {
    _evvService.dispose();
    super.dispose();
  }
}
