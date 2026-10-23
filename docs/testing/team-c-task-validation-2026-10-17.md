# Team C task validation and closure evidence

October 17, 2026, Eastern Time. Prepared for Terence Boyce with Codex assistance.
Scope: WBS 4.2.5 (M2), 4.2.7 (M1), and 4.2.11 (M1).

## Baseline and method

Fresh checkout of `team-c-develop` at `36dbdf13bad976418ceade39878c540bbe989856`.
PRs #330, #331, and #347 are independently approved and merged. This branch adds
small fixes and review evidence; it does not declare an accepted release.

Tools: Flutter 3.47.7, Dart 3.13.5, Maven 3.9.9, and Homebrew JDK 17.0.14.
Flutter dependencies and generated localization were set up in the fresh checkout.
No local secrets were copied from the main checkout. Tests use their configured
synthetic/mock or in-memory test setup. No live Cerner or deployment check was run.

## Results

| Check | Result | Evidence and limit |
| --- | --- | --- |
| Focused language suite, fresh baseline | 89 passed | Locale provider, localization, and language picker suites. |
| Focused language suite after cleanup | 89 passed | Same three suites; visible English/Spanish/system-default text and preference changes. |
| Focused language analysis before cleanup | Three warnings | Two unused fields and an unused local value. |
| Focused language analysis after cleanup | No issues | Five relevant source/test files. |
| Broad frontend tests | 11,088 passed; 448 failed; 8 skipped | Completed, failing run. 445 error outcomes and 3 assertion-failure outcomes. |
| Full frontend analysis after cleanup | 1,477 issues | 130 warnings, 1,347 info findings, no error-severity findings. This is not a clean analysis pass. |
| Web release build, baseline | Passed | Build output exists. WASM compatibility warnings remain; no browser/runtime smoke claimed. |
| Full backend baseline | 7,348 run; 1 failure; 56 errors; 0 skips | Complete failing run on the merged baseline. |
| First backend repair run | 205 run; 0 assertion failures; 56 errors | Fixed SSM count and held-item schema; startup then exposed a second filtered H2 index. |
| After both schema repairs | 208 run; 17 assertion failures; 0 errors | Startup errors cleared; the email fixtures then reached stale endpoint/auth assertions. |
| Corrected email fixtures | 32 passed; 0 failures/errors/skips | Uses the Gmail status route, synthetic JWT actors, and distinct real patient rows. |
| Final combined affected-backend run | 208 passed; 0 failures/errors/skips | JDK 17. Includes the 7 new schema checks, configuration checks, call/email integration tests, and Cerner suites. |

The broad frontend run used a 600-second limit, but completed in about 509 seconds.
Its failures were not turned into skips. Frequent affected files include file
management, AI chat, the calendar assistant, and medication tracker tests. Those
failures require their owners' test-fixture/product review. They were not repaired
by changing unrelated app behavior.

## Fixes

1. Removed unused values from LanguagePicker. Layout, selection, and saved-locale
   behavior stay covered by the 89-test regression suite.
2. Updated the SSM test's stale count from 12 to 13 and added an assertion for
   `careconnect.kvs.stream-pool-arn`. The existing configured key was missing
   from the test's expected count; no real parameter value or AWS setting changed.
3. Replaced unsupported filtered-index syntax in the H2-only held-item and
   consent setup with generated nullable keys and unique indexes. This keeps
   pending-question and active-grant uniqueness while allowing closed/revoked
   history. PostgreSQL SQL, migrations, and runtime behavior are outside this edit.

Seven new in-memory database checks cover duplicate rejection, key release after
status changes, missing hashes, separate patient/surface/grantee/scope keys, and
schema replay. The application startup tests are rerun as a separate boundary.
The new schema tests do not prove PostgreSQL storage or production security.

4. Updated EmailOAuthFlowE2ETest to use the existing Gmail status route, synthetic
   JWT principals, and patient records as credential targets. The denied-access
   test now uses a distinct patient, not an admin record that fails role validation.
   Authentication, patient access, token replay, and response assertions remain
   active. No production email endpoint or authorization rule was changed.

