import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import '../features/dashboard/models/patient_model.dart';

/// Service for generating and exporting EDI (Electronic Data Interchange) files
/// for Electronic Visit Verification (EVV) compliance
class EdiService {
  /// Generate EDI 837 format content for a visit
  static String generateEDIContent({
    required Patient patient,
    required String serviceType,
    required DateTime checkinTime,
    required DateTime checkoutTime,
    required int duration,
    required String notes,
    double? checkinLatitude,
    double? checkinLongitude,
    double? checkoutLatitude,
    double? checkoutLongitude,
    String? checkinLocationType,
    String? checkoutLocationType,
  }) {
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
        '${checkinTime.year}${checkinTime.month.toString().padLeft(2, '0')}${checkinTime.day.toString().padLeft(2, '0')}';

    String patientDob = '19700101';
    if (patient.dob.isNotEmpty) {
      try {
        final dobDate = DateTime.parse(patient.dob);
        patientDob =
            '${dobDate.year}${dobDate.month.toString().padLeft(2, '0')}${dobDate.day.toString().padLeft(2, '0')}';
      } catch (e) {
        patientDob = '19700101';
      }
    }

    final gender = (patient.gender?.toUpperCase() == 'MALE' ||
            patient.gender?.toUpperCase() == 'M')
        ? 'M'
        : 'F';

    final claimId =
        '${patient.id}${checkinTime.millisecondsSinceEpoch.toString().substring(0, 10)}';
    final evvId = 'EVV-$claimId';

    final units = ((duration / 15).ceil()).toString();
    final totalCharge = (30.0 * (duration / 15).ceil()).toStringAsFixed(2);

    final addressLine1 = patient.address?.line1 ?? '123 Main St';
    final city = patient.address?.city ?? 'Richmond';
    final state = patient.address?.state ?? 'VA';
    final zip = patient.address?.zip ?? '23220';

    final controlNumber =
        now.millisecondsSinceEpoch.toString().substring(3, 12);

    // Calculate segment count (base 30 segments + 1 if notes exist)
    final segmentCount = notes.isNotEmpty ? 31 : 30;

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
${notes.isNotEmpty ? 'NTE*ADD*${notes.replaceAll('~', '')}~\n' : ''}SE*$segmentCount*0001~
GE*1*$controlNumber~
IEA*1*$controlNumber~
''';

    return ediContent;
  }

  /// Export visit data as an EDI file
  /// Returns true if successful, false otherwise
  static Future<bool> exportVisitData({
    required Patient patient,
    required String serviceType,
    required DateTime checkinTime,
    required DateTime checkoutTime,
    required int duration,
    required String notes,
    double? checkinLatitude,
    double? checkinLongitude,
    double? checkoutLatitude,
    double? checkoutLongitude,
    String? checkinLocationType,
    String? checkoutLocationType,
  }) async {
    try {
      // Generate EDI content
      final ediContent = generateEDIContent(
        patient: patient,
        serviceType: serviceType,
        checkinTime: checkinTime,
        checkoutTime: checkoutTime,
        duration: duration,
        notes: notes,
        checkinLatitude: checkinLatitude,
        checkinLongitude: checkinLongitude,
        checkoutLatitude: checkoutLatitude,
        checkoutLongitude: checkoutLongitude,
        checkinLocationType: checkinLocationType,
        checkoutLocationType: checkoutLocationType,
      );

      // Convert to bytes
      final bytes = utf8.encode(ediContent);

      // Generate filename
      final filename =
          'visit_${patient.id}_${checkinTime.millisecondsSinceEpoch}.edi';

      // Create blob and download (web-compatible approach)
      final blob = html.Blob([bytes], 'text/plain');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;

      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      return true;
    } catch (e) {
      print('Error exporting EDI file: $e');
      return false;
    }
  }

  /// Validate EDI content format
  static bool validateEDIContent(String content) {
    if (content.isEmpty) return false;

    // Check for required segments
    final requiredSegments = ['ISA', 'GS', 'ST', 'BHT', 'SE', 'GE', 'IEA'];
    for (final segment in requiredSegments) {
      if (!content.contains(segment)) {
        return false;
      }
    }

    return true;
  }

  /// Parse service type to EDI code
  static String parseServiceTypeToCode(String serviceType) {
    final serviceTypeMap = {
      'Personal Care': 'T1019',
      'Companion Care': 'S5125',
      'Respite Care': 'T1005',
      'Homemaker Services': 'S5130',
      'Skilled Nursing': '99601',
      'Physical Therapy': '97110',
      'Occupational Therapy': '97530',
      'Speech Therapy': '92507',
      'Medical Social Work': 'G0155',
      'Home Health Aide': 'G0156',
    };

    return serviceTypeMap[serviceType] ?? 'T1019'; // Default to Personal Care
  }

  /// Calculate billable units based on duration in seconds
  /// Each unit is 15 minutes (900 seconds)
  static int calculateBillableUnits(int durationSeconds) {
    return (durationSeconds / 900).ceil();
  }

  /// Calculate total charge based on billable units
  /// Default rate is $30 per unit (15 minutes)
  static double calculateTotalCharge(int durationSeconds,
      {double ratePerUnit = 30.0}) {
    final units = calculateBillableUnits(durationSeconds);
    return units * ratePerUnit;
  }

  /// Format MA (Medicaid) number with proper padding
  static String formatMANumber(int patientId, String? existingMANumber) {
    if (existingMANumber != null && existingMANumber.isNotEmpty) {
      return existingMANumber;
    }
    return 'MA${patientId.toString().padLeft(9, '0')}';
  }

  /// Generate control number from timestamp
  static String generateControlNumber() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(3, 12);
  }

  /// Format date for EDI (YYYYMMDD)
  static String formatEDIDate(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  /// Format time for EDI (HHMM)
  static String formatEDITime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}';
  }

  /// Format date for ISA segment (YYMMDD)
  static String formatISADate(DateTime date) {
    return '${date.year.toString().substring(2)}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  /// Sanitize notes for EDI format (remove segment terminators)
  static String sanitizeNotes(String notes) {
    return notes.replaceAll('~', '').replaceAll('*', '').replaceAll(':', '');
  }

  /// Generate a mock EDI 837 file for testing purposes
  /// Returns a sample EDI 837 Professional Healthcare Claim format string
  static String generateMockEdi837({
    String? patientFirstName,
    String? patientLastName,
    String? maNumber,
    String? serviceType,
    DateTime? serviceDate,
    String? providerName,
    String? providerNPI,
    double? chargeAmount,
    int? serviceUnits,
  }) {
    // Use defaults if not provided
    final firstName = patientFirstName ?? 'John';
    final lastName = patientLastName ?? 'Doe';
    final subscriberId = maNumber ?? 'SUBSCR12345';
    final svcType = serviceType ?? 'Personal Care';
    final svcDate = serviceDate ?? DateTime.now();
    final provider = providerName ?? 'CareConnect Agency';
    final npi = providerNPI ?? '1234567893';
    final charge = chargeAmount ?? 120.00;
    final units = serviceUnits ?? 4;

    final now = DateTime.now();
    final isaDate = formatISADate(now);
    final isaTime = formatEDITime(now);
    final gsDate = formatEDIDate(now);
    final gsTime = formatEDITime(now);
    final serviceDateFormatted = formatEDIDate(svcDate);
    final controlNumber = generateControlNumber();
    final claimId =
        'MOCK${now.millisecondsSinceEpoch.toString().substring(0, 10)}';

    // Service type code
    final serviceCode = parseServiceTypeToCode(svcType);

    return '''ISA*00*          *00*          *ZZ*SUBMIT123      *ZZ*987654321      *$isaDate*$isaTime*^*00501*$controlNumber*0*P*:~
GS*HC*SUBMIT123*987654321*$gsDate*$gsTime*$controlNumber*X*005010X222A1~
ST*837*0001*005010X222A1~
BHT*0019*00*$claimId*$gsDate*$gsTime*CH~
NM1*41*2*$provider*****46*SUBMIT123~
PER*IC*Billing Contact*TE*5551234567~
NM1*40*2*ANTHEM*****46*987654321~
HL*1**20*1~
PRV*BI*PXC*251E00000X~
NM1*85*2*$provider*****XX*$npi~
N3*123 Care Street~
N4*Richmond*VA*23220~
REF*EI*123456789~
HL*2*1*22*0~
SBR*P*18**MC*****MC~
NM1*IL*1*$lastName*$firstName****MI*$subscriberId~
N3*456 Patient Ave~
N4*Richmond*VA*23220~
DMG*D8*19800515*M~
NM1*PR*2*ANTHEM*****PI*00123~
CLM*$claimId*${charge.toStringAsFixed(2)}***12:B:1**A*Y*Y~
DTP*434*RD8*$serviceDateFormatted-$serviceDateFormatted~
REF*D9*AUTH12345~
REF*F8*EVV-$claimId~
HI*BK:I10~
NM1*82*1*Smith*Jane****XX*9876543210~
PRV*PE*PXC*3747P1801X~
LX*1~
SV1*HC:$serviceCode*${charge.toStringAsFixed(2)}*UN*$units***1~
DTP*472*D8*$serviceDateFormatted~
SE*30*0001~
GE*1*$controlNumber~
IEA*1*$controlNumber~
''';
  }

  /// Generate mock EDI with custom parameters for testing
  static String generateMockEdiWithDetails({
    required String patientId,
    required String patientFirstName,
    required String patientLastName,
    required String serviceType,
    required DateTime serviceDate,
    required int durationMinutes,
    String? notes,
    String? maNumber, // Optional: Use actual MA number if provided
  }) {
    final units = (durationMinutes / 15).ceil();
    final charge = calculateTotalCharge(durationMinutes * 60);
    // Use provided MA number or generate from patientId as fallback
    final finalMaNumber = maNumber ?? 'MA${patientId.padLeft(9, '0')}';

    return generateMockEdi837(
      patientFirstName: patientFirstName,
      patientLastName: patientLastName,
      maNumber: finalMaNumber,
      serviceType: serviceType,
      serviceDate: serviceDate,
      chargeAmount: charge,
      serviceUnits: units,
    );
  }
}
