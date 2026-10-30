// Widget tests for SchedulePage
// (lib/features/evv/schedule/pages/schedule_page.dart) covering the patient
// perspective, filter bar, calendar view modes, visit navigation and the
// Schedule New Visit dialog submission paths.

import 'dart:convert';

import 'package:care_connect_app/features/evv/schedule/pages/schedule_page.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_day_schedule_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_month_calendar_view.dart';
import 'package:care_connect_app/features/evv/schedule/widgets/evv_week_calendar_view.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

late Future<http.Response> Function(http.Request) _httpHandler;

final _client = MockClient((request) => _httpHandler(request));

Map<String, dynamic> _visit({
  required int id,
  required DateTime at,
  int patientId = 10,
  String patientName = 'John Doe',
  String serviceType = 'Personal Care',
  String status = 'Scheduled',
  String priority = 'Normal',
  int durationMinutes = 60,
}) =>
    {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'serviceType': serviceType,
      'scheduledDate': DateFormat('yyyy-MM-dd').format(at),
      'scheduledTime': DateFormat('HH:mm:ss').format(at),
      'durationMinutes': durationMinutes,
      'status': status,
      'priority': priority,
    };

DateTime _daysFromToday(int days, {int hour = 10}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour);
}

/// Five future visits for two patients covering every status colour.
List<Map<String, dynamic>> _futureVisits() => [
      _visit(id: 1, at: _daysFromToday(3), status: 'Scheduled'),
      _visit(
        id: 2,
        at: _daysFromToday(4),
        status: 'In Progress',
        serviceType: 'Companionship',
      ),
      _visit(id: 3, at: _daysFromToday(5), status: 'Completed'),
      _visit(id: 4, at: _daysFromToday(6), status: 'Cancelled'),
      _visit(
        id: 5,
        at: _daysFromToday(7),
        patientId: 20,
        patientName: '',
        status: 'Missed',
        serviceType: 'Transportation',
      ),
    ];

List<Map<String, dynamic>> _patients() => [
      {
        'id': 10,
        'firstName': 'John',
        'lastName': 'Doe',
        'email': 'john@example.test',
        'phone': '555-0100',
        'dob': '1980-01-01',
      },
    ];

void _routes({
  List<Map<String, dynamic>> Function()? visits,
  http.Response Function(http.Request)? post,
  void Function(http.Request)? onRequest,
}) {
  _httpHandler = (request) async {
    onRequest?.call(request);
    final path = request.url.path;
    if (request.method == 'POST') {
      return post != null ? post(request) : http.Response('{}', 201);
    }
    if (path.contains('/range')) {
      return http.Response(jsonEncode((visits ?? _futureVisits)()), 200);
    }
    if (path.endsWith('/patients')) {
      return http.Response(jsonEncode(_patients()), 200);
    }
    return http.Response('[]', 200);
  };
}

