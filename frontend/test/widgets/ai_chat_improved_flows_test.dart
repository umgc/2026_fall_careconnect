// Additional AIChat flows: voice input and spoken answers, confirmation
// decisions, delivery-status variants, HITL resume, citation links, legacy
// file uploads and the inactivity reset.
//
// Companion to ai_chat_improved_test.dart, which covers rendering, the popup
// menu, history loading and the main Ask AI paths. Speech recognition is
// driven through the speech_to_text method channel; the plugin keeps a
// process-wide singleton, so the "unavailable" test must run before any test
// whose mocked initialize succeeds.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/tts_engine.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

const _speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const _requestId = '8aa0d978-a8fc-48bc-ab02-1af24f32e903';
const _sessionId = 'fd43f38b-ac0e-4adf-af84-d25992ce7855';
const _heldId = '11111111-1111-1111-1111-111111111111';

class _Tts implements TtsEngine {
  _Tts({this.failSetup = false, this.failAwait = false});

  final bool failSetup;
  final bool failAwait;
  final List<String> spoken = <String>[];
  int stopCount = 0;
  Completer<void>? holdSpeech;

  @override
  Future<dynamic> setLanguage(String language) async {
    if (failSetup) throw StateError('no tts');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    if (failAwait) throw UnsupportedError('no await');
    return null;
  }

  @override
  Future<dynamic> speak(String text) async {
    spoken.add(text);
    final hold = holdSpeech;
    if (hold != null) await hold.future;
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stopCount++;
    return 1;
  }
}

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return result;
  }
}

Map<String, dynamic> _delivered(
  String answer, {
  Map<String, dynamic>? escalation,
  List<Map<String, dynamic>>? citations,
}) =>
    {
      'success': true,
      'deliveryStatus': 'DELIVERED',
      'requestId': _requestId,
      'sessionId': _sessionId,
      'answer': {'text': answer},
      'citations': citations ??
          [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Record excerpt',
            },
          ],
      'disclaimer': {
        'text': 'Records-based information; not medical advice.',
        'aiNoticeRequired': true,
        'recordsBasedFraming': true,
        'locale': 'en-US',
      },
      'escalation': escalation ??
          {
            'tier': 1,
            'reason': 'Tier1_auto_deliver',
            'requiresClinicianReview': false,
          },
      'confirmation': {
        'promptConfirmWithProvider': true,
        'message': 'Confirm important details with your care provider.',
      },
    };

Widget _buildChat({
  AiChatMode mode = AiChatMode.groundedRecords,
  int? patientId = 42,
  int? userId = 1,
  bool isModal = false,
  TtsEngine? tts,
  int hitlMaxPollAttempts = 1,
}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(mockUser: MockUser(id: 1, role: 'PATIENT')),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AIChat(
          role: 'PATIENT',
          mode: mode,
          patientId: patientId,
          userId: userId,
          isModal: isModal,
          ttsEngine: tts ?? _Tts(),
          hitlMaxPollAttempts: hitlMaxPollAttempts,
          hitlPollInterval: const Duration(milliseconds: 100),
        ),
      ),
    ),
  );
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
      .onPressed!();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _speechEvent(String method, Object? arguments) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _speechChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (ByteData? _) {},
  );
}

String _speechResult(String words, {required bool isFinal}) => jsonEncode({
      'resultType': isFinal ? 2 : 0,
      'alternates': [
        {'recognizedWords': words, 'confidence': 0.9},
      ],
    });

/// testWidgets wrapper that ignores the chat header's RenderFlex overflow at
/// the default test width (as ai_chat_improved_test.dart does) and lets any
/// speech-recognition timers run out after the widget is removed.
void _chatTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      original?.call(details);
    };
    try {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    } finally {
      FlutterError.onError = original;
    }
  });
}

