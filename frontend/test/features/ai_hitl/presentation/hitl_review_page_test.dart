// Tests for HitlReviewPage (lib/features/ai_hitl/presentation/hitl_review_page.dart).
import 'dart:async';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/presentation/hitl_review_page.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHitlApi implements HitlApiService {
  _FakeHitlApi(this.details);

  /// Each fetchDetail call returns the next entry; an Exception entry throws.
  final List<Object> details;
  int fetches = 0;
  String? releasedAnswer;
  String? releasedNotes;
  String? rejectReason;
  bool rejected = false;
  Object? releaseError;
  Object? rejectError;

  @override
  Future<HitlDetail> fetchDetail(String heldItemId,
      {Duration timeout = const Duration(seconds: 20), client}) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final d = details[fetches < details.length ? fetches : details.length - 1];
    fetches++;
    if (d is Exception) throw d;
    return d as HitlDetail;
  }

  @override
  Future<HitlDetail> release(String heldItemId,
      {String? editedAnswer,
      String? notes,
      Duration timeout = const Duration(seconds: 30),
      client}) async {
    if (releaseError != null) throw releaseError!;
    releasedAnswer = editedAnswer;
    releasedNotes = notes;
    return details.first as HitlDetail;
  }

  @override
  Future<HitlDetail> reject(String heldItemId,
      {String? reason,
      Duration timeout = const Duration(seconds: 30),
      client}) async {
    if (rejectError != null) throw rejectError!;
    rejected = true;
    rejectReason = reason;
    return details.first as HitlDetail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pending = HitlDetail(
  heldItemId: 'held-1',
  patientId: 12,
  status: 'PENDING_REVIEW',
  deliveryStatus: 'HELD',
  triggerCodes: ['MEDICATION_DOSE'],
  queryText: 'Can I double my dose?',
  draftAnswer: 'Draft text',
);

const _unsupported = HitlDetail(
  heldItemId: 'held-1',
  patientId: 12,
  status: 'PENDING_REVIEW',
  deliveryStatus: 'HELD',
  triggerCodes: ['UNSUPPORTED_CLAIM'],
  draftAnswer: 'Claim',
);

/// Opens the review page from a launcher route so pop(true) is observable.
Future<List<Object?>> _open(WidgetTester tester, _FakeHitlApi api) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final r = await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HitlReviewPage(heldItemId: 'held-1', api: api),
          ));
          results.add(r);
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('pending item renders and releases an edited answer with notes',
      (tester) async {
    final api = _FakeHitlApi([_pending]);
    final results = await _open(tester, api);
    expect(find.text('Patient 12'), findsOneWidget);
    expect(find.text('Status: PENDING_REVIEW · HELD'), findsOneWidget);
    expect(find.text('Triggers: MEDICATION_DOSE'), findsOneWidget);
    expect(find.text('Can I double my dose?'), findsOneWidget);
    expect(find.text('Answer to release'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('hitl-edited-answer')), 'Edited answer');
    await tester.enterText(
        find.byKey(const Key('hitl-review-notes')), 'Checked dose');
    await tester.tap(find.byKey(const Key('hitl-release-button')));
    await tester.pumpAndSettle();
    expect(api.releasedAnswer, 'Edited answer');
    expect(api.releasedNotes, 'Checked dose');
    expect(results, [true]);
  });

  testWidgets('releasing unchanged draft sends no edited answer',
      (tester) async {
    final api = _FakeHitlApi([_pending]);
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('hitl-release-button')));
    await tester.pumpAndSettle();
    expect(api.releasedAnswer, isNull);
    expect(api.releasedNotes, isNull);
  });

  testWidgets('unsupported claim requires an edit before release',
      (tester) async {
    final api = _FakeHitlApi([_unsupported]);
    await _open(tester, api);
    expect(find.text('(no query text)'), findsOneWidget);
    expect(find.text('Unsupported claim: edit the answer before release.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('hitl-release-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('require an edited answer'), findsOneWidget);
  });

  testWidgets('release error is shown', (tester) async {
    final api = _FakeHitlApi([_pending])..releaseError = Exception('boom');
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('hitl-release-button')));
    await tester.pumpAndSettle();
    expect(find.text('Exception: boom'), findsOneWidget);
  });

  testWidgets('reject with a reason pops true', (tester) async {
    final api = _FakeHitlApi([_pending]);
    final results = await _open(tester, api);
    await tester.tap(find.byKey(const Key('hitl-reject-button')));
    await tester.pumpAndSettle();
    expect(find.text('Reject held answer'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('hitl-reject-reason')), 'Unsafe');
    await tester.tap(find.byKey(const Key('hitl-reject-confirm')));
    await tester.pumpAndSettle();
    expect(api.rejected, isTrue);
    expect(api.rejectReason, 'Unsafe');
    expect(results, [true]);
  });

  testWidgets('reject cancel does nothing; empty reason sends null; error shown',
      (tester) async {
    final api = _FakeHitlApi([_pending])..rejectError = Exception('nope');
    await _open(tester, api);
    await tester.tap(find.byKey(const Key('hitl-reject-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.rejected, isFalse);

    await tester.tap(find.byKey(const Key('hitl-reject-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hitl-reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Exception: nope'), findsOneWidget);
  });

  testWidgets('non-pending item shows final answer or no-longer-pending',
      (tester) async {
    const released = HitlDetail(
      heldItemId: 'held-1',
      patientId: 3,
      status: 'RELEASED',
      deliveryStatus: 'DELIVERED',
      finalAnswer: 'Final text',
    );
    await _open(tester, _FakeHitlApi([released]));
    expect(find.text('Draft answer'), findsOneWidget);
    expect(find.text('Final answer: Final text'), findsOneWidget);
  });

  testWidgets('load error shows retry which reloads', (tester) async {
    const rejected = HitlDetail(
      heldItemId: 'held-1',
      patientId: 3,
      status: 'REJECTED',
      deliveryStatus: 'NOT_DELIVERED',
    );
    final api = _FakeHitlApi([Exception('offline'), rejected]);
    await _open(tester, api);
    expect(find.textContaining('Unable to load held item.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('This hold is no longer pending.'), findsOneWidget);
    expect(api.fetches, 2);
  });
}
