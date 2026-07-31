import 'dart:convert';

import 'package:care_connect_app/features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mock_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets('caregiver dashboard requires explicit linked patient selection',
      (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/caregivers/') &&
          request.url.path.endsWith('/patients')) {
        return http.Response(
          jsonEncode([
            {
              'patient': {
                'id': 42,
                'firstName': 'Ada',
                'lastName': 'Patient',
              },
              'link': {
                'status': 'ACTIVE',
                'isActive': true,
                'patientName': 'Ada Patient',
              },
            },
            {
              'patient': {
                'id': 77,
                'firstName': 'Inactive',
                'lastName': 'Link',
              },
              'link': {
                'status': 'SUSPENDED',
                'isActive': false,
                'patientName': 'Inactive Link',
              },
            },
          ]),
          200,
        );
      }
      return http.Response('[]', 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
            mockUser: MockUser(
              id: 9,
              role: 'CAREGIVER',
              caregiverId: 3,
              patientId: 999, // must never be inferred
            ),
          ),
          child: const MaterialApp(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,home: CaregiverDashboard()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('caregiver-ask-ai-patient-picker')),
          findsOneWidget);
      expect(find.text('Ada Patient'), findsOneWidget);
      expect(find.text('Inactive Link'), findsNothing);

      await tester.tap(find.byKey(const Key('caregiver-ask-ai-patient-42')));
      await tester.pumpAndSettle();

      final chat = tester.widget<AIChat>(find.byType(AIChat));
      expect(chat.mode, AiChatMode.groundedRecords);
      expect(chat.patientId, 42);
      expect(chat.patientId, isNot(999));
      expect(chat.key, isA<ValueKey<String>>());
    }, () => mockClient);
  });
}
