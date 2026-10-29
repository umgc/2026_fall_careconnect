# Milestone 3 Cerner Integration Test Plan

**Owner:** Team C QA Lead (Tiffany Obi)
**Status:** Working QA baseline for the five-resource Cerner scope; AllergyIntolerance remains the reference workflow and contract-dependent details remain provisional
**Work packages:** WBS 4.7 (Cerner mapping/normalization), WBS 4.8 (Cerner API endpoint development)
**Data boundary:** Synthetic data only; retrieval only; no write-back

## 1. Purpose

This plan defines how Team C will verify Cerner FHIR R4 retrieval, mapping, API behavior, and the critical frontend-to-backend workflow for Milestone 3. The confirmed Cerner retrieval scope is Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment. It applies the approved six-level testing strategy and assigns each scenario to the lowest level that proves the behavior. A scenario is repeated at a higher level only when that level proves a new boundary, such as HTTP serialization, the approved API contract, or actual sandbox interoperability.

The initial repeatable example is AllergyIntolerance. As of October 21, Team C contains the pure allergy mapper, provisional controller, shared fixtures, fixed mapper expectations, Oracle Health SMART OAuth/PKCE and encrypted-credential services, canonical patient-crosswalk linking, a live allergy service, bounded same-source pagination, one-time token refresh after a 401, raw AllergyIntolerance retention, and focused offline tests. Patient and Appointment have limited mapper/storage coverage. Condition and Encounter now have provisional shared, source-neutral persistence records, pure fixture-driven mappers, repositories, a shared bounded Cerner Bundle client, one-time refresh after a 401, original-resource retention, idempotent normalized upserts, stale-update protection, and focused HTTP/service/JPA tests. Their controllers, approved expected outputs, contract tests, frontend workflows, and live smoke evidence remain open. The public response shape remains provisional until the canonical model and unified OpenAPI contract are approved. See [the current validation report](team-c-task-validation-2026-10-17.md) for earlier executed results and [the Test Lead packet](team-c-m1-test-lead-review-2026-10-17.md) for review decisions.

This plan is intended for active use during implementation. QA artifacts, fixtures, tests, and traceability will evolve alongside WBS 4.7 and WBS 4.8 rather than being completed after development. An unresolved dependency does not prevent semantic or lower-level testing when the temporary assumption is recorded in Section 12; affected assertions must be updated after the authoritative decision is approved.

## 2. Repository baseline and artifact status

Snapshot inspected on branch `feature/team-c-cerner-qa-implementation` after fast-forwarding `team-c-develop` to `29ca58e4` on 2026-10-21:

| Artifact | Observed status | QA consequence |
|---|---|---|
| Five-resource Cerner scope | Confirmed: Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment | QA requirements and resource coverage now include all five; Appointment remains explicitly provisional. |
| `contracts/unified-health-data.openapi.yaml` | Not found in the synchronized repository | Paths, parameters, response shapes, error codes, contract tests, and `sourceStatus` assertions remain TBD. |
| AllergyIntolerance implementation | Mapper, provisional controller, live service wiring, OAuth/refresh, patient crosswalk, bounded pagination, raw-payload retention, fixtures, and focused offline tests exist | Useful vertical-slice pattern; approved contract validation, Spring/WireMock integration, E2E, live smoke, and final partial-result/rate-limit policies remain open. |
| Patient and Appointment implementation | `CernerResourceMapper` and `CernerStorageAdapter` provide limited mapping/storage behavior | Expand to approved field rules and endpoint/client evidence; do not count storage tests as end-to-end retrieval evidence. |
| Condition and Encounter implementation | Shared source-neutral records, repositories, pure mappers, a bounded same-source HTTP client, OAuth refresh orchestration, raw-payload retention, normalized upserts, stale-update protection, and focused HTTP/service/JPA tests exist; the shapes remain provisional | Review and approve the field rules, then add controllers, approved paired expected outputs, Spring/WireMock integration, contract tests, E2E, and smoke evidence. |
| Shared adapter and persistence | Shared EHR interfaces, canonical persistence, retention, and reconciliation code are present, but the final Cerner integration boundary still requires team confirmation | Reuse approved shared contracts; do not introduce a Cerner-only canonical model. |
| Frontend health-data integration | Shared health-data UI exists, but full Cerner retrieval and connection behavior are not demonstrated | Final frontend mocks and E2E assertions must be reconciled with the approved OpenAPI contract. |

