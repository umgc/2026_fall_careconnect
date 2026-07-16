# Proposal: Injectable HTTP Client for Auth Testability (Method 1)

**Status:** Proposal — for the team to accept or decline.
**Author:** drafted while raising `lib/features/auth` toward the 95% coverage gate.
**Date:** 2026-06-25

## Problem

The auth pages (`AlexaLoginPage`, `login_page`, `password_reset_page`, …) are
mostly uncovered in their **submit handlers** — the code that calls the backend.
Those handlers route through service methods that ultimately perform HTTP. To
cover the success / failure / error branches in a **unit/widget test**, the HTTP
call must be replaceable with a canned response. If it isn't, a test either:

- hits a real socket (`http.post` → `localhost:8080`), which is slow, flaky, and
  fails in CI where no backend is running, or
- never executes the branch at all (so the lines stay red).

## Current state (important)

The injectable-client pattern is **already partially implemented** and we should
build on it rather than invent something new:

```dart
// lib/services/api_service.dart
class ApiService {
  static http.Client _httpClient = ApiServiceOffline.httpClient;

  /// Test seam — swap in a mock client.
  static void debugSetHttpClient(http.Client client) { _httpClient.close(); _httpClient = client; }
  static void debugResetHttpClient()                 { _httpClient.close(); _httpClient = http.Client(); }

  static Future<http.Response> login(String email, String password) async =>
      _httpClient.post(Uri.parse('${ApiConstants.auth}/login'), /* ... */);
}
```

Everything routed through `ApiService` (login, `password/forgot`, `password/reset`,
profile, …) is **already mockable today** via `ApiService.debugSetHttpClient(...)`.

The gap is the auth calls that **bypass `ApiService`** and use the top-level
`http.post` from `package:http` directly, e.g. in `auth_service.dart`:

- `AuthService.getAlexaAuthorizationCode(...)` (`POST /v1/api/auth/sso/alexa/code`)
- `AuthService.register(...)`, `registerCaregiver(...)`, and other direct `http.post` calls

Top-level `http.post` has **no test seam** — it cannot be mocked without either
`HttpOverrides` (brittle dart:io boilerplate) or a refactor.

## Proposal

Adopt one injectable `http.Client` seam for **all** auth network calls, so every
submit branch is coverable with `package:http`'s `MockClient`.

**Option A — route everything through `ApiService` (preferred).**
Move the remaining direct `http.post` calls in `auth_service.dart` into
`ApiService` methods that use `_httpClient`. No new seam; reuses the one that
already exists and is already mocked in tests.

```dart
// Before (auth_service.dart) — not mockable
final response = await http.post(Uri.parse('$host/v1/api/auth/sso/alexa/code'),
    headers: {...}, body: jsonEncode({...}));

// After — mockable via the existing ApiService seam
final response = await ApiService.getAlexaCode(token: token);
```

**Option B — give `AuthService` its own injectable client.**
Mirror the `ApiService` pattern on `AuthService` if you prefer not to grow
`ApiService`:

```dart
class AuthService {
  static http.Client _client = http.Client();
  static void debugSetHttpClient(http.Client c) { _client.close(); _client = c; }
  static void debugResetHttpClient()            { _client.close(); _client = http.Client(); }
  // replace every `http.post(...)` with `_client.post(...)`
}
```

## How tests would consume it

```dart
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

setUp(() {
  ApiService.debugSetHttpClient(MockClient((req) async {
    if (req.url.path.endsWith('/login')) {
      return http.Response('{"error":"Invalid credentials"}', 401);
    }
    return http.Response('{}', 404);
  }));
});
tearDown(ApiService.debugResetHttpClient);
```

This makes the success (200), failure (4xx), and transport-error (`throw`)
branches deterministic in CI with no real network.

## Trade-offs

| | Pro | Con |
|---|---|---|
| **Method 1 (this doc): injectable client** | Deterministic, fast, CI-safe; uses `package:http`'s official `MockClient`; one consistent seam; covers 100% of auth network branches | Requires a small, **behavior-neutral** app-code change to route the remaining direct `http.post` calls through the seam |
| **Method 2: `HttpOverrides` (test-only)** | Zero app-code change | Verbose dart:io `HttpClient`/`HttpClientResponse` fakes; brittle; intercepts *all* I/O including unrelated calls |

## Recommendation

The team already started Method 1 (`ApiService.debugSetHttpClient`). Finishing it —
routing the few remaining direct `http.post` auth calls through the same seam — is
behavior-neutral and unblocks deterministic coverage for every auth page,
including the Alexa OAuth and registration flows that Method 2 can only reach with
fragile dart:io fakes.

**Interim:** until the team decides, the test suite uses the **existing**
`ApiService.debugSetHttpClient` seam (test-only, no app change) for the login and
password-reset paths. The Alexa-code and registration branches remain out of reach
until their direct `http.post` calls are moved behind the seam per this proposal.
