import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/health_record.dart';

/// Why a record needs the patient's attention.
enum RecordConflictKind {
  /// Two providers reported the same record with the same details. It is
  /// shown once (the preferred source's version) and flagged so the patient
  /// can confirm it is one record or keep both: never merged silently
  /// (WBS 6.2.41, "without silent data loss").
  possibleDuplicate,

  /// Two providers reported the same record with different details. The
  /// patient confirms one version, keeps both, or decides later.
  differs,
}

/// Records from several providers that look like the same record.
class RecordConflict {
  /// Stable for the same record across loads (type + FHIR resource type +
  /// title, plus the day for one-off events), so a decision can be
  /// remembered.
  final String key;

  /// One version per source, preferred source first.
  final List<HealthRecord> versions;

  final RecordConflictKind kind;

  const RecordConflict(
      {required this.key, required this.versions, required this.kind});

  /// Changes when any version changes, so a remembered decision no longer
  /// applies and the record is flagged again.
  String get fingerprint =>
      versions.map(versionId).join('|') +
      versions.map((v) => '${_norm(v.status)}@${_day(v.date)}').join('|');

  /// [key] hashed, for storing decisions on the device without the
  /// record's title.
  String get storageKey => _hash(key);

  /// Identifies one version within this conflict. Includes the FHIR resource
  /// type, since a source's ids are only unique within one resource type.
  static String versionId(HealthRecord r) =>
      '${r.primarySource.name}:${r.resourceType ?? ''}/${r.id}';
}

class ReconciledRecords {
  /// Every record to show: duplicates combined, conflicts showing the
  /// chosen or default version, medication conflicts showing every version.
  final List<HealthRecord> records;

  /// Records still waiting for a decision.
  final List<RecordConflict> unresolved;

  const ReconciledRecords({required this.records, required this.unresolved});
}

/// Finds the same record reported by different sources.
///
/// Records match when they have the same type, FHIR resource type and title
/// (ignoring case and punctuation) and, for one-off events (visits, results,
/// claims), the same day. An Observation and a DiagnosticReport are never the
/// same record, however alike they look. Conditions, medications and allergies match on title alone, since a
/// source may date them differently. Records from the same source are never
/// matched with each other, and an ambiguous match (one source has several)
/// is left alone.
///
/// Nothing is ever deleted: every source's record stays stored, and a
/// decision only changes which version Health Data shows.
class RecordReconciler {
  const RecordReconciler._();

  /// Preferred source first. Epic is the default version.
  static const sourcePriority = [
    RecordSource.epic,
    RecordSource.athena,
    RecordSource.cerner,
    RecordSource.medicare,
  ];

  static ReconciledRecords reconcile(
    List<HealthRecord> records, {
    Map<String, String> choices = const {},
  }) {
    final groups = <String, List<HealthRecord>>{};
    for (final r in records) {
      groups.putIfAbsent(matchKey(r), () => []).add(r);
    }

    final out = <HealthRecord>[];
    final unresolved = <RecordConflict>[];
    for (final entry in groups.entries) {
      final group = entry.value;
      final bySource = <RecordSource, List<HealthRecord>>{};
      for (final r in group) {
        bySource.putIfAbsent(r.primarySource, () => []).add(r);
      }
      if (bySource.length < 2 || bySource.values.any((l) => l.length > 1)) {
        out.addAll(group);
        continue;
      }

      final versions = [...group]..sort(
          (a, b) => _rank(a.primarySource).compareTo(_rank(b.primarySource)));
      final sources = versions.map((v) => v.primarySource).toList();
      final preferred = versions.first;
      final same = versions.every((v) => _sameDetails(v, preferred));
      // A medication whose providers disagree is never overwritten
      // (FR-EHR-07): every version stays shown. It isn't flagged either, as
      // the caregiver review FR-EHR-07 asks for doesn't exist yet.
      if (!same && preferred.type == RecordType.medication) {
        out.addAll(versions);
        continue;
      }
      final kind = same
          ? RecordConflictKind.possibleDuplicate
          : RecordConflictKind.differs;
      final conflict =
          RecordConflict(key: entry.key, versions: versions, kind: kind);

      final stored = choices[conflict.storageKey];
      if (_keptBoth(conflict, stored)) {
        out.addAll(versions);
        continue;
      }
      final choice = _chosen(conflict, stored);
      if (choice == null) unresolved.add(conflict);
      // The shown version's own source stays first (primarySource), so its
      // full record is still the one that opens; the others follow.
      final shown = choice ?? preferred;
      out.add(shown.copyWith(sources: [
        shown.primarySource,
        ...sources.where((s) => s != shown.primarySource),
      ]));
    }
    return ReconciledRecords(records: out, unresolved: unresolved);
  }

  /// A stored decision is `fingerprint#versionId`, or `fingerprint#` plus
  /// the keep-both marker; it applies only while the versions are unchanged.
  static String encodeChoice(RecordConflict c, HealthRecord chosen) =>
      '${_hash(c.fingerprint)}#${RecordConflict.versionId(chosen)}';

  /// The patient said the versions are different records: show each.
  static String encodeKeepBoth(RecordConflict c) =>
      '${_hash(c.fingerprint)}#$_keepBoth';

  static const _keepBoth = '*keep-both*';

  static bool _keptBoth(RecordConflict c, String? stored) =>
      stored == encodeKeepBoth(c);

  static HealthRecord? _chosen(RecordConflict c, String? stored) {
    if (stored == null) return null;
    final i = stored.lastIndexOf('#');
    if (i < 0 || stored.substring(0, i) != _hash(c.fingerprint)) return null;
    final id = stored.substring(i + 1);
    for (final v in c.versions) {
      if (RecordConflict.versionId(v) == id) return v;
    }
    return null;
  }

  static String matchKey(HealthRecord r) {
    final title = _norm(r.title);
    final kind = '${r.type.name}|${r.resourceType ?? ''}';
    switch (r.type) {
      case RecordType.condition:
      case RecordType.medication:
      case RecordType.allergy:
        return '$kind|$title';
      case RecordType.appointment:
      case RecordType.clinicalRecord:
      case RecordType.claimService:
      case RecordType.other:
        return '$kind|$title|${_day(r.date)}';
    }
  }

  static bool _sameDetails(HealthRecord a, HealthRecord b) =>
      _norm(a.status) == _norm(b.status) && _day(a.date) == _day(b.date);

  static int _rank(RecordSource s) {
    final i = sourcePriority.indexOf(s);
    return i < 0 ? sourcePriority.length : i;
  }
}

String _norm(String? s) =>
    (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

String _day(DateTime? d) {
  if (d == null) return '';
  return '${d.year}-${d.month}-${d.day}';
}
