/// Client-side models for the hiring & onboarding digital form schema.
///
/// These mirror the bundled JSON form definitions under `assets/forms/*.form.json`
/// (which are the same definitions the backend serves). They are used to render
/// each form's sections/fields/validation read-only and to surface the
/// version/effective-date metadata and source-document mapping in the UI.
library;

/// Input control / data type for a field. Mirrors backend FieldType.
enum FormFieldType {
  text,
  textarea,
  number,
  currency,
  date,
  email,
  phone,
  ssn,
  ein,
  zip,
  state,
  routingNumber,
  accountNumber,
  checkbox,
  boolean,
  radio,
  select,
  multiselect,
  signature,
  fileRef,
  unknown;

  static FormFieldType from(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'TEXT':
        return FormFieldType.text;
      case 'TEXTAREA':
        return FormFieldType.textarea;
      case 'NUMBER':
        return FormFieldType.number;
      case 'CURRENCY':
        return FormFieldType.currency;
      case 'DATE':
        return FormFieldType.date;
      case 'EMAIL':
        return FormFieldType.email;
      case 'PHONE':
        return FormFieldType.phone;
      case 'SSN':
        return FormFieldType.ssn;
      case 'EIN':
        return FormFieldType.ein;
      case 'ZIP':
        return FormFieldType.zip;
      case 'STATE':
        return FormFieldType.state;
      case 'ROUTING_NUMBER':
        return FormFieldType.routingNumber;
      case 'ACCOUNT_NUMBER':
        return FormFieldType.accountNumber;
      case 'CHECKBOX':
        return FormFieldType.checkbox;
      case 'BOOLEAN':
        return FormFieldType.boolean;
      case 'RADIO':
        return FormFieldType.radio;
      case 'SELECT':
        return FormFieldType.select;
      case 'MULTISELECT':
        return FormFieldType.multiselect;
      case 'SIGNATURE':
        return FormFieldType.signature;
      case 'FILE_REF':
        return FormFieldType.fileRef;
      default:
        return FormFieldType.unknown;
    }
  }

  /// Human-friendly label for the control type (used in the read-only view).
  String get display {
    switch (this) {
      case FormFieldType.textarea:
        return 'Long text';
      case FormFieldType.ssn:
        return 'SSN';
      case FormFieldType.ein:
        return 'EIN';
      case FormFieldType.zip:
        return 'ZIP code';
      case FormFieldType.routingNumber:
        return 'Routing number';
      case FormFieldType.accountNumber:
        return 'Account number';
      case FormFieldType.multiselect:
        return 'Multi-select';
      case FormFieldType.fileRef:
        return 'File attachment';
      default:
        return name[0].toUpperCase() + name.substring(1);
    }
  }
}

/// A single allowed choice for radio/select/multiselect fields.
class FieldOption {
  final String value;
  final String label;
  const FieldOption({required this.value, required this.label});

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        value: (json['value'] ?? '').toString(),
        label: (json['label'] ?? json['value'] ?? '').toString(),
      );
}

/// A declarative validation rule attached to a field.
class ValidationRule {
  final String type;
  final dynamic value;
  final String? pattern;
  final String? message;
  const ValidationRule({required this.type, this.value, this.pattern, this.message});

  factory ValidationRule.fromJson(Map<String, dynamic> json) => ValidationRule(
        type: (json['type'] ?? '').toString().toUpperCase(),
        value: json['value'],
        pattern: json['pattern'] as String?,
        message: json['message'] as String?,
      );

  /// Short human description for the read-only field view.
  String get summary {
    switch (type) {
      case 'REQUIRED':
        return 'required';
      case 'MIN_LENGTH':
        return 'min length $value';
      case 'MAX_LENGTH':
        return 'max length $value';
      case 'MIN':
        return 'min $value';
      case 'MAX':
        return 'max $value';
      case 'PATTERN':
        return 'pattern';
      case 'EMAIL':
        return 'email format';
      case 'SSN':
        return 'SSN format';
      case 'EIN':
        return 'EIN format';
      case 'ROUTING_NUMBER':
        return 'ABA routing checksum';
      case 'ENUM':
        return 'allowed values';
      case 'CHECKED':
        return 'must be checked';
      case 'AGE_MIN':
        return 'min age $value';
      case 'DATE':
      case 'DATE_RANGE':
        return 'valid date';
      default:
        return type.toLowerCase();
    }
  }
}

/// Mapping of a structured field back to its location on the source document.
class SourceMapping {
  final String? documentField;
  final String? section;
  final String? line;
  final int? page;
  const SourceMapping({this.documentField, this.section, this.line, this.page});

  factory SourceMapping.fromJson(Map<String, dynamic> json) => SourceMapping(
        documentField: json['documentField'] as String?,
        section: json['section'] as String?,
        line: json['line'] as String?,
        page: json['page'] as int?,
      );