Widget _app({String role = 'CAREGIVER'}) {
  final provider = MockUserProvider(
    mockUser: MockUser(
      id: 1,
      role: role,
      caregiverId: role == 'CAREGIVER' ? 1 : null,
      patientId: role == 'PATIENT' ? 10 : null,
    ),
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SchedulePage()),
      GoRoute(
        path: '/evv/checkin-location',
        builder: (_, state) =>
            Scaffold(body: Text('Checkin ${state.uri.query}')),
      ),
      GoRoute(
        path: '/evv/select-patient',
        builder: (_, __) => const Scaffold(body: Text('Select Patient')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      routerConfig: router,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpPage(WidgetTester tester, {String role = 'CAREGIVER'}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(role: role));
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _pickDropdown(
  WidgetTester tester,
  String label,
  String option,
) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
  );
  await tester.ensureVisible(field.first);
  await tester.tap(field.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => ApiServiceOffline.debugOverrideHttpClient(_client));
  tearDownAll(() => ApiServiceOffline.debugOverrideHttpClient(null));

  setUp(() {
    _routes();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('SchedulePage patient perspective', () {
    testWidgets('patient user requests patient endpoints and sees cards',
        (tester) async {
      final paths = <String>[];
      _routes(onRequest: (r) => paths.add(r.url.path));
      await _pumpPage(tester, role: 'PATIENT');

      expect(
        paths.where((p) => p.contains('scheduled-visits/patient/10/range')),
        hasLength(3),
      );
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      expect(find.text('1 Scheduled'), findsOneWidget);
      expect(find.text('1 In Progress'), findsOneWidget);
      expect(find.text('1 Completed'), findsOneWidget);
      expect(find.text('1 Cancelled'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Companionship'), findsOneWidget);
      // Calendar view mode selector is hidden in patient perspective.
      expect(find.text('Month'), findsNothing);
    });

    testWidgets('patient view shows empty state when nothing matches',
        (tester) async {
      _routes(visits: () => []);
      await _pumpPage(tester, role: 'PATIENT');
      expect(find.text('No visits match the current filters'), findsOneWidget);
      expect(find.text('Adjust filters or schedule new visits'), findsOneWidget);
    });

    testWidgets('single patient with single visit uses singular labels',
        (tester) async {
      _routes(visits: () => [_visit(id: 9, at: _daysFromToday(2))]);
      await _pumpPage(tester, role: 'PATIENT');
      expect(find.text('1 Patient · 1 Visit'), findsOneWidget);
    });

    testWidgets('caregiver can switch to patient view and back',
        (tester) async {
      await _pumpPage(tester);
      expect(find.text('Month'), findsOneWidget);
      await _tapText(tester, 'Patient View');
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);
      expect(find.text('Month'), findsNothing);
      await _tapText(tester, 'Caregiver View');
      expect(find.text('Month'), findsOneWidget);
    });
  });

  group('SchedulePage filter bar', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Show Filters'));
      await tester.pumpAndSettle();
      expect(find.text('From Date'), findsOneWidget);
    }

    testWidgets('toggle shows and hides the filter bar', (tester) async {
      await _pumpPage(tester, role: 'PATIENT');
      expect(find.text('From Date'), findsNothing);
      await openFilters(tester);
      expect(find.text('Clear Filters'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide Filters'));
      await tester.pumpAndSettle();
      expect(find.text('From Date'), findsNothing);
    });

    testWidgets('status, patient and service filters narrow results',
        (tester) async {
      await _pumpPage(tester, role: 'PATIENT');
      await openFilters(tester);

      await _pickDropdown(tester, 'Status', 'Completed');
      expect(find.text('1 Patient · 1 Visit'), findsOneWidget);

      await _pickDropdown(tester, 'Status', 'Any');
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);

      await _pickDropdown(tester, 'Patient', 'John Doe');
      expect(find.text('1 Patient · 4 Visits'), findsOneWidget);

      await _pickDropdown(tester, 'Service Type', 'Companionship');
      expect(find.text('1 Patient · 1 Visit'), findsOneWidget);

      await _tapText(tester, 'Clear Filters');
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);
    });

    testWidgets('date range filters include and exclude visits',
        (tester) async {
      await _pumpPage(tester, role: 'PATIENT');
      await openFilters(tester);

      // From Date = today keeps every future visit.
      await _tapText(tester, 'From Date');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);
      final today = DateFormat('MMM d, yyyy').format(DateTime.now());
      expect(find.text(today), findsOneWidget);

      // To Date = today removes all future visits.
      await _tapText(tester, 'To Date');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No visits match the current filters'), findsOneWidget);

      // Clearing each date restores results.
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(find.text('2 Patients · 5 Visits'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('Any'), findsWidgets);
    });

    testWidgets('cancelling a date picker leaves the filter unset',
        (tester) async {
      await _pumpPage(tester, role: 'PATIENT');
      await openFilters(tester);
      await _tapText(tester, 'To Date');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'From Date');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('filters apply to the caregiver list view as well',
        (tester) async {
      await _pumpPage(tester);
      await openFilters(tester);
      await _pickDropdown(tester, 'Status', 'Cancelled');
      expect(find.text('Upcoming Visits'), findsOneWidget);
      expect(find.text('Companionship'), findsNothing);
    });
  });

  group('SchedulePage caregiver calendar modes', () {
    testWidgets('month mode renders month view and navigates',
        (tester) async {
      await _pumpPage(tester);
      await _tapText(tester, 'Month');
      expect(find.byType(EVVMonthCalendarView), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      expect(find.byType(EVVMonthCalendarView), findsOneWidget);
    });

    testWidgets('week mode renders week view and navigates', (tester) async {
      await _pumpPage(tester);
      await _tapText(tester, 'Week');
      expect(find.byType(EVVWeekCalendarView), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      expect(find.byType(EVVWeekCalendarView), findsOneWidget);
    });

    testWidgets('day mode visit tap opens visit details dialog',
        (tester) async {
      _routes(
        visits: () => [
          _visit(
            id: 11,
            at: _daysFromToday(1, hour: 9),
            patientName: 'Mary Major',
            priority: 'High',
            durationMinutes: 45,
          ),
        ],
      );
      await _pumpPage(tester);
      await _tapText(tester, 'Day');
      expect(find.byType(EVVDayScheduleView), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      final visit = find.descendant(
        of: find.byType(EVVDayScheduleView),
        matching: find.text('Mary Major'),
      );
      await tester.ensureVisible(visit);
      await tester.tap(visit);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Service Type:')),
        findsOneWidget,
      );
      expect(find.text('45 minutes'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('High')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
      await _tapText(tester, 'List');
      expect(find.byType(EVVDayScheduleView), findsNothing);
    });
  });

  group('SchedulePage visit card navigation', () {
    testWidgets('overdue visit button opens check-in location route',
        (tester) async {
      _routes(
        visits: () => [
          _visit(
            id: 21,
            at: _daysFromToday(-2),
            serviceType: 'Meal Preparation',
          ),
        ],
      );
      await _pumpPage(tester);
      expect(find.text('Overdue'), findsWidgets);
      final button = find.text('Start Overdue Visit');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Checkin patientId=10&serviceType=Meal%20Preparation&scheduledVisitId=21',
        ),
        findsOneWidget,
      );
    });
  });

  group('Schedule New Visit dialog submission', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Schedule New Visit'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.widgetWithText(ElevatedButton, 'Schedule Visit');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> fillForm(WidgetTester tester) async {
      await _pickDropdown(tester, 'Select a patient', 'John Doe');
      await _pickDropdown(tester, 'Select service type', 'Respite Care');
      await _pickDropdown(tester, 'Normal', 'Urgent');

      final time = find.text('--:-- --');
      await tester.ensureVisible(time);
      await tester.tap(time);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('--:-- --'), findsNothing);
    }

    testWidgets('validation messages for patient, service type and time',
        (tester) async {
      await _pumpPage(tester);
      await openDialog(tester);

      void clearSnackBars() => tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();

      await submit(tester);
      expect(find.text('Please select a patient'), findsOneWidget);
      clearSnackBars();

      await _pickDropdown(tester, 'Select a patient', 'John Doe');
      await submit(tester);
      expect(find.text('Please select a service type'), findsOneWidget);
      clearSnackBars();

      await _pickDropdown(tester, 'Select service type', 'Personal Care');
      await submit(tester);
      expect(find.text('Please select a time'), findsOneWidget);
      clearSnackBars();
      await tester.pumpAndSettle();
    });

    testWidgets('successful submission posts visit and closes dialog',
        (tester) async {
      Map<String, dynamic>? body;
      var rangeCalls = 0;
      _routes(
        post: (r) {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response('{}', 201);
        },
        onRequest: (r) {
          if (r.url.path.contains('/range')) rangeCalls++;
        },
      );
      await _pumpPage(tester);
      final initialRangeCalls = rangeCalls;
      await openDialog(tester);
      await fillForm(tester);

      // Pick a date (tomorrow) through the date picker.
      final today = DateFormat('MM/dd/yyyy').format(DateTime.now());
      await tester.ensureVisible(find.text(today));
      await tester.tap(find.text(today));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Bring keys');
      await submit(tester);
      await tester.pumpAndSettle();

      expect(body?['patientId'], 10);
      expect(body?['serviceType'], 'Respite Care');
      expect(body?['priority'], 'Urgent');
      expect(body?['notes'], 'Bring keys');
      expect(body?['durationMinutes'], 60);
      expect(find.text('Visit scheduled successfully!'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(rangeCalls, greaterThan(initialRangeCalls));
    });

    testWidgets('conflict with error field shows message and Modify Details',
        (tester) async {
      _routes(
        post: (r) => http.Response(
          jsonEncode({'error': 'Caregiver already booked'}),
          400,
        ),
      );
      await _pumpPage(tester);
      await openDialog(tester);
      await fillForm(tester);
      await submit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Scheduling Conflict'), findsOneWidget);
      expect(find.text('Caregiver already booked'), findsOneWidget);
      expect(find.text('What to do:'), findsOneWidget);

      await tester.tap(find.text('Modify Details'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduling Conflict'), findsNothing);
      // Time is reset so the user can choose another slot.
      expect(find.text('--:-- --'), findsOneWidget);
    });

    testWidgets('conflict with non-JSON body shows raw body text',
        (tester) async {
      _routes(post: (r) => http.Response('Overlapping visit', 400));
      await _pumpPage(tester);
      await openDialog(tester);
      await fillForm(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Overlapping visit'), findsOneWidget);
      await tester.tap(find.text('Try Different Time'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduling Conflict'), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('conflict JSON without error field uses default message',
        (tester) async {
      _routes(post: (r) => http.Response(jsonEncode({'code': 1}), 400));
      await _pumpPage(tester);
      await openDialog(tester);
      await fillForm(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Unable to schedule this visit'), findsOneWidget);
    });

    testWidgets('server error shows retry message', (tester) async {
      _routes(post: (r) => http.Response('boom', 500));
      await _pumpPage(tester);
      await openDialog(tester);
      await fillForm(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to schedule this visit. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