The repository's `TESTING_NORMS.md` requires shared fixtures, no live network or database dependencies in unit tests, and test-only helpers under established test locations. This plan follows those rules.

## 3. Scope

### In scope

- Mapping and normalization of approved M3 Cerner FHIR R4 resources into the approved CareConnect schema.
- Read-only retrieval for Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment.
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
| M3-REQ-16 | Retrieve and map the authorized Cerner Patient resource without using demographics to infer identity. | Critical |
| M3-REQ-17 | Retrieve and map Cerner Condition search results, preserving approved category, status, code, onset/abatement, encounter reference, and provenance behavior. | Critical |
| M3-REQ-18 | Retrieve and map Cerner Encounter search results, preserving approved status, class/type, period, participants, service provider, and provenance behavior. | Critical |
| M3-REQ-19 | Retrieve and map provisional Cerner Appointment results using an approved bounded date or `-date-or-req-period` search; no appointment write-back is permitted. | High |
| M3-REQ-20 | Keep SMART authorization, token, audience, and FHIR requests on one approved persona/host pair and request only the approved read scopes. | Critical |

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
- QA records capture status in [cerner-fixture-capture-register.md](cerner-fixture-capture-register.md) and executes live checks with [cerner-secure-sandbox-smoke-checklist.md](cerner-secure-sandbox-smoke-checklist.md).

### Verified secure-sandbox reference

The following values were verified against Oracle Health discovery/capability metadata on 2026-10-21. They are test-environment references, not application secrets:

| Persona | FHIR base | Authorization/token behavior |
|---|---|---|
| Provider/non-patient access | `https://fhir-ehr-code.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d` | Use the provider authorization endpoint and the token endpoint whose host segment is `fhir-ehr-code.cerner.com`. |
| Patient access | `https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d` | Use the patient authorization endpoint and the token endpoint whose host segment is `fhir-myrecord.cerner.com`. |

The provider discovery document is `{providerBase}/.well-known/smart-configuration`. Tests must verify S256 PKCE, exact redirect URI matching, FHIR audience consistency, approved read-only scopes, and rejection of a token used against the wrong FHIR host. No client secret, launch value, authorization code, verifier, access token, refresh token, cookie, or bearer header may be committed.

Resource request patterns for the secure sandbox are:

- `GET {base}/Patient/{id}` or approved `_id` search.
- `GET {base}/AllergyIntolerance?patient={cernerPatientId}`.
- `GET {base}/Condition?patient={cernerPatientId}`.
- `GET {base}/Encounter?patient={cernerPatientId}`.
- `GET {base}/Appointment?patient={cernerPatientId}&date=gt{start}&date=le{end}` or the approved bounded `-date-or-req-period` equivalent.

These are Oracle Health boundary calls, not final CareConnect frontend/backend endpoint paths. For pagination, the client must follow the complete same-source `Bundle.link` URL whose relation is `next`, subject to loop and page-count limits.

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

