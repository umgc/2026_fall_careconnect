# Usability Tap-Testing — Hand-off Guide

How to add a **golden-path tap check** for a follow-on feature: a headless test
that drives a feature's *designed shortest path* and reports the **minimum taps**
required to complete it. These numbers feed the Milestone-4 taps-per-task
usability report and the `kUsabilityOptimalTaps` / `kUsabilityFlows` catalogs.

- Instrument: `lib/features/telemetry/usability_tracker.dart`
- App-wide wiring: `lib/config/router/app_router.dart` (`TelemetryGoRouterObserver`)
- Harness: `test/usability/golden_flow.dart`
- Examples (12 flows): `test/usability/golden_flow_test.dart`

Run them:

```bash
flutter test test/usability/golden_flow_test.dart
dart analyze test/usability/golden_flow.dart test/usability/golden_flow_test.dart
```

---

## 1. What a "tap check" measures

`UsabilityTapCounter` wraps the app and counts every **pointer-down** as one tap.
A golden-path test drives *only the designed minimal steps*, so the count the
instrument reports **is** the minimum taps for that flow.

**What counts as a tap** (this matters for consistency):

| Action | Counts? |
|---|---|
| `tester.tap(...)` on any control | ✅ 1 tap |
| Tapping a text field to focus it before typing | ✅ 1 tap — **do this** for each field a user must fill |
| `tester.enterText(...)` | ❌ text entry is keyboard, not a tap |
| A speech/platform-channel message (`_sendVoiceResult`) | ❌ not a pointer event |
| Invoking `onPressed()` programmatically | ❌ **not counted** — always use `tester.tap` |
| `ensureVisible`, `pump`, `pumpAndSettle` | ❌ no pointer event |

Convention: **tap a field to focus it, then `enterText`.** (e.g. login = tap
username + tap password + tap Sign In = 3.)

---

## 2. The recipe (five steps)

### Step 1 — Find the screen and borrow a mock recipe
Locate the feature's screen and its **existing widget test**. The existing test
almost always shows how to pump the screen and mock its services. Reuse that
wrapper. If the existing test only covers load/error (never a *successful*
submit), you'll be pioneering the success mock — budget extra time.

### Step 2 — Identify entry, the minimal tap path, and the completion signal
- **Entry:** which screen/route the flow starts on, and its constructor params.
- **Minimal path:** the fewest designed taps to complete (focus fields, pick
  required dropdowns/pickers, submit). Check the submit method's validation to
  see what's *required* vs optional.
- **Completion signal:** what proves success — usually a `context.go/push` to a
  route (add a stub destination), a success `SnackBar`, or a `Navigator` push.

### Step 3 — Build the app wrapper
Mirror the existing test: providers + router + **localization delegates**
(most screens now call `AppLocalizations.of(context)!` and crash without them).

```dart
Widget _myApp() => ChangeNotifierProvider<UserProvider>.value(
  value: MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1)),
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/my-screen',
      routes: [
        GoRoute(path: '/my-screen', builder: (_, __) => const MyScreen(...)),
        // stub every route the flow navigates to, so context.push/go resolves:
        GoRoute(path: '/success', builder: (_, __) => const Scaffold(body: Text('Success Page'))),
      ],
    ),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  ),
);
```

### Step 4 — Mock services so the happy path completes offline
Pick the seam that matches how the screen talks to the network (see §3).

### Step 5 — Measure with the harness
```dart
testWidgets('golden path — My feature (minimum taps)', (tester) async {
  // ...install mocks + addTearDown...
  final result = await measureGoldenFlow(
    tester,
    name: 'flow_my_feature',
    optimalTaps: 3,                 // your expected designed count
    app: _myApp(),
    drive: (t) async {
      await t.pumpAndSettle();      // let the screen load
      // ...only the designed minimal taps...
      await t.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await t.pumpAndSettle();
    },
  );
  // ignore: avoid_print
  print('GOLDEN flow_my_feature -> minimum taps = ${result.taps}');
  expect(result.taps, 3);
  expect(find.text('Success Page'), findsOneWidget); // completion signal
});
```

---

## 3. Which network seam to mock (decision table)

Grep the screen (and the service it calls) for the transport, then pick:

| The screen/service calls… | Mock it with |
|---|---|
| `ApiService.<method>` (e.g. `getCaregiverPatients`, `checkEmailExists`) | `ApiService.debugSetHttpClient(MockClient(handler))` + `addTearDown(ApiService.debugResetHttpClient)` |
| `EvvService` (uses `ApiServiceOffline.httpClient`) | `ApiServiceOffline.debugOverrideHttpClient(MockClient(handler))` + reset to `null` |
| A **direct `http.post/get`** (e.g. `AuthService.resetPassword`) | `HttpOverrides.global = FakeHttpOverrides((m,u) => FakeResponse(200, '{...}'))` (see `test/helpers/fake_http_overrides.dart`); reset to `null` |
| Native plugin via method channel | `setMockMethodCallHandler(const MethodChannel('...'), ...)` |

Common **method channels** (stub the ones the flow touches):

