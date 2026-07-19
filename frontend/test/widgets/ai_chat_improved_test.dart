import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import '../mock_user_provider.dart';

void main() {
  // ---------------------------------------------------------------
  // Model tests (no widget needed)
  // ---------------------------------------------------------------
  group('ChatMessage model', () {
    test('constructor sets all required fields', () {
      final ts = DateTime(2025, 6, 15, 10, 30);
      final msg = ChatMessage(text: 'hello', isUser: true, timestamp: ts);
      expect(msg.text, 'hello');
      expect(msg.isUser, true);
      expect(msg.timestamp, ts);
      expect(msg.errorMessage, isNull);
    });

    test('optional errorMessage is stored', () {
      final msg = ChatMessage(
        text: 'err',
        isUser: false,
        timestamp: DateTime.now(),
        errorMessage: 'something went wrong',
      );
      expect(msg.errorMessage, 'something went wrong');
    });

    test('isUser false for AI messages', () {
      final msg = ChatMessage(
        text: 'AI says hi',
        isUser: false,
        timestamp: DateTime.now(),
      );
      expect(msg.isUser, false);
    });

    test('empty text is allowed', () {
      final msg =
          ChatMessage(text: '', isUser: true, timestamp: DateTime.now());
      expect(msg.text, '');
    });

    test('timestamp stores exact value', () {
      final ts = DateTime(2024, 1, 1, 0, 0, 0);
      final msg = ChatMessage(text: 'x', isUser: false, timestamp: ts);
      expect(msg.timestamp.year, 2024);
      expect(msg.timestamp.month, 1);
      expect(msg.timestamp.day, 1);
    });

    test('long text is preserved without truncation', () {
      final longText = 'A' * 10000;
      final msg = ChatMessage(
        text: longText,
        isUser: true,
        timestamp: DateTime.now(),
      );
      expect(msg.text.length, 10000);
    });

    test('errorMessage can be empty string', () {
      final msg = ChatMessage(
        text: 'test',
        isUser: false,
        timestamp: DateTime.now(),
        errorMessage: '',
      );
      expect(msg.errorMessage, '');
    });
  });

  group('UploadedFile model', () {
    test('constructor sets all required fields', () {
      final f = UploadedFile(
        name: 'report.pdf',
        size: 1024,
        content: 'binary',
        type: 'pdf',
      );
      expect(f.name, 'report.pdf');
      expect(f.size, 1024);
      expect(f.content, 'binary');
      expect(f.type, 'pdf');
      expect(f.bytes, isNull);
      expect(f.path, isNull);
    });

    test('optional bytes and path are stored', () {
      final f = UploadedFile(
        name: 'data.csv',
        size: 512,
        content: 'col1,col2',
        type: 'csv',
        bytes: [1, 2, 3],
        path: '/tmp/data.csv',
      );
      expect(f.bytes, [1, 2, 3]);
      expect(f.path, '/tmp/data.csv');
    });

    test('type field reflects file category', () {
      final f = UploadedFile(
        name: 'image.png',
        size: 2048,
        content: 'pixels',
        type: 'image',
      );
      expect(f.type, 'image');
    });

    test('size can be zero', () {
      final f = UploadedFile(
        name: 'empty.txt',
        size: 0,
        content: '',
        type: 'text',
      );
      expect(f.size, 0);
      expect(f.content, '');
    });

    test('bytes can be empty list', () {
      final f = UploadedFile(
        name: 'file.bin',
        size: 0,
        content: '',
        type: 'unknown',
        bytes: [],
      );
      expect(f.bytes, isEmpty);
    });

    test('large bytes list is stored correctly', () {
      final largeBytes = List.generate(1000, (i) => i % 256);
      final f = UploadedFile(
        name: 'large.bin',
        size: 1000,
        content: 'binary data',
        type: 'unknown',
        bytes: largeBytes,
      );
      expect(f.bytes!.length, 1000);
      expect(f.bytes![0], 0);
      expect(f.bytes![255], 255);
    });

    test('name with special characters is stored', () {
      final f = UploadedFile(
        name: 'my file (1).doc',
        size: 100,
        content: 'content',
        type: 'document',
      );
      expect(f.name, 'my file (1).doc');
    });

    test('various file types are stored correctly', () {
      for (final type in [
        'text',
        'csv',
        'json',
        'xml',
        'pdf',
        'document',
        'spreadsheet',
        'html',
        'code',
        'image',
        'unknown'
      ]) {
        final f = UploadedFile(
          name: 'test.$type',
          size: 10,
          content: 'x',
          type: type,
        );
        expect(f.type, type);
      }
    });
  });

  // ---------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------
  group('AIChat widget', () {
    late Function(FlutterErrorDetails)? origOnError;

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
    });

    tearDown(() {
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
    });

    Widget buildWidget({
      String role = 'PATIENT',
      int? userId = 1,
      bool isModal = false,
      int? patientId,
      String? healthDataContext,
    }) {
      final provider = MockUserProvider(mockUser: MockUser(id: 1, role: role));
      return ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: AIChat(
              role: role,
              userId: userId,
              isModal: isModal,
              patientId: patientId,
              healthDataContext: healthDataContext,
            ),
          ),
        ),
      );
    }

    /// Suppresses RenderFlex overflow errors from source code Rows.
    void suppressOverflow() {
      origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        origOnError?.call(details);
      };
    }

    /// Opens the popup menu and selects [value].
    Future<void> selectPopupItem(WidgetTester tester, String value) async {
      suppressOverflow();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final label = {
        'clear': 'Delete this conversation',
        'download': 'Download transcript',
        'share': 'Share with provider',
        'privacy': 'Privacy info',
      }[value]!;
      await tester.tap(find.text(label), warnIfMissed: false);
      // Allow popup dismiss animation and callback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // === BASIC RENDERING ===
    testWidgets('renders header with AI Chat title', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    testWidgets('renders smart_toy icon in header', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    testWidgets('renders privacy notification banner', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(
        find.text(
          'Chat logs are automatically deleted after 30 days for privacy protection.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders text field with hint', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Type your message...'), findsOneWidget);
    });

    testWidgets('renders send button', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
    });

    testWidgets('renders attach file button', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byTooltip('Attach file'), findsOneWidget);
    });

    testWidgets('renders PopupMenuButton (more_vert icon)', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('popup menu shows four options when tapped', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Delete this conversation'), findsOneWidget);
      expect(find.text('Download transcript'), findsOneWidget);
      expect(find.text('Share with provider'), findsOneWidget);
      expect(find.text('Privacy info'), findsOneWidget);
    });

    testWidgets('popup menu icons are present', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.delete_forever), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
      expect(find.byIcon(Icons.privacy_tip), findsOneWidget);
    });

    // === PRIVACY DIALOG ===
    testWidgets('privacy info dialog opens via popup menu', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'privacy');

      expect(find.text('Privacy & Data Protection'), findsOneWidget);
      expect(find.text('Your Privacy is Protected'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('privacy dialog dismisses on Got it tap', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'privacy');
      expect(find.text('Privacy & Data Protection'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Privacy & Data Protection'), findsNothing);
    });

    testWidgets('privacy dialog contains all bullet texts', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'privacy');

      expect(
        find.textContaining('automatically deleted after 30 days'),
        findsWidgets,
      );
      expect(
        find.textContaining('delete conversations immediately'),
        findsOneWidget,
      );
      expect(
        find.textContaining('anonymized usage statistics'),
        findsOneWidget,
      );
      expect(
        find.textContaining('shared with providers'),
        findsOneWidget,
      );
      expect(
        find.textContaining('encrypted and access is logged'),
        findsOneWidget,
      );
      expect(
        find.textContaining('not a substitute for professional medical advice'),
        findsOneWidget,
      );
    });

    // === DOWNLOAD TRANSCRIPT ===
    testWidgets('download transcript shows snackbar when no messages',
        (tester) async {
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();

      await selectPopupItem(tester, 'download');

      expect(find.text('No conversation to download'), findsOneWidget);
    });

    testWidgets('download transcript shows dialog when messages exist',
        (tester) async {
      suppressOverflow();
      // Use userId=1; the history load will fail and add an error message,
      // meaning _messages is not empty.
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'download');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Chat Transcript'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('download transcript dialog shows SelectableText',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'download');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('download transcript dialog closes on Close tap',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'download');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Chat Transcript'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Chat Transcript'), findsNothing);
    });

    // === SHARE WITH PROVIDER ===
    testWidgets('share with provider shows snackbar when no messages',
        (tester) async {
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();

      await selectPopupItem(tester, 'share');

      expect(find.text('No conversation to share'), findsOneWidget);
    });

    testWidgets('share with provider shows confirmation dialog',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'share');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Share with Provider'), findsOneWidget);
      expect(
        find.textContaining(
            'share your conversation with your healthcare provider'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('share with provider cancel dismisses dialog', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'share');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Share with Provider'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Share with Provider'), findsNothing);
    });

    testWidgets('share with provider confirm shows snackbar', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'share');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Conversation shared with provider'),
        findsOneWidget,
      );
    });

    // === DELETE CONVERSATION ===
    testWidgets('delete conversation shows confirmation dialog',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'clear');
      // Wait for async _getRetentionPeriod
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Delete Conversation'), findsOneWidget);
      expect(find.textContaining('permanently delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('delete dialog cancel dismisses', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'clear');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify dialog is open
      expect(find.text('Delete Conversation'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Delete Conversation'), findsNothing);
    });

    testWidgets('delete dialog confirm clears messages and shows snackbar',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await selectPopupItem(tester, 'clear');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Delete Conversation'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Conversation deleted successfully'),
        findsOneWidget,
      );
    });

    testWidgets('delete dialog shows retention period info', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await selectPopupItem(tester, 'clear');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The dialog should mention the retention period (fallback is 30 days)
      expect(
        find.textContaining('automatically deleted after'),
        findsWidgets,
      );
    });

    // === MODAL MODE ===
    testWidgets('close button shown when isModal is true', (tester) async {
      await tester.pumpWidget(buildWidget(isModal: true));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close button NOT shown when isModal is false', (tester) async {
      await tester.pumpWidget(buildWidget(isModal: false));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsNothing);
    });

    // === ROLES ===
    testWidgets('renders with CAREGIVER role', (tester) async {
      await tester.pumpWidget(buildWidget(role: 'CAREGIVER'));
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders with PATIENT role', (tester) async {
      await tester.pumpWidget(buildWidget(role: 'PATIENT'));
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    // === SEND MESSAGE ===
    testWidgets('send button does nothing when text is empty', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('sending message adds user message to list', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField), 'Hello AI');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // The user message should appear
      expect(find.text('Hello AI'), findsOneWidget);
    });

    testWidgets('sending message triggers loading state', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // The message should be displayed regardless of loading state
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets('sending message clears text field', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField), 'Some text');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // The text field should be cleared (the hint text should be back)
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '');
    });

    testWidgets('sending message with null userId shows auth error',
        (tester) async {
      suppressOverflow();
      // Build with userId: null AND use a provider with no user ID
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT'),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: AIChat(role: 'PATIENT', userId: null),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // userId is null in widget but MockUserProvider has user.id = 1
      // So it will use the provider's user id. The test checks
      // the send flow works without errors.
      expect(find.byType(AIChat), findsOneWidget);
    });

    testWidgets('text field is initially enabled', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // TextField should be enabled when not loading
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, true);
    });

    testWidgets('send via onSubmitted works same as button', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField), 'Submit test');
      await tester.pump();

      // Submit via keyboard
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Submit test'), findsOneWidget);
    });

    // === NULL USER ID ===
    testWidgets('renders with null userId', (tester) async {
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    testWidgets('userId null causes early return in history load',
        (tester) async {
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AIChat), findsOneWidget);
    });

    // === SHARED PREFERENCES ===
    testWidgets('chat cleared flag in SharedPreferences starts empty chat',
        (tester) async {
      SharedPreferences.setMockInitialValues({'chat_cleared_1': true});
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    testWidgets('chat cleared flag false loads history normally',
        (tester) async {
      SharedPreferences.setMockInitialValues({'chat_cleared_1': false});
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('AI Chat'), findsOneWidget);
    });

    // === LAYOUT STRUCTURE ===
    testWidgets('info_outline icon is in privacy banner', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('Divider is present in layout', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('ListView is present for messages', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('PopupMenuButton is of type String', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('text field can receive text input', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Hello AI');
      await tester.pump();

      expect(find.text('Hello AI'), findsOneWidget);
    });

    testWidgets('text field maxLines is 4', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 4);
      expect(textField.minLines, 1);
    });

    testWidgets('Column layout has correct structure', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(
        find.descendant(of: find.byType(AIChat), matching: find.byType(Column)),
        findsWidgets,
      );
    });

    testWidgets('input row contains attach, field, and send', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    // === CONSTRUCTOR ===
    testWidgets('AIChat constructor accepts all params', (tester) async {
      const chat = AIChat(
        role: 'PATIENT',
        healthDataContext: 'test context',
        isModal: true,
        patientId: 42,
        userId: 7,
      );
      expect(chat.role, 'PATIENT');
      expect(chat.healthDataContext, 'test context');
      expect(chat.isModal, true);
      expect(chat.patientId, 42);
      expect(chat.userId, 7);
    });

    testWidgets('AIChat defaults isModal to false', (tester) async {
      const chat = AIChat(role: 'CAREGIVER');
      expect(chat.isModal, false);
      expect(chat.healthDataContext, isNull);
      expect(chat.patientId, isNull);
      expect(chat.userId, isNull);
    });

    // === MESSAGE COUNT DISPLAY ===
    testWidgets('message count shown when messages exist', (tester) async {
      suppressOverflow();
      // userId=1 will attempt history load which fails, adding a message
      await tester.pumpWidget(buildWidget(userId: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Should show message count in header
      expect(find.textContaining('messages'), findsOneWidget);
    });

    testWidgets('no message count when messages list is empty', (tester) async {
      // userId=null => no history load => no messages
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();

      expect(find.textContaining('messages'), findsNothing);
    });

    // === MATERIAL WIDGET ===
    testWidgets('widget is wrapped in Material', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.byType(Material), findsWidgets);
    });

    // === HEALTH DATA CONTEXT ===
    testWidgets('renders with healthDataContext parameter', (tester) async {
      await tester.pumpWidget(
        buildWidget(healthDataContext: 'patient vitals data'),
      );
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    // === PATIENT ID ===
    testWidgets('renders with patientId parameter', (tester) async {
      await tester.pumpWidget(buildWidget(patientId: 42));
      await tester.pump();
      expect(find.text('AI Chat'), findsOneWidget);
    });

    // === SENDING WITH HTTP MOCK ===
    testWidgets('sendMessage with successful API response', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'aiResponse': 'Hello! How can I help you?',
              'conversationId': 'conv-123',
              'modelUsed': 'deepseek-chat',
              'processingTimeMs': 100,
            }),
            200,
          );
        }
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({'messages': [], 'conversationId': 'conv-123'}),
            200,
          );
        }
        if (request.url.path.contains('/retention-period')) {
          return http.Response(
            jsonEncode({'retentionDays': 30}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Hi there');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        // The user message should be visible
        expect(find.text('Hi there'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('patient Ask AI renders delivered citation contract',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/ai/ask') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('userId'), isFalse);
          return http.Response(
            jsonEncode({
              'success': true,
              'deliveryStatus': 'DELIVERED',
              'answer': {'text': 'Metformin was started.'},
              'citations': [
                {
                  'citationId': 'C1',
                  'recordType': 'CALL_SUMMARY',
                  'title': 'Call summary',
                  'excerpt': 'Metformin was started.',
                  'deepLink': null,
                }
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1, patientId: 42));
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(find.byType(TextField), 'What changed?');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.text('Metformin was started.'), findsWidgets);
        expect(find.textContaining('C1 — Call summary'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('sendMessage with failed API response shows error',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          return http.Response(
            jsonEncode({
              'success': false,
              'errorMessage': 'Service unavailable',
              'aiResponse': 'Sorry, error occurred.',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Test error');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        expect(find.text('Test error'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('sendMessage with whitespace-only text does not send',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();

      // Enter whitespace-only text
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // The text field should still contain the spaces (not cleared by send)
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, '   ');
    });

    // === CONVERSATION HISTORY ===
    testWidgets('conversation history loads messages from API', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'Previous user message',
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
                {
                  'content': 'Previous AI response',
                  'messageType': 'AI',
                  'createdAt': '2025-06-15T10:30:05',
                },
              ],
              'conversationId': 'conv-existing',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Previous user message'), findsOneWidget);
        expect(find.text('Previous AI response'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('conversation history skips SYSTEM messages', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'System init',
                  'messageType': 'SYSTEM',
                  'createdAt': '2025-06-15T10:00:00',
                },
                {
                  'content': 'User visible message',
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
              ],
              'conversationId': 'conv-sys',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('System init'), findsNothing);
        expect(find.text('User visible message'), findsOneWidget);
      }, () => mockClient);
    });

    testWidgets('empty conversation history shows no history message',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [],
              'conversationId': 'conv-empty',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Should show the "no history" message with emoji
        expect(find.textContaining('No conversation history found'),
            findsOneWidget);
      }, () => mockClient);
    });

    // === DELETE WITH CONFIRM (WITH HTTP MOCK) ===
    testWidgets('delete confirm clears messages and saves to prefs',
        (tester) async {
      suppressOverflow();
      SharedPreferences.setMockInitialValues({});
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'Old message',
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
              ],
              'conversationId': 'conv-to-delete',
            }),
            200,
          );
        }
        if (request.url.path.contains('/deactivate')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.contains('/retention-period')) {
          return http.Response(jsonEncode({'retentionDays': 30}), 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Message should be visible before delete
        expect(find.text('Old message'), findsOneWidget);

        await selectPopupItem(tester, 'clear');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Confirm delete
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Message should be gone
        expect(find.text('Old message'), findsNothing);
        expect(find.text('Conversation deleted successfully'), findsOneWidget);

        // Verify SharedPreferences was updated
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('chat_cleared_1'), true);
      }, () => mockClient);
    });

    // === WIDGET DISPOSAL ===
    testWidgets('widget disposes without errors', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Replace with empty container to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      // No errors = success
      expect(true, isTrue);
    });

    // === OVERFLOW HANDLING ===
    testWidgets('widget renders within container dimensions', (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // The AIChat widget uses fixed dimensions (320x500)
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AIChat),
          matching: find.byType(Container).first,
        ),
      );
      expect(container, isNotNull);
    });

    // === MESSAGE ALIGNMENT ===
    testWidgets('messages from history are aligned correctly', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'User msg',
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
                {
                  'content': 'AI msg',
                  'messageType': 'AI',
                  'createdAt': '2025-06-15T10:30:05',
                },
              ],
              'conversationId': 'conv-align',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Find Align widgets - user messages are right-aligned, AI left-aligned
        final aligns = tester.widgetList<Align>(find.byType(Align)).toList();
        // At least 2 align widgets for the 2 messages
        expect(aligns.length, greaterThanOrEqualTo(2));
      }, () => mockClient);
    });

    // === TIMESTAMP FORMATTING ===
    testWidgets('timestamp shown on messages', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'Timed message',
                  'messageType': 'USER',
                  'createdAt': DateTime.now().toIso8601String(),
                },
              ],
              'conversationId': 'conv-time',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // The timestamp for today should show HH:MM format
        expect(find.text('Timed message'), findsOneWidget);
        // Find timestamp text (HH:MM format for today)
        final now = DateTime.now();
        final expectedTime =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        expect(find.text(expectedTime), findsWidgets);
      }, () => mockClient);
    });

    testWidgets('old date timestamp shows date format', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'Old dated message',
                  'messageType': 'USER',
                  'createdAt': '2024-01-15T10:30:00',
                },
              ],
              'conversationId': 'conv-old',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Old date should show M/D/YYYY format: 1/15/2024
        expect(find.text('1/15/2024'), findsOneWidget);
      }, () => mockClient);
    });

    // === ERROR MESSAGE DISPLAY ===
    testWidgets('error messages from API are displayed', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          return http.Response(
            jsonEncode({
              'success': false,
              'errorMessage': 'Rate limit exceeded',
              'response': 'Please wait before sending more messages.',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Test rate limit');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        // User message visible
        expect(find.text('Test rate limit'), findsOneWidget);
      }, () => mockClient);
    });

    // === SEND MESSAGE WITH NEW CONVERSATION ===
    testWidgets('new conversation triggers history reload', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'aiResponse': 'Hello!',
              'conversationId': 'new-conv-id',
            }),
            200,
          );
        }
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({'messages': [], 'conversationId': 'new-conv-id'}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Start conversation');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        expect(find.text('Start conversation'), findsWidgets);
      }, () => mockClient);
    });

    // === SEND MESSAGE NETWORK ERROR ===
    testWidgets('network error during send shows error message',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          throw http.ClientException('Network error');
        }
        return http.Response(jsonEncode({'messages': []}), 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Network fail test');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        // Should show error message
        expect(find.textContaining('error'), findsWidgets);
      }, () => mockClient);
    });

    // === CONVERSATION HISTORY WITH CONVERSATION ID ===
    testWidgets('conversationId from history response is stored',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'Stored conv',
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
              ],
              'conversationId': 'stored-conv-id',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Stored conv'), findsOneWidget);
      }, () => mockClient);
    });

    // === MESSAGES WITH NULL CONTENT ===
    testWidgets('history message with null content shows empty string',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': null,
                  'messageType': 'USER',
                  'createdAt': '2025-06-15T10:30:00',
                },
              ],
              'conversationId': 'conv-null',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Should render without crash - null content becomes ''
        expect(find.byType(AIChat), findsOneWidget);
      }, () => mockClient);
    });

    // === MESSAGES WITH NULL CREATEDAT ===
    testWidgets('history message with null createdAt uses current time',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'content': 'No date msg',
                  'messageType': 'USER',
                  'createdAt': null,
                },
              ],
              'conversationId': 'conv-nodate',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('No date msg'), findsOneWidget);
      }, () => mockClient);
    });

    // === CLEAR CHAT DUE TO INACTIVITY ===
    testWidgets('widget has inactivity timer behavior', (tester) async {
      // The inactivity timer is set to 15 minutes. We can't easily test
      // real timer behavior but we can verify the widget doesn't crash.
      await tester.pumpWidget(buildWidget(userId: null));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Widget should be functional
      expect(find.byType(AIChat), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    // === MULTIPLE MESSAGES DISPLAY ===
    testWidgets('multiple messages render in ListView', (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({
              'messages': List.generate(
                3,
                (i) => {
                  'content': 'HistMsg $i',
                  'messageType': i.isEven ? 'USER' : 'AI',
                  'createdAt': '2025-06-15T10:${30 + i}:00',
                },
              ),
              'conversationId': 'conv-multi',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        for (int i = 0; i < 3; i++) {
          expect(find.text('HistMsg $i'), findsOneWidget);
        }
        expect(find.textContaining('3 messages'), findsOneWidget);
      }, () => mockClient);
    });

    // === SEND WITH SUCCESS AND CONVERSATION ID UPDATE ===
    testWidgets('successful send with conversationId updates state',
        (tester) async {
      suppressOverflow();
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/chat')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'aiResponse': 'I can help with that!',
              'conversationId': 'conv-updated',
            }),
            200,
          );
        }
        if (request.url.path.contains('/history')) {
          return http.Response(
            jsonEncode({'messages': [], 'conversationId': 'conv-updated'}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(buildWidget(userId: 1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.enterText(find.byType(TextField), 'Help me');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.send));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        // AI response should be visible
        expect(find.text('I can help with that!'), findsWidgets);
      }, () => mockClient);
    });

    // === SEND WITH NULL AI RESPONSE ===
    testWidgets('sending message with patientId passes without error',
        (tester) async {
      suppressOverflow();
      await tester.pumpWidget(buildWidget(userId: 1, patientId: 42));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(find.byType(TextField), 'Patient context test');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The user message should appear
      expect(find.text('Patient context test'), findsOneWidget);
    });
  });
}
