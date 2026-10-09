import '../models/health_record.dart';
final List<HealthRecord> sampleHealthRecords = [
  HealthRecord.single(
    id: 'cerner-appt-1',
    source: RecordSource.cerner,
    type: RecordType.appointment,
    title: 'Primary Care Follow-Up',
    date: DateTime(2026, 9, 15),
    details: const [
      RecordDetail('Time', '10:30 AM'),
      RecordDetail('Provider', 'Dr. Sarah Mitchell'),
    ],
  ),
  HealthRecord.single(
    id: 'athena-visit-1',
    source: RecordSource.athena,
    type: RecordType.clinicalRecord,
    title: 'Annual Wellness Visit',
    date: DateTime(2026, 8, 22),
    details: const [
      RecordDetail('Provider', 'Dr. James Carter'),
    ],
  ),
];
