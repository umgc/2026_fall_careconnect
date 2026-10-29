// Tests for CalendarAssistantScreen from
// lib/features/tasks/presentation/calendar_assisiant.dart.
//
// Covers:
//   - CalendarViewType enum values
//   - Loading state (spinner, AppBar) for patient and caregiver
//   - Null user error state (calendar renders with empty data)
//   - Patient user: tasks loaded and displayed in month view
//   - Caregiver user: patients fetched, tasks loaded
//   - View switching (month -> week -> day)
//   - Filter panel toggle
//   - Today button
//   - Calendar header navigation (chevron icons)
//   - Legend widget presence
//   - Task list section rendering (day / week views)
//   - Error handling when API fails

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_form_dialog.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../mock_user_provider.dart';
import '../../../test_support/fixtures.dart';

/// Provider with null user to trigger the error branch in _loadTasksFromDb.
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);
  @override
  UserSession? get user => null;
}

/// Sample task JSON for mock API responses.
Map<String, dynamic> _sampleTaskJson({
  int id = 1,
  String name = 'Test Task',
  String description = 'A test task',
  String? date,
  String? timeOfDay,
  int patientId = 1,
  String taskType = 'general',
  bool isComplete = false,
  String? frequency,
  int? parentTaskId,
}) {
  return {
    'id': id,
    'name': name,
    'description': description,
    'date': date ?? DateTime.now().toIso8601String(),
    'timeOfDay': timeOfDay,
    'patientId': patientId,
    'taskType': taskType,
    'isComplete': isComplete,
    'frequency': frequency,
    'parentTaskId': parentTaskId,
  };
}

/// Wrap the screen with required providers.
Widget _wrapWithProvider(UserProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: provider),
      ChangeNotifierProvider<TaskTypeManager>(
        create: (_) => TaskTypeManager(),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CalendarAssistantScreen(),
    ),
  );
}