  /// e.g. "Step 1 · line 1(b) · p.1"
  String get label {
    final parts = <String>[];
    if (section != null && section!.isNotEmpty) parts.add(section!);
    if (line != null && line!.isNotEmpty) parts.add('line $line');
    if (page != null) parts.add('p.$page');
    return parts.join(' · ');
  }
}

/// Simple field dependency: shown only when [fieldId] equals [equalsValue].
class VisibilityCondition {
  final String fieldId;
  final dynamic equalsValue;
  const VisibilityCondition({required this.fieldId, this.equalsValue});

  factory VisibilityCondition.fromJson(Map<String, dynamic> json) =>
      VisibilityCondition(
        fieldId: (json['fieldId'] ?? '').toString(),
        equalsValue: json['equals'],
      );
}

/// A structured field within a section.
class FormFieldDef {
  final String id;
  final String label;
  final FormFieldType fieldType;
  final bool required;
  final int order;
  final String? helpText;
  final bool sensitive;
  final String? completedBy;
  final List<FieldOption> options;
  final List<ValidationRule> validations;
  final SourceMapping? sourceMapping;
  final VisibilityCondition? visibleWhen;

  const FormFieldDef({
    required this.id,
    required this.label,
    required this.fieldType,
    required this.required,
    required this.order,
    this.helpText,
    this.sensitive = false,
    this.completedBy,
    this.options = const [],
    this.validations = const [],
    this.sourceMapping,
    this.visibleWhen,
  });

  factory FormFieldDef.fromJson(Map<String, dynamic> json) => FormFieldDef(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        fieldType: FormFieldType.from(json['fieldType'] as String?),
        required: json['required'] == true,
        order: (json['order'] ?? 0) as int,
        helpText: json['helpText'] as String?,
        sensitive: json['sensitive'] == true,
        completedBy: json['completedBy'] as String?,
        options: (json['options'] as List<dynamic>? ?? [])
            .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        validations: (json['validations'] as List<dynamic>? ?? [])
            .map((v) => ValidationRule.fromJson(v as Map<String, dynamic>))
            .toList(),
        sourceMapping: json['sourceMapping'] != null
            ? SourceMapping.fromJson(json['sourceMapping'] as Map<String, dynamic>)
            : null,
        visibleWhen: json['visibleWhen'] != null
            ? VisibilityCondition.fromJson(json['visibleWhen'] as Map<String, dynamic>)
            : null,
      );
}

/// A logical grouping of fields, mirroring a section/step of the source form.
class FormSectionDef {
  final String id;
  final String title;
  final String? description;
  final int order;
  final bool required;
  final bool repeatable;
  final String? completedBy;
  final List<FormFieldDef> fields;

  const FormSectionDef({
    required this.id,
    required this.title,
    this.description,
    required this.order,
    this.required = true,
    this.repeatable = false,
    this.completedBy,
    this.fields = const [],
  });

  factory FormSectionDef.fromJson(Map<String, dynamic> json) => FormSectionDef(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: json['description'] as String?,
        order: (json['order'] ?? 0) as int,
        required: json['required'] == null ? true : json['required'] == true,
        repeatable: json['repeatable'] == true,
        completedBy: json['completedBy'] as String?,
        fields: (json['fields'] as List<dynamic>? ?? [])
            .map((f) => FormFieldDef.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

/// One complete, versioned form definition (a bundled `*.form.json`).
class FormDefinition {
  final String formType;
  final String title;
  final String? description;
  final String? issuingAuthority;
  final String version;
  final String? effectiveDate;
  final String? expirationDate;
  final String? sourceFormNumber;
  final String? sourceEdition;
  final String fileCategory;
  final List<FormSectionDef> sections;

  const FormDefinition({
    required this.formType,
    required this.title,
    this.description,
    this.issuingAuthority,
    required this.version,
    this.effectiveDate,
    this.expirationDate,
    this.sourceFormNumber,
    this.sourceEdition,
    required this.fileCategory,
    this.sections = const [],
  });

  int get fieldCount =>
      sections.fold(0, (sum, s) => sum + s.fields.length);

  factory FormDefinition.fromJson(Map<String, dynamic> json) {
    final source = json['sourceDocument'] as Map<String, dynamic>?;
    final attach = json['fileAttachment'] as Map<String, dynamic>?;
    return FormDefinition(
      formType: (json['formType'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description'] as String?,
      issuingAuthority: json['issuingAuthority'] as String?,
      version: (json['version'] ?? '').toString(),
      effectiveDate: json['effectiveDate']?.toString(),
      expirationDate: json['expirationDate']?.toString(),
      sourceFormNumber: source != null ? source['formNumber'] as String? : null,
      sourceEdition: source != null ? source['edition'] as String? : null,
      fileCategory:
          (attach != null ? attach['category'] : null)?.toString() ?? 'ONBOARDING_FORM',
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((s) => FormSectionDef.fromJson(s as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}
