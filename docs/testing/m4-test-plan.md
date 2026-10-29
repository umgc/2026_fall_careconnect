# Milestone 4 Team C Quality Assurance Test Plan

**Owner:** Team C QA Lead (Tiffany Obi)  
**Status:** Working M4 QA baseline; builds on the instructor-reviewed M3 working baseline  
**Work packages:** WBS 4.10–4.13  
**Execution window:** October 10–November 3, 2026  
**Data boundary:** Synthetic data only; EHR retrieval only; no Cerner write-back

## 1. Purpose

This plan defines Team C's Milestone 4 testing approach and provides the testing team, developers, and team leads with one shared view of the work required for final implementation and sign-off. It carries forward every applicable requirement and test level from the [M3 Cerner Integration Test Plan](m3-test-plan.md) and adds the remaining M4 scope:

- WBS 4.10: localization (`l10n`) and ARB work for Social Feed, Gamification, USPS Mail Digest, Caregiver Shift Scheduling, and HHAExchange submission.
- WBS 4.11: completion of Cerner integration testing and error handling for Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment retrieval.
- WBS 4.12: a translation/localization QA pass across supported workflows.
- WBS 4.13: documentation, regression, evidence collection, and Milestone 4 demonstration preparation.

M4 is not a replacement for M3. Any M3 requirement without complete, passing evidence remains open and becomes M4 carryover work. Existing `M3-REQ-*` identifiers must remain unchanged so current test tags, fixtures, scenario references, and traceability links do not break. New M4-only requirements use `M4-REQ-*` identifiers.

Contract-dependent paths, response fields, error codes, partial-result structures, and frontend assertions remain provisional until the authoritative unified health-data OpenAPI contract is approved and available in the repository.

## 2. M4 work-package scope and intended outcomes

| WBS ID | Work package | Dates | QA outcome |
|---|---|---|---|
| 4.10 | `l10n` + ARB entries, batch 5: Social Feed, Gamification, USPS Mail Digest, Caregiver Shift Scheduling, HHAExchange submission | Oct 10–16 | Each workflow uses generated localization for user-facing text, catalogs are structurally valid, and focused functional/localization tests and review evidence exist. |
| 4.11 | Cerner integration testing and error handling | Oct 16–22 | All five approved read-only Cerner resources have appropriate automated coverage; authorization, refresh, malformed data, timeout, rate-limit, pagination, and partial-result behavior are tested at the lowest useful level. |
| 4.12 | Translation/localization QA pass across all workflows | Oct 22–28 | Catalog parity, clean generation, locale selection, fallback, layout, accessibility, RTL behavior, and human-review status are known and documented. |
| 4.13 | Documentation and M4 demo preparation | Oct 28–Nov 3 | Regression, traceability, coverage, CI, smoke tests, defect disposition, demonstration rehearsal, and the final QA report support an evidence-based release decision. |

## 3. Current repository baseline

This plan was prepared from branch `feature/team-c-cerner-qa-implementation` on October 21, 2026. The baseline must be refreshed before final execution because implementation will continue during M4.

