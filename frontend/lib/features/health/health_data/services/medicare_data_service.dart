import '../../../../services/api_client.dart';
import '../models/health_record.dart';

class MedicareFetchResult {
  final List<HealthRecord> records;
  final bool synthetic;
  const MedicareFetchResult({required this.records, this.synthetic = false});
}

class MedicareDataService {
  Future<MedicareFetchResult> fetchRecords() async {
    final visits = await _getEnvelope('/v1/api/medicare/visits');
    final coverage = await _getEnvelope('/v1/api/medicare/coverage');
    final synthetic =
        (visits?['synthetic'] == true) || (coverage?['synthetic'] == true);
    final records = <HealthRecord>[
      ..._mapVisits(visits),
      ..._mapCoverage(coverage),
    ];
    return MedicareFetchResult(records: records, synthetic: synthetic);
  }

  Future<Map<String, dynamic>?> _getEnvelope(String path) async {
    try {
      return await ApiClient.instance.getJson<Map<String, dynamic>>(
        path,
        parser: (json) =>
            json is Map<String, dynamic> ? json : <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  List<HealthRecord> _mapVisits(Map<String, dynamic>? env) {
    final resources = (env?['resources'] as List?) ?? const [];
    final out = <HealthRecord>[];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      if (r['resourceType'] != 'ExplanationOfBenefit') continue;
      final status = r['status'] as String?;
      if (status != null && status != 'active') continue;
      out.add(_eobToRecord(r));
    }
    return out;
  }

  HealthRecord _eobToRecord(Map<String, dynamic> eob) {
    final id = (eob['id'] ?? '').toString();
    String title = _typeText(eob) ?? 'Medicare claim';
    final items = eob['item'] as List?;
    if (items != null && items.isNotEmpty && items.first is Map) {
      final t = _conceptText((items.first as Map)['productOrService']);
      if (t != null) title = t;
    }
    final date = _parseDate(eob['billablePeriod']?['start'] ?? eob['created']);
    final details = <RecordDetail>[];
    final provider = eob['provider']?['display'];
    if (provider is String) details.add(RecordDetail('Provider', provider));
    final facility = eob['facility']?['display'];
    if (facility is String) details.add(RecordDetail('Facility', facility));
    final dx = _firstDiagnosisText(eob);
    if (dx != null) details.add(RecordDetail('Diagnosis', dx));
    final submitted = _totalSubmitted(eob);
    if (submitted != null) details.add(RecordDetail('Amount', submitted));
    final paid = _money(eob['payment']?['amount']);
    if (paid != null) details.add(RecordDetail('Medicare paid', paid));
    final svc = eob['billablePeriod']?['start'];
    if (svc is String) details.add(RecordDetail('Service date', _friendlyDate(svc)));
    return HealthRecord.single(
      id: id,
      source: RecordSource.medicare,
      type: RecordType.claimService,
      title: title,
      date: date,
      details: details,
      status: eob['payment']?['amount']?['value'] != null ? 'Paid' : 'Processed',
    );
  }

  List<HealthRecord> _mapCoverage(Map<String, dynamic>? env) {
    final resources = (env?['resources'] as List?) ?? const [];
    final out = <HealthRecord>[];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      if (r['resourceType'] != 'Coverage') continue;
      final id = (r['id'] ?? 'coverage').toString();
      final details = <RecordDetail>[];
      final payorList = r['payor'] as List?;
      final payor = (payorList != null && payorList.isNotEmpty)
          ? (payorList.first['display'] ?? 'Medicare')
          : 'Medicare';
      if (payor is String) details.add(RecordDetail('Payer', payor));
      final start = r['period']?['start'];
      if (start is String) details.add(RecordDetail('Effective', _friendlyDate(start)));
      final klass = (r['class'] as List?)
          ?.map((c) => c is Map ? _conceptText(c['type']) : null)
          .whereType<String>()
          .join(', ');
      if (klass != null && klass.isNotEmpty) details.add(RecordDetail('Plan', klass));
      out.add(HealthRecord.single(
        id: id,
        source: RecordSource.medicare,
        type: RecordType.other,
        title: _conceptText(r['type']) ?? 'Medicare coverage',
        details: details,
        status: (r['status'] as String?) == 'active' ? 'Active' : null,
      ));
    }
    return out;
  }

  String? _typeText(Map<String, dynamic> r) {
    final t = r['type'];
    return t is Map<String, dynamic> ? t['text'] as String? : null;
  }

  String? _conceptText(dynamic c) {
    if (c is Map<String, dynamic>) {
      final text = c['text'];
      if (text is String) return text;
      final coding = c['coding'];
      if (coding is List && coding.isNotEmpty && coding.first is Map) {
        return coding.first['display'] as String?;
      }
    }
    return null;
  }

  String? _firstDiagnosisText(Map<String, dynamic> eob) {
    final dx = eob['diagnosis'];
    if (dx is List && dx.isNotEmpty && dx.first is Map) {
      return _conceptText((dx.first as Map)['diagnosisCodeableConcept']);
    }
    return null;
  }

  String? _totalSubmitted(Map<String, dynamic> eob) {
    final totals = eob['total'];
    if (totals is List) {
      for (final t in totals) {
        if (t is Map && _catCode(t['category']) == 'submitted') {
          return _money(t['amount']);
        }
      }
    }
    return null;
  }

  String? _catCode(dynamic category) {
    if (category is Map) {
      final coding = category['coding'];
      if (coding is List && coding.isNotEmpty && coding.first is Map) {
        return coding.first['code'] as String?;
      }
    }
    return null;
  }

  String? _money(dynamic amount) {
    if (amount is Map && amount['value'] != null) {
      final v = amount['value'];
      final num? n = v is num ? v : num.tryParse(v.toString());
      if (n != null) return '\$${n.toStringAsFixed(2)}';
    }
    return null;
  }

  DateTime? _parseDate(dynamic s) => s is String ? DateTime.tryParse(s) : null;

  String _friendlyDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}