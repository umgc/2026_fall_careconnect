// Tests for HitlQueuePage (lib/features/ai_hitl/presentation/hitl_queue_page.dart).
import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/presentation/hitl_queue_page.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/titled_route_probe.dart';

/// Returns a fixed queue; the review page's calls are never made because the
/// probe doesn't build that page.
class _FakeHitlApi implements HitlApiService {
  _FakeHitlApi(this.items);
  final List<HitlQueueItem> items;

  @override
  Future<List<HitlQueueItem>> fetchQueue(
          {Duration timeout = const Duration(seconds: 20), client}) async =>
      items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TitledRouteProbe probe;

  Future<void> pumpQueue(WidgetTester tester, List<HitlQueueItem> items) async {
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: HitlQueuePage(api: _FakeHitlApi(items)),
    ));
    await tester.pumpAndSettle();
  }

  const item = HitlQueueItem(
    heldItemId: 'held-1',
    patientId: 12,
    triggerCodes: ['MEDICATION_DOSE'],
    queryPreview: 'Can I double my dose?',
  );

  testWidgets('lists held answers with patient and trigger', (tester) async {
    await pumpQueue(tester, [item]);
    expect(find.text('Can I double my dose?'), findsOneWidget);
    expect(find.text('Patient 12 · MEDICATION_DOSE'), findsOneWidget);
  });

  testWidgets('an empty queue says nothing is waiting', (tester) async {
    await pumpQueue(tester, const []);
    expect(find.text('No held answers waiting for review.'), findsOneWidget);
  });

  testWidgets('opening an item pushes a page titled "Review AI Result"',
      (tester) async {
    await pumpQueue(tester, [item]);
    expect(
        await probe.tapAndReadTitle(
            tester, find.byKey(const Key('hitl-queue-item-held-1'))),
        'Review AI Result');
  });
}