| Area | Observed state | M4 implication |
|---|---|---|
| Cerner AllergyIntolerance | A vertical slice exists with mapping, provisional controller/service wiring, SMART OAuth/PKCE, encrypted credential handling, patient crosswalk, bounded pagination, one-time refresh after an upstream 401, raw-payload retention, fixtures, and focused offline tests. | Reuse this as the reference pattern. Add remaining integration, contract, frontend, live-smoke, and sign-off evidence. |
| Cerner Patient and Appointment | Limited mapper/storage behavior and source fixtures exist. | Complete approved field mapping, service/client/controller coverage, expected outputs, failure cases, and end-to-end evidence where the resource changes the user workflow. |
| Cerner Condition and Encounter | Shared source-neutral records, repositories, pure fixture-driven mappers, bounded same-source Bundle retrieval, OAuth refresh, original-resource retention, normalized upserts, stale-update protection, provisional controllers, MVC slices, candidate expected outputs, and Spring/WireMock coverage now exist. The public shapes and candidate outputs remain unapproved and disabled by default. | Review and approve or revise the field/route assumptions, then add formal contract, E2E, and smoke evidence. |
| Unified OpenAPI contract | `contracts/unified-health-data.openapi.yaml` was not found in the inspected repository. | API paths, normalized response fields, error codes, source-status behavior, and formal contract tests remain provisional. |
| Localization foundation | Flutter generated localization, locale selection, 14 ARB catalogs, and focused localization tests exist. | Reuse the foundation; validate it from a clean checkout and extend evidence to complete workflows. |
| Current catalog parity | English currently contains 1,130 message keys, Spanish 1,109, most other locale catalogs 948, and Urdu 949. | File presence is not translation completion. Produce a key-by-key parity report, resolve approved gaps, and document qualified human review for sensitive copy. |
| Batch-5 workflow tests | Existing frontend tests cover portions of Social Feed, Gamification, USPS, Shift Scheduling, and HHAExchange. | Run and assess them, then add only the functional, localization, accessibility, RTL, or error-state coverage that is missing. |
| React/Vite prototype | The localization audit found no implemented localization framework for the separate prototype. | Team leads must classify it as preview-only or production-bound. Flutter localization evidence must not be presented as coverage of that prototype. |

Status language in this plan is deliberate:

- **Implemented** means relevant production code was found.
- **Covered** means an appropriate automated test was found and executed successfully against the named commit.
- **Approved** requires a recorded team, product, architecture, contract, or instructor decision.
- **Complete** requires the exit criteria and traceable evidence in this plan; code or fixture presence alone is not completion.

## 4. Scope

### In scope

- All unresolved requirements from the M3 Cerner test plan.
- Read-only Cerner retrieval for Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment.
- SMART-on-FHIR authorization, patient context, source credentials, refresh behavior, crosswalk enforcement, and disconnect/reconnect behavior.
- Mapping, normalization, source identity, `sourceRecordId` or approved equivalent, provenance, and approved raw-payload retention.
- Successful, empty, missing-field, malformed, authorization, timeout, rate-limit, pagination, duplicate, loop, mixed-entry, upstream-error, and partial-result cases.
- Backend unit, controller-slice, OpenAPI contract, WireMock integration, and regression testing.
- Frontend model/service/state, unit/widget, accessibility, contract-fixture, and critical frontend-to-backend workflows.
- Localization of complete batch-5 workflows, not only catalog key creation.
- ARB validity and parity, reproducible code generation, locale selection/persistence/fallback, formatting, overflow, RTL, focus order, semantics, and human translation review status.
- Weekly and pre-sign-off Cerner sandbox smoke tests using synthetic data.
- Documentation, traceability, defect triage, final regression, CI evidence, demonstration rehearsal, and QA sign-off reporting.

### Out of scope

- Writes to Cerner or another EHR.
- Production PHI, production credentials, or production endpoints.
- Patient identity matching from name or date of birth alone.
- Unreviewed machine translation represented as approved translation.
- Final API field names, error codes, paths, or `sourceStatus` values before contract approval.
- Treating the separate React/Vite prototype as localized unless it is explicitly made a supported M4 surface and receives its own localization implementation and tests.
- Broad redesign or repair of unrelated application behavior solely to make a test convenient.

## 5. Requirements

### 5.1 M3 requirements carried into M4

All `M3-REQ-01` through `M3-REQ-20` remain applicable until each has passing traceability evidence. The following groups are especially important for M4:

| M3 requirement group | M4 completion focus |
|---|---|
| M3-REQ-01–03, 06, 12 | Approved mapping, normalization, patient/source authorization, missing/malformed data, provenance, and identity separation across all five resources. |
| M3-REQ-04, 16–19 | Complete AllergyIntolerance, Patient, Condition, Encounter, and provisional Appointment retrieval coverage. |
| M3-REQ-05, 07–09, 20 | Token expiration/refresh, timeout/retry/rate-limit, paging/partial results, distinct authorization failures, and consistent SMART persona/host/scope handling. |
| M3-REQ-10–11 | One authoritative frontend/backend contract and a small set of critical frontend-to-backend workflows. |
| M3-REQ-13–15 | Regression, live sandbox smoke, coverage, CI stability, defect disposition, and final evidence. |

### 5.2 M4-specific requirements

| ID | Requirement | Criticality |
|---|---|---|
| M4-REQ-01 | Carry forward all unresolved M3 requirements without weakening the synthetic-only, retrieval-only, authorization, provenance, or no-write-back boundaries. | Critical |
| M4-REQ-02 | Complete and verify the approved read-only Cerner workflow for Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment. | Critical |
| M4-REQ-03 | Verify deterministic Cerner error handling for denial, insufficient scope, expiration, refresh failure, timeout, malformed responses, rate limits, upstream failures, pagination, duplicates/loops, and partial results. | Critical |
| M4-REQ-04 | Validate each implemented CareConnect endpoint and every frontend contract fixture against the same approved unified OpenAPI contract. | Critical |
| M4-REQ-05 | Localize the complete Social Feed workflow, including navigation, headings, actions, dialogs, validation, loading, empty, error, and accessibility text. | High |
| M4-REQ-06 | Localize the complete Gamification workflow, including achievements, leaderboard, points/levels, empty/error states, and accessibility text. | High |
| M4-REQ-07 | Localize the complete USPS Mail Digest workflow, including connection state, digest navigation, mail/package details, dates, errors, read-aloud controls, and accessibility text. | High |
| M4-REQ-08 | Localize the complete Caregiver Shift Scheduling workflow, including calendar views, recurrence, validation, conflicts, save/error states, dates/times, and accessibility text. | High |
| M4-REQ-09 | Localize the complete HHAExchange submission workflow, including eligibility, selection, payload/download warnings, submission progress, success/failure, and accessibility text. | High |
| M4-REQ-10 | Enforce valid ARB structure and exact approved key/placeholder schema parity, and generate localization sources successfully from a clean checkout. | Critical |
| M4-REQ-11 | Verify locale selection, persistence, supported/unsupported fallback, plural/parameter behavior, date/number formatting, layout/overflow, and no unintended raw localization keys or English literals. | High |
| M4-REQ-12 | Verify representative patient and caregiver workflows in an RTL locale for directionality, reading order, directional icons, keyboard/focus order, semantics, and usable layout. | High |
| M4-REQ-13 | Record qualified human review status for medical, medication, safety, privacy, and legal translations; unresolved review must be reported and cannot be called release-complete. | Critical |
| M4-REQ-14 | Preserve existing Cerner, localization, and shared health-data behavior through focused regression across frontend and backend. | High |
| M4-REQ-15 | Produce traceable CI, coverage, contract, accessibility, E2E, sandbox-smoke, localization-review, defect, and demo evidence for the final release decision. | Critical |
| M4-REQ-16 | Demonstrate the agreed M4 user journeys in a stable, rehearsed environment without relying on live EHR availability for the main demonstration. | High |

Tests should use the applicable requirement ID in their name, JUnit `@Tag`/`@DisplayName`, Flutter test description, test report metadata, or traceability record. A test may cover both an M3 and M4 requirement; the traceability matrix should list both rather than duplicating the test.

## 6. Test strategy and ownership

Use the lowest test level that proves a scenario. Repeat a scenario higher only when the higher level proves a new boundary.

