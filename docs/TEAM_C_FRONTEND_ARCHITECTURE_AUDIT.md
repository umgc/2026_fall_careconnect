# Team C Frontend Localization Architecture Audit

## Item 3.2 disposition and remaining-workflow prioritization

**Audit date:** 2026-08-28

**Repository:** `umgc/2026_fall_careconnect`

**Branch:** `main`

**Audited commit:** `87f42ff13b8e243e5f2191be72a2ec4c3a14f7b5`

**Repository refresh:** `git pull --ff-only` returned `Already up to date.`

## Executive conclusion

The Flutter application has a usable localization foundation, but the localization program is **not complete at the workflow or release-readiness level**. Generated localization is configured, 14 locale catalogs are present, runtime delegates are wired into the application, the selected locale persists, and the focused localization tests pass after generated sources are created.

The remaining risk is concentrated in catalog parity, hard-coded display text, incomplete workflow-by-workflow migration, limited right-to-left (RTL) evidence, and a separate React/Vite prototype that has no implemented localization framework. Team C should treat localization as a controlled workflow migration program, not as a one-time catalog translation task.

Medical, medication, safety, privacy, and legal copy must receive qualified human review before any locale is represented as complete.

## Scope and method

This audit covers:

- The primary Flutter application in `frontend/`.
- Generated-localization configuration, ARB catalogs, runtime locale selection, and focused tests.
- A source scan for direct `Text("...")` and `Text('...')` literals as a **heuristic indicator** of untranslated display text.
- The separate React/Vite prototype in `ui-integration/mobile-app/`.
- The prioritized remaining-workflow list carried forward in the Team C technical design work for item 3.2.

The literal-string scan is not a semantic accessibility or release-completeness metric. It can include developer-only or intentionally fixed text and can miss strings supplied through other widget properties, constants, or runtime data.

## Verified architecture

| Area | Verified state | Repository evidence |
|---|---|---|
| Localization generator | Flutter `gen-l10n` uses `lib/l10n`, `app_en.arb`, generated `app_localizations.dart`, and `missing_translations.txt`. | `frontend/l10n.yaml:1-4`; `frontend/pubspec.yaml:219-222` |
| Runtime wiring | `MaterialApp.router` installs Flutter and application delegates, uses generated supported locales, and reads the selected locale from `LocaleProvider`. | `frontend/lib/main.dart:286-304` |
| Locale persistence | The language code is stored under `selected_locale`; unsupported saved locales are cleared during load. | `frontend/lib/providers/locale_provider.dart:5-44` |
| Catalog coverage | 14 locale catalogs are present: `am`, `ar`, `bn`, `en`, `es`, `fa`, `fr`, `hi`, `ja`, `ne`, `pt`, `ru`, `ur`, and `zh`. The English template contains 954 message keys. | `frontend/lib/l10n/app_*.arb` |
| Focused automated tests | Generated lookup/delegate behavior, 14 supported locales, English/Spanish labels, saved-locale behavior, picker selection, and responsive picker behavior are covered. | `frontend/test/l10n/app_localizations_test.dart:1-238`; `frontend/test/providers/locale_provider_test.dart:7-170`; `frontend/test/widgets/language_picker_test.dart:16-232` |
| Secondary UI surface | `ui-integration/mobile-app` is a separate React/Vite web prototype. Its dependencies do not include a localization library, and no locale catalogs or runtime localization implementation were found under `src/`. | `ui-integration/mobile-app/README.md:1-28`; `ui-integration/mobile-app/package.json:1-90` |

## Findings

### P0 — Enforce catalog schema parity before expanding workflow coverage

English and Spanish contain all 954 English-template keys. Twelve other locales each miss the same six keys:

- `aiDisclaimer`
- `medicationDisclaimer`
- `disclaimerLabel`
- `dailyBrief`
- `stmlSearch`
- `stmlCheckIn`

The generated untranslated-message record confirms those six missing keys for `am`, `ar`, `bn`, `fa`, `fr`, `hi`, `ja`, `ne`, `pt`, `ru`, `ur`, and `zh` (`frontend/missing_translations.txt:1-109`). Urdu also contains one key that is not present in the English template: `ssubselection_continueToPayment`.

**Required action:** add a blocking catalog-integrity check that fails on missing keys, extra keys, invalid JSON/ARB structure, and generation failure. Do not populate the safety-related keys with unreviewed machine translations to make the check green.

### P0 — Keep generated localization validation reproducible

The first focused test attempt failed because the ignored generated source `frontend/lib/l10n/app_localizations.dart` did not exist in the fresh checkout. Running `flutter gen-l10n` from `frontend/` generated the sources successfully. The same three focused test files then passed all 88 tests.

**Required action:** make generation an explicit prerequisite in developer and CI workflows, or rely on a build step that deterministically performs generation before tests. A clean-checkout localization test must not depend on files left behind by a previous local build.

### P0 — Make localization checks blocking on protected branches

The Team B workflow runs Flutter analysis and unit tests with `continue-on-error: true` (`.github/workflows/team-b-ci.yml:98-127`). The workflow does perform a blocking web build and a later coverage gate, but it does not define a dedicated catalog-parity or clean-generation gate.

