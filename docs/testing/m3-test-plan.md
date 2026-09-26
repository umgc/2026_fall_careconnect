# Milestone 3 Cerner Integration Test Plan

**Owner:** Team C QA Lead (Tiffany Obi)
**Status:** Draft pending unified OpenAPI 1.0 approval and final M3 resource scope
**Work packages:** WBS 4.7 (Cerner mapping/normalization), WBS 4.8 (Cerner API endpoint development)
**Data boundary:** Synthetic data only; retrieval only; no write-back

## 1. Purpose

This plan defines how Team C will verify Cerner FHIR R4 retrieval, mapping, API behavior, and the critical frontend-to-backend workflow for Milestone 3. It applies the approved six-level testing strategy and assigns each scenario to the lowest level that proves the behavior. A scenario is repeated at a higher level only when that level proves a new boundary, such as HTTP serialization, the approved API contract, or actual sandbox interoperability.

The initial repeatable example is AllergyIntolerance. The repository does not yet contain an AllergyIntolerance mapper or approved normalized allergy response, so allergy expected-output assertions remain provisional until the canonical model and OpenAPI 1.0 are approved.

## 2. Repository baseline and artifact status

Snapshot inspected on 2026-09-26:

| Artifact | Observed status | QA consequence |
|---|---|---|
| `docs/team-c-m3-qa` | QA documentation branch created from `team-c-develop` (`87f42ff1`) | These documents change no application behavior. |
| `integration/unified-health-data` | Not present in available local or remote refs | Contract and cross-team tests cannot be finalized. |
| `contracts/unified-health-data.openapi.yaml` | Not present in available refs | Paths, parameters, response shapes, error codes, and `sourceStatus` assertions are TBD. |
| Team C Cerner mapping | Implemented on `origin/feature/team-c-cerner-resource-mapping` (`29b94dd2`), not on this baseline | Pure Patient/Appointment projection exists with 57 reported focused tests; AllergyIntolerance and HTTP integration remain unimplemented. |
| Shared adapter | `EhrApiClient` exists on Team D and Team B branches in different packages/forms | The shared adapter interface is proposed, not approved for Team C use. |
| Shared persistence/reconciliation | Models and SQL exist on feature branches, not this baseline | ERD/canonical persistence and reconciliation rules require approval before persistence assertions. |
| Frontend health-data model | Exists on `origin/feature/e-health-data-frontend` | Mock and E2E assertions must be reconciled with OpenAPI 1.0 before sign-off. |

The repository's `TESTING_NORMS.md` requires shared fixtures, no live network or database dependencies in unit tests, and test-only helpers under established test locations. This plan follows those rules.

## 3. Scope

### In scope

- Mapping and normalization of approved M3 Cerner FHIR R4 resources into the approved CareConnect schema.
- Source identity and provenance retention, including source system and source record identity.
- Successful authorized retrieval and FHIR Bundle processing.
- Missing optional data, malformed required/core data, empty results, and mixed valid/invalid Bundle entries.
- Authorization denial, expired access tokens, approved refresh behavior, and refresh failure.
- Timeouts, retry behavior, rate limits, pagination, loop/duplicate protection, partial results, and upstream errors.
- Controller status codes and serialization.
- Validation of backend responses and frontend mock fixtures against the same approved OpenAPI file.
- Frontend model, service, state-management, unit, widget, accessibility, and regression testing for approved Cerner-backed views.
- Critical frontend-to-backend workflows, regression, and a small live Cerner sandbox smoke test.
- Synthetic fixtures and sanitized sandbox captures only.

### Out of scope

- Writes to Cerner or any other EHR.
- Production PHI, production credentials, or production endpoints.
- Patient matching by name or other uncertain demographic inference.
- Final endpoint paths, normalized output JSON, error code names, or `sourceStatus` values before OpenAPI 1.0 approval.
- Treating draft feature-branch schema or mapping artifacts as approved cross-team contracts.

