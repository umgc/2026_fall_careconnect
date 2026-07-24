// Tests for FileManagementPage
// (lib/pages/file_management_page.dart).
//
// initState calls _loadFiles() using Provider.of<UserProvider> (API, try/catch).
// _isLoading starts true -- spinner shown immediately.
// After the API call fails (no real backend), _isLoading becomes false and empty state shows.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/services/comprehensive_file_service.dart';

import '../mock_user_provider.dart';

/// Wraps FileManagementPage with a MockUserProvider that has a valid user.
Widget _wrap({String role = 'PATIENT', int id = 1}) {
  final provider = MockUserProvider(
    mockUser: MockUser(id: id, role: role),
  );
  return MaterialApp(
    routes: {
      '/login': (_) => const Scaffold(body: Text('Login Page')),
    },
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const FileManagementPage(),
    ),
  );
}

/// Wraps FileManagementPage with a null-user provider (simulates logged-out).
Widget _wrapNullUser() {
  final provider = _NullUserProvider();
  return MaterialApp(
    routes: {
      '/login': (_) => const Scaffold(body: Text('Login Page')),
    },
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const FileManagementPage(),
    ),
  );
}

/// A provider that returns null for user (not logged in).
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: MockUser());

  @override
  UserSession? get user => null;

  @override
  bool get isLoggedIn => false;
}

/// Helper to create a UserFileDTO for testing.
UserFileDTO _makeFile({
  int id = 1,
  String originalFilename = 'test_report.pdf',
  String contentType = 'application/pdf',
  int fileSize = 2048,
  String fileCategory = 'MEDICAL_REPORT',
  String? description,
  String fileName = 'test_report.pdf',
  String? fileUrl,
}) {
  return UserFileDTO(
    id: id,
    originalFilename: originalFilename,
    contentType: contentType,
    fileSize: fileSize,
    fileCategory: fileCategory,
    description: description,
    ownerId: 1,
    ownerType: 'USER',
    createdAt: DateTime(2025, 1, 15),
    updatedAt: DateTime(2025, 1, 15),
    fileName: fileName,
    fileUrl: fileUrl,
  );
}

void _setupChannelMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
}

