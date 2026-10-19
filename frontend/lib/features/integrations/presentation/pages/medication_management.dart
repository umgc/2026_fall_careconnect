import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class MedicationManagementScreen extends StatefulWidget {
  const MedicationManagementScreen({super.key});

  @override
  State<MedicationManagementScreen> createState() =>
      _MedicationManagementScreenState();
}

class _MedicationManagementScreenState
    extends State<MedicationManagementScreen> {
  List<Map<String, dynamic>> medications = [];
  bool isLoading = true;
  static const String _fdaApiBaseUrl =
      'https://api.fda.gov/drug/ndc.json?search=product_ndc:';
  static const String _fdaApiSuffix = '&limit=1';

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final medicationsJson = prefs.getString('medications');

      if (medicationsJson != null) {
        final List<dynamic> decodedList = jsonDecode(medicationsJson);
        setState(() {
          medications = decodedList
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _saveMedications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final medicationsJson = jsonEncode(medications);
      await prefs.setString('medications', medicationsJson);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error saving medication. Please try again'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _isDuplicateMedication(String brandName, String? genericName,
      {String? excludeId}) {
    return medications.any((med) =>
        med['id'] != excludeId &&
        (med['brandName']?.toLowerCase() == brandName.toLowerCase() ||
            (genericName != null &&
                med['genericName']?.toLowerCase() ==
                    genericName.toLowerCase())));
  }

  Future<void> _generateAndSharePDF() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Medication List',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.Text(
                'Total medications: ${medications.length}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 20),
              ...medications.map((med) => _buildMedicationPDFEntry(med)),
            ];
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/medications_list.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Medication List',
        subject: 'Patient Medication List',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error generating PDF. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  pw.Widget _buildMedicationPDFEntry(Map<String, dynamic> med) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            med['brandName'] ?? 'Unknown Medication',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          if (med['genericName'] != null &&
              med['genericName'] != 'Not specified')
            pw.Text('Generic: ${med['genericName']}'),
          if (med['strength'] != null && med['strength'] != 'Not specified')
            pw.Text('Strength: ${med['strength']}'),
          if (med['dosage']?.isNotEmpty == true)
            pw.Text('Dosage: ${med['dosage']}'),
          if (med['frequency']?.isNotEmpty == true)
            pw.Text('Frequency: ${med['frequency']}'),
          if (med['timeToTake']?.isNotEmpty == true)
            pw.Text('Time to take: ${med['timeToTake']}'),
          if (med['takeWith']?.isNotEmpty == true)
            pw.Text('Take with: ${med['takeWith']}'),
          if (med['doNotTakeWith']?.isNotEmpty == true)
            pw.Text('Do not take with: ${med['doNotTakeWith']}'),
          if (med['startDate'] != null || med['endDate'] != null)
            pw.Text(
                'Duration: ${_formatDateRange(med['startDate'], med['endDate'])}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        drawer: const CommonDrawer(currentRoute: '/medication'),
        appBar: AppBarHelper.createAppBar(
          context,
          title: 'Medication Management',
          centerTitle: true,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading medications...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/medication'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Medication Management',
        centerTitle: true,
        additionalActions: [
          if (medications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share medication list',
              onPressed: _generateAndSharePDF,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _navigateToAddMedication();
            },
          ),
        ],
      ),
      body: medications.isEmpty ? _buildEmptyState() : _buildMedicationList(),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No Medications Added',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Scan medication barcodes, enter NDC codes, or manually add medications to manage your patient\'s medication schedule.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 40),
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _scanMedicationCode();
                  },
                  icon: Icon(
                    Icons.qr_code_scanner,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  label: const Text(
                    'Scan Medication Barcode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: AppTheme.primaryButtonStyle.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _enterMedicationCode();
                  },
                  icon: Icon(Icons.keyboard, color: AppTheme.primary),
                  label: Text(
                    'Enter NDC Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: AppTheme.primaryButtonStyle.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    _addMedicationManually();
                  },
                  icon: Icon(Icons.edit, color: AppTheme.primary),
                  label: Text(
                    'Add Medication Manually',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: AppTheme.primaryButtonStyle.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMedicationList() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Medications',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${medications.length} medications being managed',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _generateAndSharePDF,
                    icon:
                        const Icon(Icons.share, color: Colors.indigo, size: 28),
                    tooltip: 'Share medication list',
                  ),
                  IconButton(
                    onPressed: _navigateToAddMedication,
                    icon: const Icon(Icons.add_circle,
                        color: Colors.indigo, size: 32),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: medications.length,
              itemBuilder: (context, index) {
                final medication = medications[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.medication,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    title: Text(
                      medication['brandName'] ?? 'Unknown Medication',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(medication['genericName'] ?? 'Unknown Generic'),
                        const SizedBox(height: 2),
                        Text(
                          'Strength: ${medication['strength'] ?? 'Not specified'}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (medication['dosage']?.isNotEmpty == true)
                          Text(
                            'Dosage: ${medication['dosage']} - ${medication['frequency'] ?? 'As needed'}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue),
                          ),
                        if (medication['timeToTake']?.isNotEmpty == true)
                          Text(
                            'Time to take: ${medication['timeToTake']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orange),
                          ),
                        if (medication['takeWith']?.isNotEmpty == true)
                          Text(
                            'Take with: ${medication['takeWith']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green),
                          ),
                        if (medication['doNotTakeWith']?.isNotEmpty == true)
                          Text(
                            'Do not take with: ${medication['doNotTakeWith']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                          ),
                        if (medication['startDate'] != null ||
                            medication['endDate'] != null)
                          Text(
                            'Duration: ${_formatDateRange(medication['startDate'], medication['endDate'])}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.purple),
                          ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editMedication(index);
                            break;
                          case 'remove':
                            _removeMedication(index);
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'remove',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Remove'),
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

  String _formatDateRange(String? startDate, String? endDate) {
    if (startDate == null && endDate == null) return 'Not specified';

    final start = startDate != null ? _formatDate(startDate) : 'Start not set';
    final end = endDate != null ? _formatDate(endDate) : 'Ongoing';

    if (startDate != null && endDate != null) {
      return '$start to $end';
    } else if (startDate != null) {
      return 'From $start';
    } else {
      return 'Until $end';
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _scanMedicationCode() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required to scan barcodes'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BarcodeScannerScreen(
          onCodeScanned: (String code) async {
            Navigator.pop(context);
            await _processScannedCode(code);
          },
        ),
      ),
    );
  }

  Future<void> _processScannedCode(String code) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Looking up medication...'),
            ],
          ),
        );
      },
    );

    try {
      final medicationData = await _lookupMedication(code);
      Navigator.pop(context);

      if (medicationData != null) {
        // Check for duplicates before showing details
        if (_isDuplicateMedication(
          medicationData['brandName'],
          medicationData['genericName'],
        )) {
          _showDuplicateWarning(medicationData);
        } else {
          _showMedicationDetails(medicationData);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Medication not found. You can add it manually.'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Add Manually',
              textColor: Colors.white,
              onPressed: () {
                _addMedicationManually();
              },
            ),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error looking up medication. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDuplicateWarning(Map<String, dynamic> medicationData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Duplicate Medication Warning'),
          content: Text(
            'A medication with the name "${medicationData['brandName']}" or similar generic name is already in the list. Do you want to add it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showMedicationDetails(medicationData);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Add Anyway',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _enterMedicationCode() {
    final TextEditingController codeController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enter NDC Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter the NDC (National Drug Code) in product format:',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Product NDC',
                      hintText: 'e.g., 50580-937',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use format: XXXXX-XXX (5 digits, dash, 3 digits)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Looking up medication...'),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (codeController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter an NDC code'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                          });

                          try {
                            final medicationData = await _lookupMedication(
                              codeController.text.trim(),
                            );

                            Navigator.pop(context);

                            if (medicationData != null) {
                              // Check for duplicates
                              if (_isDuplicateMedication(
                                medicationData['brandName'],
                                medicationData['genericName'],
                              )) {
                                _showDuplicateWarning(medicationData);
                              } else {
                                _showMedicationDetails(medicationData);
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'NDC code not found. Please check the code and try again.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isLoading = false;
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error looking up medication: ${e.toString()}',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                  ),
                  child: Text(
                    isLoading ? 'Looking up...' : 'Lookup',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addMedicationManually() {
    final Map<String, TextEditingController> controllers = {
      'brandName': TextEditingController(),
      'genericName': TextEditingController(),
      'strength': TextEditingController(),
      'dosageForm': TextEditingController(),
      'manufacturer': TextEditingController(),
      'ndc': TextEditingController(),
      'dosage': TextEditingController(),
      'frequency': TextEditingController(),
      'timeToTake': TextEditingController(),
      'takeWith': TextEditingController(),
      'doNotTakeWith': TextEditingController(),
    };

    DateTime? startDate;
    DateTime? endDate;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Medication Manually'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controllers['brandName']!,
                      decoration: const InputDecoration(
                        labelText: 'Brand Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['genericName']!,
                      decoration: const InputDecoration(
                        labelText: 'Generic Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['strength']!,
                      decoration: const InputDecoration(
                        labelText: 'Strength (e.g., 10mg)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['dosageForm']!,
                      decoration: const InputDecoration(
                        labelText: 'Dosage Form (e.g., Tablet)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['manufacturer']!,
                      decoration: const InputDecoration(
                        labelText: 'Manufacturer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['ndc']!,
                      decoration: const InputDecoration(
                        labelText: 'NDC Code (optional)',
                        hintText: 'e.g., 50580-937',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['dosage']!,
                      decoration: const InputDecoration(
                        labelText: 'Dosage (e.g., 1 tablet)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['frequency']!,
                      decoration: const InputDecoration(
                        labelText: 'Frequency (e.g., Twice daily)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['timeToTake']!,
                      decoration: const InputDecoration(
                        labelText: 'Time to Take (e.g., 8:00 PM)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['takeWith']!,
                      decoration: const InputDecoration(
                        labelText: 'Take With (e.g., milk, food)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_dining),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['doNotTakeWith']!,
                      decoration: const InputDecoration(
                        labelText:
                            'Do Not Take With (e.g., alcohol, other meds)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.warning),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            startDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(
                              startDate != null
                                  ? 'Start Date: ${_formatDate(startDate!.toIso8601String())}'
                                  : 'Select Start Date (optional)',
                              style: TextStyle(
                                color: startDate != null
                                    ? Colors.black
                                    : Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? (startDate ?? DateTime.now()),
                          firstDate: startDate ?? DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            endDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(
                              endDate != null
                                  ? 'End Date: ${_formatDate(endDate!.toIso8601String())}'
                                  : 'Select End Date (optional)',
                              style: TextStyle(
                                color: endDate != null
                                    ? Colors.black
                                    : Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    if (controllers['brandName']!.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Brand name is required')),
                      );
                      return;
                    }

                    // Check for duplicates
                    if (_isDuplicateMedication(
                      controllers['brandName']!.text.trim(),
                      controllers['genericName']!.text.trim().isEmpty
                          ? null
                          : controllers['genericName']!.text.trim(),
                    )) {
                      Navigator.pop(context);
                      _showDuplicateWarningManual(
                          controllers, startDate, endDate);
                      return;
                    }

                    final medicationData = {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'brandName': controllers['brandName']!.text.trim(),
                      'genericName':
                          controllers['genericName']!.text.trim().isEmpty
                              ? 'Not specified'
                              : controllers['genericName']!.text.trim(),
                      'strength': controllers['strength']!.text.trim().isEmpty
                          ? 'Not specified'
                          : controllers['strength']!.text.trim(),
                      'dosageForm':
                          controllers['dosageForm']!.text.trim().isEmpty
                              ? 'Not specified'
                              : controllers['dosageForm']!.text.trim(),
                      'manufacturer':
                          controllers['manufacturer']!.text.trim().isEmpty
                              ? 'Not specified'
                              : controllers['manufacturer']!.text.trim(),
                      'ndc': controllers['ndc']!.text.trim().isEmpty
                          ? 'Manual Entry'
                          : controllers['ndc']!.text.trim(),
                      'dosage': controllers['dosage']!.text.trim(),
                      'frequency': controllers['frequency']!.text.trim(),
                      'timeToTake': controllers['timeToTake']!.text.trim(),
                      'takeWith': controllers['takeWith']!.text.trim(),
                      'doNotTakeWith':
                          controllers['doNotTakeWith']!.text.trim(),
                      'startDate': startDate?.toIso8601String(),
                      'endDate': endDate?.toIso8601String(),
                      'addedAt': DateTime.now().toIso8601String(),
                      'isManualEntry': true,
                    };

                    Navigator.pop(context);
                    _addMedicationToList(medicationData);
                  },
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  child: const Text('Add Medication',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDuplicateWarningManual(
    Map<String, TextEditingController> controllers,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Duplicate Medication Warning'),
          content: Text(
            'A medication with the name "${controllers['brandName']!.text.trim()}" or similar generic name is already in the list. Do you want to add it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final medicationData = {
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'brandName': controllers['brandName']!.text.trim(),
                  'genericName': controllers['genericName']!.text.trim().isEmpty
                      ? 'Not specified'
                      : controllers['genericName']!.text.trim(),
                  'strength': controllers['strength']!.text.trim().isEmpty
                      ? 'Not specified'
                      : controllers['strength']!.text.trim(),
                  'dosageForm': controllers['dosageForm']!.text.trim().isEmpty
                      ? 'Not specified'
                      : controllers['dosageForm']!.text.trim(),
                  'manufacturer':
                      controllers['manufacturer']!.text.trim().isEmpty
                          ? 'Not specified'
                          : controllers['manufacturer']!.text.trim(),
                  'ndc': controllers['ndc']!.text.trim().isEmpty
                      ? 'Manual Entry'
                      : controllers['ndc']!.text.trim(),
                  'dosage': controllers['dosage']!.text.trim(),
                  'frequency': controllers['frequency']!.text.trim(),
                  'timeToTake': controllers['timeToTake']!.text.trim(),
                  'takeWith': controllers['takeWith']!.text.trim(),
                  'doNotTakeWith': controllers['doNotTakeWith']!.text.trim(),
                  'startDate': startDate?.toIso8601String(),
                  'endDate': endDate?.toIso8601String(),
                  'addedAt': DateTime.now().toIso8601String(),
                  'isManualEntry': true,
                };

                Navigator.pop(context);
                _addMedicationToList(medicationData);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Add Anyway',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _editMedication(int index) {
    final medication = medications[index];
    final Map<String, TextEditingController> controllers = {
      'brandName': TextEditingController(text: medication['brandName'] ?? ''),
      'genericName':
          TextEditingController(text: medication['genericName'] ?? ''),
      'strength': TextEditingController(text: medication['strength'] ?? ''),
      'dosageForm': TextEditingController(text: medication['dosageForm'] ?? ''),
      'manufacturer':
          TextEditingController(text: medication['manufacturer'] ?? ''),
      'dosage': TextEditingController(text: medication['dosage'] ?? ''),
      'frequency': TextEditingController(text: medication['frequency'] ?? ''),
      'timeToTake': TextEditingController(text: medication['timeToTake'] ?? ''),
      'takeWith': TextEditingController(text: medication['takeWith'] ?? ''),
      'doNotTakeWith':
          TextEditingController(text: medication['doNotTakeWith'] ?? ''),
    };

    DateTime? startDate = medication['startDate'] != null
        ? DateTime.tryParse(medication['startDate'])
        : null;
    DateTime? endDate = medication['endDate'] != null
        ? DateTime.tryParse(medication['endDate'])
        : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Medication'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controllers['brandName']!,
                      decoration: const InputDecoration(
                        labelText: 'Brand Name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['genericName']!,
                      decoration: const InputDecoration(
                        labelText: 'Generic Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['strength']!,
                      decoration: const InputDecoration(
                        labelText: 'Strength',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['dosageForm']!,
                      decoration: const InputDecoration(
                        labelText: 'Dosage Form',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['manufacturer']!,
                      decoration: const InputDecoration(
                        labelText: 'Manufacturer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['dosage']!,
                      decoration: const InputDecoration(
                        labelText: 'Dosage',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['frequency']!,
                      decoration: const InputDecoration(
                        labelText: 'Frequency',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['timeToTake']!,
                      decoration: const InputDecoration(
                        labelText: 'Time to Take (e.g., 8:00 PM)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['takeWith']!,
                      decoration: const InputDecoration(
                        labelText: 'Take With (e.g., milk, food)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_dining),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controllers['doNotTakeWith']!,
                      decoration: const InputDecoration(
                        labelText:
                            'Do Not Take With (e.g., alcohol, other meds)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.warning),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            startDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                startDate != null
                                    ? 'Start Date: ${_formatDate(startDate!.toIso8601String())}'
                                    : 'Select Start Date (optional)',
                                style: TextStyle(
                                  color: startDate != null
                                      ? Colors.black
                                      : Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (startDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setDialogState(() {
                                    startDate = null;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? (startDate ?? DateTime.now()),
                          firstDate: startDate ?? DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            endDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                endDate != null
                                    ? 'End Date: ${_formatDate(endDate!.toIso8601String())}'
                                    : 'Select End Date (optional)',
                                style: TextStyle(
                                  color: endDate != null
                                      ? Colors.black
                                      : Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (endDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setDialogState(() {
                                    endDate = null;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
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
                    if (controllers['brandName']!.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Brand name is required')),
                      );
                      return;
                    }

                    // Check for duplicates (excluding current medication)
                    if (_isDuplicateMedication(
                      controllers['brandName']!.text.trim(),
                      controllers['genericName']!.text.trim().isEmpty
                          ? null
                          : controllers['genericName']!.text.trim(),
                      excludeId: medication['id'],
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'A medication with this name already exists'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      medications[index] = {
                        ...medication,
                        'brandName': controllers['brandName']!.text.trim(),
                        'genericName': controllers['genericName']!.text.trim(),
                        'strength': controllers['strength']!.text.trim(),
                        'dosageForm': controllers['dosageForm']!.text.trim(),
                        'manufacturer':
                            controllers['manufacturer']!.text.trim(),
                        'dosage': controllers['dosage']!.text.trim(),
                        'frequency': controllers['frequency']!.text.trim(),
                        'timeToTake': controllers['timeToTake']!.text.trim(),
                        'takeWith': controllers['takeWith']!.text.trim(),
                        'doNotTakeWith':
                            controllers['doNotTakeWith']!.text.trim(),
                        'startDate': startDate?.toIso8601String(),
                        'endDate': endDate?.toIso8601String(),
                        'lastModified': DateTime.now().toIso8601String(),
                      };
                    });

                    _saveMedications();

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Medication updated successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  child: const Text('Save Changes',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeMedication(int index) {
    final medication = medications[index];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Medication'),
          content: Text(
              'Are you sure you want to remove "${medication['brandName']}" from the medication list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  medications.removeAt(index);
                });
                _saveMedications();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('${medication['brandName']} removed successfully'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child:
                  const Text('Remove', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _lookupMedication(String code) async {
    final cleanCode = code.trim();

    try {
      final uri = Uri.parse('$_fdaApiBaseUrl"$cleanCode"$_fdaApiSuffix');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          return _parseNDCResult(result, cleanCode);
        }
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }

    return null;
  }

  Map<String, dynamic>? _parseNDCResult(
    Map<String, dynamic> result,
    String code,
  ) {
    try {
      return {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'ndc': code,
        'brandName': result['brand_name'] ??
            result['proprietary_name'] ??
            'Unknown Brand',
        'genericName': result['generic_name'] ??
            result['nonproprietary_name'] ??
            'Unknown Generic',
        'dosageForm': result['dosage_form_name'] ?? 'Unknown Form',
        'strength': result['active_ingredients']?.isNotEmpty == true
            ? '${result['active_ingredients'][0]['strength']} ${result['active_ingredients'][0]['unit']}'
            : 'Unknown Strength',
        'manufacturer': result['labeler_name'] ?? 'Unknown Manufacturer',
        'warnings': [],
        'indications': [],
        'dosageAndAdministration': [],
        'activeIngredients': result['active_ingredients'] ?? [],
        'dosage': '',
        'frequency': '',
        'timeToTake': '',
        'takeWith': '',
        'doNotTakeWith': '',
        'startDate': null,
        'endDate': null,
        'addedAt': DateTime.now().toIso8601String(),
        'isManualEntry': false,
      };
    } catch (e) {
      return null;
    }
  }

  void _showMedicationDetails(Map<String, dynamic> medicationData) {
    DateTime? startDate;
    DateTime? endDate;
    final dosageController = TextEditingController();
    final frequencyController = TextEditingController();
    final timeToTakeController = TextEditingController();
    final takeWithController = TextEditingController();
    final doNotTakeWithController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(medicationData['brandName']),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDetailRow(
                        'Generic Name:', medicationData['genericName']),
                    _buildDetailRow(
                        'Dosage Form:', medicationData['dosageForm']),
                    _buildDetailRow('Strength:', medicationData['strength']),
                    _buildDetailRow(
                      'Manufacturer:',
                      medicationData['manufacturer'],
                    ),
                    _buildDetailRow('NDC Code:', medicationData['ndc']),
                    const SizedBox(height: 16),
                    const Text(
                      'Treatment Information:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      decoration: const InputDecoration(
                        labelText: 'Dosage (e.g., 1 tablet)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: frequencyController,
                      decoration: const InputDecoration(
                        labelText: 'Frequency (e.g., Twice daily)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: timeToTakeController,
                      decoration: const InputDecoration(
                        labelText: 'Time to Take (e.g., 8:00 PM)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: takeWithController,
                      decoration: const InputDecoration(
                        labelText: 'Take With (e.g., milk, food)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_dining),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: doNotTakeWithController,
                      decoration: const InputDecoration(
                        labelText:
                            'Do Not Take With (e.g., alcohol, other meds)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.warning),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            startDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(
                              startDate != null
                                  ? 'Start Date: ${_formatDate(startDate!.toIso8601String())}'
                                  : 'Select Start Date (optional)',
                              style: TextStyle(
                                color: startDate != null
                                    ? Colors.black
                                    : Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: endDate ?? (startDate ?? DateTime.now()),
                          firstDate: startDate ?? DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            endDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(
                              endDate != null
                                  ? 'End Date: ${_formatDate(endDate!.toIso8601String())}'
                                  : 'Select End Date (optional)',
                              style: TextStyle(
                                color: endDate != null
                                    ? Colors.black
                                    : Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final updatedMedicationData = {
                      ...medicationData,
                      'dosage': dosageController.text.trim(),
                      'frequency': frequencyController.text.trim(),
                      'timeToTake': timeToTakeController.text.trim(),
                      'takeWith': takeWithController.text.trim(),
                      'doNotTakeWith': doNotTakeWithController.text.trim(),
                      'startDate': startDate?.toIso8601String(),
                      'endDate': endDate?.toIso8601String(),
                    };

                    Navigator.pop(context);
                    _addMedicationToList(updatedMedicationData);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: Text(
                    'Add Medication',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _addMedicationToList(Map<String, dynamic> medicationData) async {
    setState(() {
      medications.add({
        ...medicationData,
        'addedAt':
            medicationData['addedAt'] ?? DateTime.now().toIso8601String(),
        'nextDose': null,
      });
    });

    await _saveMedications();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${medicationData['brandName']} added successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _navigateToAddMedication() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Medication',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.indigo,
                ),
                title: const Text('Scan Barcode'),
                subtitle: const Text('Use camera to scan medication barcode'),
                onTap: () {
                  Navigator.pop(context);
                  _scanMedicationCode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.keyboard, color: Colors.indigo),
                title: const Text('Enter NDC Code'),
                subtitle: const Text('Type NDC code manually'),
                onTap: () {
                  Navigator.pop(context);
                  _enterMedicationCode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.indigo),
                title: const Text('Add Manually'),
                subtitle: const Text('Enter medication details manually'),
                onTap: () {
                  Navigator.pop(context);
                  _addMedicationManually();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  final Function(String) onCodeScanned;

  const BarcodeScannerScreen({
    super.key,
    required this.onCodeScanned,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  bool isScanning = true;
  bool flashOn = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Medication Barcode'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(flashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() {
                flashOn = !flashOn;
                cameraController.toggleTorch();
              });
            },
          ),
          IconButton(
            icon: Icon(isScanning ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                isScanning = !isScanning;
                if (isScanning) {
                  cameraController.start();
                } else {
                  cameraController.stop();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: MobileScanner(
              controller: cameraController,
              onDetect: (capture) {
                if (!isScanning) return;

                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    setState(() {
                      isScanning = false;
                    });
                    cameraController.stop();

                    widget.onCodeScanned(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 24,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.view_module,
                      size: 24,
                      color: Colors.indigo,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scanning for QR codes and barcodes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Position any barcode or QR code in the camera view',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                      label: const Text('Cancel',
                          style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        cameraController.switchCamera();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo),
                      icon: const Icon(Icons.flip_camera_ios,
                          color: Colors.white, size: 18),
                      label: const Text('Flip',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
