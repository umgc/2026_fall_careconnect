import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_token_manager.dart';

/// Definition of a single form field captured from a document.
class DocumentFieldSpec {
  final String key;
  final String label;
  final bool required;
  final bool isDate;
  final String? hint;

  const DocumentFieldSpec(
    this.key,
    this.label, {
    this.required = false,
    this.isDate = false,
    this.hint,
  });
}

/// Field templates per document type for structured form entry.
///
/// Keys and required flags must stay aligned with the backend rules in
/// `com.careconnect.model.StructuredDocumentEntry.REQUIRED_FIELDS` so that a
/// form that validates locally is also accepted by the server.
class DocumentFieldTemplates {
  DocumentFieldTemplates._();

  static const Map<String, List<DocumentFieldSpec>> _templates = {
    'EMPLOYMENT_APPLICATION': [
      DocumentFieldSpec('applicantName', 'Applicant name', required: true),
      DocumentFieldSpec('positionApplied', 'Position applied for',
          required: true),
      DocumentFieldSpec('applicationDate', 'Application date',
          required: true, isDate: true),
      DocumentFieldSpec('phone', 'Phone'),
      DocumentFieldSpec('email', 'Email'),
    ],
    'ONBOARDING_FORM': [
      DocumentFieldSpec('employeeName', 'Employee name', required: true),
      DocumentFieldSpec('startDate', 'Start date', required: true, isDate: true),
      DocumentFieldSpec('supervisorName', 'Supervisor name'),
      DocumentFieldSpec('notes', 'Notes'),
    ],
    'HIRING_DOCUMENT': [
      DocumentFieldSpec('documentTitle', 'Document title',
          required: true, hint: 'e.g. Offer letter, Job description'),
      DocumentFieldSpec('employeeName', 'Employee name', required: true),
      DocumentFieldSpec('documentDate', 'Document date', isDate: true),
      DocumentFieldSpec('notes', 'Notes'),
    ],
    'BACKGROUND_CHECK': [
      DocumentFieldSpec('subjectName', 'Subject name', required: true),
      DocumentFieldSpec('screeningAgency', 'Screening agency', required: true),
      DocumentFieldSpec('screeningDate', 'Screening date',
          required: true, isDate: true),
      DocumentFieldSpec('result', 'Result',
          required: true, hint: 'e.g. Clear, Pending'),
      DocumentFieldSpec('notes', 'Notes'),
    ],
    'CERTIFICATION': [
      DocumentFieldSpec('certificationName', 'Certification name',
          required: true, hint: 'e.g. CPR / First Aid'),
      DocumentFieldSpec('holderName', 'Holder name', required: true),
      DocumentFieldSpec('issuingAuthority', 'Issuing authority',
          required: true),
      DocumentFieldSpec('issueDate', 'Issue date', required: true, isDate: true),
      DocumentFieldSpec('expirationDate', 'Expiration date', isDate: true),
    ],
    'REFERENCE': [
      DocumentFieldSpec('referenceName', 'Reference name', required: true),
      DocumentFieldSpec('relationship', 'Relationship', required: true),
      DocumentFieldSpec('phone', 'Phone'),
      DocumentFieldSpec('email', 'Email'),
      DocumentFieldSpec('notes', 'Notes'),
    ],
    'EMPLOYMENT_CONTRACT': [
      DocumentFieldSpec('employeeName', 'Employee name', required: true),
      DocumentFieldSpec('employerName', 'Employer name', required: true),
      DocumentFieldSpec('contractStartDate', 'Contract start date',
          required: true, isDate: true),
      DocumentFieldSpec('contractEndDate', 'Contract end date', isDate: true),
      DocumentFieldSpec('payRate', 'Pay rate'),
    ],
    'TAX_FORM': [
      DocumentFieldSpec('employeeName', 'Employee name', required: true),
      DocumentFieldSpec('taxYear', 'Tax year', required: true),
      DocumentFieldSpec('filingStatus', 'Filing status', required: true),
      DocumentFieldSpec('withholdingAllowances', 'Withholding allowances'),
    ],
    'WORK_AUTHORIZATION': [
      DocumentFieldSpec('employeeName', 'Employee name', required: true),
      DocumentFieldSpec('documentTitle', 'Document title',
          required: true, hint: 'e.g. Passport, Permanent Resident Card'),
      DocumentFieldSpec('documentNumber', 'Document number', required: true),
      DocumentFieldSpec('expirationDate', 'Expiration date', isDate: true),
    ],
    'EMERGENCY_CONTACT': [
      DocumentFieldSpec('contactName', 'Contact name', required: true),
      DocumentFieldSpec('relationship', 'Relationship', required: true),
      DocumentFieldSpec('phone', 'Phone', required: true),
      DocumentFieldSpec('alternatePhone', 'Alternate phone'),
      DocumentFieldSpec('address', 'Address'),
    ],
    'INSURANCE_DOCUMENT': [
      DocumentFieldSpec('policyHolderName', 'Policy holder name',
          required: true),
      DocumentFieldSpec('insuranceProvider', 'Insurance provider',
          required: true),
      DocumentFieldSpec('policyNumber', 'Policy number', required: true),
      DocumentFieldSpec('groupNumber', 'Group number'),
      DocumentFieldSpec('effectiveDate', 'Effective date', isDate: true),
    ],
  };

