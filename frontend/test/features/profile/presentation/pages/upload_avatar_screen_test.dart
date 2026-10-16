// Tests for UploadAvatarScreen
// (lib/features/profile/presentation/pages/upload_avatar_screen.dart).
//
// No API calls in initState — upload only fires on button press.
// Tests cover initial render and UI element presence.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/profile/presentation/pages/upload_avatar_screen.dart';

Widget _wrap() => const MaterialApp(home: UploadAvatarScreen());

void main() {
  group('UploadAvatarScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(UploadAvatarScreen), findsOneWidget);
    });

    testWidgets('shows "Upload Avatar" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Upload Avatar'), findsOneWidget);
    });

    testWidgets('shows "Pick Avatar" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Pick Avatar'), findsOneWidget);
    });

    testWidgets('shows "Upload" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Upload'), findsOneWidget);
    });

    testWidgets('"Upload" button is enabled when not uploading', (tester) async {
      await tester.pumpWidget(_wrap());
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Upload'),
      );
      // isUploading=false → onPressed is not null.
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows image icon on "Pick Avatar" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.image), findsOneWidget);
    });

    testWidgets('does NOT show "Remove Image" button initially', (tester) async {
      // "Remove Image" only appears when a file has been selected.
      await tester.pumpWidget(_wrap());
      expect(find.text('Remove Image'), findsNothing);
    });

    testWidgets('does NOT show preview CircleAvatar initially', (tester) async {
      // Preview only shown after successful upload.
      await tester.pumpWidget(_wrap());
      expect(find.text('Preview:'), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('does NOT show CircularProgressIndicator initially',
        (tester) async {
      // isUploading=false → no spinner.
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