| Plugin | Channel | Minimal handler |
|---|---|---|
| Secure storage | `plugins.it_nomads.com/flutter_secure_storage` | `readAll → {}`, `read → 'mock_token'` |
| Connectivity | `dev.fluttercommunity.plus/connectivity` | `check → ['wifi']` (online) |
| Speech-to-text | `plugin.csdcorp.com/speech_to_text` | `has_permission/initialize/listen → true`; feed results with a `textRecognition` platform message |
| Wake word | `flutter.picovoice.ai/porcupine_manager` | `→ null` |

For **native GPS (`Geolocator`)** there is no simple channel stub — it needs a
`GeolocatorPlatform` fake (`extends GeolocatorPlatform with MockPlatformInterfaceMixin`).
Prefer a non-GPS path where one exists (e.g. EVV "Use Patient Address"), or push
the GPS variant to an on-device `integration_test`.

**Shared EVV helper:** `_setupEvvPatientMocks()` in `golden_flow_test.dart`
installs secure-storage + connectivity + a one-patient `getCaregiverPatients`
response and its teardowns — reuse it for any EVV screen that loads a patient.

---

## 4. Multi-screen goals → flow mode

The router auto-brackets **each route** as its own task. For a goal that spans
several screens (e.g. schedule → confirm → success), use **flow mode** so taps
accrue to the whole goal:

- **In a test:** `measureGoldenFlow` already brackets the whole `drive` as one
  flow via `startFlow`/`endFlow`, so a single test that navigates across screens
  measures the end-to-end total.
- **In the app (production instrumentation):** declare the goal in
  `kUsabilityFlows` (start route, end route, in-flow screens, optimalTaps) and
  the observer measures it end-to-end automatically — no per-screen wiring.

Feed a measured minimum back into `kUsabilityOptimalTaps['/route'] = N;` (or a
`UsabilityFlow.optimalTaps`) to switch that route/flow from `unknown` to a
scored Easy/Medium/Hard difficulty.

---

## 5. Gotchas (all hit while building the 12 flows)

- **Button labels/types vary.** "Continue" vs "Confirm"; `FilledButton` vs
  `ElevatedButton` vs `TextButton`. If a `widgetWithText` finder finds 0, check
  the actual type/label. For **localized** buttons, find by *type*
  (`find.byType(ElevatedButton).first`), not by text.
- **Off-screen controls.** Tall screens push the submit button below the fold —
  `await tester.ensureVisible(finder)` before tapping, and/or set a big surface:
  `tester.view.physicalSize = const Size(1600, 2400)` (reset in teardown).
- **Overflow noise.** Some screens (LoginPage) overflow by design; wrap with an
  overflow-suppressing `FlutterError.onError` (see `_suppressOverflow`).
- **Placeholders aren't obvious.** A "time" field's tap target was the text
  `'--:-- --'`, not a label — read the widget to find the real text.
- **Real async I/O** (dart:io `http` via `FakeHttpOverrides`, or a delayed
  `context.go`) won't advance under `pump`. Do the submit inside
  `tester.runAsync(() async { await tester.tap(...); await Future.delayed(...); })`.
- **Plugin timers.** speech_to_text leaves a 2s/12s timer — drain with
  `for (var i=0;i<5;i++) await tester.pump(const Duration(seconds:3));` before
  teardown, or you'll get "A Timer is still pending".
- **Stale generated l10n.** If a test fails to compile with
  `AppLocalizations` getter errors after a pull, run `flutter gen-l10n`
  (the generated file is gitignored).
- **Shader exceptions** on `tester.tap` are already suppressed globally by
  `test/flutter_test_config.dart`, so tap normally — do **not** copy the
  workaround of invoking `onPressed()` directly (it wouldn't count as a tap).

---

## 6. Candidate follow-on features (prioritized)

**Quick** (reuse `_setupEvvPatientMocks` + a stub destination):
- Remaining EVV micro-flows / corrections, offline-sync, visit-history entry.

**Medium** (one form + one mock, expect a finder iteration or two):
- **Add Patient** — needs `checkEmailExists → {'exists':true}`,
  `sendConnectionRequest` (a `ConnectionRequestResponse` success body), a
  relationship + message field, and `navigateToDashboard` routes.
- **Symptom logging** — screen is patient-ID-gated; resolve a patient first,
  then drive the add-symptom form (no existing success recipe — investigate).
- Password-reset **request** variant, OAuth callback.

**Heavy** (multi-step wizards / hard-to-mock deps — consider on-device
`integration_test` instead of headless):
- **Sign-up / registration** — 5-step wizard with date + gender pickers.
- **Payments** (Stripe SDK), **Secure messaging** (WebSocket).
- **EVV check-in/out GPS variant** — needs a `GeolocatorPlatform` fake.

---

## 7. Current baseline — 12 measured minimums

| Flow | Min taps |
|---|--:|
| Request password reset · Log in · Set new password | 2 · 3 · 4 |
| Voice command navigation | 2 |
| EVV: select patient · start visit · check-in · ready-to-checkout · check-out · complete-visit | 1 · 3 · 2 · 1 · 2 · 1 |
| Schedule a new visit · File an incident report | 8 · 8 |

Notes: EVV check-in/out and complete-visit are **page-level** variants
(patient-address / submit step), not the full multi-screen journeys the M4 slide
implied — log them as distinct measurements.
