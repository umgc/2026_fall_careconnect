// Coverage-focused widget tests for small widgets/pages (group I).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/presentation/hitl_queue_page.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:care_connect_app/features/condition_detection/models/condition_flags.dart';
import 'package:care_connect_app/features/condition_detection/presentation/widgets/condition_flags_card.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/mood_history_card.dart';
import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_event_details_screen.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/home_monitoring_screen.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_piece_image.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/shortcut_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/language/language_picker.dart';
import 'package:care_connect_app/widgets/menu/shortcut_search_delegate.dart';

class _FakeHitlApi implements HitlApiService {
  _FakeHitlApi({this.fail = false, this.items = const []});
  final bool fail;
  final List<HitlQueueItem> items;
  int calls = 0;

  @override
  Future<List<HitlQueueItem>> fetchQueue(
      {Duration timeout = const Duration(seconds: 20), client}) async {
    calls++;
    if (fail) throw const HitlApiException(500, 'server down');
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _l10nApp(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HitlQueuePage', () {
    testWidgets('shows error text when queue fails', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: HitlQueuePage(api: _FakeHitlApi(fail: true))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to load the review queue.'),
          findsOneWidget);
      expect(find.textContaining('server down'), findsOneWidget);
    });

    testWidgets('refresh reloads and lists multiple items', (tester) async {
      final api = _FakeHitlApi(items: const [
        HitlQueueItem(heldItemId: 'a', patientId: 1),
        HitlQueueItem(
            heldItemId: 'b', patientId: 2, queryPreview: 'Dose question'),
      ]);
      await tester.pumpWidget(MaterialApp(home: HitlQueuePage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Held Ask AI answer'), findsOneWidget);
      expect(find.text('Patient 1 · Review required'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hitl-queue-refresh')));
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      expect(find.text('AI review queue'), findsOneWidget);
    });
  });

  group('MoodHistorySection', () {
    testWidgets('fallback row and label-derived emojis', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodHistorySection(entries: [
              MoodHistoryEntry(date: DateTime(2024, 3, 5), label: 'Unknown'),
              MoodHistoryEntry(
                  date: DateTime(2024, 4, 6), label: 'Excellent', score10: 9),
              MoodHistoryEntry(
                  date: DateTime(2024, 4, 7), label: 'Mystery', score10: 4),
            ]),
          ),
        ),
      ));
      expect(find.text('Mood History'), findsOneWidget);
      expect(find.text('Missing score for Unknown on Mar 5'), findsOneWidget);
      expect(find.text('😄'), findsOneWidget);
    });
  });

  group('MailPieceImage', () {
    testWidgets('undecodable data URL falls back to missing state',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            MailPieceImage(imageRef: 'data:image/png;base64,AAAA'),
            MailPieceImage(imageRef: 'data:%zz,AAAA'),
            MailPieceImage(imageRef: 'data:%zz,***'),
          ]),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.byKey(MailPieceImage.missingNormalKey), findsWidgets);
    });
  });

  group('ShortcutSearchDelegate navigation', () {
    Future<ShortcutProvider> provider() async {
      final sp = ShortcutProvider();
      await sp.init();
      return sp;
    }

    Widget app(ShortcutProvider sp) {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showSearch(
                  context: context,
                  delegate:
                      ShortcutSearchDelegate(roleUpper: 'CAREGIVER', userId: '1'),
                ),
                child: const Text('Search'),
              ),
            ),
          ),
        ],
        errorBuilder: (_, __) => const Scaffold(body: Text('Landed')),
      );
      return ChangeNotifierProvider<ShortcutProvider>.value(
        value: sp,
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('results view, long-press toggle and tap navigates',
        (tester) async {
      final sp = await provider();
      await tester.pumpWidget(app(sp));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dash');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      await tester.longPress(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Landed'), findsOneWidget);
    });
  });

  group('LanguagePicker', () {
    Widget app(LocaleProvider p) => ChangeNotifierProvider<LocaleProvider>.value(
          value: p,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en'), Locale('es')],
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => LanguagePicker.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('close button and selecting English', (tester) async {
      final p = LocaleProvider();
      await tester.pumpWidget(app(p));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(p.locale?.languageCode, 'en');
    });
  });

  group('ConditionFlagsCard severities', () {
    testWidgets('renders low/mild/moderate/severe labels', (tester) async {
      final result = ConditionFlagsResult.fromJson({
        'disclaimer': 'Not a diagnosis.',
        'runs': [
          {
            'modelId': ConditionFlagsCard.voiceModelId,
            'displayName': 'Voice',
            'inputKind': 'PATIENT_AUDIO',
            'status': 'COMPLETE',
            'completedAt': '2026-10-07T21:00:00Z',
            'flags': [
              {'condition': 'DEPRESSION', 'severityLevel': 1, 'severityLabel': 'LOW'},
              {'condition': 'ANXIETY', 'severityLevel': 1, 'severityLabel': 'MILD'},
              {'condition': 'PTSD', 'severityLevel': 2, 'severityLabel': 'MODERATE'},
              {'condition': 'BIPOLAR', 'severityLevel': 3, 'severityLabel': 'SEVERE'},
            ],
          },
        ],
      });
      await tester.pumpWidget(_l10nApp(Scaffold(
          body: SingleChildScrollView(child: ConditionFlagsCard(result: result)))));
      await tester.pump();
      expect(find.byKey(const Key('conditionFlagsCard')), findsOneWidget);
      expect(find.textContaining('Severe'), findsWidgets);
    });
  });

  group('HealthEventDetailsScreen record types', () {
    for (final type in [
      RecordType.medication,
      RecordType.clinicalRecord,
      RecordType.other,
    ]) {
      testWidgets('renders ${type.name}', (tester) async {
        await tester.pumpWidget(_l10nApp(HealthEventDetailsScreen(
          record: HealthRecord.single(
            id: 'r-${type.name}',
            source: RecordSource.medicare,
            type: type,
            title: 'Record ${type.name}',
          ),
        )));
        expect(find.text('Record ${type.name}'), findsOneWidget);
        expect(find.text('Health Event Details'), findsOneWidget);
      });
    }
  });

  group('HomeMonitoringScreen add camera', () {
    testWidgets('OK shows coming soon snackbar', (tester) async {
      final provider = UserProvider()
        ..setUser(UserSession(
            id: 1, email: 'cg@example.com', role: 'CAREGIVER', token: 't'));
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeMonitoringScreen()),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('Nest camera setup coming soon!'), findsOneWidget);
    });
  });
}