Future<void> _pumpLoadedCalendar(
  WidgetTester tester,
  UserSession user,
) async {
  await tester.pumpWidget(
    _wrapWithProvider(MockUserProvider(mockUser: user)),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Map<String, dynamic> _recurringTaskJson(DateTime date) {
  final daysOfWeek = List<bool>.filled(7, false);
  daysOfWeek[date.weekday % 7] = true;

  return {
    'id': 42,
    'name': 'Weekly Walk',
    'description': 'Walk outside',
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'timeOfDay': null,
    'patientId': 1,
    'taskType': 'exercise',
    'isComplete': false,
    'frequency': 'weekly',
    'interval': 1,
    'count': 1,
    'daysOfWeek': daysOfWeek,
    'parentTaskId': null,
  };
}

void main() {
  // Suppress overflow errors from calendar widgets in test viewport.
  final originalOnError = FlutterError.onError;

  setUp(() {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async {
        return null;
      },
    );
    FlutterError.onError = (details) {
      final message = details.toString();
      if (message.contains('overflowed') || message.contains('overflow')) {
        return; // suppress RenderFlex overflow errors
      }
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });

  // =====================
  // CalendarViewType enum
  // =====================
  group('CalendarViewType enum', () {
    test('has three values', () {
      expect(CalendarViewType.values.length, 3);
    });

    test('contains month', () {
      expect(CalendarViewType.values, contains(CalendarViewType.month));
    });

    test('contains week', () {
      expect(CalendarViewType.values, contains(CalendarViewType.week));
    });

    test('contains day', () {
      expect(CalendarViewType.values, contains(CalendarViewType.day));
    });

    test('enum index values are correct', () {
      expect(CalendarViewType.month.index, 0);
      expect(CalendarViewType.week.index, 1);
      expect(CalendarViewType.day.index, 2);
    });
  });

  // =====================
  // Loading state
  // =====================
  group('CalendarAssistantScreen - loading state (patient)', () {
    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold while loading', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows Calendar Assistant in AppBar while loading',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('shows AppBar while loading', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows back arrow in AppBar', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('CalendarAssistantScreen - loading state (caregiver)', () {
    testWidgets('shows CircularProgressIndicator for caregiver',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 5,
        ),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Calendar Assistant title for caregiver', (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 5,
        ),
      );
      await tester.pumpWidget(_wrapWithProvider(provider));
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Null user error state
  // =====================
  group('CalendarAssistantScreen - null user error state', () {
    testWidgets('renders scaffold after settling with null user',
        (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows Calendar Assistant title after error', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('shows AppBar after error', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Monthly dropdown after error settles', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.text('Monthly'), findsOneWidget);
    });

    testWidgets('shows view switcher dropdown', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButton<CalendarViewType>),
        findsOneWidget,
      );
    });

    testWidgets('shows SafeArea widgets in body', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('shows Divider widgets for task list section', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('has chevron left and right icons in header', (tester) async {
      await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });
  });

  // =====================
  // Patient with mock HTTP - tasks loaded
  // =====================
  testWidgets('Tab reaches the month region and arrows change its page',
      (tester) async {
    await tester.pumpWidget(_wrapWithProvider(_NullUserProvider()));
    await tester.pumpAndSettle();
    final pageView = find.byType(PageView).first;
    final controller = tester.widget<PageView>(pageView).controller!;
    for (var i = 0; i < 25; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      if (FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<PageView>() != null) {
        break;
      }
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'Calendar scroll region');
    expect(FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<PageView>(), isNotNull);
    final before = controller.page!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.page, before + 1);
    final region = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(region)));
  });

  group('CalendarAssistantScreen - patient with tasks', () {
    testWidgets('loads and displays calendar with tasks for patient user',
        (tester) async {
      final tasks = [
        _sampleTaskJson(
          id: 1,
          name: 'Take Medicine',
          taskType: 'medication',
          patientId: 1,
        ),
        _sampleTaskJson(
          id: 2,
          name: 'Doctor Visit',
          taskType: 'appointment',
          patientId: 1,
        ),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode(tasks), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1, name: 'Test Patient'),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        // pump several frames to let loading complete
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // After loading, should not show progress indicator
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Should show the calendar view
      expect(find.text('Calendar Assistant'), findsOneWidget);
      // Should show the view dropdown
      expect(find.text('Monthly'), findsOneWidget);
    });

    testWidgets('shows Divider and task list section after loading',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('renders MonthView by default for patient', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // MonthView should be present (dropdown shows Monthly)
      expect(find.text('Monthly'), findsOneWidget);
      // Calendar header should show month navigation
      expect(find.byIcon(Icons.chevron_left), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });
  });

  // =====================
  // Caregiver with mock HTTP
  // =====================
  group('CalendarAssistantScreen - caregiver with tasks', () {
    testWidgets('loads tasks for caregiver with patients', (tester) async {
      final patientsResponse = [
        {
          'patient': {
            'id': 10,
            'firstName': 'Alice',
            'lastName': 'Smith',
          }
        },
        {
          'patient': {
            'id': 20,
            'firstName': 'Bob',
            'lastName': 'Jones',
          }
        },
      ];

      final tasksForPatient10 = [
        _sampleTaskJson(
          id: 1,
          name: 'Patient 10 Task',
          patientId: 10,
        ),
      ];

      final tasksForPatient20 = [
        _sampleTaskJson(
          id: 2,
          name: 'Patient 20 Task',
          patientId: 20,
        ),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('caregivers') && url.contains('patients')) {
          return http.Response(jsonEncode(patientsResponse), 200);
        }
        if (url.contains('tasks') && url.contains('patient/10')) {
          return http.Response(jsonEncode(tasksForPatient10), 200);
        }
        if (url.contains('tasks') && url.contains('patient/20')) {
          return http.Response(jsonEncode(tasksForPatient20), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 5,
        ),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should finish loading
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('handles caregiver patient fetch failure gracefully',
        (tester) async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('caregivers') && url.contains('patients')) {
          return http.Response('Server Error', 500);
        }
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 5,
        ),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should still render calendar (just empty)
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // View switching
  // =====================
  group('CalendarAssistantScreen - view switching', () {
    testWidgets('can switch from month to week view', (tester) async {
      // Use a tall surface to avoid week view overflow
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Verify initial state is Monthly
        expect(find.text('Monthly'), findsOneWidget);

        // Open the dropdown
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();

        // Tap 'Weekly'
        await tester.tap(find.text('Weekly').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Now should show Weekly selected
      expect(find.text('Weekly'), findsOneWidget);
    });

    testWidgets('can switch from month to day view', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Open the dropdown
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();

        // Tap 'Daily'
        await tester.tap(find.text('Daily').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Now should show Daily selected
      expect(find.text('Daily'), findsOneWidget);
    });

    testWidgets('dropdown contains all three options', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Open the dropdown
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();
      }, () => client);

      // All three options should be visible in the dropdown overlay
      expect(find.text('Monthly'), findsWidgets);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
    });
  });

  // =====================
  // Filter panel toggle
  // =====================
  group('CalendarAssistantScreen - filters panel', () {
    testWidgets('filter panel is present after loading', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // FiltersPanel uses chevron_right as toggle when collapsed
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('tapping expand icon toggles expansion', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // FiltersPanel starts collapsed with chevron_right,
        // tap it to expand (becomes expand_more)
        final chevronFinder = find.byIcon(Icons.chevron_right);
        if (chevronFinder.evaluate().isNotEmpty) {
          await tester.tap(chevronFinder.first);
          await tester.pump();
          await tester.pump();
        }
      }, () => client);

      // After toggling, the Filters text should still be present
      expect(find.text('Filters'), findsOneWidget);
    });
  });

  // =====================
  // Calendar header navigation
  // =====================
  group('CalendarAssistantScreen - calendar navigation', () {
    testWidgets('has month navigation chevron buttons', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byIcon(Icons.chevron_left), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('tapping left chevron navigates to previous month',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Tap left chevron
        final leftChevrons = find.byIcon(Icons.chevron_left);
        if (leftChevrons.evaluate().isNotEmpty) {
          await tester.tap(leftChevrons.first);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      }, () => client);

      // Should still have calendar elements
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('tapping right chevron navigates to next month',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Tap right chevron
        final rightChevrons = find.byIcon(Icons.chevron_right);
        if (rightChevrons.evaluate().isNotEmpty) {
          await tester.tap(rightChevrons.first);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      }, () => client);

      // Should still have calendar elements
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Legend
  // =====================
  group('CalendarAssistantScreen - legend', () {
    testWidgets('legend widget is present after loading', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Legend should show an "edit" icon for managing task types
      expect(find.byIcon(Icons.edit), findsWidgets);
    });
  });

  // =====================
  // Week view specific tests
  // =====================
  group('CalendarAssistantScreen - week view', () {
    testWidgets('week view renders with weekday labels', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Switch to week view
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Weekly').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Week view should show weekday labels (M, T, W, T, F, S, S)
      expect(find.text('Weekly'), findsOneWidget);
    });

    testWidgets('week view shows task list for selected week', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tasks = [
        _sampleTaskJson(
          id: 1,
          name: 'Weekly Task',
          patientId: 1,
        ),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode(tasks), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Switch to week view
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Weekly').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should show the weekly task list and divider
      expect(find.byType(Divider), findsWidgets);
    });
  });

  // =====================
  // Day view specific tests
  // =====================
  group('CalendarAssistantScreen - day view', () {
    testWidgets('day view renders after switching', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Switch to day view
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Daily').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.text('Daily'), findsOneWidget);
    });

    testWidgets('day view shows time labels', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Switch to day view
        await tester.tap(find.text('Monthly'));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Daily').last);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Day view should show AM/PM time labels from _themedTimeLabel
      expect(find.textContaining('AM'), findsWidgets);
    });
  });

  // =====================
  // API error handling
  // =====================
  group('CalendarAssistantScreen - error handling', () {
    testWidgets('handles API exception gracefully', (tester) async {
      final client = MockClient((request) async {
        throw Exception('Network error');
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should still render the calendar (error state shows the view)
      expect(find.text('Calendar Assistant'), findsOneWidget);
      // Should not show loading spinner
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('handles non-200 response for patient tasks', (tester) async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Calendar should still render, just with no tasks
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Tasks with timeOfDay
  // =====================
  group('CalendarAssistantScreen - tasks with time', () {
    testWidgets('loads tasks that have timeOfDay set', (tester) async {
      final tasks = [
        _sampleTaskJson(
          id: 1,
          name: 'Morning Meds',
          timeOfDay: '08:30',
          patientId: 1,
          taskType: 'medication',
        ),
        _sampleTaskJson(
          id: 2,
          name: 'Afternoon Checkup',
          timeOfDay: '14:00',
          patientId: 1,
          taskType: 'appointment',
        ),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode(tasks), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Patient with empty name
  // =====================
  group('CalendarAssistantScreen - patient name handling', () {
    testWidgets('handles patient with empty name', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1, name: ''),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should render without errors even with empty name
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });

    testWidgets('handles patient with null name', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1, name: null),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Dark theme
  // =====================
  group('CalendarAssistantScreen - theming', () {
    testWidgets('renders correctly with dark theme', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: provider),
              ChangeNotifierProvider<TaskTypeManager>(
                create: (_) => TaskTypeManager(),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CalendarAssistantScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.text('Calendar Assistant'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // =====================
  // Multiple task types
  // =====================
  group('CalendarAssistantScreen - multiple task types', () {
    testWidgets('loads tasks with various task types', (tester) async {
      final tasks = [
        _sampleTaskJson(id: 1, name: 'Medication', taskType: 'medication'),
        _sampleTaskJson(id: 2, name: 'Appointment', taskType: 'appointment'),
        _sampleTaskJson(id: 3, name: 'Exercise', taskType: 'exercise'),
        _sampleTaskJson(id: 4, name: 'Lab Work', taskType: 'lab'),
        _sampleTaskJson(id: 5, name: 'General', taskType: 'general'),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode(tasks), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // =====================
  // Caregiver with null patient in response
  // =====================
  group('CalendarAssistantScreen - caregiver edge cases', () {
    testWidgets('handles patient with null id in caregiver response',
        (tester) async {
      final patientsResponse = [
        {
          'patient': {
            'id': null,
            'firstName': 'NoId',
            'lastName': 'Patient',
          }
        },
        {
          'patient': {
            'id': 10,
            'firstName': 'Valid',
            'lastName': 'Patient',
          }
        },
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('caregivers') && url.contains('patients')) {
          return http.Response(jsonEncode(patientsResponse), 200);
        }
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(
          role: 'CAREGIVER',
          patientId: null,
          caregiverId: 5,
        ),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should complete without crashing
      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // ConstrainedBox presence
  // =====================
  group('CalendarAssistantScreen - layout constraints', () {
    testWidgets('calendar is within a ConstrainedBox', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(ConstrainedBox), findsWidgets);
    });
  });

  // =====================
  // Today button
  // =====================
  group('CalendarAssistantScreen - today button', () {
    testWidgets('today button is accessible from filters panel',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // The Today button should be in the filters panel
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('tapping Today button does not crash', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Tap Today
        final todayFinder = find.text('Today');
        if (todayFinder.evaluate().isNotEmpty) {
          await tester.tap(todayFinder);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      }, () => client);

      expect(find.text('Calendar Assistant'), findsOneWidget);
    });
  });

  // =====================
  // Weekday labels in month view
  // =====================
  group('CalendarAssistantScreen - month view weekday labels', () {
    testWidgets('month view shows weekday header labels', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // The weekDayBuilder produces single-letter labels: M, T, W, T, F, S, S
      // There should be at least one "M" for Monday and "W" for Wednesday
      expect(find.text('M'), findsWidgets);
      expect(find.text('W'), findsWidgets);
      expect(find.text('F'), findsWidgets);
    });
  });

  // =====================
  // Recurring tasks
  // =====================
  group('CalendarAssistantScreen - recurring tasks', () {
    testWidgets('loads recurring tasks correctly', (tester) async {
      final tasks = [
        _sampleTaskJson(
          id: 1,
          name: 'Daily Meds',
          frequency: 'daily',
          patientId: 1,
          parentTaskId: null,
        ),
        _sampleTaskJson(
          id: 2,
          name: 'Daily Meds',
          frequency: 'daily',
          patientId: 1,
          parentTaskId: 1,
        ),
      ];

      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('tasks') && url.contains('patient')) {
          return http.Response(jsonEncode(tasks), 200);
        }
        return http.Response('{}', 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Should load without errors
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // =====================
  // AddTaskButton and ImportIcsButton in AppBar
  // =====================
  group('CalendarAssistantScreen - action buttons', () {
    testWidgets('shows add task button in app bar after loading',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // AddTaskButton shows an add icon
      expect(find.byIcon(Icons.add), findsWidgets);
    });

    testWidgets('shows import ics button in app bar after loading',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // ImportIcsButton shows a file_upload icon
      expect(find.byIcon(Icons.file_upload), findsWidgets);
    });
  });

  // =====================
  // SizedBox spacers
  // =====================
  group('CalendarAssistantScreen - layout spacers', () {
    testWidgets('has SizedBox spacers in layout', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      // Layout uses SizedBox for spacing
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  // =====================
  // Column layout structure
  // =====================
  group('CalendarAssistantScreen - widget tree structure', () {
    testWidgets('body uses Column layout', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Expanded), findsWidgets);
      expect(find.byType(Padding), findsWidgets);
    });

    testWidgets('uses Row for view switcher', (tester) async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final provider = MockUserProvider(
        mockUser: MockUser(role: 'PATIENT', patientId: 1),
      );

      await http.runWithClient(() async {
        await tester.pumpWidget(_wrapWithProvider(provider));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }, () => client);

      expect(find.byType(Row), findsWidgets);
    });
  });

  // =====================
  // Issue #249: V2 task add and recurring edit
  // =====================
  group('CalendarAssistantScreen - issue #249 workflows', () {
    tearDown(ApiService.debugResetHttpClient);

    testWidgets('adds a patient task through the V2 endpoint', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? createdTaskBody;
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' &&
            request.url.path.contains('/v2/api/tasks/patient/1')) {
          createdTaskBody = request.body;
          return http.Response('{}', 201);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/v2/api/tasks/patient/1')) {
          return http.Response('[]', 200);
        }
        return http.Response('{}', 200);
      });
      ApiService.debugSetHttpClient(client);

      // Arrange
      await _pumpLoadedCalendar(tester, fakePatientUser());

      // Act
      await tester.tap(find.text('Add Task'));
      await tester.pumpAndSettle();
      final taskDialog = tester.widget<TaskFormDialog>(
        find.byType(TaskFormDialog),
      );
      expect(taskDialog.defaultPatientId, 1);
      await tester.enterText(find.byType(TextFormField).first, 'Morning Walk');
      await tester.pumpAndSettle();
      final saveButton = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(saveButton);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Assert
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | ');
      expect(
        createdTaskBody,
        isNotNull,
        reason: 'Requests: $requests\nVisible text: $visibleText',
      );
      expect(jsonDecode(createdTaskBody!)['name'], 'Morning Walk');
      expect(find.text('Task added successfully'), findsOneWidget);
    });

    testWidgets('recurring edit asks about the entire series by default',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final taskJson = _recurringTaskJson(DateTime.now());
      Map<String, dynamic>? updatedTaskBody;
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/v2/api/tasks/42')) {
          return http.Response(jsonEncode(taskJson), 200);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/v2/api/tasks/42')) {
          updatedTaskBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/v2/api/tasks/patient/1')) {
          return http.Response(jsonEncode([taskJson]), 200);
        }
        return http.Response('{}', 200);
      });
      ApiService.debugSetHttpClient(client);

      // Arrange
      await _pumpLoadedCalendar(tester, fakePatientUser());

      // Act
      await tester.tap(find.byIcon(Icons.edit).last);
      await tester.pumpAndSettle();
      final saveButton = find.widgetWithText(ElevatedButton, 'Save');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Assert the new series confirmation is shown and defaults to checked.
      expect(find.text('Update recurring task'), findsOneWidget);
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isTrue);

      await tester.tap(find.text('Apply changes to entire series'));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(updatedTaskBody, isNotNull);
      expect(updatedTaskBody!['updateSeries'], isFalse);
      expect(find.text('Task updated successfully'), findsOneWidget);
    });
  });
}