## Reproduce

From the repository root:

```sh
cd frontend
flutter pub get
flutter gen-l10n
flutter test test/providers/locale_provider_test.dart test/widgets/language_picker_test.dart test/l10n/app_localizations_test.dart --reporter expanded
flutter analyze lib/providers/locale_provider.dart lib/widgets/language/language_picker.dart test/providers/locale_provider_test.dart test/widgets/language_picker_test.dart test/l10n/app_localizations_test.dart
flutter test --reporter json --concurrency 8
flutter analyze --no-pub
flutter build web --release
```

For the backend, use JDK 17 and run from `backend/core`:

```sh
mvn -B -ntp test
mvn -B -ntp -Dtest=SsmPropertySourceInitializerTest,SchemaPatchRunnerTest,SchemaPatchRunnerH2HeldItemTest,SchemaPatchRunnerH2ConsentTest,CallFlowIntegrationTest,EmailOAuthFlowE2ETest,CernerAllergyFixtureCompatibilityTest,CernerAllergyMapperTest,CernerAllergyControllerTest,CernerAllergyControllerConfigurationTest,CernerResourceMapperTest,CernerStorageAdapterTest test
```

The final command is an affected-test run. It must not be labeled a new full-suite pass.
All 57 tests that failed or errored in the full baseline were included in the later
affected checks and now pass. A full backend rerun after these fixes remains open.
Local Maven Checkstyle reported zero violations. The language file format check,
local report links, unique 26-row trace check, and git diff --check also passed.

## CI and branch-rule evidence

The live branch is protected. An earlier direct push was rejected because a PR is
required. PRs #331 and #347 have non-author approval and merge records. Detailed
branch-protection lookup returned HTTP 404 to this account, so exact required
review counts and rules remain Not verified.

The [PR #347 quality run](https://github.com/umgc/2026_fall_careconnect/actions/runs/39040670296)
finished green, but the report lists whole-repo findings. The existing
`quality/ci/gate/policy.yaml` sets `gate.mode: report_only`; green does not mean
zero findings. No thresholds or security settings were relaxed in this change.

## WBS decisions

| Task | Finding | Workbook action | Remaining gate |
| --- | --- | --- | --- |
| 4.2.5 | Met for the named M2 language test/review/integration scope | Done / 100% | No whole-app translation or release claim. |
| 4.2.7 | Partly met | Keep In Work / 75%; append current runs and fixes | Broad frontend failures, full final-candidate validation, and detailed branch-rule evidence remain open. |
| 4.2.11 | Partly met | Keep In Work / 75%; link the Test Lead packet | Controlled SRS/API links and a named Test Lead decision remain open. |

The closure input for 4.2.5 is `Weekly Progress!F818` (Week 9 actual cumulative
progress), not a replacement of WBS formulas. The authoritative WBS row 23
calculates Done/100%. Its mirrored Latest WBS row 25 is kept consistent.
No labor, estimates, rates, planned dates, or other tasks' percentages were changed.

## Test Lead review

Use [the 26-row M1 design/test packet](team-c-m1-test-lead-review-2026-10-17.md).
It names current design boundaries and exact tests, carries forward all M1 work
packages, and leaves untested or unapproved items explicit. The current M3 plan
now acknowledges the merged mapper and fixtures while retaining its dated
September snapshot. Approval of the shared model, API, or release was not invented.

Full logs and machine-readable summaries are retained in the course evidence
folder `output/M3/Task_Validation_2026-10-17/`. This repository report records the
useful results without copying build output or large raw logs into Git.

## Guides read

Course AGENTS.md, START_HERE.md, USING_WITH_OPENAI_CODEX.md, Project-Planning.md,
MODULE_MAP.md, Feature-Building.md, Debugging.md, and repository TESTING_NORMS.md.
