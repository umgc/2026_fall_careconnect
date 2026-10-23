import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:universal_html/html.dart' as html;
import '../../../../providers/user_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../services/api_service.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../dashboard/models/patient_model.dart';

class VisitCompletedSuccessPage extends StatefulWidget {
  final int patientId;
  final String serviceType;
  final String checkinLocationType;
  final String checkoutLocationType;
  final double? checkinLatitude;
  final double? checkinLongitude;
  final double? checkoutLatitude;
  final double? checkoutLongitude;
  final String notes;
  final int duration; // seconds
  final DateTime checkinTime;
  final DateTime checkoutTime;

  const VisitCompletedSuccessPage({
    super.key,
    required this.patientId,
    required this.serviceType,
    required this.checkinLocationType,
    required this.checkoutLocationType,
    this.checkinLatitude,
    this.checkinLongitude,
    this.checkoutLatitude,
    this.checkoutLongitude,
    required this.notes,
    required this.duration,
    required this.checkinTime,
    required this.checkoutTime,
  });

  @override
  State<VisitCompletedSuccessPage> createState() =>
      _VisitCompletedSuccessPageState();
}

class _VisitCompletedSuccessPageState extends State<VisitCompletedSuccessPage> {
  Patient? _selectedPatient;
  bool _isLoading = true;
  String? _error;

  // spacing
  static const double _kPad = 10.0;

  @override
  void initState() {
    super.initState();
    _loadPatientDetails();
  }

  // ---------- data ----------
  Future<void> _loadOffline(VoidCallback done) async {
    if (!mounted) return;
    setState(done);
  }