| Level | What it proves | Primary owner | Examples/tooling |
|---|---|---|---|
| Backend unit | Mapper fields, exclusions, normalization, service decisions, pagination/refresh algorithms | Backend developer; QA supplies/reviews scenarios, fixtures, and expected results | JUnit 5, Mockito |
| Frontend unit/widget | Models, services, state changes, localized rendering, validation, empty/error states, layout, semantics, regressions | Frontend developer; QA supplies/reviews scenarios and evidence | Flutter unit/widget tests |
| Controller slice | Request validation, CareConnect authorization, status codes, serialization, and exception translation | Backend developer; QA reviews expected behavior | Spring MVC slice/MockMvc |
| OpenAPI contract | Backend responses and frontend mocks match one authoritative interface | QA coordinates; frontend/backend developers maintain their producers | Team-approved OpenAPI validator |
| Integration | Real Spring wiring survives Cerner/OAuth success and failure behavior | QA owns failure stubs/integration suite with developer support | `@SpringBootTest`, WireMock |
| End-to-end | A small number of critical user journeys work through real frontend/backend boundaries | QA with frontend/backend developers | Existing Flutter integration framework and controlled test backend |
| Manual exploratory/accessibility | Translation meaning, clipping, visual hierarchy, RTL behavior, keyboard/focus, and assistive output | QA with UI/UX and qualified language reviewers | Device/browser matrix, screen reader, screenshots/checklist |
| Live Cerner smoke | Local stubs still represent the real secure sandbox and OAuth/FHIR interoperability | QA coordinates; authorized tester executes | Manual secure-sandbox checklist with sanitized evidence |
| Demo rehearsal | The final narrative, data, environment, timing, fallback, and presenter handoffs are ready | Team lead coordinates; QA records result | Release candidate plus approved synthetic demo data |

### Responsibility summary

**Developers are responsible for:**

- Unit tests for every mapper, service, model, and state-management component they implement.
- Controller-slice tests for each backend endpoint.
- Frontend unit/widget/accessibility tests for changed workflows.
- Fixing defects and adding a regression test with each fix.
- Reviewing expected normalized outputs with QA and confirming implementation assumptions.

**QA is responsible for:**

- This plan, the M4 scenario catalog, traceability matrix, execution record, and final summary.
- Synthetic fixture governance, sanitization, metadata, paired expected outputs, and coverage review.
- WireMock OAuth/FHIR failure stubs and integration tests.
- A small number of critical E2E tests.
- Localization parity reporting, workflow QA, RTL/accessibility coordination, and evidence tracking.
- Weekly/pre-sign-off Cerner smoke coordination, defect triage, regression coordination, demo readiness verification, and sign-off recommendation.

**Shared responsibilities:**

- QA and the assigned developer pair on the first implementation of each new testing pattern.
- Frontend, backend, architecture, and QA approve or record assumptions for the unified contract, canonical model, source identity, pagination, and partial-result behavior.
- UI/UX and qualified language reviewers validate meaning and presentation; QA does not independently certify unfamiliar translations.
- The team lead assigns presenters, approves the demo scope, and resolves scope or ownership gaps.

## 7. WBS 4.10 batch-5 localization coverage

For each workflow, test the entire user journey rather than checking only that ARB keys exist.

| Workflow | Minimum functional/localization coverage | Existing evidence to assess | M4 additions expected |
|---|---|---|---|
| Social Feed | Load feed, empty/error states, create post, comments, friend search/requests, messages/chat, validation, permissions, semantics | Social page, model, chat, and interaction tests exist | Confirm all display text uses generated localization; add locale/RTL/overflow/accessibility cases where missing. |
| Gamification | Dashboard, points/level, achievements, leaderboard, unnamed/empty/error states, notification text, semantics | Service and screen tests exist | Add localized parameter/plural cases, long-text layout, fallback, and accessibility evidence. |
| USPS Mail Digest | Connect/disconnect, fetch/cache, empty/error/expired connection, dates/counts, mail/package details, read aloud, images/action links | Broad domain, repository, widget, page, read-aloud, and accessibility tests exist | Verify localized UI coverage, date/count formatting, long text, RTL controls, and connection/error copy. |
| Caregiver Shift Scheduling | Day/week/month views, create/edit schedule, recurrence, start/end time, no-time validation, conflict warning, save/error states | Model, service, screen, calendar, dialog, and conflict tests exist | Add locale-aware dates/times, first-day/direction behavior, long-text/RTL layout, and semantics evidence. |
| HHAExchange submission | Load eligibility, select/deselect, payload download warning, progress, approved/no-eligible/error states, submission success/failure | Submission-page tests exist | Add localized state/validation coverage, long-text/RTL layout, accessibility, and safe error-message assertions. |