## 4. Requirements

| ID | Requirement | Criticality |
|---|---|---|
| M3-REQ-01 | Map each approved Cerner FHIR R4 resource to the approved canonical CareConnect model while preserving source identity and provenance. | Critical |
| M3-REQ-02 | Normalize approved codes, cardinalities, dates, and date-times without inventing absent values; emit UTC where the API contract requires it. | Critical |
| M3-REQ-03 | Bind every Cerner request to the server-controlled, authorized synthetic patient context and prevent cross-patient or cross-source access. | Critical |
| M3-REQ-04 | Retrieve AllergyIntolerance records from Cerner, map every approved allergy field, and return successful empty results without fabricating records. | Critical |
| M3-REQ-05 | On token expiry, perform only the approved refresh flow, bound refresh attempts, and never expose or log tokens. | Critical |
| M3-REQ-06 | Handle missing optional fields and reject or isolate malformed required/core data deterministically without fabricating clinical meaning. | High |
| M3-REQ-07 | Bound timeouts and retries; honor the approved retry policy for transient errors and rate limits without retry storms. | High |
| M3-REQ-08 | Follow valid pagination links, prevent loops/duplicates, and return or report partial results according to OpenAPI 1.0. | Critical |
| M3-REQ-09 | Distinguish and handle CareConnect denial, missing Cerner authorization, insufficient scope, expired source authorization, refresh failure, and upstream authorization rejection according to OpenAPI 1.0. | Critical |
| M3-REQ-10 | Serialize and validate frontend mocks and backend success, error, and partial responses against the same authoritative OpenAPI file in CI. | Critical |
| M3-REQ-11 | Complete critical frontend-to-backend retrieval workflows without EHR write-back. | Critical |
| M3-REQ-12 | Retain original source payload/provenance under approved access controls and keep uncertain matches separate. | Critical |
| M3-REQ-13 | Preserve existing health-data behavior through focused regression tests. | High |
| M3-REQ-14 | Demonstrate current interoperability with a documented synthetic live-sandbox smoke test weekly and before sign-off. | Critical |
| M3-REQ-15 | Meet coverage, CI stability, contract coverage, defect, and evidence requirements for sign-off. | Critical |

Requirements must be referenced in JUnit tags or display names, for example `@Tag("M3-REQ-04")` and `@DisplayName("M3-REQ-04: complete AllergyIntolerance maps every field")`. Scenario IDs from the catalog may also be included.

The M3 AllergyIntolerance reference workflow uses `M3-REQ-04` for allergy retrieval and `M3-REQ-09` for source authorization failures. Do not renumber them without updating the catalog, fixtures, test tags, and traceability matrix together.

## 5. Test levels and ownership

| Level | Proves | Primary owner | Typical tooling |
|---|---|---|---|
| 1. Unit | Mapper normalization, service decisions, token-refresh decisions, pagination/partial-result algorithms | Developer; QA pairs on first mapper pattern and reviews cases/fixtures | JUnit 5, Mockito |
| 1b. Frontend unit/widget | Frontend models, services, state transitions, rendering, source attribution, empty/error/partial states, accessibility, and regressions | Frontend developer; QA reviews scenarios and approved contract fixtures | Flutter test/widget framework and approved mock fixtures |
| 2. Controller slice | Routing, CareConnect authorization, status codes, DTO serialization, exception translation | Developer; QA reviews against catalog | Spring MVC slice tests / MockMvc |
| 3. OpenAPI contract | Backend responses and frontend mocks conform to one approved interface | QA coordinates; backend/frontend developers maintain producers | OpenAPI validator selected by team |
| 4. Integration | Real Spring wiring plus stubbed Cerner/OAuth HTTP behavior, retries, pagination, failures | QA | `@SpringBootTest`, WireMock |
| 5. End-to-end | A small number of critical UI-to-backend workflows | QA with frontend/backend developers | Existing Flutter integration framework plus test backend |
| 6. Live smoke | Current OAuth and Cerner sandbox interoperability using synthetic data | QA coordinates; authorized team member executes | Manual checklist and sanitized evidence |

