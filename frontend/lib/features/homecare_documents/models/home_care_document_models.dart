// Models for Home Care Document Digitization (OCR + LLM prefill).

/// Statuses returned by the backend extraction endpoint.
class HomeCareExtractionStatus {
  static const String prefilled = 'PREFILLED';
  static const String manualEntryRequired = 'MANUAL_ENTRY_REQUIRED';
}

/// One allowed field in a document type's schema.
class HomeCareFieldSpec {
  final String key;
  final String label;

  const HomeCareFieldSpec({required this.key, required this.label});

  factory HomeCareFieldSpec.fromJson(Map<String, dynamic> json) {
    return HomeCareFieldSpec(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

/// A digitizable home-care document type and its field schema.
class HomeCareDocumentTypeInfo {
  final String type;
  final String displayName;
  final List<HomeCareFieldSpec> fields;

  const HomeCareDocumentTypeInfo({
    required this.type,
    required this.displayName,
    required this.fields,
  });

  factory HomeCareDocumentTypeInfo.fromJson(Map<String, dynamic> json) {
    final fieldsList = (json['fields'] as List?) ?? const [];
    return HomeCareDocumentTypeInfo(
      type: json['type'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      fields: fieldsList
          .map((e) => HomeCareFieldSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single structured field, possibly prefilled by the OCR + LLM pipeline.
class HomeCareExtractedField {
  final String key;
  final String label;
  final String value;

  /// True when the value was prefilled by AI rather than typed by a person.
  final bool machineGenerated;
  final bool editable;

  const HomeCareExtractedField({
    required this.key,
    required this.label,
    required this.value,
    required this.machineGenerated,
    this.editable = true,
  });

  factory HomeCareExtractedField.fromJson(Map<String, dynamic> json) {
    return HomeCareExtractedField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '',
      machineGenerated: json['machineGenerated'] == true,
      editable: json['editable'] != false,
    );
  }
}

/// Extraction result for one uploaded document: either AI-prefilled draft
/// fields, or an empty schema when the pipeline fell back to manual entry.
class HomeCareExtractionResult {
  final String documentType;
  final String documentTypeDisplayName;
  final String status;
  final String? message;
  final String? documentLink;
  final List<HomeCareExtractedField> fields;

  const HomeCareExtractionResult({
    required this.documentType,
    required this.documentTypeDisplayName,
    required this.status,
    this.message,
    this.documentLink,
    required this.fields,
  });

  bool get manualEntryRequired =>
      status == HomeCareExtractionStatus.manualEntryRequired;

  factory HomeCareExtractionResult.fromJson(Map<String, dynamic> json) {
    final fieldsList = (json['fields'] as List?) ?? const [];
    return HomeCareExtractionResult(
      documentType: json['documentType'] as String? ?? '',
      documentTypeDisplayName: json['documentTypeDisplayName'] as String? ?? '',
      status:
          json['status'] as String? ?? HomeCareExtractionStatus.manualEntryRequired,
      message: json['message'] as String?,
      documentLink: json['documentLink'] as String?,
      fields: fieldsList
          .map((e) => HomeCareExtractedField.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Clean local fallback to manual entry when the backend is unreachable or
  /// extraction failed client-side: full schema, all fields blank and human.
  factory HomeCareExtractionResult.manualFallback(
    HomeCareDocumentTypeInfo type, {
    String? message,
  }) {
    return HomeCareExtractionResult(
      documentType: type.type,
      documentTypeDisplayName: type.displayName,
      status: HomeCareExtractionStatus.manualEntryRequired,
      message: message,
      fields: type.fields
          .map(
            (f) => HomeCareExtractedField(
              key: f.key,
              label: f.label,
              value: '',
              machineGenerated: false,
            ),
          )
          .toList(),
    );
  }
}

/// Local mirror of the backend document-type schemas, used when the /types
/// endpoint is unavailable so manual entry still works.
const List<HomeCareDocumentTypeInfo> defaultHomeCareDocumentTypes = [
  HomeCareDocumentTypeInfo(
    type: 'EMPLOYMENT_APPLICATION',
    displayName: 'Employment Application',
    fields: [
      HomeCareFieldSpec(key: 'fullName', label: 'Full Name'),
      HomeCareFieldSpec(key: 'phone', label: 'Phone Number'),
      HomeCareFieldSpec(key: 'email', label: 'Email Address'),
      HomeCareFieldSpec(key: 'address', label: 'Home Address'),
      HomeCareFieldSpec(key: 'positionAppliedFor', label: 'Position Applied For'),
      HomeCareFieldSpec(key: 'desiredStartDate', label: 'Desired Start Date'),
      HomeCareFieldSpec(key: 'previousEmployer', label: 'Most Recent Employer'),
      HomeCareFieldSpec(key: 'yearsOfExperience', label: 'Years of Experience'),
    ],
  ),
  HomeCareDocumentTypeInfo(
    type: 'CERTIFICATION',
    displayName: 'Certification / License',
    fields: [
      HomeCareFieldSpec(key: 'holderName', label: 'Certificate Holder Name'),
      HomeCareFieldSpec(
          key: 'certificationType', label: 'Certification / License Type'),
      HomeCareFieldSpec(
          key: 'certificationNumber', label: 'Certification / License Number'),
      HomeCareFieldSpec(
          key: 'issuingOrganization', label: 'Issuing Organization or State'),
      HomeCareFieldSpec(key: 'issueDate', label: 'Issue Date'),
      HomeCareFieldSpec(key: 'expirationDate', label: 'Expiration Date'),
    ],
  ),
  HomeCareDocumentTypeInfo(
    type: 'TAX_FORM',
    displayName: 'Tax Form (W-4)',
    fields: [
      HomeCareFieldSpec(key: 'employeeName', label: 'Employee Name'),
      HomeCareFieldSpec(key: 'address', label: 'Home Address'),
      HomeCareFieldSpec(key: 'filingStatus', label: 'Filing Status'),
      HomeCareFieldSpec(
          key: 'multipleJobs', label: 'Multiple Jobs or Spouse Works'),
      HomeCareFieldSpec(
          key: 'dependentsAmount', label: 'Claimed Dependents Amount'),
      HomeCareFieldSpec(key: 'otherIncome', label: 'Other Income'),
      HomeCareFieldSpec(key: 'extraWithholding', label: 'Extra Withholding'),
    ],
  ),
  HomeCareDocumentTypeInfo(
    type: 'WORK_AUTHORIZATION',
    displayName: 'Work Authorization (I-9)',
    fields: [
      HomeCareFieldSpec(key: 'employeeName', label: 'Employee Name'),
      HomeCareFieldSpec(key: 'dateOfBirth', label: 'Date of Birth'),
      HomeCareFieldSpec(
          key: 'citizenshipStatus', label: 'Citizenship / Immigration Status'),
      HomeCareFieldSpec(key: 'documentTitle', label: 'Document Title'),
      HomeCareFieldSpec(key: 'documentNumber', label: 'Document Number'),
      HomeCareFieldSpec(
          key: 'documentExpiration', label: 'Document Expiration Date'),
    ],
  ),
];
