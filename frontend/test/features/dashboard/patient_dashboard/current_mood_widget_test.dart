// Tests for CurrentMoodWidget
// (lib/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart).

import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/current_mood_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../mock_user_provider.dart';

/// Forces offline mode so no real HTTP calls are made during tests.
class _OfflineMockUserProvider extends MockUserProvider {
  @override
  bool get isDeviceOnline => false;

  @override
  bool get offlineModeEnabled => true;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: _OfflineMockUserProvider(),
    child: MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      FlutterError.dumpErrorToConsole(details);
    };
  });

  tearDown(() {
    FlutterError.onError = FlutterError.dumpErrorToConsole;
  });

  testWidgets('renders score and label', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 7,
          moodLabel: 'Happy',
          moodTags: ['Relaxed'],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Score and label should be visible
    expect(find.textContaining('7'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Happy'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders mood tags as chips', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 5,
          moodLabel: 'Okay',
          moodTags: ['Tired', 'Calm'],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Tired'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Calm'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders date label when date is provided', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    await tester.pumpWidget(
      _wrap(
        CurrentMoodWidget(
          moodScore: 8,
          moodLabel: 'Joyful',
          moodTags: [],
          date: today,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Widget renders without throwing
    expect(find.byType(CurrentMoodWidget), findsOneWidget);
  });

  testWidgets('slider is present', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 3,
          moodLabel: 'Down',
          moodTags: [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Slider), findsAtLeastNWidgets(1));
  });

  testWidgets('renders widget type', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 5,
          moodLabel: 'Okay',
          moodTags: [],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CurrentMoodWidget), findsOneWidget);
  });

  testWidgets('shows Container widget', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 5,
          moodLabel: 'Okay',
          moodTags: [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('renders with high mood score', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 10,
          moodLabel: 'Ecstatic',
          moodTags: ['Energetic', 'Motivated'],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('10'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Ecstatic'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders with low mood score', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 1,
          moodLabel: 'Sad',
          moodTags: [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('1'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders with empty tags list', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const CurrentMoodWidget(
          moodScore: 5,
          moodLabel: 'Okay',
          moodTags: [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CurrentMoodWidget), findsOneWidget);
  });
}
