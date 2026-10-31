// showRecordConflictDialog: each kind of flagged record, what each answer
// returns, and the provenance and changed-field marks on each version.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/record_reconciler.dart';
import 'package:care_connect_app/features/health/health_data/widgets/record_conflict_dialog.dart';

HealthRecord _rec(
  String id,
  RecordSource source, {
  RecordType type = RecordType.condition,
  String? status = 'active',
  DateTime? date,
  List<RecordDetail> details = const [],
}) =>
    HealthRecord.single(
        id: id,
        source: source,
        type: type,
        title: 'Type 2 diabetes',
        status: status,
        date: date ?? DateTime.utc(2026, 7, 1),
        details: details);

RecordConflict _conflict(RecordConflictKind kind, List<HealthRecord> versions) =>
    RecordConflict(key: 'k', versions: versions, kind: kind);

final _differs = _conflict(RecordConflictKind.differs, [
  _rec('epic-1', RecordSource.epic,
      details: const [RecordDetail('Retrieved', 'Oct 14, 2026')]),
  _rec('ath-1', RecordSource.athena,
      status: 'resolved',
      details: const [RecordDetail('Category', 'Conditions')]),
]);

/// Opens the dialog from a button and returns a holder for its result.
Future<List<RecordConflictDecision?>> _open(
    WidgetTester t, RecordConflict c, {int index = 1, int total = 1}) async {
  final result = <RecordConflictDecision?>[];
  await t.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => result.add(await showRecordConflictDialog(
              context, c,
              index: index, total: total)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('differs: "Which is correct?", one Use button per version, '
      'and each version names its source and when it was retrieved', (t) async {
    final result = await _open(t, _differs, index: 2, total: 3);
    expect(find.text('Which is correct? (2 of 3)'), findsOneWidget);
    expect(find.textContaining('Choose the version that\'s correct'),
        findsOneWidget);
    expect(find.text('From Epic, updated Oct 14, 2026'), findsOneWidget);
    expect(find.text('From athenahealth'), findsOneWidget);
    expect(find.text('Use version 1'), findsOneWidget);
    expect(find.text('Same record'), findsNothing);
    // Retrieved is provenance, not a compared field.
    expect(find.text('Retrieved'), findsNothing);
    expect(find.text('Category'), findsNWidgets(2));
    // The athena-only Category is blank on Epic's version.
    expect(find.text('—'), findsOneWidget);

    await t.tap(find.text('Use version 2'));
    await t.pumpAndSettle();
    expect(result.single!.keepBoth, isFalse);
    expect(result.single!.chosen!.id, 'ath-1');
  });

  testWidgets('differs: only the fields that differ are marked, for colour '
      'and for screen readers', (t) async {
    final semantics = t.ensureSemantics();
    await _open(t, _differs);
    // Status and Category differ on each version (2 x 2); Record and Date don't.
    expect(find.bySemanticsLabel('Different'), findsNWidgets(4));
    semantics.dispose();
  });

  testWidgets('Keep both and Decide later', (t) async {
    var result = await _open(t, _differs);
    await t.tap(find.text('Keep both'));
    await t.pumpAndSettle();
    expect(result.single!.keepBoth, isTrue);
    expect(result.single!.chosen, isNull);

    result = await _open(t, _differs);
    await t.tap(find.text('Decide later'));
    await t.pumpAndSettle();
    expect(result, [null]);
  });

  testWidgets('tapping outside the dialog is Decide later', (t) async {
    final result = await _open(t, _differs);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(result, [null]);
  });

  testWidgets('possible duplicate: Same record keeps the preferred version',
      (t) async {
    final result = await _open(
        t,
        _conflict(RecordConflictKind.possibleDuplicate, [
          _rec('epic-1', RecordSource.epic),
          _rec('ath-1', RecordSource.athena),
        ]));
    expect(find.text('Is this the same record?'), findsOneWidget);
    expect(find.textContaining('Use version'), findsNothing);
    expect(find.bySemanticsLabel('Different'), findsNothing);
    await t.tap(find.text('Same record'));
    await t.pumpAndSettle();
    expect(result.single!.chosen!.id, 'epic-1');
  });

  testWidgets('a version without a date or status shows a dash', (t) async {
    await _open(
        t,
        _conflict(RecordConflictKind.differs, [
          _rec('epic-1', RecordSource.epic, date: DateTime.utc(2026, 12, 3)),
          HealthRecord.single(
              id: 'ath-1',
              source: RecordSource.athena,
              type: RecordType.condition,
              title: 'Type 2 diabetes'),
        ]));
    expect(find.text('Dec 3, 2026'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });
}
