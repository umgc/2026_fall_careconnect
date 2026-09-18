import 'package:flutter/material.dart';
import '../models/health_record.dart';

class HealthDataScreen extends StatelessWidget {
  const HealthDataScreen({super.key});

  static const _teal = Color(0xFF00A7C8);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  List<HealthRecord> get _sample => [
        HealthRecord.single(
          id: 'epic-med-1',
          source: RecordSource.epic,
          type: RecordType.medication,
          title: 'Lisinopril 10 mg',
          status: 'Active',
          details: const [
            RecordDetail('Route', 'Oral'),
            RecordDetail('Prescriber', 'Dr. Sarah Mitchell'),
          ],
        ),
        HealthRecord.single(
          id: 'epic-cond-1',
          source: RecordSource.epic,
          type: RecordType.condition,
          title: 'Hypertension',
          status: 'Active',
          date: DateTime(2021, 3, 15),
          details: const [RecordDetail('Diagnosed', 'Mar 15, 2021')],
        ),
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
          details: const [RecordDetail('Provider', 'Dr. James Carter')],
        ),
        HealthRecord.single(
          id: 'medicare-eob-1',
          source: RecordSource.medicare,
          type: RecordType.claimService,
          title: 'Primary Care Office Visit',
          status: 'Processed',
          date: DateTime(2026, 3, 12),
          details: const [
            RecordDetail('Provider', 'Dr. Rivera, Internal Medicine'),
            RecordDetail('Amount', '\$120.00'),
            RecordDetail('Claim #', 'MC-2026-0312'),
          ],
        ),
        const HealthRecord(
          id: 'multi-appt-1',
          sources: [RecordSource.epic, RecordSource.cerner],
          type: RecordType.appointment,
          title: 'Primary Care Follow-Up',
          details: [RecordDetail('Provider', 'Dr. Sarah Mitchell')],
          status: 'Scheduled',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final records = _sample;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text('Health Data',
            style: TextStyle(
                color: _text, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('View your health information from connected sources.',
              style: TextStyle(color: _muted)),
          const SizedBox(height: 16),
          ...records.map(_recordCard),
        ],
      ),
    );
  }

  Widget _recordCard(HealthRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r.type.label.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (r.status != null) _statusChip(r.status!),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _text)),
          const SizedBox(height: 8),
          ...r.details.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, color: _text),
                    children: [
                      TextSpan(
                          text: '${d.label}: ',
                          style: const TextStyle(color: _muted)),
                      TextSpan(text: d.value),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
          _sourceBadges(r),
        ],
      ),
    );
  }

  Widget _sourceBadges(HealthRecord r) {
    return Wrap(
      children: [
        if (r.isMultiSource)
          Container(
            margin: const EdgeInsets.only(right: 6, bottom: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Found in ${r.sources.length} sources',
                style: const TextStyle(
                    fontSize: 12,
                    color: _teal,
                    fontWeight: FontWeight.w600)),
          ),
        ...r.sources.map((s) => Container(
              margin: const EdgeInsets.only(right: 6, bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              child: Text(s.badge,
                  style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
            )),
      ],
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status,
          style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF10B981),
              fontWeight: FontWeight.w600)),
    );
  }
}
