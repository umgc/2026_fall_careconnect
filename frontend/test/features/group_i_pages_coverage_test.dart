// Coverage-focused page tests (group I): form validators, date pickers,
// dismissible rows and callback wiring.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/dashboards/participation_screen.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-add-input-form.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-header.dart';
import 'package:care_connect_app/features/social/in-app-chat/pages/message-list.dart';
import 'package:care_connect_app/features/tasks/presentation/pre_defined_task_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';
import 'package:care_connect_app/widgets/manual_text_entry_upload.dart';

import '../mock_user_provider.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void _api(http.Response Function(http.Request) handler) {
  ApiService.debugSetHttpClient(MockClient((req) async => handler(req)));
  addTearDown(ApiService.debugResetHttpClient);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure,
            (call) async => call.method == 'readAll' ? <String, String>{} : null);
  });

  group('ManualTextEntryCard', () {
    testWidgets('validators report empty and invalid input', (tester) async {
      _bigView(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: UserProvider(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(key: formKey, child: const ManualTextEntryCard()),
            ),
          ),
        ),
      ));
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text(t.manualentrywidget_noCateSelected), findsOneWidget);
      expect(find.text(t.manualentrywidget_fileNameEmpty), findsOneWidget);
      expect(find.text(t.manualentrywidget_fileContentEmpty), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'bad name!');
      formKey.currentState!.validate();
      await tester.pump();
      expect(find.text(t.manualentrywidget_invalidCharacters), findsOneWidget);
    });

    testWidgets('upload without a logged in user shows error', (tester) async {
      _bigView(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      final errors = <String>[];
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: UserProvider(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManualTextEntryCard(onUploadError: errors.add),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(FileCategory.clinicalNotes.icon).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'note');
      await tester.enterText(find.byType(TextFormField).at(1), 'Body');
      await tester.tap(find.text(t.manualentrywidget_saveToFile));
      await tester.pump();
      expect(errors.single, contains(t.manualentrywidget_userNotLogged));
    });
  });

  group('ParticipationScreen date range dialog', () {
    testWidgets('picking From and To dates updates the range', (tester) async {
      _bigView(tester);
      _api((_) => http.Response(
          jsonEncode({
            'status': 'STABLE',
            'weeklyCounts': [
              {'weekStartDate': '2026-09-07', 'totalLogs': 2},
            ],
            'activities': [
              {
                'activityId': 1,
                'activityName': 'Bathing',
                'category': 'adl',
                'totalLogsInPeriod': 6,
                'lastLoggedAt': '2026-09-29T10:15:00',
                'noRecentActivity': false,
              },
            ],
          }),
          200));
      await tester.pumpWidget(const MaterialApp(
          home: ParticipationScreen(clientId: 7, clientName: 'Jane Doe')));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      expect(find.text('Select date range'), findsOneWidget);

      await tester.tap(find.text('From'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('To'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Select date range'), findsOneWidget);
    });
  });

  group('MessagesListPage', () {
    testWidgets('swipe deletes a conversation and old dates render',
        (tester) async {
      _bigView(tester);
      SharedPreferences.setMockInitialValues({
        'local_messages': jsonEncode({
          '1_2': [
            {
              'senderName': 'Romilda Smith',
              'message': 'See you at 3',
              'messageType': 'Patient',
              'timestamp': '2020-01-05T15:00:00',
              'read': true,
            }
          ],
          '1_3': [
            {
              'senderName': 'Bad Stamp',
              'message': 'Hi',
              'timestamp': 'not-a-date',
            }
          ],
        }),
      });
      await tester.pumpWidget(const MaterialApp(home: MessagesListPage()));
      await tester.pumpAndSettle();
      expect(find.text('Romilda Smith'), findsOneWidget);
      expect(find.text('1/5/2020'), findsOneWidget);

      await tester.drag(find.text('Romilda Smith'), const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(find.text('Romilda Smith'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_messages'), isNot(contains('1_2')));
    });
  });

  group('MedicationsTrackerPage callbacks', () {
    testWidgets('status change, removal refresh and add modal', (tester) async {
      _bigView(tester);
      _api((_) => http.Response(
          jsonEncode([
            {
              'id': 1,
              'patientId': 12,
              'medicationName': 'Lisinopril',
              'dosage': '10 mg',
              'frequency': 'Once daily',
              'route': 'Oral',
              'medicationType': 'PRESCRIPTION',
              'isActive': true,
            }
          ]),
          200));
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
            mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 12)),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MedicationsTrackerPage(),
        ),
      ));
      await _settle(tester);
      expect(find.text('Lisinopril'), findsOneWidget);

      final card = tester.widget<MedicationCard>(find.byType(MedicationCard));
      card.onStatusChanged(MedicationStatus.taken);
      await tester.pump();
      card.onMedicationRemoved!();
      await _settle(tester);

      tester
          .widget<MedicationAppHeader>(find.byType(MedicationAppHeader))
          .onAddPressed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final modal =
          tester.widget<AddMedicationModal>(find.byType(AddMedicationModal));
      modal.onMedicationAdded(Medication.fromJson({
        'id': 2,
        'patientId': 12,
        'medicationName': 'Metformin',
        'dosage': '5 mg',
        'frequency': 'Daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
        'isActive': true,
      }));
      await tester.pump();
      expect(find.byType(MedicationsTrackerPage), findsOneWidget);
    });
  });

  group('PreDefinedTaskScreen', () {
    testWidgets('loads template and shows offline-queued snackbar',
        (tester) async {
      _bigView(tester);
      _api((req) => http.Response(
            jsonEncode({
              'id': 3,
              'name': 'Morning walk',
              'description': 'Walk outside',
              'frequency': 'DAILY',
              'taskInterval': 1,
              'doCount': 2,
              'timeOfDay': '08:30',
            }),
            200,
            headers: {'x-offline-queued': 'true'},
          ));
      await tester.pumpWidget(const MaterialApp(
        home: PreDefinedTaskScreen(
            patientId: 1, templateId: 3, patientName: 'Bob'),
      ));
      await _settle(tester);
      expect(find.text('Predefined Task Scheduling'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton).last);
      await _settle(tester);
      expect(find.text('Task queued for sync when internet is restored'),
          findsOneWidget);
    });
  });
}
