import '../models/health_record.dart';

/// Maps one EHR list row to a [HealthRecord].
///
/// The row is the backend's `EhrResourceListItem`, the shape shared by
/// GET /api/ehr/resources (Epic) and GET /api/athena/resources:
/// `{ resourceType, resourceId, category, title, status, occurredAt,
/// lastSyncedAt, source }`.
class EhrResourceMapper {
  const EhrResourceMapper._();

  /// The source a row came from, or null when the app doesn't know it.
  ///
  /// A resource whose source the app does not know is dropped, never
  /// relabelled as another source: provenance shown to a patient must be the
  /// real one (DEF-MCR-22, as DEF-MCR-14 for HealthRecord.fromJson).
  /// athenahealth rows are stored as `ATHENAHEALTH` (AthenaProperties).
  static RecordSource? sourceFrom(dynamic source) {
    switch (source?.toString().trim().toUpperCase()) {
      case 'EPIC':
        return RecordSource.epic;
      case 'CERNER':
      case 'ORACLE_HEALTH':
        return RecordSource.cerner;
      case 'ATHENA':
      case 'ATHENAHEALTH':
        return RecordSource.athena;
      case 'MEDICARE':
        return RecordSource.medicare;
      default:
        return null;
    }
  }

  /// The record type for a row. The FHIR [resourceType] decides when the
  /// app knows it, because one backend category can hold several kinds of
  /// record (Care Context holds visits as well as care plans); otherwise the
  /// backend's [category] (EhrResourceCategory) decides.
  static RecordType recordTypeFrom(dynamic category, {dynamic resourceType}) {
    switch (resourceType?.toString()) {
      case 'Condition':
        return RecordType.condition;
      case 'MedicationRequest':
      case 'MedicationStatement':
        return RecordType.medication;
      case 'AllergyIntolerance':
        return RecordType.allergy;
      case 'Encounter':
        return RecordType.appointment;
      case 'Observation':
      case 'DiagnosticReport':
      case 'Immunization':
      case 'Procedure':
      case 'DocumentReference':
        return RecordType.clinicalRecord;
    }
    switch (category?.toString()) {
      case 'Conditions':
        return RecordType.condition;
      case 'Medications':
        return RecordType.medication;
      case 'Allergies':
        return RecordType.allergy;
      case 'Results':
      case 'Immunizations':
      case 'Procedures':
      case 'Documents':
        return RecordType.clinicalRecord;
      default:
        // Care plans, goals, care team, family history, devices and
        // insurance have no closer type than a general record.
        return RecordType.other;
    }
  }

  /// The record for [row], or null when its source is unknown. Ends with the
  /// row's Category, for every source alike (so neither the cards nor a
  /// conflict review can tell sources apart by it), then a
  /// [lastUpdatedLabel] detail when the row says when it was retrieved, the
  /// provenance a conflict review shows (WBS 6.2.41).
  static HealthRecord? toHealthRecord(Map<String, dynamic> row,
      {List<RecordDetail> details = const []}) {
    final source = sourceFrom(row['source']);
    if (source == null) return null;
    final synced = parseDate(row['lastSyncedAt']);
    final category = stringOrNull(row['category']);
    return HealthRecord.single(
      id: (row['resourceId'] ?? '').toString(),
      source: source,
      type: recordTypeFrom(row['category'], resourceType: row['resourceType']),
      title: stringOrNull(row['title']) ?? 'Health record',
      date: parseDate(row['occurredAt']),
      status: stringOrNull(row['status']),
      resourceType: stringOrNull(row['resourceType']),
      details: [
        ...details,
        if (category != null) RecordDetail('Category', category),
        if (synced != null) RecordDetail(lastUpdatedLabel, shortDate(synced)),
      ],
    );
  }

  /// When the record was retrieved (FR-MCR-21). Same label for every
  /// source.
  static const lastUpdatedLabel = 'Retrieved';

  static String shortDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = d.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  static String? stringOrNull(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