Backend developers own mapper/service unit tests and controller slice tests. Frontend developers own model, service, state-management, unit, widget, accessibility, and regression tests for the UI code they implement. QA owns this plan, the scenario catalog, traceability, fixture governance and expected outputs, WireMock failure stubs/integration tests, critical E2E tests, live smoke coordination, defect triage, and final sign-off. QA and the assigned developer pair on the first AllergyIntolerance mapper to establish the pattern.

As a planning guide for each resource workflow, target approximately 10–20 backend unit tests, 6–10 controller-slice tests, 6–10 WireMock integration tests, and 2–3 E2E tests. For the first AllergyIntolerance UI workflow, target approximately 8–15 frontend unit/widget tests, followed by resource-specific additions only where another resource introduces distinct presentation behavior. These are guidance rather than quotas. If E2E coverage grows beyond the critical user journeys, move scenarios to the lowest level that can prove them.

## 6. Delivery phases

| Phase | Timing | QA activity |
|---|---|---|
| 0. Preparation | First 2–3 days, before mapping code | Establish requirement IDs; capture and sanitize FHIR fixtures; define paired expected outputs; complete the scenario catalog. |
| 1. WBS 4.7 | Alongside mapper development | Developers write mapper/unit tests using the fixtures; QA verifies that every approved expected-output field is asserted. |
| 2. Start of WBS 4.8 | While mapping finishes | Add controller-slice and OpenAPI contract tests using mocked services; add frontend unit/widget tests as approved models, state handling, and views appear. |
| 3. Middle of WBS 4.8 | First endpoint reaches a stubbed Cerner call | Add WireMock happy-path, authorization, timeout, retry, malformed-body, rate-limit, and pagination integration tests. |
| 4. End of WBS 4.8 | Integrated frontend/backend available | Run only the critical frontend-to-backend workflows with the backend pointed at WireMock. |
| 5. Sign-off | Release candidate | Run regression, the recent sandbox smoke test, coverage/CI checks, and produce the test summary report. |

WBS 4.7 and 4.8 intentionally overlap. Carry AllergyIntolerance through all phases first, then reuse the established pattern for each remaining approved resource.

## 7. Environments and test data

- Backend unit, frontend unit/widget, slice, contract, integration, and E2E tests must be deterministic, offline, and use synthetic fixtures.
- WireMock represents Cerner FHIR and OAuth boundaries. Tests must never depend on live sandbox availability.
- The live smoke test uses Oracle Health code Console Test Sandbox only, an approved synthetic patient, S256 PKCE, provider authentication, and short-lived bearer tokens.
- Secrets, authorization codes, code verifiers, access/refresh tokens, cookies, and identifying headers must never enter fixtures, logs, screenshots, or commits.
- Sanitized captures must follow [fixtures-README.md](fixtures-README.md).

## 8. Entry criteria

Work that can start now:

- Approve these requirement identifiers and scenario taxonomy.
- Create synthetic source fixtures and general success/failure WireMock stubs.
- Pair on the first mapper and implement mapper/service tests that do not rely on unresolved API fields.
- Establish traceability and evidence collection.

Contract-dependent testing starts only after:

1. A protected `integration/unified-health-data` branch exists from the verified frontend baseline.
2. `contracts/unified-health-data.openapi.yaml` version 1.0 is reviewed and approved by frontend, backend, Cerner, Epic, and Athena contributors.
3. The canonical model/ERD, shared adapter interface, reconciliation rules, and final M3 resource scope are approved.
4. The contract defines paths/parameters, camelCase response fields, normalized records, `source` values, `sourceRecordId`, UTC dates, authorization states/errors, common error envelope, pagination, and partial-result `sourceStatus` behavior.

