// DOB confirmation (identity reconciliation UI). Backend vocabulary:
// EhrConflictStatus PENDING / ACCEPTED / REJECTED, PENDING only for
// date_of_birth (ck_ehr_identity_conflict_pending_dob).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';

import 'package:care_connect_app/features/health/health_data/models/identity_conflict.dart';
import 'package:care_connect_app/features/health/health_data/pages/dob_confirmation_screen.dart';
import 'package:care_connect_app/features/health/health_data/services/identity_conflict_service.dart';

import '../health_data_test_support.dart';

IdentityConflict _dob(int id,
        {String before = '1980-05-14',
        String incoming = '1985-05-14',
        ConflictStatus status = ConflictStatus.pending}) =>
    IdentityConflict(
      id: id,
      fieldName: 'date_of_birth',
      canonicalValueBefore: before,
      incomingValue: incoming,
      canonicalSourceLabel: 'Epic',
      incomingSourceLabel: 'Cerner',
      status: status,
    );

class _FakeConflicts extends IdentityConflictService {
  _FakeConflicts(this.pending,
      {this.resolveResult = true, this.throwOnResolve, this.throwOnFetch})
      : super(useMock: false);

  final List<IdentityConflict> pending;
  final Object? throwOnFetch;
  final bool resolveResult;
  final Object? throwOnResolve;
  final resolved = <String>[];

  @override
  Future<List<IdentityConflict>> fetchPending() async {
    if (throwOnFetch != null) throw throwOnFetch!;
    return pending;
  }

  @override
  Future<bool> resolve(int conflictId, {required bool accepted}) async {
    resolved.add('$conflictId:${accepted ? 'ACCEPTED' : 'REJECTED'}');
    if (throwOnResolve != null) throw throwOnResolve!;
    return resolveResult;
  }
}

Future<void> _pump(WidgetTester t, IdentityConflictService s) async {
  await t.pumpWidget(MaterialApp(home: DobConfirmationScreen(service: s)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('TC-EHR-REC-032: only pending date-of-birth conflicts are '
      'listed, each with current and new values and their sources',
      (t) async {
    await _pump(
        t,
        _FakeConflicts([
          _dob(1),
          _dob(2, status: ConflictStatus.rejected, incoming: '1990-01-01'),
          const IdentityConflict(
              id: 3,
              fieldName: 'gender',
              canonicalValueBefore: 'female',
              incomingValue: 'unknown'),
        ]));
    expect(find.text('1 item needs your confirmation'), findsOneWidget);
    expect(find.text('Which date of birth is correct?'), findsOneWidget);
    expect(find.text('1980-05-14'), findsOneWidget);
    expect(find.text('1985-05-14'), findsOneWidget);
    expect(find.text('From Epic'), findsOneWidget);
    expect(find.text('From Cerner'), findsOneWidget);
    expect(find.text('1990-01-01'), findsNothing);
    expect(find.text('unknown'), findsNothing);
  });

  testWidgets('TC-EHR-REC-033: Keep current rejects the incoming value, '
      'removes the card and confirms', (t) async {
    final s = _FakeConflicts([_dob(7)]);
    await _pump(t, s);
    await t.tap(find.text('Keep current'));
    await t.pumpAndSettle();
    expect(s.resolved, ['7:REJECTED']);
    expect(find.text('Which date of birth is correct?'), findsNothing);
    expect(find.text('Kept your current date of birth.'), findsOneWidget);
  });

  testWidgets('TC-EHR-REC-034: Use new date accepts the incoming value, '
      'removes the card and confirms', (t) async {
    final s = _FakeConflicts([_dob(8)]);
    await _pump(t, s);
    await t.tap(find.text('Use new date'));
    await t.pumpAndSettle();
    expect(s.resolved, ['8:ACCEPTED']);
    expect(find.text('Which date of birth is correct?'), findsNothing);
    expect(find.text('Date of birth updated.'), findsOneWidget);
  });

  testWidgets('TC-EHR-REC-035: when the choice is not saved the card stays '
      'and the patient is told', (t) async {
    final s = _FakeConflicts([_dob(9)], resolveResult: false);
    await _pump(t, s);
    await t.tap(find.text('Use new date'));
    await t.pumpAndSettle();
    expect(s.resolved, ['9:ACCEPTED']);
    expect(find.text('Which date of birth is correct?'), findsOneWidget);
    expect(find.text('Date of birth updated.'), findsNothing);
    expect(find.textContaining(RegExp('couldn.t save')), findsOneWidget);
  });

  testWidgets('TC-EHR-REC-036: when saving fails with an error the buttons '
      'come back and the patient is told', (t) async {
    final s = _FakeConflicts([_dob(10)], throwOnResolve: Exception('offline'));
    await _pump(t, s);
    await t.tap(find.text('Keep current'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Keep current'), findsOneWidget);
    expect(find.textContaining(RegExp('couldn.t save')), findsOneWidget);
  });

  testWidgets('TC-EHR-REC-037: with nothing pending the screen says the '
      'patient is all caught up', (t) async {
    await _pump(t, _FakeConflicts(const []));
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(find.text('Which date of birth is correct?'), findsNothing);
  });

  test('TC-EHR-REC-038: IdentityConflict.fromJson reads camelCase and '
      'snake_case and the backend status vocabulary', () {
    final camel = IdentityConflict.fromJson({
      'id': 4,
      'fieldName': 'date_of_birth',
      'canonicalValueBefore': '1980-05-14',
      'incomingValue': '1985-05-14',
      'status': 'ACCEPTED',
      'detectedAt': '2026-09-26T10:00:00Z',
    });
    expect(camel.id, 4);
    expect(camel.isDob, isTrue);
    expect(camel.status, ConflictStatus.accepted);
    expect(camel.detectedAt, DateTime.utc(2026, 9, 26, 10));
    final snake = IdentityConflict.fromJson({
      'id': 5,
      'field_name': 'date_of_birth',
      'canonical_value_before': '1980-05-14',
      'incoming_value': '1985-05-14',
      'status': 'REJECTED',
    });
    expect(snake.canonicalValueBefore, '1980-05-14');
    expect(snake.incomingValue, '1985-05-14');
    expect(snake.status, ConflictStatus.rejected);
    expect(IdentityConflict.fromJson({'status': 'PENDING'}).isPending, isTrue);
  });

  for (final theme in {
    'default': null,
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('TC-EHR-REC-039: every text on the screen has at least 4.5:1 '
        'contrast against what is behind it, in the ${theme.key} theme '
        '(WCAG 2.1 SC 1.4.3)', (t) async {
      await t.pumpWidget(MaterialApp(
          theme: theme.value,
          home: DobConfirmationScreen(service: _FakeConflicts([_dob(1)]))));
      await t.pumpAndSettle();
      final low = lowContrastText(t, find.byType(ListView));
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  testWidgets('TC-EHR-REC-045: DOB load failure says so instead of "all caught up", and '
      'offers Try again (#263 review)', (t) async {
    await _pump(t, _FakeConflicts([_dob(1)], throwOnFetch: Exception('down')));
    expect(find.text('We couldn\u2019t check your information'), findsOneWidget);
    expect(find.textContaining('all caught up'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  test('TC-EHR-REC-046: with the mock off, resolve never reports a save that did not happen '
      '(#263 review)', () async {
    expect(await IdentityConflictService(useMock: false).resolve(1, accepted: true),
        isFalse);
  });
}