| Dependency | Current status | Temporary testing assumption | Affected scenarios/tests | Approval owner/source | Required update after approval |
|---|---|---|---|---|---|
| Protected integration branch and verified frontend baseline | Not observed | Develop deterministic tests on the Team C branch; defer cross-team execution. | Contract, E2E, cross-team CI | Cross-team technical leads | Record branch and baseline commit; enable cross-team checks. |
| Unified OpenAPI 1.0 | Not observed | Use semantic outcomes only; illustrated paths, fields, errors, and `sourceStatus` are provisional. | CTL-001–008, CON-001–004, INT-001–010, E2E-002–003 | Frontend/backend/integration contributors | Pin path, version, and checksum; replace provisional assertions and validate fixtures/responses. |
| Approved canonical model/ERD | Draft implementations exist on feature branches | Preserve source facts and provenance without finalizing normalized JSON. | MAP-001–015 and expected outputs | Cross-team architecture/model owners | Create or revise paired expected outputs and field-level assertions. |
| Approved shared adapter interface | Competing/proposed feature-branch forms exist | Test behavior at service boundaries without assuming a package or concrete interface. | Service/client and integration tests | Cross-team technical leads | Align test wiring and shared client/service cases to the approved interface. |
| Oracle Health source identifier | Team C adopted the seeded persistence code `ORACLE_HEALTH`; the earlier provisional mapper value `CERNER` was retired | Use `ORACLE_HEALTH` in mapper records, persistence, connection status, and source error envelopes. | Mapper, controller, OAuth, persistence, contract | Team C plus OpenAPI approvers | Confirm that OpenAPI 1.0 exposes `ORACLE_HEALTH`; otherwise document and test an explicit API-to-persistence translation. |
| Approved reconciliation rules | Proposed | Keep uncertain matches separate and do not infer identity. | MAP-007–008, SVC-009–011, partial-result tests | Architecture/reconciliation owners | Finalize duplicate, crosswalk, uncertain-match, and partial-result assertions. |
| Final M3 resource scope | Confirmed for Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment | AllergyIntolerance remains the first reference workflow; apply the reusable pattern to the other four resources. | M3-REQ-04 and M3-REQ-16–20; resource matrix; smoke tests | Team C lead/product owner | Record any Appointment scope change and update affected tests without renumbering existing requirements. |
| Refresh-token policy for Cerner | Implementation baseline: refresh near local expiry, or once after an upstream 401; a failed refresh marks the credential `NEEDS_REAUTH` | Treat one forced refresh as the current bounded safety rule, pending backend approval. | SVC-003–004, INT-003–004 | Cerner/backend auth owners | Approve or revise the exact refresh rule and lock it with WireMock call-count assertions. |
| Pagination and partial-result contract | Client follows at most 20 unique, same-scheme/host/port/base-path pages; any later page failure currently fails the source request | Use the bounded same-source rule for internal client tests; do not finalize API partial-result assertions. | SVC-008–011, CTL-007, INT-008–009, E2E-003 | Contract and backend owners | Approve page limit, duplicate policy, later-page failure behavior, and `sourceStatus` assertions. |
| Approved frontend presentation rules | Pending | Test distinct loading, empty, denial, reconnect, error, retry, and partial states using provisional labels. | Frontend unit/widget and E2E | Frontend/product contributors | Replace provisional copy and presentation assertions with approved behavior. |

Update this register whenever an assumption is adopted or an authoritative decision is approved. Link the approving artifact, decision, or pull request; do not silently replace one competing approach with another.

## 13. Implementation coordination record

Complete this record with Team C as implementation begins:

| Coordination item | Assigned person/reference | Date/status |
|---|---|---|
| AllergyIntolerance mapper developer | TBD | TBD |
| Cerner allergy endpoint developer | Team C branch implementation | OAuth, crosswalk, live allergy service, pagination, and raw-payload baseline added 2026-10-21 |
| QA/developer first-mapper pairing session | Tiffany Obi + TBD | TBD |
| Implementation branch/pull request | `feature/team-c-cerner-qa-implementation` | Local implementation in progress; pull request TBD |
| Source fixture and sanitization reviewer | TBD | TBD |
| Expected-output/mapping reviewer | TBD | TBD |
| OpenAPI 1.0 approval reference and checksum | TBD | Pending approval |
| Canonical model approval reference | TBD | Pending approval |
