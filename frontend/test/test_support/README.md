# Frontend Test Support

## Purpose
This folder provides shared fixture data and widget bootstrap helpers for Flutter tests.  
The goal is to keep tests deterministic and reduce repeated mock setup in each file.

## Scope
- Test-only fake session/auth payload builders.
- Shared `pump` helper to wrap widgets in common app scaffolding.
- Utilities used by unit/widget tests that should avoid live backend/env dependencies.

## Non-Goals
- No production runtime behavior changes.
- No replacement of all existing tests in one pass.
- No introduction of integration-test network flows.

## Quick Usage
```dart
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_support/fixtures.dart';
import 'test_support/pump_app.dart';

final user = fakePatientUser();
await pumpCareConnectApp(
  tester,
  const Text('Hello'),
  providers: [
    Provider<UserSession>.value(value: user),
  ],
);
```

`pumpCareConnectApp` wraps the child in a `MaterialApp` with the app's
localization delegates (English by default; pass `locale:` for another
language), so widgets that call `AppLocalizations.of(context)!` render
without extra setup. `providers` is optional. Prefer it over a hand-rolled
`MaterialApp` in new tests; existing tests can move over when they are next
touched.

## Ownership
Owned by the testing workstream for REQ-2.2 (Flutter mock data framework).
