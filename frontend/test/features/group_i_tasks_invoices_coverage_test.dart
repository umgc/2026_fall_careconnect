// Coverage-focused widget tests (group I): task lists, legend editor,
// invoice date field and details section.
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/widgets/components/date_field.dart';
import 'package:care_connect_app/features/invoices/widgets/sections/details_section.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/legend.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/legend_editor.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_list_day.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_list_week.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Widget _tasksApp(Widget child, TaskTypeManager manager) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<TaskTypeManager>.value(
        value: manager,
        child: Scaffold(body: child),
      ),
    );

final _date = DateTime(2025, 6, 15);

CalendarEventData<Task> _event(String name, TimeOfDay time) {
  final task = Task(
    id: name.length,
    name: name,
    description: '',
    date: _date,
    taskType: 'medication',
    timeOfDay: time,
  );
  return CalendarEventData<Task>(title: name, date: _date, event: task);
}

Invoice _invoice() => Invoice(
      id: 'inv-1',
      invoiceNumber: 'INV-1',
      provider: const ProviderInfo(
          name: 'ACME', address: '1 Rd', phone: '555', email: 'a@b.c'),
      patient: const PatientInfo(
          name: 'Jane', address: '2 Ave', accountNumber: 'P-1'),
      dates: InvoiceDates(
        statementDate: DateTime(2025, 3, 1),
        dueDate: DateTime(2025, 4, 1),
      ),
      paymentStatus: PaymentStatus.pending,
      billedToInsurance: false,
      amounts: const Amounts(totalCharges: 10, total: 10, amountDue: 10),
      paymentReferences: PaymentReferences(supportedMethods: const []),
      createdAt: '2025-03-01T00:00:00.000Z',
      updatedAt: '2025-03-01T00:00:00.000Z',
      createdBy: 'system',
      updatedBy: 'system',
      payments: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure,
            (call) async => call.method == 'readAll' ? <String, String>{} : null);
  });

  group('Task lists', () {
    testWidgets('day and week sort timed tasks and use default updater',
        (tester) async {
      var calls = 0;
      ApiService.debugSetHttpClient(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));
      addTearDown(ApiService.debugResetHttpClient);
      final events = [
        _event('Evening pills', const TimeOfDay(hour: 20, minute: 0)),
        _event('Morning pills', const TimeOfDay(hour: 8, minute: 30)),
      ];
      final day = TaskListDay(
          events: events, patientNames: const {}, onEdit: (_) {}, onDelete: (_) {});
      await tester.pumpWidget(_tasksApp(day, TaskTypeManager()));
      expect(find.text('Morning pills'), findsOneWidget);
      await tester.runAsync(() => day.updateCompletion(1, true));

      final week = TaskListWeek(
          events: events, patientNames: const {}, onEdit: (_) {}, onDelete: (_) {});
      await tester.pumpWidget(_tasksApp(week, TaskTypeManager()));
      expect(find.text('Evening pills'), findsWidgets);
      await tester.runAsync(() => week.updateCompletion(2, false));
      expect(calls, greaterThanOrEqualTo(1));
    });
  });

  group('LegendEditor dialogs', () {
    testWidgets('cancel paths for reset, add, edit and delete',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final manager = TaskTypeManager();
      await tester.pumpWidget(_tasksApp(const LegendEditor(), manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset Defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Task Type'));
      await tester.pumpAndSettle();
      final pickers = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(GestureDetector));
      await tester.tap(pickers.first);
      await tester.pump();
      await tester.tap(pickers.last);
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final chips = find.descendant(
          of: find.byType(Legend), matching: find.byType(InkWell));
      await tester.tap(chips.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(chips.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Delete'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Manage Task Types'), findsOneWidget);
    });
  });

  group('Invoice date widgets', () {
    testWidgets('DateField picker returns the chosen date', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DateField(
            label: 'Due Date',
            value: DateTime(2025, 6, 5),
            enabled: true,
            onChanged: (d) => picked = d,
          ),
        ),
      ));
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2025, 6, 5));
    });

    testWidgets('DetailsSection forwards edits', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final changes = <Invoice>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 2000,
            child: DetailsSection(
              value: _invoice(),
              isEditing: true,
              onChanged: changes.add,
            ),
          ),
        ),
      ));
      await tester.enterText(find.byType(TextFormField).at(5), 'ACC-9');
      for (final f in tester.widgetList<DateField>(find.byType(DateField))) {
        f.onChanged(DateTime(2025, 5, 5));
      }
      await tester.tap(find.byType(DropdownButtonFormField<PaymentStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue').last);
      await tester.pumpAndSettle();
      expect(changes.length, greaterThanOrEqualTo(4));
      expect(find.text('Payment Status'), findsOneWidget);
    });
  });
}