**Required action:** add a small, deterministic localization job or step that runs generation, validates every catalog against `app_en.arb`, and executes the focused localization tests without `continue-on-error` on protected-branch pull requests.

### P1 — Migrate user-facing strings by complete workflow

A heuristic scan of 542 non-generated Dart source files found 2,357 direct `Text(...)` string-literal occurrences across 265 files. Only 60 non-generated library files referenced `AppLocalizations`. These numbers do not prove that every match is user-facing, but they show that catalog growth alone is not a sufficient completion measure.

**Required action:** migrate one workflow slice at a time, including headings, buttons, tooltips, validation messages, empty states, dialogs, error messages, and semantics labels. Review and test the whole journey before calling it complete.

### P1 — Add workflow-level RTL and accessibility evidence

The focused tests verify supported locale lookup and picker behavior, but the audit found no representative Arabic- or Urdu-rendered end-to-end workflow assertion for directionality, reading order, overflow, keyboard/focus order, and semantics.

**Required action:** select at least one patient workflow and one caregiver workflow for Arabic or Urdu visual/widget coverage. Record overflow, directional icon, focus order, and screen-reader findings alongside the workflow acceptance evidence.

### P2 — Decide the localization status of the React/Vite prototype

The prototype is explicitly separate from Flutter and has no implemented i18n dependency or catalog structure. If it remains a design preview, this is a documented limitation. If it becomes a supported user surface, it needs its own localization architecture and parity policy.

**Required action:** mark the prototype as either preview-only or production-bound. Do not count Flutter catalog coverage as coverage of the React surface.

## Prioritized remaining-workflow backlog

The order below is a Fall 2026 planning recommendation. Team C leads should confirm it against the active backlog, current ownership, and instructor direction.

### Priority 0 — Stabilize the contract and shared entry surfaces

1. Add blocking ARB parity and clean-generation validation.
2. Resolve the six missing keys in 12 locales through qualified review, and resolve the Urdu-only extra key.
3. Localize new Dashboard widgets and textual elements.
4. Externalize remaining Welcome page display text.
5. Keep Email Verification translation deferred until its logic and final copy are stable; then migrate it as one complete Sign In workflow slice.

### Priority 1 — Core patient and financial journeys

1. Contact Provider workflow.
2. Patient Symptoms and Allergy workflow.
3. Patient Daily Check-in workflow.
4. Invoice Assistant workflow for Patient and Caregiver roles.
5. Patient Report workflow.

### Priority 2 — Coordination and shared operational journeys

1. Calendar Assistant workflow for Patient and Caregiver roles.
2. Medication Tracker feature workflow, separate from the Dashboard widget.
3. Notetaker Assistant workflow for Patient and Caregiver roles.
4. Informed Delivery workflow for Patient and Caregiver roles.
5. Patient List workflow.
6. Analytics workflow.
7. EVV Dashboard workflow.
8. Visit Schedule workflow.
9. Profile workflow for Patient and Caregiver roles.
10. Messages workflow for Patient and Caregiver roles.

### Priority 3 — Integrations, engagement, and administration

1. Wearables workflow for Patient and Caregiver roles.
2. Smart Devices workflow for Patient and Caregiver roles.
3. Fall Alert workflow for Patient and Caregiver roles.
4. Add Patient workflow.
5. Family workflow.
6. Social Feed workflow.
7. Gamification workflow.
8. USPS Mail Digest workflow.
9. Caregiver shift-scheduling workflow.
10. Submit to HHAExchange workflow.

## Workflow completion gate

A workflow may be marked localization-complete only when all applicable conditions below are satisfied:

1. Every user-facing string in the workflow is routed through generated `AppLocalizations` accessors; any fixed display text has a documented justification.
2. `app_en.arb` contains the required keys. Any parameters use valid metadata, and every supported locale has exact schema parity.
3. `flutter gen-l10n` succeeds from a clean checkout and catalog validation reports no missing, extra, duplicate, or malformed entries.
4. Focused widget or integration tests pass for the workflow, including fallback and unsupported-locale behavior where applicable.
5. English and Spanish receive a manual UI check.
6. A representative RTL locale, Arabic or Urdu, receives a check for layout direction, reading order, text overflow, directional icons, focus order, and semantics.
7. Medical, medication, safety, privacy, and legal translations have documented qualified human review before release.
8. Evidence is attached to the work item or pull request: affected paths, test command/results, screenshots where visual behavior matters, known gaps, reviewer, and completion date.

## Validation record

Performed on 2026-08-28 at the audited commit:

- `git pull --ff-only` — passed; repository already up to date.
- ARB JSON/schema comparison — completed; results recorded above.
- `flutter gen-l10n` from `frontend/` — passed.
- `flutter test test/l10n/app_localizations_test.dart test/providers/locale_provider_test.dart test/widgets/language_picker_test.dart` — passed, 88 tests.
- Direct `Text(...)` source scan — completed as a heuristic inventory only.
- React/Vite dependency and source inspection — completed; no implemented localization framework found.

## Disposition

Item 3.2 is complete as an architecture audit and prioritization artifact. Implementation remains open until the catalog, workflow, RTL, accessibility, human-review, and evidence gates above are satisfied. This document does not assign individual owners or claim instructor approval; Team C leads must map priorities to the active backlog.
