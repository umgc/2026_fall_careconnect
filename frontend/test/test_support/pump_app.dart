import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Shared widget bootstrap helper for frontend tests.
///
/// This helper standardizes how tests pump widgets with app-level wrappers so
/// each test does not duplicate provider/material setup.
///
/// The [MaterialApp] carries the app's localization delegates, so widgets that
/// call `AppLocalizations.of(context)!` work without extra setup. Pass
/// [locale] to render in a language other than English.
Future<void> pumpCareConnectApp(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget> providers = const [],
  Locale locale = const Locale('en'),
}) async {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  // MultiProvider asserts on an empty list, so only wrap when needed.
  await tester.pumpWidget(
    providers.isEmpty ? app : MultiProvider(providers: providers, child: app),
  );
}