void main() {
  late bool speechAvailable;
  late bool speechInitThrows;
  late bool listenFails;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    speechAvailable = true;
    speechInitThrows = false;
    listenFails = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    messenger.setMockMethodCallHandler(_speechChannel, (call) async {
      switch (call.method) {
        case 'has_permission':
        case 'initialize':
          if (speechInitThrows) {
            throw PlatformException(code: 'no_speech');
          }
          return speechAvailable;
        case 'listen':
          if (listenFails) {
            throw PlatformException(code: 'listen_failed');
          }
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    messenger.setMockMethodCallHandler(_speechChannel, null);
  });

  _chatTest('voice input reports when speech recognition is unavailable',
      (tester) async {
    speechInitThrows = true;
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.text('Speech recognition is unavailable.', skipOffstage: false),
          findsOneWidget);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('a spoken question is sent and its answer is read aloud',
      (tester) async {
    final tts = _Tts()..holdSpeech = Completer<void>();
    final askBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        askBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode(_delivered('**Metformin** _twice_ daily')),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat(tts: tts));
      await tester.pump(const Duration(seconds: 1));

      // Status and error callbacks registered by initialize.
      await _speechEvent('notifyStatus', 'listening');
      await _speechEvent(
        'notifyError',
        jsonEncode({'errorMsg': 'error_no_match', 'permanent': false}),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      expect(find.byTooltip('Stop listening'), findsOneWidget);

      await _speechEvent(
        'textRecognition',
        _speechResult('what do I take', isFinal: false),
      );
      await tester.pump();
      expect(find.text('what do I take', skipOffstage: false), findsOneWidget);

      await _speechEvent(
        'textRecognition',
        _speechResult('what do I take daily', isFinal: true),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(askBodies.single['inputModality'], 'VOICE');
      expect(tts.spoken, ['Metformin twice daily']);
      expect(find.byTooltip('Stop speaking'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      expect(tts.stopCount, greaterThanOrEqualTo(2));
      expect(find.byTooltip('Voice input'), findsOneWidget);
      tts.holdSpeech!.complete();
      await tester.pump();

      await _speechEvent('notifyStatus', 'done');
      await tester.pump();
    }, () => client);
  });

  _chatTest('tapping the mic again stops listening', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      expect(find.byTooltip('Stop listening'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      expect(find.byTooltip('Voice input'), findsOneWidget);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('a listen failure resets the mic', (tester) async {
    listenFails = true;
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Voice input'), findsOneWidget);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('disposing while listening stops recognition', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      expect(find.byTooltip('Stop listening'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('disposing while speaking stops the answer', (tester) async {
    final tts = _Tts()..holdSpeech = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(jsonEncode(_delivered('Answer text')), 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat(tts: tts));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('ask-ai-mic')));
      await tester.pump();
      await _speechEvent(
        'textRecognition',
        _speechResult('question', isFinal: true),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tts.spoken, ['Answer text']);

      // Removing the chat while the answer is still being spoken stops it.
      final stopsBefore = tts.stopCount;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tts.stopCount, stopsBefore + 1);
      tts.holdSpeech!.complete();
      await tester.pump();
    }, () => client);
  });

  _chatTest('text-to-speech setup failures are tolerated', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat(tts: _Tts(failSetup: true)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(_buildChat(
        tts: _Tts(failAwait: true),
        patientId: 43,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('confirmation decisions are recorded or reported as failed',
      (tester) async {
    var confirmCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(
          jsonEncode(_delivered('Take with food.')),
          200,
        );
      }
      if (request.url.path == '/api/ai/ask/confirmation') {
        confirmCalls++;
        return http.Response('{}', confirmCalls < 3 ? 500 : 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await _ask(tester, 'How do I take it?');

      await tester.tap(find.byKey(const Key('ask-ai-confirm-decline')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Could not record confirmation. Please try again.',
            skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ask-ai-confirm-session')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('ask-ai-confirm-once')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ask-ai-confirm-once')), findsNothing);
      expect(confirmCalls, 3);
    }, () => client);
  });

  _chatTest('delivery-status variants render their messages', (tester) async {
    final responses = <Map<String, dynamic>>[
      {'deliveryStatus': 'NO_RECORDS', 'message': 'Nothing on file.'},
      {'deliveryStatus': 'NO_RECORDS'},
      {'deliveryStatus': 'WITHHELD'},
      _delivered('Escalated one', escalation: {
        'tier': 1,
        'reason': 'no_records',
        'requiresClinicianReview': false,
      }),
      _delivered('Escalated two', escalation: {
        'tier': 1,
        'reason': 'hitl_hold',
        'requiresClinicianReview': false,
      }),
      {
        'deliveryStatus': 'NO_RECORDS',
        'message': 'Escalated three',
        'escalation': {
          'tier': 2,
          'reason': 'other_reason',
          'requiresClinicianReview': true,
        },
      },
      _delivered('Escalated four', escalation: {
        'tier': 1,
        'reason': 'other_reason',
        'requiresClinicianReview': false,
      }),
    ];
    var index = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(jsonEncode(responses[index++]), 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      const expected = <String>[
        'Nothing on file.',
        'No matching records were found for this question.',
        'Ask AI could not safely answer this question.',
        'No matching records were reviewed for this question.',
        'This answer was held for clinician review.',
        'Escalated three',
        'Reviewed automatically.',
      ];
      for (var i = 0; i < responses.length; i++) {
        await _ask(tester, 'Question $i');
        expect(
          find.text(expected[i], skipOffstage: false),
          findsOneWidget,
          reason: 'response $i',
        );
      }
    }, () => client);
  });

  _chatTest('a citation deep link that cannot open shows a message',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(
          jsonEncode(_delivered('See record', citations: [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Linked excerpt',
              'deepLink': '/records/1',
            },
          ])),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await _ask(tester, 'Show the record');
      final link = find.textContaining('Linked excerpt', skipOffstage: false);
      await tester.ensureVisible(link);
      await tester.pump();
      await tester.tap(link);
      await tester.pump();
      expect(find.text('Could not open that citation.', skipOffstage: false),
          findsOneWidget);
    }, () => client);
  });

  _chatTest('resuming a timed-out review shows the final outcome',
      (tester) async {
    var polls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(
          jsonEncode({
            'deliveryStatus': 'HELD',
            'held': true,
            'heldItemId': _heldId,
            'message': '  ',
          }),
          200,
        );
      }
      if (request.url.path == '/v1/api/ai/hitl/$_heldId/status') {
        polls++;
        return http.Response(
          jsonEncode(polls == 1
              ? {'status': 'PENDING_REVIEW', 'deliveryStatus': 'HELD'}
              : {
                  'status': 'REJECTED',
                  'deliveryStatus': 'REJECTED',
                  'message': 'A clinician declined to release this.',
                }),
          200,
        );
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await _ask(tester, 'Needs review');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byKey(const Key('ask-ai-hitl-resume')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ask-ai-hitl-resume')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(
        find.text('A clinician declined to release this.', skipOffstage: false),
        findsOneWidget,
      );
      expect(polls, 2);
    }, () => client);
  });

  _chatTest('an expired review without a message uses the fallback',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(
          jsonEncode({
            'deliveryStatus': 'HELD',
            'held': true,
            'heldItemId': _heldId,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'status': 'EXPIRED', 'deliveryStatus': 'HELD'}),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await _ask(tester, 'Old question');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(
        find.text(
          'This answer is no longer available. Please ask again or contact your care provider.',
        ),
        findsOneWidget,
      );
    }, () => client);
  });

  group('legacy general mode', () {
    late _FakeFilePicker picker;

    setUp(() => FilePicker.platform = picker = _FakeFilePicker());

    Widget legacy({bool isModal = false}) => _buildChat(
          mode: AiChatMode.legacyGeneral,
          patientId: null,
          isModal: isModal,
        );

    _chatTest('picked files are previewed, removable and uploaded',
        (tester) async {
      final names = <String>[
        'a.txt',
        'b.csv',
        'c.json',
        'd.xml',
        'e.pdf',
        'f.docx',
        'g.xlsx',
        'h.html',
        'i.py',
        'j.png',
        'k.jpeg',
        'l.gif',
        'm.svg',
        'n.zzz',
      ];
      picker.result = FilePickerResult([
        for (final name in names)
          PlatformFile(name: name, size: 3, bytes: Uint8List.fromList([1, 2])),
        PlatformFile(name: 'unreadable.txt', size: 3),
      ]);
      final release = Completer<void>();
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/chat')) {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          await release.future;
          return http.Response(
            jsonEncode({
              'success': true,
              'aiResponse': 'Files reviewed.',
              'conversationId': 'conv-9',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });
      await http.runWithClient(() async {
        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(legacy());
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.byTooltip('Attach file'));
        await tester.pump();
        await tester.pump();
        expect(
            find.text('Files to upload:', skipOffstage: false), findsOneWidget);
        expect(find.text('unreadable.txt', skipOffstage: false), findsNothing);
        expect(find.text('n.zzz', skipOffstage: false), findsOneWidget);

        tester
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip('Remove').last,
                matching: find.byType(IconButton)))
            .onPressed!();
        await tester.pump();
        expect(find.text('n.zzz', skipOffstage: false), findsNothing);

        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('📎 Uploaded 13 files', skipOffstage: false),
            findsOneWidget);
        expect(
            find.text('📎 Analyzing 13 uploaded files...', skipOffstage: false),
            findsOneWidget);
        expect(find.text('Processing...', skipOffstage: false), findsOneWidget);

        release.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
            find.text('Files reviewed.', skipOffstage: false), findsOneWidget);
        expect(
            find.text('Files to upload:', skipOffstage: false), findsNothing);
      }, () => client);

      final files =
          (sentBody!['uploadedFiles'] as List).cast<Map<String, dynamic>>();
      expect(
        files.map((f) => f['contentType']).toSet(),
        containsAll(<String>[
          'text/plain',
          'text/csv',
          'application/json',
          'application/xml',
          'application/pdf',
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/svg+xml',
          'application/octet-stream',
        ]),
      );
    });

    _chatTest('a single uploaded file is labelled in the singular',
        (tester) async {
      picker.result = FilePickerResult([
        PlatformFile(name: 'only.txt', size: 1, bytes: Uint8List(1)),
      ]);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/chat')) {
          return http.Response(
            jsonEncode({'success': true, 'aiResponse': 'ok'}),
            200,
          );
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(legacy());
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pump();
        await _ask(tester, '');
        expect(find.text('📎 Uploaded 1 file', skipOffstage: false),
            findsOneWidget);
      }, () => client);
    });

    _chatTest('cancelling the file picker adds nothing', (tester) async {
      picker.result = null;
      await http.runWithClient(() async {
        await tester.pumpWidget(legacy());
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pump();
        expect(
            find.text('Files to upload:', skipOffstage: false), findsNothing);
      },
          () => MockClient((_) async {
                return http.Response(jsonEncode({'messages': []}), 200);
              }));
    });

    _chatTest('malformed history shows a load error', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(legacy());
        await tester.pump(const Duration(seconds: 1));
        expect(
            find.textContaining('Error loading history', skipOffstage: false),
            findsOneWidget);
      },
          () => MockClient((_) async {
                return http.Response(jsonEncode({'messages': 'oops'}), 200);
              }));
    });

    _chatTest('sharing without a selected patient asks for one',
        (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(legacy());
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Share with caregivers'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Select a patient before sharing with caregivers',
              skipOffstage: false),
          findsOneWidget,
        );
      },
          () => MockClient((_) async {
                return http.Response(
                  jsonEncode({
                    'messages': [
                      {'messageType': 'USER', 'content': 'hello'},
                    ],
                  }),
                  200,
                );
              }));
    });

    _chatTest('the modal close button pops the route', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(legacy(isModal: true));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
          () => MockClient((_) async {
                return http.Response(jsonEncode({'messages': []}), 200);
              }));
    });
  });

  _chatTest('a failed share reports the backend message', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(jsonEncode(_delivered('An answer')), 200);
      }
      if (request.url.path == '/api/ai/ask/share') {
        return http.Response('{}', 500);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      await _ask(tester, 'Anything new?');
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Share with caregivers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsOneWidget);
    }, () => client);
  });

  _chatTest('fifteen idle minutes clear the chat', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/ai/ask') {
        return http.Response(jsonEncode(_delivered('Short answer')), 200);
      }
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(seconds: 1));
      // Rebuilding with the same scope keeps the conversation.
      await tester.pumpWidget(_buildChat());
      await _ask(tester, 'Before the break');
      await tester.pump(const Duration(minutes: 16));
      await tester.pump();
      expect(
        find.text('⏰ Chat cleared due to 15 minutes of inactivity',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Before the break', skipOffstage: false), findsNothing);
    }, () => client);
  });

  _chatTest('the inactivity timer also fires without any activity',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_buildChat());
      await tester.pump(const Duration(minutes: 16));
      await tester.pump();
      expect(
        find.text('⏰ Chat cleared due to 15 minutes of inactivity',
            skipOffstage: false),
        findsOneWidget,
      );
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
}