Each workflow is localization-complete only when:

1. User-facing strings—including buttons, tooltips, validation, dialogs, empty/error states, and semantics—use generated localization or have an approved fixed-text justification.
2. The English template has valid keys and placeholder metadata, and every supported catalog has the approved schema.
3. Clean-checkout localization generation succeeds.
4. Focused functional and localized widget tests pass.
5. English and Spanish receive manual UI checks.
6. At least one approved RTL locale receives layout, reading-order, focus, icon-direction, and semantics checks where applicable.
7. Sensitive translation review status is documented.
8. Evidence links identify the commit, command/result, screenshots when visual behavior matters, reviewer, date, and known gaps.

## 8. WBS 4.11 Cerner resource and failure coverage

### Resource coverage

| Resource | Required success evidence | Required edge/failure evidence | Current emphasis |
|---|---|---|---|
| Patient | Authorized patient retrieval and approved field/provenance mapping | Optional fields absent, malformed/core identity data, wrong patient/crosswalk, denial | Complete beyond limited mapper fixtures; never infer identity from demographics alone. |
| Condition | Bundle retrieval and approved code/status/category/onset/abatement/encounter/provenance mapping | Empty Bundle, optional fields absent, invalid/mixed entries, pagination, denial | Provisional record/mapper plus HTTP, refresh, raw-retention, upsert, stale-update, unit/JPA tests exist; controller/contract/higher-level evidence remains. |
| AllergyIntolerance | Active/confirmed retrieval, complete field mapping, empty result, provenance/raw payload | Missing reaction, text-only code, unknown severity, inactive rule, entered-in-error exclusion, malformed/mixed entries | Finish higher-level and contract evidence using the existing reference slice. |
| Encounter | Bundle retrieval and approved status/class/type/period/participant/provider/provenance mapping | Empty Bundle, optional fields absent, paging, invalid/mixed entries, denial | Provisional record/mapper plus trusted paging, HTTP, refresh, raw-retention, upsert, stale-update, unit/JPA tests exist; controller/contract/higher-level evidence remains. |
| Appointment (provisional) | Approved bounded-date retrieval and mapping | Empty Bundle, proposed/no confirmed time, paging, duplicates/version ordering, malformed dates | Confirm final M4 scope and search parameter; no creation or update in Cerner. |

### Cross-resource failure scenarios

The following must be represented in the scenario catalog and assigned to the lowest useful level:

- Missing CareConnect login, forbidden local-patient access, missing source connection, insufficient SMART scope, upstream 401, expired token with one approved successful refresh, refresh failure, and wrong audience/host.
- OAuth state mismatch, PKCE/redirect mismatch, missing patient context when required, disconnect, reconnect, and credentials marked for reauthorization.
- Connection timeout, read timeout, connection refusal, upstream 5xx, malformed JSON/FHIR, wrong resource type, missing required/core identifiers, mixed valid/invalid entries, and safe error logging.
- HTTP 429 behavior using the approved retry/backoff and `Retry-After` policy; call counts prove there is no retry storm.
- Empty Bundles, multiple pages, same-source next links, maximum-page enforcement, duplicate/loop protection, and later-page failure.
- Approved partial-result behavior when one EHR fails and other source data is available. Exact response fields and `sourceStatus` assertions remain provisional until contract approval.
- Source attribution, original source record identity, raw-payload access controls/retention, and no leakage of bearer tokens or sensitive headers.
- No write-back method, HTTP call, or test fixture may imply Cerner creation/update/deletion.

