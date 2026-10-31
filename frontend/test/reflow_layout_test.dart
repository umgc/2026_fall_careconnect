import 'dart:io';
import 'dart:convert';

import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_dashboard.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/wrapping_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_user_provider.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';

class _NoUser extends MockUserProvider {
  @override
  UserSession? get user => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the app's actual font metrics rather than the wide Ahem test font.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((package) => package['name'] == 'flutter');
    final sdk =
        Directory.fromUri(configFile.uri.resolve(flutter['rootUri'] as String))
            .parent
            .parent
            .uri;
    // Roboto ships with the tests (test/fixtures/fonts, Apache 2.0) because
    // CI's Flutter cache doesn't include it; the SDK copy is the fallback.
    final loader = FontLoader('Roboto');
    for (final font in ['regular', 'medium', 'bold']) {
      final bundled = File('test/fixtures/fonts/roboto-$font.ttf');
      final file = bundled.existsSync()
          ? bundled
          : File.fromUri(sdk
              .resolve('bin/cache/artifacts/material_fonts/roboto-$font.ttf'));
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  void viewport(WidgetTester tester, double height) {
    tester.view.physicalSize = Size(320, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(Widget child, double scale) => MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      );

  for (final width in [320.0, 800.0]) {
    for (final role in ['PATIENT', 'CAREGIVER']) {
      testWidgets('dashboard header reflows at $width / 200% / $role',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const bodyKey = ValueKey('dashboard-body');
        Widget dashboard(double scale) => app(
              Builder(
                  builder: (context) => Scaffold(
                        appBar: DashboardAppHeader(
                          context: context,
                          userName: 'Alexandra Montgomery',
                          role: role,
                        ),
                        body: const SizedBox.expand(key: bodyKey),
                      )),
              scale,
            );
        await tester.pumpWidget(dashboard(1.2));
        await tester.pumpAndSettle();
        final originalHeight = tester.getSize(find.byType(AppBar)).height;

        await tester.pumpWidget(dashboard(2));
        await tester.pumpAndSettle();
        final header = tester.getRect(find.byType(AppBar));
        final body = tester.getRect(find.byKey(bodyKey));
        expect(header.height, greaterThan(originalHeight));
        expect(header.bottom, lessThanOrEqualTo(body.top));
        for (final text in tester.widgetList<Text>(find.descendant(
            of: find.byType(DashboardAppHeader),
            matching: find.byType(Text)))) {
          final finder = find.byWidget(text);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          final rect = tester.getRect(finder);
          expect(rect.bottom, lessThanOrEqualTo(header.bottom));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final height in [568.0, 256.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full app-bar title at 320 x $height and ${scale}x text',
          (tester) async {
        viewport(tester, height);
        await tester.pumpWidget(app(
            Builder(
                builder: (context) => Scaffold(
                      appBar: AppBarHelper.createAppBar(context,
                          title: 'Medication Management',
                          additionalActions: [
                            IconButton(
                                onPressed: () {}, icon: const Icon(Icons.add))
                          ]),
                    )),
            scale));
        await tester.pumpAndSettle();
        final paragraph = tester
            .renderObject<RenderParagraph>(find.text('Medication Management'));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getRect(find.text('Medication Management')).right,
            lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'all navigation labels and destinations at 320 x $height / ${scale}x',
          (tester) async {
        viewport(tester, height);
        const labels = [
          'Home',
          'Symptoms and Allergies',
          'Virtual Check-In',
          'Messages',
          'Schedule',
          'Menu'
        ];
        int? destination;
        await tester.pumpWidget(app(
            Scaffold(
              body: const Text('Content'),
              bottomNavigationBar: WrappingBottomNavigationBar(
                labels: labels,
                icons:
                    List.generate(labels.length, (_) => const Icon(Icons.home)),
                selectedIndex: 0,
                onSelected: (index) => destination = index,
                selectedColor: Colors.teal,
                unselectedColor: Colors.black,
              ),
            ),
            scale));
        await tester.pumpAndSettle();
        for (final label in labels) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
              tester.getRect(find.text(label)).right, lessThanOrEqualTo(320));
        }
        await tester.ensureVisible(find.text('Messages'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Messages'));
        expect(destination, 3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('calendar month fits all rows at 320 x $height / ${scale}x',
          (tester) async {
        viewport(tester, height);
        final imageKey = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: imageKey,
            child: app(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider<UserProvider>.value(
                        value: _NoUser()),
                    ChangeNotifierProvider(create: (_) => TaskTypeManager()),
                  ],
                  child: const CalendarAssistantScreen(),
                ),
                scale)));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('calendar-page-scroll')), findsOneWidget);
        final month = find.byType(MonthView<Task>);
        expect(month, findsOneWidget);
        final states = tester.stateList<ScrollableState>(
            find.descendant(of: month, matching: find.byType(Scrollable)));
        for (final state
            in states.where((state) => state.widget.axis == Axis.vertical)) {
          expect(state.position.maxScrollExtent, lessThanOrEqualTo(1));
        }
        final today = DateTime.now();
        final lastDate = DateTime(today.year, today.month + 1, 0).day;
        final lastDay =
            find.descendant(of: month, matching: find.text('$lastDate')).last;
        await tester.ensureVisible(lastDay);
        await tester.pumpAndSettle();
        expect(lastDay.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('EVV actions remain unobscured at 320 x $height / ${scale}x',
          (tester) async {
        viewport(tester, height);
        await tester.pumpWidget(app(
            ChangeNotifierProvider<UserProvider>.value(
              value: MockUserProvider(
                  mockUser: MockUser(id: 1, role: 'CAREGIVER')),
              child: const EvvDashboard(),
            ),
            scale));
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('Start Visit'), findsOneWidget);
        // The test HTTP stub produces a temporary error snackbar.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Visit Schedules'));
        await tester.pumpAndSettle();
        expect(find.text('Visit Schedules').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