  /// Document types (backend category tokens) that support structured entry.
  static List<String> get supportedTypes => _templates.keys.toList();

  static bool isSupported(String? category) =>
      category != null && _templates.containsKey(category);

  static List<DocumentFieldSpec> fieldsFor(String category) =>
      _templates[category] ?? const [];
}

/// Structured form entry captured from an uploaded document.
class StructuredEntryDTO {
  final int id;
  final int fileId;
  final String documentType;
  final int? patientId;
  final int? employeeUserId;
  final Map<String, String> fields;
  final String? originalFilename;
  final String? fileUrl;

  StructuredEntryDTO({
    required this.id,
    required this.fileId,
    required this.documentType,
    this.patientId,
    this.employeeUserId,
    required this.fields,
    this.originalFilename,
    this.fileUrl,
  });

  factory StructuredEntryDTO.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    return StructuredEntryDTO(
      id: json['id'] ?? 0,
      fileId: json['fileId'] ?? 0,
      documentType: json['documentType'] ?? '',
      patientId: json['patientId'],
      employeeUserId: json['employeeUserId'],
      fields: rawFields is Map
          ? rawFields.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : <String, String>{},
      originalFilename: json['originalFilename'],
      fileUrl: json['fileUrl'],
    );
  }
}

/// API client for structured form entries on uploaded documents.
class StructuredEntryService {
  /// HTTP client, overridable in tests (e.g. with `MockClient`).
  static http.Client client = http.Client();

  /// Auth-header provider, overridable in tests to avoid secure storage.
  static Future<Map<String, String>> Function() authHeadersProvider =
      AuthTokenManager.getAuthHeaders;

  /// Fetch the structured entry for a file, or `null` when none exists yet.
  static Future<StructuredEntryDTO?> getEntryForFile(int fileId) async {
    try {
      final headers = await authHeadersProvider();
      final response = await client
          .get(
            Uri.parse('${ApiConstants.files}/$fileId/structured-entry'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return StructuredEntryDTO.fromJson(responseData['data']);
      }
      if (response.statusCode == 404) {
        return null; // No entry yet is not an error
      }
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to load structured entry');
    } catch (e) {
      print('Error loading structured entry: $e');
      return null;
    }
  }

  /// Create a structured entry for [fileId]. Throws with the backend's
  /// validation message on failure so callers can surface it to the user.
  static Future<StructuredEntryDTO> createEntry({
    required int fileId,
    required String documentType,
    required Map<String, String> fields,
    int? patientId,
    int? employeeUserId,
  }) async {
    final headers = await authHeadersProvider();
    headers['Content-Type'] = 'application/json';
    final response = await client
        .post(
          Uri.parse('${ApiConstants.files}/$fileId/structured-entry'),
          headers: headers,
          body: json.encode({
            'documentType': documentType,
            'patientId': patientId,
            'employeeUserId': employeeUserId,
            'fields': fields,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return StructuredEntryDTO.fromJson(responseData['data']);
    }
    final errorData = json.decode(response.body);
    throw Exception(errorData['error'] ?? 'Failed to save structured entry');
  }

  /// Update an existing structured entry. Throws with the backend's
  /// validation message on failure.
  static Future<StructuredEntryDTO> updateEntry({
    required int entryId,
    required String documentType,
    required Map<String, String> fields,
    int? patientId,
    int? employeeUserId,
  }) async {
    final headers = await authHeadersProvider();
    headers['Content-Type'] = 'application/json';
    final response = await client
        .put(
          Uri.parse('${ApiConstants.files}/structured-entries/$entryId'),
          headers: headers,
          body: json.encode({
            'documentType': documentType,
            'patientId': patientId,
            'employeeUserId': employeeUserId,
            'fields': fields,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return StructuredEntryDTO.fromJson(responseData['data']);
    }
    final errorData = json.decode(response.body);
    throw Exception(errorData['error'] ?? 'Failed to update structured entry');
  }

  /// List structured entries linked to a patient (care-circle context).
  static Future<List<StructuredEntryDTO>> listEntriesForPatient(
    int patientId,
  ) async {
    try {
      final headers = await authHeadersProvider();
      final response = await client
          .get(
            Uri.parse(
              '${ApiConstants.files}/structured-entries/patient/$patientId',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> entries = responseData['data'];
        return entries
            .map((json) => StructuredEntryDTO.fromJson(json))
            .toList();
      }
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to list structured entries');
    } catch (e) {
      print('Error listing structured entries: $e');
      return [];
    }
  }
}