Suggested planning ranges from M3 remain guidance, not quotas: approximately 10–20 backend unit tests, 6–10 controller-slice tests, and 6–10 WireMock integration tests per resource where behavior is distinct. Keep E2E coverage to the critical user journeys; do not repeat mapper edge cases through the UI.

## 9. WBS 4.12 localization QA pass

The final localization pass must include:

1. Parse every ARB catalog and produce missing-key, extra-key, malformed-entry, and placeholder-metadata results against `app_en.arb`.
2. Run `flutter gen-l10n` from a clean checkout before localization and workflow tests.
3. Run focused localization, locale-provider, language-picker, batch-5 workflow, and affected regression tests.
4. Verify locale selection persists and an unsupported/stale locale follows the approved fallback behavior.
5. Exercise parameterized messages, plurals, long translations, dates, times, numbers, and text scaling.
6. Check narrow and representative screen sizes for clipping, overflow, hidden controls, or inaccessible scrolling.
7. Check representative patient and caregiver workflows in Arabic or Urdu for RTL direction, reading order, icons, focus order, and semantics.
8. Check English and Spanish manually across batch-5 workflows and record qualified review status for other supported languages.
9. Search changed workflows for hard-coded user-facing strings, using the result as a review aid rather than a standalone completion metric.
10. Record the separate React/Vite prototype disposition and do not combine its status with Flutter evidence.

No locale may be reported as fully translated solely because its ARB file exists or builds successfully.

## 10. WBS 4.13 regression, documentation, and demo preparation

### Regression and CI

- Run the relevant backend and frontend suites on the exact release-candidate commit.
- Run contract validation after the contract is approved and pin the contract version/checksum in the evidence.
- Run localization generation/parity and focused workflow checks as blocking checks, not informational checks.
- Confirm no test is skipped, muted, weakened, or marked non-blocking without documented approval.
- Investigate flaky failures; do not use reruns alone as proof of stability.
- Record three consecutive passing relevant CI runs on the final candidate, consistent with the M3 sign-off expectation.

### Documentation/evidence package

- M4 test plan, scenario catalog, and traceability matrix.
- Fixture register, paired expected-output review record, and WireMock stub inventory.
- Backend and frontend test reports and coverage reports.
- OpenAPI validation output for each implemented endpoint and frontend fixture set.
- Localization parity/generation report, workflow checklist, screenshots, RTL/accessibility findings, and human-review status.
- Critical E2E evidence and recent Cerner sandbox smoke record.
- Defect list with severity, disposition, regression evidence, and accepted limitations.
- One- or two-page M4 test summary naming the tested commit and QA recommendation.

### Demo readiness

- Agree on a short stakeholder-focused narrative and the exact workflows demonstrated.
- Use stable synthetic data and a controlled backend for the main demonstration.
- Keep a tested fallback recording or screenshots for external sandbox/network failure.
- Rehearse presenter handoffs, timing, environment setup, account state, and reset steps.
- Do not expose tokens, credentials, raw headers, or identifying information on screen.
- Clearly label implemented behavior, provisional behavior, mocked behavior, and future work.

## 11. Environments, test data, and fixture rules

- Unit, widget, slice, contract, integration, and automated E2E tests must be deterministic and must not depend on a live EHR or production database.
- Use shared synthetic fixtures rather than inline ad hoc objects where practical, following `TESTING_NORMS.md`.
- Cerner source fixtures belong under `backend/core/src/test/resources/cerner/fhir/<resource>/`; OAuth fixtures belong under `backend/core/src/test/resources/cerner/oauth/`; paired normalized outputs belong under `backend/core/src/test/resources/cerner/expected/<resource>/`; WireMock mappings and bodies belong under the approved test-resource WireMock directories.
- One fixture has one clear purpose. Input and expected output use the same base name when an approved normalized output exists.
- YAML `.meta.yaml` files document provenance, capture date, purpose, sanitization, and expected handling; they do not replace expected JSON output.
- Never commit authorization codes, PKCE verifiers, access/refresh tokens, cookies, secrets, bearer headers, production PHI, or unsanitized logs/screenshots.
- WireMock represents OAuth and FHIR behavior for automation. The live sandbox is used only for a small scheduled smoke test with synthetic patients and sanitized evidence.
- Localization tests use repository catalogs and controlled locale/device settings; manual reviewers record locale, device/viewport, text scale, workflow, commit, and result.

