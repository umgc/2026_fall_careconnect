// Golden-render test used to produce documentation screenshots of the real
// EpicConnectTile widget (the Settings "Connected Services" / Epic connect surface).
//
// Generate the PNGs with:
//   flutter test test/goldens/epic_connect_golden_test.dart --update-goldens
//
// These render the ACTUAL production EpicConnectTile widget. With no backend
// reachable, EpicService.status() fails fast and the tile settles into its
// disconnected ("Connect") state — exactly what a user sees before linking Epic.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/widgets/epic_connect_tile.dart';

/// Register a real TTF as the default 'Roboto' family so golden text is legible
/// instead of the flutter_test placeholder boxes.
Future<void> _loadRealFonts() async {
  const candidates = [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\calibri.ttf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      final data = ByteData.view(Uint8List.fromList(bytes).buffer);
      for (final family in ['Roboto', 'packages/care_connect_app/Roboto']) {
        final loader = FontLoader(family)..addFont(Future.value(data));
        await loader.load();
      }
      break;
    }
  }
  // Material Icons so leading icons render instead of boxes.
  const iconFont =
      r'C:\flutter\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';
  final iconFile = File(iconFont);
  if (iconFile.existsSync()) {
    final bytes = iconFile.readAsBytesSync();
    final data = ByteData.view(Uint8List.fromList(bytes).buffer);
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(data));
    await loader.load();
  }
}

Future<void> _settle(WidgetTester tester) async {
  // Let the real async status() call complete (fails -> caught -> _loading=false).
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(seconds: 2));
  });
  await tester.pump();
}

void main() {
  setUpAll(_loadRealFonts);

  final theme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF00695C),
    fontFamily: 'Roboto',
  );

  testWidgets('Settings section with Epic connect tile', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(414 * 2, 496 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(Icons.lock, color: theme.colorScheme.primary),
                title: const Text('Change Password'),
              ),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Connected Services',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const EpicConnectTile(),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text('Logout', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
        ),
      ),
    ));

    await _settle(tester);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('epic_settings_section.png'));
  });

  testWidgets('Epic connect tile close-up', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(414 * 2, 132 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: const EpicConnectTile(),
          ),
        ),
      ),
    ));

    await _settle(tester);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('epic_connect_tile.png'));
  });
}
