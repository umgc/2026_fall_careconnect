import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';

void main() {
  test('TC-HDATA-001: toJson/fromJson round-trips every field of a '
      'multi-source record', () {
    final r = HealthRecord(
      id: 'rec-1',
      sources: const [RecordSource.medicare, RecordSource.cerner],
      type: RecordType.claimService,
      title: 'Office visit',
      date: DateTime.utc(2026, 7, 14),
      details: const [
        RecordDetail('Provider', 'Mercy Internal Medicine Associates'),
        RecordDetail('Amount', r'$185.00'),
      ],
      status: 'Paid',
    );
    final back = HealthRecord.fromJson(r.toJson());
    expect(back.id, 'rec-1');
    expect(back.sources, [RecordSource.medicare, RecordSource.cerner]);
    expect(back.isMultiSource, isTrue);
    expect(back.primarySource, RecordSource.medicare);
    expect(back.type, RecordType.claimService);
    expect(back.title, 'Office visit');
    expect(back.date, DateTime.utc(2026, 7, 14));
    expect(back.details.map((d) => '${d.label}=${d.value}'),
        ['Provider=Mercy Internal Medicine Associates', r'Amount=$185.00']);
    expect(back.status, 'Paid');
    expect(RecordSource.medicare.badge, 'From Medicare');
  });

  test('TC-HDATA-002: a source the app does not know is never shown as '
      'coming from Epic', () {
    final r = HealthRecord.fromJson({
      'id': 'x',
      'sources': ['medicare', 'allscripts'],
      'type': 'claimService',
      'title': 'Claim',
    });
    expect(r.sources, isNot(contains(RecordSource.epic)));
    expect(r.sources, [RecordSource.medicare]);
  });
}