## 12. Entry criteria

Testing that can proceed immediately:

- M3 regression and completion work that does not depend on final API fields.
- Mapper/service unit tests, source fixtures, fixture metadata, WireMock failure behavior, and internal client behavior.
- Batch-5 localization inventory, ARB validation, clean generation, widget tests, accessibility checks, and manual English/Spanish/RTL review.
- Traceability, defect tracking, evidence templates, and demo planning.

Contract-dependent testing requires:

1. The authoritative unified health-data OpenAPI contract is present, versioned, and approved.
2. The canonical model, shared adapter boundary, source naming/translation, reconciliation behavior, and partial-result policy are recorded.
3. Final CareConnect paths, request parameters, normalized fields, error envelope/codes, and source-status semantics are known.
4. Frontend mocks and backend producers use the same contract version.

Release-candidate execution additionally requires a deployable integrated build, stable synthetic test accounts/data, known supported platforms/locales, and an assigned demo environment.

## 13. Exit and sign-off criteria

M4 is eligible for QA sign-off only when all applicable conditions are true:

- Every approved M3 and M4 requirement has a traceability row with a specific test or test group, level, expected result, latest result, and evidence link.
- All Critical scenarios pass; no open Critical or High defect remains.
- The five-resource Cerner scope has passing evidence at the appropriate levels, or an approved scope change is explicitly documented.
- Cerner mapping coverage reaches at least 80% line and 70% branch, and Cerner integration coverage reaches at least 70% line, using the established M3 JaCoCo targets.
- Every implemented CareConnect endpoint and frontend contract fixture passes validation against the same approved OpenAPI version.
- Batch-5 workflows meet the localization completion gate, and the cross-workflow localization report accurately identifies any unapproved/missing translations.
- Clean localization generation and catalog integrity checks pass on the final candidate.
- Relevant frontend functional, widget, accessibility, RTL, and regression checks pass.
- Three consecutive relevant CI runs pass on the release candidate without unexplained flakiness or suppressed failures.
- A Cerner live-sandbox smoke test has passed within the final sign-off window using synthetic data, with sanitized evidence.
- The documentation/evidence package is complete, the demonstration has been rehearsed, and all accepted limitations are disclosed.
- Security/privacy review confirms synthetic-only testing, correct patient/source authorization, safe logging/evidence, provenance controls, and no Cerner write-back.

QA may recommend **Pass**, **Pass with accepted conditions**, or **Fail**. A conditional pass requires no Critical or High defect and written acceptance of each remaining limitation by the appropriate owner.

## 14. Defect severity and reporting

- **Critical:** authorization bypass, cross-patient/source disclosure, token/PHI exposure, unintended EHR write, dangerous clinical misrepresentation, or total failure of a critical workflow. Blocks merge, demo sign-off, and release.
- **High:** incorrect clinical mapping, silent record loss, broken refresh/pagination/partial-result semantics, contract incompatibility, unusable critical localization, or missing required safety/legal translation review. Blocks sign-off.
- **Medium:** limited workflow, localization, accessibility, or presentation failure with a documented workaround and owner-approved disposition.
- **Low:** minor presentation, wording, or evidence issue that does not prevent safe completion of a supported workflow.

Each defect must include requirement/scenario IDs, tested commit, environment/locale, fixture or synthetic data reference, steps, expected/actual result, sanitized evidence, severity rationale, owner, and retest result.

## 15. Dependencies and decisions requiring confirmation

