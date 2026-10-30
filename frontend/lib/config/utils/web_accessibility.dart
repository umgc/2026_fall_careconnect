import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

/// Turns on the accessibility tree at startup on the web.
///
/// Flutter web builds its semantics tree only after a screen reader user
/// presses a hidden "Enable accessibility" button. NVDA users who never press
/// it hear "blank" on every screen, and announcements such as the sign-in
/// error (#456) have nowhere to go. Mobile platforms enable semantics on
/// their own, so this does nothing there.
///
/// Returns the handle that keeps semantics on. The app never disposes it, so
/// the tree stays on for the app's whole lifetime.
SemanticsHandle? enableWebAccessibility({bool isWeb = kIsWeb}) {
  if (!isWeb) return null;
  return SemanticsBinding.instance.ensureSemantics();
}