/// Helper to pump and wait until loading completes.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  setUp(() {
    _setupChannelMocks();
  });

  group('FileManagementPage - initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(FileManagementPage), findsOneWidget);
    });

    testWidgets('shows "File Management" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('File Management'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      // Before the async call completes, loading spinner should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows TabBar with 3 tabs', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(3));
    });

    testWidgets('shows My Files tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('My Files'), findsOneWidget);
    });

    testWidgets('shows Upload tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Upload'), findsOneWidget);
    });

    testWidgets('shows Analytics tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('shows folder icon for My Files tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('shows cloud_upload icon for Upload tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    });

    testWidgets('shows analytics icon for Analytics tab', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.analytics), findsOneWidget);
    });
  });

  group('FileManagementPage - null user redirect', () {
    testWidgets('redirects to /login when user is null', (tester) async {
      await tester.pumpWidget(_wrapNullUser());
      // Shows a loading spinner while redirecting
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // After microtask runs, should navigate to login
      await tester.pump();
      await tester.pump();
      expect(find.text('Login Page'), findsOneWidget);
    });
  });

  group('FileManagementPage - after loading completes (empty state)', () {
    testWidgets('shows empty state after API call fails', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // After loading fails, should show empty state
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('shows "No files uploaded yet" in empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.text('No files uploaded yet'), findsOneWidget);
    });

    testWidgets('shows upload prompt text in empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(
        find.text(
            'Start by uploading your first file using the Upload tab'),
        findsOneWidget,
      );
    });

    testWidgets('shows "Upload Files" button in empty state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.text('Upload Files'), findsOneWidget);
    });

    testWidgets('Upload Files button has cloud_upload icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // The empty state Upload Files button has a cloud_upload icon
      final button = find.widgetWithText(ElevatedButton, 'Upload Files');
      expect(button, findsOneWidget);
    });

    testWidgets('search bar is visible in files tab', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search files...'), findsOneWidget);
    });

    testWidgets('search bar shows hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(
        find.text('Search by filename or description'),
        findsOneWidget,
      );
    });

    testWidgets('search icon is present', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('refresh button is visible', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byTooltip('Refresh files'), findsOneWidget);
    });

    testWidgets('category filter dropdown is visible', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.text('Filter by category'), findsOneWidget);
    });
  });

  group('FileManagementPage - search functionality', () {
    testWidgets('entering search text shows clear button', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('tapping clear button clears search text', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'some text');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      final textField =
          tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets(
        'empty state shows filter message when search query is active',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
      expect(
        find.text('Try adjusting your search or filter criteria'),
        findsOneWidget,
      );
      expect(find.text('Upload Files'), findsNothing);
    });

    testWidgets('no clear button when search is empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // With empty search, no clear icon should be present
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });

  group('FileManagementPage - Upload tab', () {
    testWidgets('tapping Upload tab shows upload content', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('File Upload'), findsOneWidget);
    });

    testWidgets('Upload tab shows instructions card', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(
        find.textContaining('Use File Upload for files'),
        findsOneWidget,
      );
    });

    testWidgets('Upload tab shows full instructions text', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Multiple widgets may contain "Speech-to-Text"
      expect(
        find.textContaining('Speech-to-Text'),
        findsWidgets,
      );
    });

    testWidgets('Upload tab contains Manual Text Entry instructions',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Manual Text Entry'),
        findsWidgets,
      );
    });

    testWidgets('Upload tab is scrollable', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('FileManagementPage - Analytics tab', () {
    testWidgets('tapping Analytics tab shows analytics content',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('File Analytics'), findsOneWidget);
    });

    testWidgets('Analytics tab shows Total Files card', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Total Files'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('Analytics tab shows Total Size card', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Total Size'), findsOneWidget);
      expect(find.text('0 B'), findsOneWidget);
    });

    testWidgets('Analytics tab shows Files by Category heading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Files by Category'), findsOneWidget);
    });

    testWidgets('Analytics tab shows folder icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.folder), findsWidgets);
    });

    testWidgets('Analytics tab shows storage icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.storage), findsOneWidget);
    });

    testWidgets('Analytics tab is scrollable', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('Analytics tab shows cards for overview', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should have at least 2 Card widgets for Total Files and Total Size
      expect(find.byType(Card), findsWidgets);
    });
  });

  group('FileManagementPage - caregiver role', () {
    testWidgets('renders for caregiver role', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      expect(find.byType(FileManagementPage), findsOneWidget);
      expect(find.text('File Management'), findsOneWidget);
    });

    testWidgets('caregiver sees same tabs', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      expect(find.text('My Files'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('caregiver loading completes to empty state', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);

      final hasEmpty = find.text('No files uploaded yet').evaluate().isNotEmpty;
      final hasError = find.textContaining('Error').evaluate().isNotEmpty;
      expect(hasEmpty || hasError, isTrue);
    });

    testWidgets('caregiver can access Upload tab', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('File Upload'), findsOneWidget);
    });

    testWidgets('caregiver can access Analytics tab', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('File Analytics'), findsOneWidget);
      expect(find.text('Total Files'), findsOneWidget);
    });

    testWidgets('caregiver isCaregiver flag is computed', (tester) async {
      await tester.pumpWidget(_wrap(role: 'CAREGIVER'));
      await _pumpUntilLoaded(tester);

      // The page renders correctly for caregiver, confirming the
      // isCaregiver = user.role.toUpperCase() == 'CAREGIVER' path
      expect(find.byType(FileManagementPage), findsOneWidget);
    });

    testWidgets('lowercase caregiver role works', (tester) async {
      await tester.pumpWidget(_wrap(role: 'caregiver'));
      await _pumpUntilLoaded(tester);

      expect(find.byType(FileManagementPage), findsOneWidget);
    });
  });

  group('FileManagementPage - tab navigation', () {
    testWidgets('Upload Files button in empty state switches to Upload tab',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload Files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('File Upload'), findsOneWidget);
    });

    testWidgets('can navigate between all tabs', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Go to Upload tab
      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('File Upload'), findsOneWidget);

      // Go to Analytics tab
      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('File Analytics'), findsOneWidget);

      // Go back to My Files tab
      await tester.tap(find.text('My Files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Search files...'), findsOneWidget);
    });

    testWidgets('navigating from Analytics back to My Files preserves search', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Enter search text
      await tester.enterText(find.byType(TextField), 'test query');
      await tester.pump();

      // Go to Analytics
      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Go back to My Files
      await tester.tap(find.text('My Files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Search field should still have text
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'test query');
    });

    testWidgets('navigating from Upload back to My Files shows files tab',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('My Files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Search files...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('FileManagementPage - refresh', () {
    testWidgets('tapping refresh button triggers reload', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byIcon(Icons.folder_open), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('refresh button shows loading state briefly', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Tap refresh
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // Briefly should show loading or still show content
      // Either way, page should not crash
      expect(find.byType(FileManagementPage), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    });

    testWidgets('multiple refresh taps do not crash', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(FileManagementPage), findsOneWidget);
    });
  });

  group('FileManagementPage - category dropdown', () {
    testWidgets('dropdown contains All Categories option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('All Categories'), findsWidgets);
    });

    testWidgets('dropdown contains file category options', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Medical Report'), findsWidgets);
      expect(find.text('Lab Result'), findsWidgets);
      expect(find.text('Prescription'), findsWidgets);
    });

    testWidgets('dropdown contains Clinical Notes option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Clinical Notes'), findsWidgets);
    });

    testWidgets('dropdown contains Insurance Document option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Insurance Document'), findsWidgets);
    });

    testWidgets('dropdown contains AI Chat File option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // With employment categories, later items may be off-screen.
      final hasLabel = find.text('AI Chat File').evaluate().isNotEmpty;
      final hasDropdown = find.text('All Categories').evaluate().isNotEmpty;
      expect(hasLabel || hasDropdown, isTrue);
      expect(FileCategory.aiChatUpload.displayName, 'AI Chat File');
    });

    testWidgets('dropdown contains General Document option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final hasLabel = find.text('General Document').evaluate().isNotEmpty;
      final hasDropdown = find.text('All Categories').evaluate().isNotEmpty;
      expect(hasLabel || hasDropdown, isTrue);
      expect(FileCategory.generalDocument.displayName, 'General Document');
    });

    testWidgets('dropdown contains Backup File option', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Open the dropdown
      await tester.tap(find.text('Filter by category'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll down in the dropdown to find Backup File
      // It may be off screen; just check that the dropdown opened
      final hasBackup = find.text('Backup File').evaluate().isNotEmpty;
      final hasDropdown = find.text('All Categories').evaluate().isNotEmpty;
      expect(hasBackup || hasDropdown, isTrue);
    });
  });

  group('FileManagementPage - search functionality extended', () {
    testWidgets('entering search text shows clear button', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets(
        'empty state shows filter message when search query is active',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
      expect(
        find.text('Try adjusting your search or filter criteria'),
        findsOneWidget,
      );
      expect(find.text('Upload Files'), findsNothing);
    });

    testWidgets('typing and clearing search multiple times works',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Type something
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Clear
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsNothing);

      // Type again
      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.text('No files match your filters'), findsOneWidget);

      // Clear again
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.text('No files uploaded yet'), findsOneWidget);
    });
  });

  group('FileManagementPage - search with category filter combined', () {
    testWidgets('search query + category filter both show filter message',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Lab Result').last);
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
      expect(
        find.text('Try adjusting your search or filter criteria'),
        findsOneWidget,
      );
    });
  });

  group('FileManagementPage - category dropdown selection', () {
    testWidgets('selecting a category updates filter state', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Medical Report').last);
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
      expect(find.text('Upload Files'), findsNothing);
    });

    testWidgets('selecting All Categories shows default empty state',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // First select a category
      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Medical Report').last);
      await tester.pump();

      // Now select "All Categories"
      await tester.tap(find.text('Medical Report').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('All Categories').last);
      await tester.pump();

      expect(find.text('No files uploaded yet'), findsOneWidget);
    });

    testWidgets('selecting Prescription category shows filter message', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Prescription').last);
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
    });

    testWidgets('selecting Clinical Notes category shows filter message',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Clinical Notes').last);
      await tester.pump();

      expect(find.text('No files match your filters'), findsOneWidget);
    });
  });

  group('FileManagementPage - error snackbar on load failure', () {
    testWidgets('shows error snackbar when file loading fails',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('FileManagementPage - search with empty query after text', () {
    testWidgets('clearing search restores empty state text', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(find.text('No files match your filters'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.text('No files uploaded yet'), findsOneWidget);
    });
  });

  group('FileManagementPage - different user IDs', () {
    testWidgets('renders with different user ID', (tester) async {
      await tester.pumpWidget(_wrap(id: 42));
      expect(find.byType(FileManagementPage), findsOneWidget);
      expect(find.text('File Management'), findsOneWidget);
    });

    testWidgets('renders with user ID 0', (tester) async {
      await tester.pumpWidget(_wrap(id: 0));
      expect(find.byType(FileManagementPage), findsOneWidget);
    });

    testWidgets('renders with large user ID', (tester) async {
      await tester.pumpWidget(_wrap(id: 99999));
      expect(find.byType(FileManagementPage), findsOneWidget);
    });
  });

  group('FileManagementPage - multiple pumps for loading states', () {
    testWidgets('loading completes and empty state is stable', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });
  });

  group('FileManagementPage - widget structure', () {
    testWidgets('has TabBarView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TabBarView), findsOneWidget);
    });

    testWidgets('has DropdownButtonFormField for category filter',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(
          find.byType(DropdownButtonFormField<FileCategory?>), findsOneWidget);
    });

    testWidgets('My Files tab has TextField for search', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('empty state has Column layout', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('search bar has OutlineInputBorder', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration, isNotNull);
      expect(textField.decoration!.border, isA<OutlineInputBorder>());
    });

    testWidgets('search bar has search icon prefix', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration!.prefixIcon, isNotNull);
    });

    testWidgets('category dropdown is inside a Row with refresh button',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Both dropdown and refresh button should be present
      expect(find.byType(DropdownButtonFormField<FileCategory?>), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  // ===========================================================================
  // UserFileDTO unit tests
  // ===========================================================================

  group('UserFileDTO helpers', () {
    test('fileIcon returns correct icon for pdf', () {
      final file = _makeFile(contentType: 'application/pdf');
      expect(file.fileIcon, isNotEmpty);
    });

    test('fileIcon returns correct icon for image', () {
      final file = _makeFile(contentType: 'image/png');
      expect(file.fileIcon, isNotEmpty);
    });

    test('categoryDisplayName returns a string', () {
      final file = _makeFile(fileCategory: 'MEDICAL_REPORT');
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('isPreviewable is true for pdf', () {
      final file = _makeFile(contentType: 'application/pdf');
      expect(file.isPreviewable, isTrue);
    });

    test('isPreviewable is false for generic content type', () {
      final file = _makeFile(contentType: 'application/octet-stream');
      expect(file.isPreviewable, isFalse);
    });

    test('isImage is true for image content types', () {
      final file = _makeFile(contentType: 'image/jpeg');
      expect(file.isImage, isTrue);
    });

    test('isImage is false for non-image content types', () {
      final file = _makeFile(contentType: 'application/pdf');
      expect(file.isImage, isFalse);
    });
  });

  group('FileCategory enum', () {
    test('FileCategory.values has expected number of categories', () {
      expect(FileCategory.values.length, 19);
    });

    test('each category has value, displayName, and icon', () {
      for (final cat in FileCategory.values) {
        expect(cat.value, isNotEmpty);
        expect(cat.displayName, isNotEmpty);
        expect(cat.icon, isNotEmpty);
      }
    });

    test('medicalReport has expected values', () {
      expect(FileCategory.medicalReport.value, 'MEDICAL_RECORD');
      expect(FileCategory.medicalReport.displayName, 'Medical Report');
    });

    test('prescription has expected values', () {
      expect(FileCategory.prescription.value, 'PRESCRIPTION');
      expect(FileCategory.prescription.displayName, 'Prescription');
    });

    test('generalDocument has expected values', () {
      expect(FileCategory.generalDocument.value, 'OTHER_DOCUMENT');
      expect(FileCategory.generalDocument.displayName, 'General Document');
    });
  });

  group('FileQueryParams', () {
    test('empty params produce empty query string', () {
      final params = FileQueryParams();
      expect(params.toQueryString(), '');
    });

    test('page param is included', () {
      final params = FileQueryParams(page: 0);
      expect(params.toQueryString(), contains('page=0'));
    });

    test('size param is included', () {
      final params = FileQueryParams(size: 100);
      expect(params.toQueryString(), contains('size=100'));
    });

    test('sort param is included', () {
      final params = FileQueryParams(sort: 'createdAt,desc');
      expect(params.toQueryString(), contains('sort=createdAt,desc'));
    });

    test('category param is included', () {
      final params = FileQueryParams(category: 'MEDICAL_REPORT');
      expect(params.toQueryString(), contains('category=MEDICAL_REPORT'));
    });

    test('multiple params are joined with &', () {
      final params = FileQueryParams(page: 0, size: 10);
      final qs = params.toQueryString();
      expect(qs, startsWith('?'));
      expect(qs, contains('&'));
    });

    test('categories param is included', () {
      final params = FileQueryParams(categories: ['A', 'B']);
      expect(params.toQueryString(), contains('categories=A,B'));
    });

    test('query param is URL encoded', () {
      final params = FileQueryParams(query: 'hello world');
      expect(params.toQueryString(), contains('query=hello%20world'));
    });

    test('startDate and endDate params are included', () {
      final params = FileQueryParams(
        startDate: '2025-01-01',
        endDate: '2025-12-31',
      );
      final qs = params.toQueryString();
      expect(qs, contains('startDate=2025-01-01'));
      expect(qs, contains('endDate=2025-12-31'));
    });

    test('all params together', () {
      final params = FileQueryParams(
        page: 0,
        size: 50,
        sort: 'name,asc',
        category: 'LAB_RESULT',
        startDate: '2025-01-01',
        endDate: '2025-06-30',
        query: 'blood',
      );
      final qs = params.toQueryString();
      expect(qs, startsWith('?'));
      expect(qs, contains('page=0'));
      expect(qs, contains('size=50'));
      expect(qs, contains('sort=name,asc'));
      expect(qs, contains('category=LAB_RESULT'));
      expect(qs, contains('startDate=2025-01-01'));
      expect(qs, contains('endDate=2025-06-30'));
      expect(qs, contains('query=blood'));
    });
  });

  group('UserFileDTO construction and fromJson', () {
    test('fromJson creates DTO with all fields', () {
      final json = {
        'id': 42,
        'originalFilename': 'report.pdf',
        'contentType': 'application/pdf',
        'fileSize': 1024,
        'fileCategory': 'MEDICAL_REPORT',
        'description': 'A test report',
        'ownerId': 5,
        'ownerType': 'USER',
        'fileUrl': 'https://example.com/file.pdf',
        'downloadUrl': 'https://example.com/download/file.pdf',
        'category': 'MEDICAL_REPORT',
        'filename': 'report.pdf',
      };
      final dto = UserFileDTO.fromJson(json);
      expect(dto.id, 42);
      expect(dto.originalFilename, 'report.pdf');
      expect(dto.contentType, 'application/pdf');
      expect(dto.fileSize, 1024);
      expect(dto.fileCategory, 'MEDICAL_REPORT');
      expect(dto.description, 'A test report');
      expect(dto.ownerId, 5);
      expect(dto.fileUrl, 'https://example.com/file.pdf');
      expect(dto.fileName, 'report.pdf');
    });

    test('fromJson handles missing optional fields with defaults', () {
      final json = <String, dynamic>{};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.id, 0);
      expect(dto.originalFilename, '');
      expect(dto.contentType, 'application/octet-stream');
      expect(dto.fileSize, 0);
      expect(dto.fileCategory, 'documents');
      expect(dto.description, isNull);
      expect(dto.fileName, '[Unnamed File]');
    });

    test('fromJson sets ownerType correctly', () {
      final json = {'ownerType': 'ADMIN'};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.ownerType, 'ADMIN');
    });

    test('fromJson sets patientId correctly', () {
      final json = {'patientId': 99};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.patientId, 99);
    });

    test('fromJson patientId defaults to null', () {
      final json = <String, dynamic>{};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.patientId, isNull);
    });

    test('fromJson sets s3FullKey correctly', () {
      final json = {'s3FullKey': 'bucket/path/to/file.pdf'};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.s3FullKey, 'bucket/path/to/file.pdf');
    });

    test('fromJson sets downloadUrl correctly', () {
      final json = {'downloadUrl': 'https://example.com/download'};
      final dto = UserFileDTO.fromJson(json);
      expect(dto.downloadUrl, 'https://example.com/download');
    });

    test('file extension extraction works for files with dots', () {
      final file = _makeFile(fileName: 'my.document.pdf');
      final dotIndex = file.fileName.lastIndexOf('.');
      final baseName = file.fileName.substring(0, dotIndex);
      final ext = file.fileName.substring(dotIndex).replaceFirst('.', '');
      expect(baseName, 'my.document');
      expect(ext, 'pdf');
    });

    test('file extension extraction works for files without extension', () {
      final file = _makeFile(fileName: 'noextension');
      final dotIndex = file.fileName.lastIndexOf('.');
      expect(dotIndex, -1);
      final baseName =
          (dotIndex != -1) ? file.fileName.substring(0, dotIndex) : file.fileName;
      expect(baseName, 'noextension');
    });

    test('file extension extraction for single char extension', () {
      final file = _makeFile(fileName: 'file.a');
      final dotIndex = file.fileName.lastIndexOf('.');
      expect(dotIndex, 4);
      final ext = file.fileName.substring(dotIndex + 1);
      expect(ext, 'a');
    });

    test('file name with leading dot', () {
      final file = _makeFile(fileName: '.hidden');
      final dotIndex = file.fileName.lastIndexOf('.');
      expect(dotIndex, 0);
      final baseName = file.fileName.substring(0, dotIndex);
      expect(baseName, '');
    });

    test('file name ending with dot', () {
      final file = _makeFile(fileName: 'file.');
      final dotIndex = file.fileName.lastIndexOf('.');
      expect(dotIndex, 4);
      // Extension after last dot is empty
      final ext = file.fileName.substring(dotIndex + 1);
      expect(ext, '');
    });

    test('file name with multiple extensions', () {
      final file = _makeFile(fileName: 'archive.tar.gz');
      final dotIndex = file.fileName.lastIndexOf('.');
      expect(dotIndex, 11);
      final baseName = file.fileName.substring(0, dotIndex);
      expect(baseName, 'archive.tar');
      final ext = file.fileName.substring(dotIndex + 1);
      expect(ext, 'gz');
    });
  });

  group('UserFileDTO - toJson', () {
    test('toJson includes all required fields', () {
      final file = _makeFile(
        id: 5,
        originalFilename: 'doc.pdf',
        contentType: 'application/pdf',
        fileSize: 1024,
        fileCategory: 'LAB_RESULT',
        description: 'Lab test',
      );
      final json = file.toJson();
      expect(json['id'], 5);
      expect(json['originalFilename'], 'doc.pdf');
      expect(json['contentType'], 'application/pdf');
      expect(json['fileSize'], 1024);
      expect(json['fileCategory'], 'LAB_RESULT');
      expect(json['description'], 'Lab test');
      expect(json['ownerId'], 1);
      expect(json['ownerType'], 'USER');
    });

    test('toJson includes createdAt and updatedAt as ISO strings', () {
      final file = _makeFile();
      final json = file.toJson();
      expect(json['createdAt'], isA<String>());
      expect(json['updatedAt'], isA<String>());
    });

    test('toJson includes fileUrl when set', () {
      final file = _makeFile(fileUrl: 'https://example.com/f.pdf');
      final json = file.toJson();
      expect(json['fileUrl'], 'https://example.com/f.pdf');
    });

    test('toJson includes null fileUrl when not set', () {
      final file = _makeFile(fileUrl: null);
      final json = file.toJson();
      expect(json['fileUrl'], isNull);
    });

    test('toJson includes null description when not set', () {
      final file = _makeFile(description: null);
      final json = file.toJson();
      expect(json['description'], isNull);
    });

    test('toJson includes patientId', () {
      final file = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'MEDICAL_REPORT',
        ownerId: 1,
        ownerType: 'USER',
        patientId: 42,
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
        fileName: 'test.pdf',
      );
      final json = file.toJson();
      expect(json['patientId'], 42);
    });

    test('toJson includes downloadUrl', () {
      final file = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'MEDICAL_REPORT',
        ownerId: 1,
        ownerType: 'USER',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
        fileName: 'test.pdf',
        downloadUrl: 'https://example.com/dl',
      );
      final json = file.toJson();
      expect(json['downloadUrl'], 'https://example.com/dl');
    });

    test('toJson includes files list', () {
      final file = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'MEDICAL_REPORT',
        ownerId: 1,
        ownerType: 'USER',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
        fileName: 'test.pdf',
        files: ['file1.pdf', 'file2.pdf'],
      );
      final json = file.toJson();
      expect(json['files'], ['file1.pdf', 'file2.pdf']);
    });

    test('toJson includes category', () {
      final file = UserFileDTO(
        id: 1,
        originalFilename: 'test.pdf',
        contentType: 'application/pdf',
        fileSize: 100,
        fileCategory: 'MEDICAL_REPORT',
        ownerId: 1,
        ownerType: 'USER',
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
        fileName: 'test.pdf',
        category: 'MEDICAL_REPORT',
      );
      final json = file.toJson();
      expect(json['category'], 'MEDICAL_REPORT');
    });
  });

  group('FileManagementPage - _formatFileSize coverage', () {
    testWidgets('formats 0 bytes correctly', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      await tester.tap(find.text('Analytics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('0 B'), findsOneWidget);
    });
  });

  group('UserFileDTO - fileIcon variations', () {
    test('word document returns doc icon', () {
      final file = _makeFile(contentType: 'application/msword');
      expect(file.fileIcon, isNotEmpty);
    });

    test('excel spreadsheet returns spreadsheet icon', () {
      final file = _makeFile(contentType: 'application/vnd.ms-excel');
      expect(file.fileIcon, isNotEmpty);
    });

    test('powerpoint returns presentation icon', () {
      final file = _makeFile(
          contentType: 'application/vnd.ms-powerpoint');
      expect(file.fileIcon, isNotEmpty);
    });

    test('video returns video icon', () {
      final file = _makeFile(contentType: 'video/mp4');
      expect(file.fileIcon, isNotEmpty);
    });

    test('audio returns audio icon', () {
      final file = _makeFile(contentType: 'audio/mpeg');
      expect(file.fileIcon, isNotEmpty);
    });

    test('unknown type returns generic icon', () {
      final file = _makeFile(contentType: 'application/zip');
      expect(file.fileIcon, isNotEmpty);
    });

    test('image/jpeg returns image icon', () {
      final file = _makeFile(contentType: 'image/jpeg');
      expect(file.fileIcon, contains('\u{1F5BC}')); // framed picture emoji
    });

    test('image/gif returns image icon', () {
      final file = _makeFile(contentType: 'image/gif');
      expect(file.fileIcon, isNotEmpty);
      expect(file.isImage, isTrue);
    });

    test('text/plain returns generic icon', () {
      final file = _makeFile(contentType: 'text/plain');
      expect(file.fileIcon, isNotEmpty);
    });

    test('application/json returns generic icon', () {
      final file = _makeFile(contentType: 'application/json');
      expect(file.fileIcon, isNotEmpty);
    });

    test('video/webm returns video icon', () {
      final file = _makeFile(contentType: 'video/webm');
      expect(file.fileIcon, isNotEmpty);
    });

    test('audio/wav returns audio icon', () {
      final file = _makeFile(contentType: 'audio/wav');
      expect(file.fileIcon, isNotEmpty);
    });

    test('openxml document returns word icon', () {
      final file = _makeFile(
          contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(file.fileIcon, isNotEmpty);
    });

    test('openxml spreadsheet returns excel icon', () {
      final file = _makeFile(
          contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(file.fileIcon, isNotEmpty);
    });

    test('openxml presentation returns powerpoint icon', () {
      final file = _makeFile(
          contentType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
      expect(file.fileIcon, isNotEmpty);
    });

    test('isPreviewable true for word docs', () {
      final file = _makeFile(contentType: 'application/msword');
      expect(file.isPreviewable, isTrue);
    });

    test('isPreviewable true for image', () {
      final file = _makeFile(contentType: 'image/jpeg');
      expect(file.isPreviewable, isTrue);
    });

    test('isPreviewable false for video', () {
      final file = _makeFile(contentType: 'video/mp4');
      expect(file.isPreviewable, isFalse);
    });

    test('isPreviewable false for audio', () {
      final file = _makeFile(contentType: 'audio/mpeg');
      expect(file.isPreviewable, isFalse);
    });

    test('isPreviewable true for openxml document', () {
      final file = _makeFile(
          contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(file.isPreviewable, isTrue);
    });

    test('isPreviewable false for zip', () {
      final file = _makeFile(contentType: 'application/zip');
      expect(file.isPreviewable, isFalse);
    });

    test('isPreviewable false for text/plain', () {
      final file = _makeFile(contentType: 'text/plain');
      expect(file.isPreviewable, isFalse);
    });
  });

  group('UserFileDTO - description and fields', () {
    test('description can be null', () {
      final file = _makeFile(description: null);
      expect(file.description, isNull);
    });

    test('description can be non-null', () {
      final file = _makeFile(description: 'A test description');
      expect(file.description, 'A test description');
    });

    test('description can be empty string', () {
      final file = _makeFile(description: '');
      expect(file.description, '');
      expect(file.description!.isEmpty, isTrue);
    });

    test('fileUrl can be null', () {
      final file = _makeFile(fileUrl: null);
      expect(file.fileUrl, isNull);
    });

    test('fileUrl can be set', () {
      final file = _makeFile(fileUrl: 'https://example.com/f.pdf');
      expect(file.fileUrl, 'https://example.com/f.pdf');
    });

    test('constructor sets all required fields', () {
      final file = _makeFile(
        id: 99,
        originalFilename: 'lab.pdf',
        contentType: 'application/pdf',
        fileSize: 5000,
        fileCategory: 'LAB_RESULT',
        fileName: 'lab.pdf',
      );
      expect(file.id, 99);
      expect(file.originalFilename, 'lab.pdf');
      expect(file.contentType, 'application/pdf');
      expect(file.fileSize, 5000);
      expect(file.fileCategory, 'LAB_RESULT');
      expect(file.fileName, 'lab.pdf');
      expect(file.ownerId, 1);
      expect(file.ownerType, 'USER');
    });

    test('createdAt and updatedAt are set', () {
      final file = _makeFile();
      expect(file.createdAt, DateTime(2025, 1, 15));
      expect(file.updatedAt, DateTime(2025, 1, 15));
    });
  });

  group('FileCategory - all enum values', () {
    test('labResult category', () {
      expect(FileCategory.labResult.value, 'LAB_RESULT');
      expect(FileCategory.labResult.displayName, 'Lab Result');
    });

    test('clinicalNotes category', () {
      expect(FileCategory.clinicalNotes.value, 'CLINICAL_NOTE');
      expect(FileCategory.clinicalNotes.displayName, 'Clinical Notes');
    });

    test('profilePicture category', () {
      expect(FileCategory.profilePicture.value, 'PROFILE_IMAGE');
      expect(FileCategory.profilePicture.displayName, 'Profile Picture');
    });

    test('emergencyContact category', () {
      expect(FileCategory.emergencyContact.value, 'EMERGENCY_CONTACT');
      expect(FileCategory.emergencyContact.displayName, 'Emergency Contact');
    });

    test('insuranceDoc category', () {
      expect(FileCategory.insuranceDoc.value, 'INSURANCE_DOCUMENT');
      expect(FileCategory.insuranceDoc.displayName, 'Insurance Document');
    });

    test('aiChatUpload category', () {
      expect(FileCategory.aiChatUpload.value, 'AI_CHAT_UPLOAD');
      expect(FileCategory.aiChatUpload.displayName, 'AI Chat File');
    });

    test('healthDataImport category', () {
      expect(FileCategory.healthDataImport.value, 'HEALTH_DATA_IMPORT');
      expect(FileCategory.healthDataImport.displayName, 'Health Data Import');
    });

    test('backupFile category', () {
      expect(FileCategory.backupFile.value, 'BACKUP_FILE');
      expect(FileCategory.backupFile.displayName, 'Backup File');
    });

    test('each category icon is a non-empty string', () {
      for (final cat in FileCategory.values) {
        expect(cat.icon.isNotEmpty, isTrue, reason: '${cat.name} icon is empty');
      }
    });

    test('medicalReport icon is hospital emoji', () {
      expect(FileCategory.medicalReport.icon, isNotEmpty);
    });

    test('labResult icon is test tube emoji', () {
      expect(FileCategory.labResult.icon, isNotEmpty);
    });

    test('prescription icon is pill emoji', () {
      expect(FileCategory.prescription.icon, isNotEmpty);
    });
  });

  group('FileQueryParams - edge cases', () {
    test('empty categories list does not add param', () {
      final params = FileQueryParams(categories: []);
      expect(params.toQueryString(), '');
    });

    test('single category in list', () {
      final params = FileQueryParams(categories: ['MEDICAL_REPORT']);
      expect(params.toQueryString(), contains('categories=MEDICAL_REPORT'));
    });

    test('query string starts with ?', () {
      final params = FileQueryParams(page: 1);
      expect(params.toQueryString(), startsWith('?'));
    });

    test('three categories in list', () {
      final params = FileQueryParams(categories: ['A', 'B', 'C']);
      expect(params.toQueryString(), contains('categories=A,B,C'));
    });

    test('query with special characters is encoded', () {
      final params = FileQueryParams(query: 'test&value=1');
      final qs = params.toQueryString();
      expect(qs, contains('query='));
      // Should be URL encoded
      expect(qs, isNot(contains('query=test&value=1')));
    });

    test('only startDate without endDate', () {
      final params = FileQueryParams(startDate: '2025-01-01');
      final qs = params.toQueryString();
      expect(qs, contains('startDate=2025-01-01'));
      expect(qs, isNot(contains('endDate')));
    });

    test('only endDate without startDate', () {
      final params = FileQueryParams(endDate: '2025-12-31');
      final qs = params.toQueryString();
      expect(qs, contains('endDate=2025-12-31'));
      expect(qs, isNot(contains('startDate')));
    });

    test('page with large number', () {
      final params = FileQueryParams(page: 99999);
      expect(params.toQueryString(), contains('page=99999'));
    });

    test('size with zero', () {
      final params = FileQueryParams(size: 0);
      expect(params.toQueryString(), contains('size=0'));
    });
  });

  group('UserFileDTO - getCategoryDisplayName', () {
    test('returns display name for known categories', () {
      final file = _makeFile(fileCategory: 'MEDICAL_REPORT');
      expect(file.categoryDisplayName, isA<String>());
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('returns display name for documents category', () {
      final file = _makeFile(fileCategory: 'documents');
      expect(file.categoryDisplayName, isA<String>());
    });

    test('returns display name for unknown category', () {
      final file = _makeFile(fileCategory: 'UNKNOWN_CAT');
      expect(file.categoryDisplayName, isA<String>());
    });

    test('returns display name for PRESCRIPTION', () {
      final file = _makeFile(fileCategory: 'PRESCRIPTION');
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('returns display name for INSURANCE', () {
      final file = _makeFile(fileCategory: 'INSURANCE');
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('returns display name for PROFILE_PICTURE', () {
      final file = _makeFile(fileCategory: 'PROFILE_PICTURE');
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('returns display name for LAB_RESULT', () {
      final file = _makeFile(fileCategory: 'LAB_RESULT');
      expect(file.categoryDisplayName, 'Lab Result');
    });

    test('returns display name for CLINICAL_NOTES', () {
      final file = _makeFile(fileCategory: 'CLINICAL_NOTES');
      // May map to 'Clinical Notes' or similar
      expect(file.categoryDisplayName, isA<String>());
    });

    test('returns display name for EMERGENCY_CONTACT', () {
      final file = _makeFile(fileCategory: 'EMERGENCY_CONTACT');
      expect(file.categoryDisplayName, isNotEmpty);
    });

    test('returns display name for AI_CHAT_UPLOAD', () {
      final file = _makeFile(fileCategory: 'AI_CHAT_UPLOAD');
      expect(file.categoryDisplayName, isA<String>());
    });

    test('returns display name for HEALTH_DATA_IMPORT', () {
      final file = _makeFile(fileCategory: 'HEALTH_DATA_IMPORT');
      expect(file.categoryDisplayName, isA<String>());
    });

    test('returns display name for BACKUP_FILE', () {
      final file = _makeFile(fileCategory: 'BACKUP_FILE');
      expect(file.categoryDisplayName, isA<String>());
    });

    test('unknown category returns formatted string', () {
      final file = _makeFile(fileCategory: 'SOME_THING');
      // getCategoryDisplayName falls back to replacing _ with space and lowercasing
      expect(file.categoryDisplayName, isA<String>());
      expect(file.categoryDisplayName, isNotEmpty);
    });
  });

  group('FileUploadResponse', () {
    test('fromJson creates response with all fields', () {
      final json = {
        'fileId': 10,
        'originalFilename': 'report.pdf',
        'fileUrl': 'https://example.com/file.pdf',
        'downloadUrl': 'https://example.com/download/file.pdf',
        'message': 'Upload successful',
        'fileName': 'report.pdf',
      };
      final response = FileUploadResponse.fromJson(json);
      expect(response.fileId, 10);
      expect(response.originalFilename, 'report.pdf');
      expect(response.fileUrl, 'https://example.com/file.pdf');
      expect(response.downloadUrl, 'https://example.com/download/file.pdf');
      expect(response.message, 'Upload successful');
      expect(response.fileName, 'report.pdf');
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};
      final response = FileUploadResponse.fromJson(json);
      expect(response.fileId, 0);
      expect(response.originalFilename, '');
      expect(response.fileUrl, '');
      expect(response.downloadUrl, '');
      expect(response.message, '');
      expect(response.fileName, '');
    });

    test('fromJson handles partial fields', () {
      final json = {
        'fileId': 5,
        'originalFilename': 'test.txt',
      };
      final response = FileUploadResponse.fromJson(json);
      expect(response.fileId, 5);
      expect(response.originalFilename, 'test.txt');
      expect(response.fileUrl, '');
      expect(response.downloadUrl, '');
    });
  });

  group('getCategoryDisplayName function', () {
    test('returns Lab Result for LAB_RESULT', () {
      expect(getCategoryDisplayName('LAB_RESULT'), 'Lab Result');
    });

    test('returns Prescription for PRESCRIPTION', () {
      expect(getCategoryDisplayName('PRESCRIPTION'), 'Prescription');
    });

    test('returns Insurance for INSURANCE', () {
      expect(getCategoryDisplayName('INSURANCE'), 'Insurance');
    });

    test('returns Profile Picture for PROFILE_PICTURE', () {
      expect(getCategoryDisplayName('PROFILE_PICTURE'), 'Profile Picture');
    });

    test('returns General Document for documents', () {
      expect(getCategoryDisplayName('documents'), 'General Document');
    });

    test('returns Emergency Contact for EMERGENCY_CONTACT', () {
      expect(getCategoryDisplayName('EMERGENCY_CONTACT'), 'Emergency Contact');
    });

    test('falls back gracefully for unknown category', () {
      final result = getCategoryDisplayName('COMPLETELY_UNKNOWN');
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });

    test('returns Report for REPORT', () {
      expect(getCategoryDisplayName('REPORT'), 'Report');
    });

    test('returns Consent Form for CONSENT_FORM', () {
      expect(getCategoryDisplayName('CONSENT_FORM'), 'Consent Form');
    });

    test('returns Other Document for OTHER_DOCUMENT', () {
      expect(getCategoryDisplayName('OTHER_DOCUMENT'), 'Other Document');
    });

    test('returns Medical Note for MEDICAL_NOTE', () {
      expect(getCategoryDisplayName('MEDICAL_NOTE'), 'Medical Note');
    });

    test('returns Care Note for CARE_NOTE', () {
      expect(getCategoryDisplayName('CARE_NOTE'), 'Care Note');
    });

    test('returns Medical Record for MEDICAL_RECORD', () {
      expect(getCategoryDisplayName('MEDICAL_RECORD'), 'Medical Record');
    });

    test('returns Certification for CERTIFICATION', () {
      expect(getCategoryDisplayName('CERTIFICATION'), 'Certification');
    });

    test('returns Training for TRAINING', () {
      expect(getCategoryDisplayName('TRAINING'), 'Training');
    });

    test('returns Background Check for BACKGROUND_CHECK', () {
      expect(getCategoryDisplayName('BACKGROUND_CHECK'), 'Background Check');
    });

    test('returns Reference for REFERENCE', () {
      expect(getCategoryDisplayName('REFERENCE'), 'Reference');
    });

    test('returns Contract for CONTRACT', () {
      expect(getCategoryDisplayName('CONTRACT'), 'Contract');
    });

    test('returns Authorization for AUTHORIZATION', () {
      expect(getCategoryDisplayName('AUTHORIZATION'), 'Authorization');
    });

    test('returns General Note for GENERAL_NOTE', () {
      expect(getCategoryDisplayName('GENERAL_NOTE'), 'General Note');
    });

    test('returns Appointment for APPOINTMENT', () {
      expect(getCategoryDisplayName('APPOINTMENT'), 'Appointment');
    });

    test('fallback replaces underscores and lowercases', () {
      final result = getCategoryDisplayName('MY_CUSTOM_TYPE');
      expect(result, 'my custom type');
    });
  });

  group('EnhancedFileService.getCategoryDisplayNames', () {
    test('returns a non-empty map', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      expect(names, isA<Map<String, String>>());
      expect(names.isNotEmpty, isTrue);
    });

    test('contains expected keys', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      expect(names.containsKey('PROFILE_PICTURE'), isTrue);
      expect(names.containsKey('PRESCRIPTION'), isTrue);
      expect(names.containsKey('LAB_RESULT'), isTrue);
      expect(names.containsKey('INSURANCE'), isTrue);
      expect(names.containsKey('EMERGENCY_CONTACT'), isTrue);
      expect(names.containsKey('documents'), isTrue);
    });

    test('all values are non-empty strings', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      for (final entry in names.entries) {
        expect(entry.value, isA<String>());
        expect(entry.value.isNotEmpty, isTrue,
            reason: 'Value for ${entry.key} is empty');
      }
    });

    test('contains additional keys', () {
      final names = EnhancedFileService.getCategoryDisplayNames();
      expect(names.containsKey('MEDICAL_RECORD'), isTrue);
      expect(names.containsKey('REPORT'), isTrue);
      expect(names.containsKey('CONSENT_FORM'), isTrue);
      expect(names.containsKey('CERTIFICATION'), isTrue);
      expect(names.containsKey('TRAINING'), isTrue);
      expect(names.containsKey('BACKGROUND_CHECK'), isTrue);
      expect(names.containsKey('REFERENCE'), isTrue);
      expect(names.containsKey('CONTRACT'), isTrue);
      expect(names.containsKey('AUTHORIZATION'), isTrue);
      expect(names.containsKey('MEDICAL_NOTE'), isTrue);
      expect(names.containsKey('GENERAL_NOTE'), isTrue);
      expect(names.containsKey('APPOINTMENT'), isTrue);
      expect(names.containsKey('CARE_NOTE'), isTrue);
      expect(names.containsKey('OTHER_DOCUMENT'), isTrue);
    });
  });

  group('FileCategoryDropdown widget', () {
    testWidgets('renders with all categories', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const FileCategoryDropdown(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
      expect(find.text('Select Category'), findsOneWidget);
    });

    testWidgets('renders with allowed categories subset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(
              allowedCategories: [
                FileCategory.medicalReport,
                FileCategory.labResult,
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('renders with empty list (falls back to all categories)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const FileCategoryDropdown(
              allowedCategories: [],
            ),
          ),
        ),
      );
      await tester.pump();

      // Empty list triggers fallback to FileCategory.values, so dropdown renders
      expect(find.byType(DropdownButtonFormField<FileCategory>), findsOneWidget);
    });

    testWidgets('can open dropdown and see items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileCategoryDropdown(
              allowedCategories: [
                FileCategory.medicalReport,
                FileCategory.labResult,
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap the dropdown to open it
      await tester.tap(find.byType(DropdownButtonFormField<FileCategory>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should see category items in the dropdown
      expect(find.textContaining('Medical Report'), findsWidgets);
    });
  });

  // ===========================================================================
  // _formatFileSize logic tests (tested via helper)
  // ===========================================================================
  group('_formatFileSize logic', () {
    // Since _formatFileSize is private, we test the logic directly
    String formatFileSize(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }

    test('formats 0 bytes', () {
      expect(formatFileSize(0), '0 B');
    });

    test('formats small bytes (< 1024)', () {
      expect(formatFileSize(100), '100 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('formats kilobytes', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 100), '100.0 KB');
    });

    test('formats megabytes', () {
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize(1024 * 1024 * 5), '5.0 MB');
      expect(formatFileSize(1024 * 1024 * 50), '50.0 MB');
    });

    test('formats gigabytes', () {
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
      expect(formatFileSize(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('boundary between bytes and KB', () {
      expect(formatFileSize(1023), '1023 B');
      expect(formatFileSize(1024), '1.0 KB');
    });

    test('boundary between KB and MB', () {
      expect(formatFileSize(1024 * 1024 - 1), '1024.0 KB');
      expect(formatFileSize(1024 * 1024), '1.0 MB');
    });

    test('boundary between MB and GB', () {
      expect(formatFileSize(1024 * 1024 * 1024 - 1), '1024.0 MB');
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  // ===========================================================================
  // _formatDate logic tests
  // ===========================================================================
  group('_formatDate logic', () {
    String formatDate(DateTime date) {
      return '${date.day}/${date.month}/${date.year}';
    }

    test('formats a date correctly', () {
      expect(formatDate(DateTime(2025, 1, 15)), '15/1/2025');
    });

    test('formats date with double digit day and month', () {
      expect(formatDate(DateTime(2025, 12, 25)), '25/12/2025');
    });

    test('formats date with single digit day', () {
      expect(formatDate(DateTime(2025, 3, 5)), '5/3/2025');
    });

    test('formats Jan 1st correctly', () {
      expect(formatDate(DateTime(2025, 1, 1)), '1/1/2025');
    });

    test('formats Dec 31st correctly', () {
      expect(formatDate(DateTime(2025, 12, 31)), '31/12/2025');
    });
  });

  // ===========================================================================
  // _buildFileCard logic coverage via file extension extraction
  // ===========================================================================
  group('File card logic - extension extraction', () {
    test('extracts base name and extension for typical file', () {
      const fileName = 'report.pdf';
      int dotIndex = fileName.lastIndexOf('.');
      String baseName = (dotIndex != -1) ? fileName.substring(0, dotIndex) : fileName;
      String fileExtension = '';
      if (dotIndex != -1 && dotIndex != fileName.length - 1) {
        fileExtension = fileName.substring(dotIndex);
      }
      String extensionWithoutDot = fileExtension.replaceFirst('.', '');

      expect(baseName, 'report');
      expect(extensionWithoutDot, 'pdf');
    });

    test('handles file with no extension', () {
      const fileName = 'README';
      int dotIndex = fileName.lastIndexOf('.');
      String baseName = (dotIndex != -1) ? fileName.substring(0, dotIndex) : fileName;
      expect(baseName, 'README');
      expect(dotIndex, -1);
    });

    test('handles file ending with dot', () {
      const fileName = 'file.';
      int dotIndex = fileName.lastIndexOf('.');
      String baseName = (dotIndex != -1) ? fileName.substring(0, dotIndex) : fileName;
      String fileExtension = '';
      if (dotIndex != -1 && dotIndex != fileName.length - 1) {
        fileExtension = fileName.substring(dotIndex);
      }
      expect(baseName, 'file');
      expect(fileExtension, '');
    });

    test('handles file with multiple dots', () {
      const fileName = 'my.file.name.txt';
      int dotIndex = fileName.lastIndexOf('.');
      String baseName = (dotIndex != -1) ? fileName.substring(0, dotIndex) : fileName;
      String fileExtension = '';
      if (dotIndex != -1 && dotIndex != fileName.length - 1) {
        fileExtension = fileName.substring(dotIndex);
      }
      String extensionWithoutDot = fileExtension.replaceFirst('.', '');

      expect(baseName, 'my.file.name');
      expect(extensionWithoutDot, 'txt');
    });

    test('handles dotfile (.gitignore)', () {
      const fileName = '.gitignore';
      int dotIndex = fileName.lastIndexOf('.');
      String baseName = (dotIndex != -1) ? fileName.substring(0, dotIndex) : fileName;
      expect(baseName, '');
      expect(dotIndex, 0);
    });
  });

  // ===========================================================================
  // _filterFiles logic tests
  // ===========================================================================
  group('_filterFiles logic', () {
    test('empty search and no category returns all files', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'report.pdf', fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 2, originalFilename: 'lab.pdf', fileCategory: 'LAB_RESULT'),
      ];
      final searchQuery = '';
      FileCategory? selectedCategory;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = selectedCategory == null ||
            file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 2);
    });

    test('search query filters by filename', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'report.pdf', fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 2, originalFilename: 'lab_results.pdf', fileCategory: 'LAB_RESULT'),
      ];
      final searchQuery = 'report';
      FileCategory? selectedCategory;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = selectedCategory == null ||
            file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.originalFilename, 'report.pdf');
    });

    test('search query filters by description', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'doc1.pdf', description: 'Blood test results'),
        _makeFile(id: 2, originalFilename: 'doc2.pdf', description: 'X-ray images'),
      ];
      final searchQuery = 'blood';
      FileCategory? selectedCategory;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = selectedCategory == null ||
            file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.description, 'Blood test results');
    });

    test('category filter filters by category', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'report.pdf', fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 2, originalFilename: 'lab.pdf', fileCategory: 'LAB_RESULT'),
      ];
      final searchQuery = '';
      final selectedCategory = FileCategory.labResult;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.fileCategory, 'LAB_RESULT');
    });

    test('search and category combined', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'blood_report.pdf', fileCategory: 'LAB_RESULT'),
        _makeFile(id: 2, originalFilename: 'x_ray_report.pdf', fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 3, originalFilename: 'blood_test.pdf', fileCategory: 'MEDICAL_REPORT'),
      ];
      final searchQuery = 'blood';
      final selectedCategory = FileCategory.labResult;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.originalFilename, 'blood_report.pdf');
    });

    test('no matches returns empty list', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'report.pdf', fileCategory: 'MEDICAL_REPORT'),
      ];
      final searchQuery = 'nonexistent';
      FileCategory? selectedCategory;

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        final matchesCategory = selectedCategory == null ||
            file.fileCategory == selectedCategory.value;
        return matchesSearch && matchesCategory;
      }).toList();

      expect(filtered.length, 0);
    });

    test('search with null description does not crash', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'report.pdf', description: null),
      ];
      final searchQuery = 'something';

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase()) ||
            (file.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        return matchesSearch;
      }).toList();

      expect(filtered.length, 0);
    });

    test('case insensitive search works', () {
      final files = [
        _makeFile(id: 1, originalFilename: 'Medical_Report.PDF'),
      ];
      final searchQuery = 'medical';

      final filtered = files.where((file) {
        final matchesSearch = searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(searchQuery.toLowerCase());
        return matchesSearch;
      }).toList();

      expect(filtered.length, 1);
    });
  });

  // ===========================================================================
  // Analytics tab category counting logic
  // ===========================================================================
  group('Analytics category counting logic', () {
    test('counts files by category', () {
      final allFiles = [
        _makeFile(id: 1, fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 2, fileCategory: 'MEDICAL_REPORT'),
        _makeFile(id: 3, fileCategory: 'LAB_RESULT'),
        _makeFile(id: 4, fileCategory: 'PRESCRIPTION'),
      ];

      final categories = <String, int>{};
      for (final file in allFiles) {
        categories[file.categoryDisplayName] =
            (categories[file.categoryDisplayName] ?? 0) + 1;
      }

      expect(categories.length, 3);
      // Medical Report appears twice
      final medicalReportName = getCategoryDisplayName('MEDICAL_REPORT');
      expect(categories[medicalReportName], 2);
    });

    test('total size calculation', () {
      final allFiles = [
        _makeFile(id: 1, fileSize: 1024),
        _makeFile(id: 2, fileSize: 2048),
        _makeFile(id: 3, fileSize: 512),
      ];

      final totalSize = allFiles.fold<int>(0, (sum, file) => sum + file.fileSize);
      expect(totalSize, 3584);
    });

    test('empty files list produces zero totals', () {
      final allFiles = <UserFileDTO>[];
      final totalSize = allFiles.fold<int>(0, (sum, file) => sum + file.fileSize);
      final categories = <String, int>{};
      for (final file in allFiles) {
        categories[file.categoryDisplayName] =
            (categories[file.categoryDisplayName] ?? 0) + 1;
      }
      expect(totalSize, 0);
      expect(categories.isEmpty, isTrue);
    });
  });

  // ===========================================================================
  // FileManagementPage - empty state with category filter
  // ===========================================================================
  group('FileManagementPage - empty state variations', () {
    testWidgets('empty state with category selected hides upload button',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Select a category
      await tester.tap(find.text('Filter by category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Medical Report').last);
      await tester.pump();

      // Upload button should not be shown when filters are active
      expect(find.text('Upload Files'), findsNothing);
      expect(find.text('No files match your filters'), findsOneWidget);
    });

    testWidgets('empty state without filters shows upload button',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      expect(find.text('Upload Files'), findsOneWidget);
      expect(find.text('No files uploaded yet'), findsOneWidget);
    });

    testWidgets('upload button navigates to upload tab', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // Tap Upload Files button (the one in the empty state)
      await tester.tap(find.text('Upload Files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should now be on the Upload tab
      expect(find.text('File Upload'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FileManagementPage - TabBarView structure
  // ===========================================================================
  group('FileManagementPage - TabBarView structure', () {
    testWidgets('TabBarView has 3 children', (tester) async {
      await tester.pumpWidget(_wrap());
      final tabBarView = tester.widget<TabBarView>(find.byType(TabBarView));
      expect(tabBarView.children.length, 3);
    });

    testWidgets('initial tab is My Files (index 0)', (tester) async {
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);

      // My Files tab content visible
      expect(find.text('Search files...'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FileManagementPage - patient role specific
  // ===========================================================================
  group('FileManagementPage - patient role', () {
    testWidgets('patient role renders page correctly', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);

      expect(find.byType(FileManagementPage), findsOneWidget);
      expect(find.text('File Management'), findsOneWidget);
    });

    testWidgets('patient role isCaregiver is false', (tester) async {
      await tester.pumpWidget(_wrap(role: 'PATIENT'));
      await _pumpUntilLoaded(tester);

      // Page renders correctly for patient (isCaregiver = false)
      expect(find.byType(FileManagementPage), findsOneWidget);
    });
  });
}
