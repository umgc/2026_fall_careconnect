// RecordChoiceStore: the patient's decisions on flagged records and the
// decision log, kept on the device in SharedPreferences.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/record_choice_store.dart';
import 'package:care_connect_app/features/health/health_data/services/record_reconciler.dart';

const _choicesKey = 'health_data.record_choices';
const _logKey = 'health_data.record_decision_log';

HealthRecord _rec(String id, RecordSource source, String status) =>
    HealthRecord.single(
        id: id,
        source: source,
        type: RecordType.condition,
        title: 'Asthma',
        status: status,
        date: DateTime.utc(2026, 7, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('choices', () {
    test('nothing stored loads as no choices', () async {
      expect(await RecordChoiceStore().load(), isEmpty);
    });

    test('a saved choice loads back, and saving another keeps the first',
        () async {
      final store = RecordChoiceStore();
      await store.save('k1', 'fp1#epic:e1');
      await store.save('k2', 'fp2#*keep-both*');
      await store.save('k1', 'fp1#athena:a1');
      expect(await store.load(), {'k1': 'fp1#athena:a1', 'k2': 'fp2#*keep-both*'});
    });

    test('damaged or unexpected stored data loads as no choices', () async {
      for (final raw in ['{not json', '["a list"]', '"text"']) {
        SharedPreferences.setMockInitialValues({_choicesKey: raw});
        expect(await RecordChoiceStore().load(), isEmpty, reason: raw);
      }
    });

    test('values that are not strings are read as text', () async {
      SharedPreferences.setMockInitialValues(
          {_choicesKey: jsonEncode({'k': 7})});
      expect(await RecordChoiceStore().load(), {'k': '7'});
    });
  });

  group('decision log', () {
    test('every decision is kept, oldest first, ids only', () async {
      final store = RecordChoiceStore();
      final at = DateTime.utc(2026, 10, 20, 9);
      await store.logDecision(RecordDecisionEntry(
          at: at, decision: 'deferred', versions: const ['epic:e1', 'athena:a1']));
      await store.logDecision(RecordDecisionEntry(
          at: at.add(const Duration(minutes: 1)),
          decision: 'confirmed',
          versions: const ['epic:e1', 'athena:a1'],
          chosen: 'athena:a1'));
      final log = await store.decisionLog();
      expect(log.map((e) => e.decision), ['deferred', 'confirmed']);
      expect(log.first.chosen, isNull);
      expect(log.last.chosen, 'athena:a1');
      expect(log.last.versions, ['epic:e1', 'athena:a1']);
      expect(log.last.at, at.add(const Duration(minutes: 1)));

      final stored = jsonDecode(
          (await SharedPreferences.getInstance()).getString(_logKey)!) as List;
      expect(stored.first, {
        'at': '2026-10-20T09:00:00.000Z',
        'decision': 'deferred',
        'versions': ['epic:e1', 'athena:a1'],
      });
    });

    test('a local time is stored as UTC', () {
      final local = DateTime(2026, 10, 20, 9);
      expect(
          RecordDecisionEntry(at: local, decision: 'deferred', versions: const [])
              .toJson()['at'],
          local.toUtc().toIso8601String());
    });

    test('past ${RecordChoiceStore.maxLogEntries} entries the oldest are dropped',
        () async {
      final base = DateTime.utc(2026, 1, 1);
      SharedPreferences.setMockInitialValues({
        _logKey: jsonEncode([
          for (var i = 0; i < RecordChoiceStore.maxLogEntries; i++)
            RecordDecisionEntry(
                    at: base.add(Duration(minutes: i)),
                    decision: 'deferred',
                    versions: ['epic:$i'])
                .toJson(),
        ]),
      });
      final store = RecordChoiceStore();
      await store.logDecision(RecordDecisionEntry(
          at: base.add(const Duration(days: 1)),
          decision: 'keep_both',
          versions: const ['epic:new']));
      final log = await store.decisionLog();
      expect(log, hasLength(RecordChoiceStore.maxLogEntries));
      expect(log.first.versions, ['epic:1']);
      expect(log.last.decision, 'keep_both');
    });

    test('damaged entries are skipped; a damaged log reads as empty', () async {
      SharedPreferences.setMockInitialValues({
        _logKey: jsonEncode([
          'text',
          {'at': 'never', 'decision': 'deferred'},
          {'at': '2026-10-20T09:00:00Z', 'decision': null, 'versions': null},
        ]),
      });
      final log = await RecordChoiceStore().decisionLog();
      expect(log, hasLength(1));
      expect(log.single.decision, '');
      expect(log.single.versions, isEmpty);

      for (final raw in ['[broken', '{"a":1}']) {
        SharedPreferences.setMockInitialValues({_logKey: raw});
        expect(await RecordChoiceStore().decisionLog(), isEmpty, reason: raw);
      }
      expect(RecordDecisionEntry.fromJson('text'), isNull);
    });

    test('a damaged log does not stop a new decision being logged', () async {
      SharedPreferences.setMockInitialValues({_logKey: '[broken'});
      final store = RecordChoiceStore();
      await store.logDecision(RecordDecisionEntry(
          at: DateTime.utc(2026, 10, 20), decision: 'deferred', versions: const []));
      expect(await store.decisionLog(), hasLength(1));
    });
  });

  test('negative: a choice stored by one patient on this device does not '
      'resolve another patient\'s record with the same name and day', () async {
    // The store is per device, not per account (logout does not clear it).
    // A choice is bound to the versions' source:id pairs, so it must not
    // apply to a second patient's records.
    final store = RecordChoiceStore();
    final first = [
      _rec('epic-A', RecordSource.epic, 'active'),
      _rec('ath-A', RecordSource.athena, 'resolved'),
    ];
    final c = RecordReconciler.reconcile(first).unresolved.single;
    await store.save(c.storageKey, RecordReconciler.encodeKeepBoth(c));

    final second = [
      _rec('epic-B', RecordSource.epic, 'active'),
      _rec('ath-B', RecordSource.athena, 'resolved'),
    ];
    final r = RecordReconciler.reconcile(second, choices: await store.load());
    expect(r.unresolved, hasLength(1));
    expect(r.records.map((x) => x.id), ['epic-B']);
  });

  // Review follow-up: save() and logDecision() read, change, then write, with
  // awaits in between, so two calls that overlap could lose one write.
  group('overlapping writes', () {
    test('saves that overlap all keep their choice', () async {
      final store = RecordChoiceStore();
      await Future.wait([
        for (var i = 0; i < 5; i++) store.save('k$i', 'fp$i#epic:e$i'),
      ]);
      expect(await store.load(), {
        for (var i = 0; i < 5; i++) 'k$i': 'fp$i#epic:e$i',
      });
    });

    test('decisions logged at the same time are all kept, in call order',
        () async {
      final store = RecordChoiceStore();
      final at = DateTime.utc(2026, 10, 21);
      await Future.wait([
        for (var i = 0; i < 5; i++)
          store.logDecision(RecordDecisionEntry(
              at: at, decision: 'deferred', versions: ['epic:$i'])),
      ]);
      expect((await store.decisionLog()).map((e) => e.versions.single),
          ['epic:0', 'epic:1', 'epic:2', 'epic:3', 'epic:4']);
    });

    test('a write that fails does not stop the ones after it', () async {
      final store = RecordChoiceStore();
      SharedPreferences.setMockInitialValues({_choicesKey: '{broken'});
      await Future.wait([store.save('a', '1'), store.save('b', '2')]);
      expect(await store.load(), {'a': '1', 'b': '2'});
    });
  });
}