| Dependency/decision | Current status | Temporary QA position | Required owner/action |
|---|---|---|---|
| Unified health-data OpenAPI contract | Not found in inspected repository | Keep paths, public response shapes, errors, and partial-result assertions provisional. | Frontend/backend/integration owners approve and commit the authoritative contract; QA pins its version/checksum. |
| Five-resource Cerner M4 scope | Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment carried forward | Plan and test all five; continue labeling Appointment provisional. | Team C lead/product owner confirms any scope change in writing. |
| Canonical model and shared adapter boundary | Shared components exist; final Cerner boundary still needs confirmation | Reuse shared models/contracts and do not create a competing Cerner-only canonical model. | Architecture and backend owners record the approved boundary and mappings. |
| API/persistence source name | Persistence uses `ORACLE_HEALTH`; prior examples used `CERNER` | Test `ORACLE_HEALTH` internally and require an explicit mapping if the public contract chooses another value. | Contract and architecture owners approve the public/persistence representation. |
| Mapping and record lifecycle rules | Allergy has a working baseline; other resources remain incomplete | Preserve source facts, original precision, provenance, and uncertain-match separation; do not invent clinical values. | Backend/architecture/clinical owners approve per-resource rules and deletion/inactive behavior. |
| Retry, 429, pagination, and partial-result policy | Some bounded allergy behavior exists; final public semantics unresolved | Test internal safety bounds; keep final API assertions provisional. | Backend and contract owners approve limits, retry/backoff, later-page failure, and partial-result behavior. |
| Localization catalog parity and translation review | Current catalogs are not at key parity | Report actual gaps; never fill sensitive copy only to make a check pass. | Localization owner/UI lead assigns qualified reviewers and approves supported-locale completion. |
| Supported UI/platform matrix | Not recorded in this plan | Cover current primary Flutter target and representative viewports; report exact environment. | Team/product lead confirms required web/mobile platforms, devices, and browsers. |
| RTL workflow selection | Required but not yet assigned | Use at least one patient and one caregiver journey, including relevant batch-5 workflows where practical. | QA and UI/UX select workflows and Arabic or Urdu reviewers. |
| React/Vite prototype disposition | Unresolved | Treat as separate and not covered by Flutter localization evidence. | Team lead marks it preview-only or production-bound. |
| Demo scope and presenters | Pending | Prepare stable synthetic-data paths and a sandbox-independent fallback. | Team lead assigns presenters, journey order, time limits, and environment. |

Assumptions must be recorded in the traceability matrix or decision log and replaced when an authoritative decision is approved. Do not silently choose between competing architectures or contract shapes.

## 16. M4 QA deliverables and working cadence

### Deliverables

- `docs/testing/m4-test-plan.md` — this document.
- `docs/testing/m4-scenario-catalog.md` — detailed cases, level, priority, owner, fixture/data, and expected result.
- `docs/testing/m4-traceability-matrix.md` — requirement ID, description, test identifiers, level, expected result, latest result, and evidence.
- `docs/testing/m4-localization-qa-checklist.md` — workflow, locale, device/viewport, accessibility/RTL, reviewer, result, and evidence.
- `docs/testing/m4-test-summary.md` — final execution, defects, deviations, coverage, CI, smoke, and sign-off recommendation.
- Updated fixture register, smoke-test record, contract-validation output, coverage reports, and demo-rehearsal record.

### Cadence

- QA and developers review new fixtures and expected outputs before mapper behavior is treated as approved.
- Each pull request includes requirement/scenario references and the lowest useful automated tests.
- QA reviews test adequacy and evidence; developers remain responsible for lower-level tests in the code they implement.
- Run or review localization parity and affected workflow tests with every batch-5 change.
- Conduct the Cerner live smoke weekly while integration changes and once in the final sign-off window.
- Review traceability and open Critical/High defects at least twice weekly through M4.
- Freeze the release-candidate commit before the final regression, smoke test, evidence package, and demo rehearsal.
