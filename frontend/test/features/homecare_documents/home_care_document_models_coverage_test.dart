import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('homeCareDocumentTypeToFileCategory maps types', () {
    expect(homeCareDocumentTypeToFileCategory('tax_form'), 'ONBOARDING_FORM');
    expect(
      homeCareDocumentTypeToFileCategory('WORK_AUTHORIZATION'),
      'ONBOARDING_FORM',
    );
    expect(
      homeCareDocumentTypeToFileCategory('EMPLOYMENT_APPLICATION'),
      'HIRING_DOCUMENT',
    );
  });

  test('HomeCareDocumentTypeInfo.fromJson parses field specs', () {
    final info = HomeCareDocumentTypeInfo.fromJson({
      'type': 'TAX_FORM',
      'displayName': 'Tax Form',
      'fields': [
        {'key': 'ssn', 'label': 'SSN'},
        <String, dynamic>{},
      ],
    });
    expect(info.type, 'TAX_FORM');
    expect(info.displayName, 'Tax Form');
    expect(info.fields, hasLength(2));
    expect(info.fields.first.key, 'ssn');
    expect(info.fields.first.label, 'SSN');
    expect(info.fields.last.key, '');

    final empty = HomeCareDocumentTypeInfo.fromJson(<String, dynamic>{});
    expect(empty.type, '');
    expect(empty.fields, isEmpty);
  });
}