## 9. Execution and evidence

- Pull-request checks: backend unit, frontend unit/widget, controller slice, contract validation, accessibility checks, and relevant regression tests.
- Integration checks: WireMock suites for success and failure paths, including deterministic virtual delays and sequential responses.
- E2E: only critical user journeys that add UI/backend evidence.
- Live smoke: weekly while integration is active and again within the sign-off window defined by the team; record date/time, sandbox, synthetic patient alias, resource, result, executor, related commit/build, and sanitized evidence link.
- Store CI links, coverage reports, test reports, contract validator output, smoke records, and defects in the traceability matrix or linked evidence location.
- Assemble the sign-off evidence package: a one- or two-page test summary, completed traceability matrix, JaCoCo report, CI links, E2E screenshots/video, live-smoke record, and defect list.

No live token value, PHI, raw credential, or unsanitized request/response header is acceptable evidence.

## 10. Defect handling

- **Critical:** authorization bypass, cross-patient data, token/PHI exposure, write-back, broad data corruption, or total critical-flow failure. Blocks merge and sign-off.
- **High:** incorrect clinical mapping, silent record loss, broken pagination/partial-result semantics, contract incompatibility, or unrecoverable authorized retrieval. Blocks sign-off.
- **Medium/Low:** limited non-critical behavior or presentation issue with a documented workaround and product-owner disposition.

QA records requirement/scenario IDs, environment, fixture, expected/actual result, logs with secrets removed, reproducibility, severity, and retest evidence. Critical security/privacy findings are escalated immediately.

## 11. Exit and sign-off criteria

Milestone 3 is eligible for QA sign-off only when all are true:

- Every approved M3 requirement has passing evidence in the traceability matrix.
- All critical scenarios pass at their assigned level; required higher-level boundary checks also pass.
- JaCoCo reports at least 80% line and 70% branch coverage for mapping code and at least 70% line coverage for Cerner integration code overall.
- Every implemented endpoint has approved OpenAPI contract validation, and frontend mocks validate against the same file.
- Relevant frontend model, state-management, unit, widget, accessibility, and regression tests pass.
- No open Critical or High defects.
- Three consecutive relevant CI runs pass on the sign-off candidate without test suppression or unexplained flakiness.
- A recent documented live Cerner sandbox smoke test passes.
- Synthetic-only, retrieval-only, provenance, authorization, logging, and no-write-back boundaries have been reviewed.

QA may issue **Pass**, **Pass with accepted conditions** (no Critical/High defects and explicit approver acceptance), or **Fail**. The final report must name the commit, contract version/checksum, test results, coverage, CI runs, smoke evidence, open defects, deviations, and approvers.

## 12. Dependencies and open decisions

| Dependency | Status at draft time | Blocks |
|---|---|---|
| Protected integration branch and verified frontend baseline | Not observed | Cross-team integration execution |
| Unified OpenAPI 1.0 | Not observed | Endpoint paths, DTOs, exact errors, `sourceStatus`, contract tests, final expected JSON |
| Approved canonical model/ERD | Draft implementations exist on feature branches | Final mapping/persistence expectations |
| Approved shared adapter interface | Competing/proposed feature-branch forms exist | Client/service integration pattern |
| Approved reconciliation rules | Proposed | Duplicate/uncertain-match assertions |
| Final M3 resource scope | Pending | Complete requirement and endpoint coverage |
| Refresh-token policy for Cerner | Pending | Exact refresh assertions and retry limits |
| Pagination and partial-result contract | Pending OpenAPI | Exact client-facing assertions |
| Approved frontend presentation rules | Pending | Exact empty, loading, reconnect, access-denied, source-label, error, retry, partial-result, and accessibility assertions |

These items are gates, not assumptions. Update this plan, the catalog, fixtures, and matrix when each decision is approved.
