# PR Plan — Integrate an Accessibility subsystem into CareConnect

**Target repo:** `umgc/2026_summer_careconnect` → `frontend/` (package `care_connect_app`)
**Source:** SWEN 661 UI-course prototype (D. Kinchen `AccessibilityModel` / `AccessibilityProvider`, adapted)
**Goal:** Add app-wide text scaling, high contrast, tremor-mode touch targets, and a settings screen — the one genuinely non-duplicative contribution from the UI prototypes.

This lands the feature in two phases so the high-value, low-risk part (real large-print support) can ship inside a small budget, with high-contrast theming as an optional follow-up.

---

## Files added (drop in as-is)

```
frontend/lib/features/accessibility/models/accessibility_model.dart
frontend/lib/features/accessibility/providers/accessibility_provider.dart
frontend/lib/features/accessibility/presentation/pages/accessibility_page.dart
frontend/test/features/accessibility/accessibility_model_test.dart
```

These have zero dependency on the prototype's own theme/widget files — the page is written against the capstone's `AppTheme` and `provider`.

---

## PHASE 1 — Text scaling + touch targets + screen + navigation

### Edit 1 — Register the provider (`frontend/lib/main.dart`)

Add the import with the other provider imports near the top:

```dart
import 'features/accessibility/providers/accessibility_provider.dart';
```

In `main()`, add one line to the `MultiProvider` `providers:` list (alongside the existing `ChangeNotifierProvider.value(...)` entries):

```dart
        providers: [
          ChangeNotifierProvider.value(value: userProvider),
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider.value(value: shortcutProvider),
          ChangeNotifierProvider.value(value: localeProvider),
          ChangeNotifierProvider(create: (_) => TaskTypeManager()),
          ChangeNotifierProvider(create: (_) => AccessibilityProvider()), // <-- add
        ],
```

### Edit 2 — Drive text scale from the provider, remove the 1.2 cap (`frontend/lib/main.dart`)

In the `build()` method of `_CareConnectAppWithErrorBoundaryState`, read the provider next to the existing ones (around line ~272):

```dart
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final accessibility = Provider.of<AccessibilityProvider>(context); // <-- add
```

Then, in the `MaterialApp.router` `builder:` (around line ~334), **replace** the current clamp:

```dart
      // BEFORE
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final textScaleFactor = mediaQuery.textScaleFactor.clamp(0.8, 1.2);
```

with:

```dart
      // AFTER
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // Combine the OS text scale with the in-app accessibility setting.
        // The old hard cap of 1.2 silently defeated large-print users;
        // "Largest" needs 1.5x. Ceiling of 2.0 keeps layouts from breaking.
        final osScale = mediaQuery.textScaler.scale(1.0);
        final textScaleFactor =
            (osScale * accessibility.textScale).clamp(0.8, 2.0);
```

The line further down that already reads
`textScaler: TextScaler.linear(textScaleFactor),` needs **no change** — it now
receives the provider-driven value.

> Why this is the single most important change: the app currently caps text at
> 1.2x, so the "Largest" setting would appear to do nothing. Removing the cap is
> what actually makes large-print work.

### Edit 3 — Register a route (`frontend/lib/config/router/app_router.dart`)

Add the import near the other feature imports:

```dart
import '../../features/accessibility/presentation/pages/accessibility_page.dart';
```

Add a `GoRoute` inside the `routes:` list:

```dart
    GoRoute(
      path: '/accessibility',
      builder: (_, __) => const AccessibilityPage(),
    ),
```

### Edit 4 — Add a drawer entry (matches the existing sibling pattern)

In **`frontend/lib/config/navigation/caregiver_more_features_bottom_drawer.dart`**
(and the patient equivalent `patient_more_features_bottom_drawer.dart`), add the
import:

```dart
import 'package:care_connect_app/features/accessibility/presentation/pages/accessibility_page.dart';
```

and add a `FeatureItem` to the `features` list, using the same `Navigator.push`
form the other items use:

```dart
      FeatureItem(
        icon: Icons.accessibility_new,
        iconColor: Colors.blue,
        title: 'Accessibility',
        subtitle: 'Text size, contrast, and steadiness settings.',
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AccessibilityPage(),
            ),
          );
        },
      ),
```

### Edit 5 — Enforce the touch-target floor where it matters

Optional but recommended for the demo: anywhere you build primary action buttons
for low-vision flows, size them from the provider instead of hard-coded heights,
e.g.:

```dart
final a11y = context.watch<AccessibilityProvider>();
SizedBox(
  height: a11y.primaryButtonHeight, // 64 / 72 (tremor)
  child: ElevatedButton(...),
);
```

Start with the emergency (`emergency_qr`) and medication-tracker action buttons —
those are the highest-value low-vision surfaces and give a visible tremor-mode
effect.

### Verify Phase 1

```bash
cd frontend
flutter pub get
flutter analyze
flutter test test/features/accessibility/
flutter run    # toggle Largest text + tremor mode from the drawer screen
```

---

## PHASE 2 (optional) — High-contrast theme + reduce-motion

Only do this if Phase 1 landed with budget to spare.

### Add high-contrast theme variants (`frontend/lib/config/theme/app_theme.dart`)

Add getters that reuse the existing themes but override the color scheme for
maximum contrast (pure black text on white, thicker card borders):

```dart
  static ThemeData get highContrastLightTheme => lightTheme.copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF004A5C),      // darkened primary
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
          error: Color(0xFFB00020),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
```

### Select it in `main.dart`

In `build()`, choose the theme based on the flag:

```dart
      theme: (accessibility.highContrast
              ? AppTheme.highContrastLightTheme
              : AppTheme.lightTheme)
          .copyWith(/* keep the existing copyWith chain */),
```

### Reduce motion

In the `pageTransitionsTheme`, swap to `FadeUpwardsPageTransitionsBuilder()` (or a
no-animation builder) for all platforms when `accessibility.reduceMotion` is true.

---

## What was intentionally NOT integrated

The prototypes' other screens (login, dashboard, profile, medication,
appointments, symptoms, emergency, AI assistant) **already exist** in the capstone
under `features/auth`, `features/dashboard`, `features/profile`,
`features/health/medication-tracker`, `features/health/symptom-tracker`,
`features/health/virtual_check_in`, `features/emergency_qr`, and `features/ai`.
Importing them would create duplicate, competing implementations. Treat those
prototype screens as **design/UX reference only** (esp. the Foss et al.
screenshots and the Clearcare low-vision layouts), and log them as
"reference — deferred."

The Clearcare prototype uses **Riverpod**; porting its screens would mean
rewriting `ConsumerWidget`/`ref.watch` to `context.watch` and pulling
`flutter_riverpod` into a Provider codebase — not worth it for screens you already
have.

---

## Suggested commit sequence

1. `feat(a11y): add accessibility model, provider, and settings screen`
2. `feat(a11y): drive app text scale from accessibility provider (remove 1.2 cap)`
3. `feat(a11y): add accessibility route + drawer entry`
4. `test(a11y): unit tests for accessibility model`
5. *(phase 2)* `feat(a11y): high-contrast theme + reduce-motion transitions`
