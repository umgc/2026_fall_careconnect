// AthenaResourceDetailPage (/athena/{type}/{id}): loading, the record with
// its FHIR resource, a record that is gone, and a read that fails.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/pages/athena_resource_detail_page.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_data_service.dart';
import 'package:care_connect_app/services/api_client.dart';

import '../health_data_test_support.dart';

const _detailPath = '/api/athena/resources/Condition/ath-1';

final _detail = {
  'resourceType': 'Condition',
  'resourceId': 'ath-1',
  'category': 'Conditions',
  'title': 'Type 2 diabetes',
  'status': 'active',
  'occurredAt': '2026-07-01T00:00:00Z',
  'lastSyncedAt': '2026-10-14T12:00:00Z',
  'source': 'ATHENAHEALTH',
  'resource': {'resourceType': 'Condition', 'id': 'ath-1'},
};

/// A service whose one read waits on [gate].
class _GatedService extends AthenaDataService {
  _GatedService(this.gate);
  final Completer<Map<String, dynamic>?> gate;
  @override
  Future<Map<String, dynamic>?> fetchResource(String type, String id) =>
      gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
  });
  tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

  Future<void> pump(WidgetTester t, RouteAdapter a) async {
    ApiClient.instance.debugSetHttpClientAdapter(a);
    await t.pumpWidget(const MaterialApp(
        home: AthenaResourceDetailPage(
            resourceType: 'Condition', resourceId: 'ath-1')));
    // Dio runs outside the fake clock.
    for (var i = 0;
        i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
  }

  testWidgets('shows a spinner until the record is read', (t) async {
    final gate = Completer<Map<String, dynamic>?>();
    await t.pumpWidget(MaterialApp(
        home: AthenaResourceDetailPage(
            resourceType: 'Condition',
            resourceId: 'ath-1',
            service: _GatedService(gate))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(_detail);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
  });

  testWidgets('reads GET /api/athena/resources/{type}/{id} and shows every '
      'field and the FHIR resource', (t) async {
    final a = RouteAdapter({_detailPath: jsonEncode(_detail)});
    await pump(t, a);
    expect(a.paths, [_detailPath]);
    expect(find.text('Health Record'), findsOneWidget);
    for (final text in [
      'Condition',
      'Conditions',
      'Type 2 diabetes',
      'active',
      '2026-07-01T00:00:00Z',
      'ath-1',
      '2026-10-14T12:00:00Z',
      'FHIR resource',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('"resourceType": "Condition"'), findsOneWidget);
  });

  testWidgets('a type and id with reserved characters are encoded in the path',
      (t) async {
    final a = RouteAdapter(const {});
    ApiClient.instance.debugSetHttpClientAdapter(a);
    await t.pumpWidget(const MaterialApp(
        home: AthenaResourceDetailPage(
            resourceType: 'Condition', resourceId: 'a/b c')));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(a.paths.single, '/api/athena/resources/Condition/a%2Fb%20c');
  });

  testWidgets('only the fields the backend sent are listed; a missing '
      'resource says so', (t) async {
    await pump(
        t,
        RouteAdapter({
          _detailPath: jsonEncode({'resourceId': 'ath-1', 'resource': null}),
        }));
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Condition'), findsOneWidget); // from the route
    for (final label in ['Category', 'Title', 'Status', 'Date', 'Last synced']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.text('(payload unavailable)'), findsOneWidget);
  });

  testWidgets('a record that is gone (404) says it is no longer available',
      (t) async {
    await pump(
        t,
        RouteAdapter(const {},
            status: {_detailPath: 404},
            statusBodies: {_detailPath: '{"code":"NOT_FOUND"}'}));
    expect(find.text('Resource type'), findsOneWidget);
    expect(find.text('FHIR id'), findsOneWidget);
    expect(find.textContaining('no longer available'), findsOneWidget);
  });

  // Failing-first for R381-D02: a read that fails (offline, server error) was
  // told to the patient as a record that was removed or not synced.
  for (final c in [
    ('offline (no connection)', RouteAdapter(const {})),
    (
      'a server error (500)',
      RouteAdapter(const {},
          status: {_detailPath: 500}, statusBodies: {_detailPath: '{}'})
    ),
  ]) {
    testWidgets('${c.$1}: says the record could not be loaded, not that it '
        'was removed, and offers Try again', (t) async {
      await pump(t, c.$2);
      expect(find.textContaining('no longer available'), findsNothing);
      expect(find.textContaining('removed'), findsNothing);
      expect(find.text('We couldn\'t load this record. Check your connection '
          'and try again.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);

      // Try again reads it again; this time it answers.
      ApiClient.instance.debugSetHttpClientAdapter(
          RouteAdapter({_detailPath: jsonEncode(_detail)}));
      await t.tap(find.text('Try again'));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle();
      expect(find.text('Type 2 diabetes'), findsOneWidget);
    });
  }

  // Failing-first for R381-D06: the same page shown for another record (the
  // URL changed, e.g. browser history) must read that record.
  testWidgets('a new type or id on the same page reads the new record',
      (t) async {
    final service = _RecordingService();
    final id = ValueNotifier('missing');
    await t.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<String>(
        valueListenable: id,
        builder: (_, value, __) => AthenaResourceDetailPage(
            resourceType: 'Condition', resourceId: value, service: service),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('no longer available'), findsOneWidget);

    id.value = 'ath-1';
    await t.pumpAndSettle();
    expect(service.reads, ['Condition/missing', 'Condition/ath-1']);
    expect(find.textContaining('no longer available'), findsNothing);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
  });
}

/// Answers ath-1 with [_detail]; anything else is not found.
class _RecordingService extends AthenaDataService {
  final reads = <String>[];
  @override
  Future<Map<String, dynamic>?> fetchResource(String type, String id) async {
    reads.add('$type/$id');
    return id == 'ath-1' ? _detail : null;
  }
}