  Future<void> _loadPatientDetails() async {
    try {
      await _loadOffline(() {
        _isLoading = true;
        _error = null;
      });

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      if (user == null) throw Exception('User not authenticated');

      final caregiverId = user.caregiverId ?? user.id;
      final response = await ApiService.getCaregiverPatients(caregiverId);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (var json in data) {
          try {
            Map<String, dynamic> patientJson;
            if (json is Map &&
                json.containsKey('patient') &&
                json['patient'] != null) {
              final patientData = json['patient'];
              patientJson = patientData is Map
                  ? Map<String, dynamic>.from(patientData)
                  : Map<String, dynamic>.from(json);
            } else {
              patientJson = Map<String, dynamic>.from(json);
            }
            final patient = Patient.fromJson(patientJson);
            if (patient.id == widget.patientId) {
              if (!mounted) return;
              setState(() {
                _selectedPatient = patient;
                _isLoading = false;
              });
              return;
            }
          } catch (_) {}
        }
        throw Exception('Patient not found');
      } else {
        throw Exception(
            'Failed to load patient details: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ---------- formatting ----------
  String _formatAddress(Patient p) {
    final a = p.address;
    if (a == null) return 'Address not available';
    final parts = <String>[
      if ((a.line1 ?? '').isNotEmpty) a.line1!,
      if ((a.line2 ?? '').isNotEmpty) a.line2!,
      if ((a.city ?? '').isNotEmpty) a.city!,
      if ((a.state ?? '').isNotEmpty) a.state!,
      if ((a.zip ?? '').isNotEmpty) a.zip!,
    ];
    return parts.join(', ');
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0 && s == 0) return '${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${d.inSeconds}s';
  }

  String _formatDurationDetailed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  String _formatTime(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : t.hour;
    final display = h == 0 ? 12 : h;
    final am = t.hour >= 12 ? 'PM' : 'AM';
    return '$display:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} $am';
  }

  String _formatLocation(String type, double? lat, double? lng, Patient p) {
    if (type.toLowerCase() == 'gps' && lat != null && lng != null) {
      return 'GPS ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    }
    if (type.toLowerCase() == 'gps') return 'GPS (coords unavailable)';
    return _formatAddress(p);
  }

  String _uniqueFileName(String base) {
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    final rand =
        math.Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${base}_${ts}_$rand.edi';
  }

  // ---------- actions ----------
  void _goToDashboard() => context.go('/dashboard?role=CAREGIVER');

  Future<void> _exportVisitData() async {
    try {
      if (_selectedPatient == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Patient data not available for export'),
              backgroundColor: Colors.red),
        );
        return;
      }
      final edi = _generateEDIContent();
      final bytes = utf8.encode(edi);

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'text/plain');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final a = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download =
              'visit_${_selectedPatient!.id}_${widget.checkinTime.millisecondsSinceEpoch}.edi';
        html.document.body?.children.add(a);
        a.click();
        html.document.body?.children.remove(a);
        html.Url.revokeObjectUrl(url);
      } else {
        final fileName = _uniqueFileName('visit_${_selectedPatient!.id}');
        try {
          String downloadsPath = '/storage/emulated/0/Download';
          if (!await Directory(downloadsPath).exists()) {
            final ext = await getExternalStorageDirectory();
            downloadsPath = ext?.path ?? downloadsPath;
          }
          final savePath = '$downloadsPath/$fileName';
          await File(savePath)
              .writeAsBytes(Uint8List.fromList(bytes), flush: true);
          await OpenFilex.open(savePath);
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Saved to: $savePath')));
        } catch (_) {
          final tmp = await getTemporaryDirectory();
          final path = '${tmp.path}/$fileName';
          await File(path).writeAsBytes(Uint8List.fromList(bytes), flush: true);
          final xfile = XFile(path, mimeType: 'text/plain', name: fileName);
          await Share.shareXFiles([xfile], text: 'EVV EDI export');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Visit data exported successfully'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _previewVisitEdi() async {
    if (kIsWeb) return;
    final edi = _generateEDIContent();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final border = cs.outlineVariant;
        final bg = cs.surfaceContainerHighest;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Preview EDI',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(edi,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: edi));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Copied to clipboard')));
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _exportVisitData,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Save to Downloads'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- EDI ----------
  String _generateEDIContent() {
    final patient = _selectedPatient!;
    final maNumber =
        patient.maNumber ?? 'SUBSCR${patient.id.toString().padLeft(5, '0')}';

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
        '${widget.checkinTime.year}${widget.checkinTime.month.toString().padLeft(2, '0')}${widget.checkinTime.day.toString().padLeft(2, '0')}';

    String patientDob = '19700101';
    if (patient.dob.isNotEmpty) {
      try {
        final dob = DateTime.parse(patient.dob);
        patientDob =
            '${dob.year}${dob.month.toString().padLeft(2, '0')}${dob.day.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final gender = (patient.gender?.toUpperCase() == 'MALE' ||
            patient.gender?.toUpperCase() == 'M')
        ? 'M'
        : 'F';
    final claimId =
        '${patient.id}${widget.checkinTime.millisecondsSinceEpoch.toString().substring(0, 10)}';
    final evvId = 'EVV-$claimId';
    final units = ((widget.duration / 15).ceil()).toString();
    final totalCharge =
        (30.0 * (widget.duration / 15).ceil()).toStringAsFixed(2);

    final addressLine1 = patient.address?.line1 ?? '123 Main St';
    final city = patient.address?.city ?? 'Richmond';
    final state = patient.address?.state ?? 'VA';
    final zip = patient.address?.zip ?? '23220';

    final controlNumber =
        now.millisecondsSinceEpoch.toString().substring(3, 12);
    final segmentCount = widget.notes.isNotEmpty ? 31 : 30;

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
NM1*IL*1*${patient.lastName}*${patient.firstName}****MI*$maNumber~
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
${widget.notes.isNotEmpty ? 'NTE*ADD*${widget.notes.replaceAll('~', '')}~\n' : ''}SE*$segmentCount*0001~
GE*1*$controlNumber~
IEA*1*$controlNumber~
''';

    return ediContent;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit Completed'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/dashboard?role=CAREGIVER'),
            icon: Icon(Icons.cancel, color: cs.error),
            label: Text('Close', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildErrorState();
    if (_selectedPatient == null) return _buildPatientNotFoundState();
    return _buildSuccessPage();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            const Text('Error Loading Patient',
                style: AppTheme.headingSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_error!,
                style: AppTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: _loadPatientDetails,
                style: AppTheme.primaryButtonStyle,
                child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientNotFoundState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('Patient Not Found',
                style: AppTheme.headingSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('The selected patient could not be found.',
                style: AppTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: () => context.go('/evv/select-patient'),
                style: AppTheme.primaryButtonStyle,
                child: const Text('Back to Patient Selection')),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessPage() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final patient = _selectedPatient!;
    final fullName = '${patient.firstName} ${patient.lastName}';
    final maNumber =
        patient.maNumber ?? 'MA${patient.id.toString().padLeft(9, '0')}';
    final addr = _formatAddress(patient);
    final duration = Duration(seconds: widget.duration);

    final inLoc = _formatLocation(widget.checkinLocationType,
        widget.checkinLatitude, widget.checkinLongitude, patient);
    final outLoc = _formatLocation(widget.checkoutLocationType,
        widget.checkoutLatitude, widget.checkoutLongitude, patient);

    // success banner colors that work in dark and light
    final successColor = Colors.green;
    final successText = isDark ? Colors.green.shade200 : Colors.green.shade800;
    final successBg = successColor.withOpacity(isDark ? 0.20 : 0.12);
    final successBorder = successColor.withOpacity(isDark ? 0.35 : 0.25);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(_kPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: successBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: successBorder),
            ),
            child: Text('Visit completed and ready for submission',
                style: TextStyle(
                    color: successText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),

          // EVV section
          _evvCompact(context, inLoc, outLoc),

          const SizedBox(height: 8),

          LayoutBuilder(builder: (c, cons) {
            final isWide = cons.maxWidth >= 640;

            final left = _card(
              context: context,
              children: [
                _sectionHeader(
                    context, Icons.person_outline, 'Patient & Service'),
                const SizedBox(height: 6),
                Text(fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _chip(context, maNumber),
                const SizedBox(height: 6),
                Text(addr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const Divider(height: 16),
                Text('Service Type',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(widget.serviceType,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            );

            final right = _card(
              context: context,
              children: [
                _sectionHeader(context, Icons.schedule, 'Time & Duration'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                        child: _kv(context, 'Check-In',
                            _formatTime(widget.checkinTime))),
                    Expanded(
                        child: _kv(context, 'Check-Out',
                            _formatTime(widget.checkoutTime))),
                  ],
                ),
                const SizedBox(height: 4),
                _kv(context, 'Total', _formatDuration(duration)),
                Text('(${_formatDurationDetailed(duration)})',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            );

            if (!isWide) return Column(children: [left, right]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: left),
              const SizedBox(width: 8),
              Expanded(child: right),
            ]);
          }),

          // Actions
          _actionsRow(context),
        ],
      ),
    );
  }

  // ---------- pieces ----------
  Widget _card(
      {required BuildContext context, required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children)),
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 1),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _chip(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = cs.outlineVariant.withOpacity(isDark ? 0.28 : 0.18);
    final border = cs.outlineVariant.withOpacity(isDark ? 0.45 : 0.35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border)),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _badge(BuildContext context, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(isDark ? 0.40 : 0.28)),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _evvCompact(BuildContext context, String inLoc, String outLoc) {
    final cs = Theme.of(context).colorScheme;
    final okText = Theme.of(context).brightness == Brightness.dark
        ? Colors.blue.shade200
        : Colors.blue.shade700;
    final okBg = Colors.blue.withOpacity(
        Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.12);
    final okBorder = Colors.blue.withOpacity(
        Theme.of(context).brightness == Brightness.dark ? 0.40 : 0.28);

    return _card(
      context: context,
      children: [
        _sectionHeader(context, Icons.verified, 'EVV Location Verification'),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
                widget.checkinLocationType.toLowerCase() == 'gps'
                    ? Icons.gps_fixed
                    : Icons.home,
                size: 16,
                color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Check-In',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            _badge(
                context,
                widget.checkinLocationType.toLowerCase() == 'gps'
                    ? 'GPS'
                    : 'PATIENT ADDRESS',
                Colors.blue),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(inLoc, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
                widget.checkoutLocationType.toLowerCase() == 'gps'
                    ? Icons.gps_fixed
                    : Icons.home,
                size: 16,
                color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Check-Out',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            _badge(
                context,
                widget.checkoutLocationType.toLowerCase() == 'gps'
                    ? 'GPS'
                    : 'PATIENT ADDRESS',
                Colors.blue),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(outLoc, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: okBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: okBorder)),
          child: Text('EVV compliance confirmed for this visit.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: okText)),
        ),
      ],
    );
  }

  Widget _actionsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPad, 6, _kPad, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exportVisitData,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: shape),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export EDI'),
            ),
          ),
          const SizedBox(width: 8),
          if (!kIsWeb)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _previewVisitEdi,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: shape),
                icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                label: const Text('Preview'),
              ),
            ),
          if (!kIsWeb) const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _goToDashboard,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: shape,
                  backgroundColor: cs.secondary),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: Text('Dashboard', style: TextStyle(color: cs.onSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
