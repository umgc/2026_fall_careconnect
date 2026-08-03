// Tests for ScheduleApiService.
// (lib/features/shift_scheduling/services/schedule_api_service.dart)
//
// Covers both the error paths (via an immediately-failing Dio adapter) and the
// populated happy paths (via a JSON-routing adapter), by injecting the shared
// ApiClient.instance's HttpClientAdapter.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';
import 'package:care_connect_app/features/shift_scheduling/services/schedule_api_service.dart';
import 'package:care_connect_app/services/api_client.dart';

/// Dio adapter that fails immediately — never touches the network.
class _ImmediateFailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'mocked connection failure',
      message: 'mocked connection failure',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Dio adapter that returns a canned JSON body based on the request path.
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.routes);
  final Map<String, String> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final body = routes.entries
            .firstWhere((e) => path.contains(e.key),
                orElse: () => const MapEntry('', '{}'))
            .value;
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

String get _visitJson => '''
{"id":1,"caregiverId":1,"patientId":10,"patientName":"Mary Johnson",
 "serviceType":"Personal Care","scheduledDate":"2026-03-17",
 "scheduledTime":"09:00","durationMinutes":60,"priority":"High",
 "status":"Scheduled","createdAt":"2026-03-01T00:00:00.000",
 "updatedAt":"2026-03-01T00:00:00.000"}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduleApiService - error paths', () {
    late ScheduleApiService service;
    late HttpClientAdapter originalAdapter;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient.instance;
      originalAdapter = api.debugHttpClientAdapter;
      api.debugSetTimeouts();
      api.debugSetHttpClientAdapter(_ImmediateFailAdapter());
      service = ScheduleApiService();
    });

    tearDown(() {
      ApiClient.instance.debugSetHttpClientAdapter(originalAdapter);
      ApiClient.instance.debugSetTimeouts(
        connect: const Duration(seconds: 20),
        receive: const Duration(seconds: 30),
        send: const Duration(seconds: 20),
      );
    });

    test('can be instantiated', () {
      expect(service, isA<ScheduleApiService>());
    });

    test('getDaySchedule returns empty list on error', () async {
      expect(await service.getDaySchedule(1, DateTime(2026, 3, 17)), isEmpty);
    });

    test('getMonthSchedule returns empty list on error', () async {
      expect(await service.getMonthSchedule(1, 2026, 3), isEmpty);
    });

    test('getWeekSchedule returns empty list on error', () async {
      expect(await service.getWeekSchedule(1, DateTime(2026, 3, 16)), isEmpty);
    });

    test('checkConflicts returns null on error', () async {
      expect(
          await service.checkConflicts(1, {'patientId': 10}), isNull);
    });

    test('getAuditHistory returns empty list on error', () async {
      expect(await service.getAuditHistory(42), isEmpty);
    });
  });

  group('ScheduleApiService - populated responses', () {
    late ScheduleApiService service;
    late HttpClientAdapter originalAdapter;

    void install(Map<String, String> routes) {
      ApiClient.instance.debugSetHttpClientAdapter(_JsonAdapter(routes));
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        if (call.method == 'readAll') return <String, String>{};
        return null;
      });
      final api = ApiClient.instance;
      originalAdapter = api.debugHttpClientAdapter;
      api.debugSetTimeouts();
      service = ScheduleApiService();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
      ApiClient.instance.debugSetHttpClientAdapter(originalAdapter);
      ApiClient.instance.debugSetTimeouts(
        connect: const Duration(seconds: 20),
        receive: const Duration(seconds: 30),
        send: const Duration(seconds: 20),
      );
    });

    test('getMonthSchedule parses visits nested under days', () async {
      install({
        '/calendar/month': '{"days":{"2026-03-17":{"visits":[$_visitJson]}}}'
      });
      final visits = await service.getMonthSchedule(1, 2026, 3);
      expect(visits, hasLength(1));
      expect(visits.first.patientName, 'Mary Johnson');
    });

    test('getWeekSchedule parses visits nested under date keys', () async {
      install({
        '/calendar/week': '{"2026-03-16":{"visits":[$_visitJson]}}'
      });
      final visits = await service.getWeekSchedule(1, DateTime(2026, 3, 16));
      expect(visits, hasLength(1));
      expect(visits.first.serviceType, 'Personal Care');
    });

    test('getDaySchedule parses a visit list', () async {
      install({'/date/': '[$_visitJson]'});
      final visits = await service.getDaySchedule(1, DateTime(2026, 3, 17));
      expect(visits, hasLength(1));
      expect(visits.first.id, 1);
    });

    test('checkConflicts returns a VisitConflict when a conflict exists',
        () async {
      install({
        '/check-conflicts': '{"hasConflicts":true,'
            '"conflictingVisits":[$_visitJson],'
            '"conflictType":"overlap",'
            '"conflictMessages":["Overlaps an existing visit"]}'
      });
      final conflict = await service.checkConflicts(1, {'patientId': 10});
      expect(conflict, isNotNull);
      expect(conflict!.conflictType, 'overlap');
      expect(conflict.conflictingVisits, hasLength(1));
      expect(conflict.message, contains('Overlaps'));
    });

    test('checkConflicts returns null when no conflict exists', () async {
      install({'/check-conflicts': '{"hasConflicts":false}'});
      expect(await service.checkConflicts(1, {'patientId': 10}), isNull);
    });

    test('getAuditHistory parses audit entries', () async {
      install({
        '/audit-history': '[{"id":1,"visitId":42,"action":"UPDATED",'
            '"changedField":"status","oldValue":"Scheduled",'
            '"newValue":"Completed","changedAt":"2026-03-01T00:00:00.000",'
            '"changedBy":"admin"}]'
      });
      final audits = await service.getAuditHistory(42);
      expect(audits, hasLength(1));
      expect(audits.first.action, 'UPDATED');
      expect(audits.first.changedBy, 'admin');
    });
  });
}
