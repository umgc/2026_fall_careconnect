// The built-in sample records. #256 stopped showing them on the Health Data
// screen; they remain as fixture data, so they must stay well-formed and must
// never pass for the patient's own Medicare data.

import 'package:care_connect_app/features/health/health_data/mock/sample_health_records.dart';
import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every sample has a unique id, a title, a date and at least one detail', () {
    final ids = sampleHealthRecords.map((r) => r.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    for (final record in sampleHealthRecords) {
      expect(record.title, isNotEmpty);
      expect(record.date, isNotNull);
      expect(record.details, isNotEmpty);
    }
  });

  test('no sample claims to come from Medicare', () {
    for (final record in sampleHealthRecords) {
      expect(record.sources, isNot(contains(RecordSource.medicare)));
    }
  });

  test('each sample has exactly one source', () {
    for (final record in sampleHealthRecords) {
      expect(record.sources, hasLength(1));
    }
  });
}
