# M3 Cerner Expected Test Coverage and Team Responsibilities

**Audience:** Team C developers, QA, frontend contributors, and integration reviewers
**Owner:** Team C QA Lead
**Status:** Draft execution guide; exact API assertions remain pending OpenAPI 1.0 approval
**Applies to:** WBS 4.7 Cerner mapping and WBS 4.8 Cerner endpoint development
**Boundary:** Synthetic data only, retrieval only, no EHR write-back

## 1. Purpose

This document tells the implementation and testing teams which automated and manual tests are expected for the complete M3 Cerner integration, who creates them, and when work is considered test-complete. It supplements the M3 test plan, scenario catalog, traceability matrix, and fixture guide.

AllergyIntolerance is the first reference workflow. It must pass through every testing level so the team can establish reusable fixture loading, expected-output comparison, controller testing, contract validation, WireMock configuration, E2E setup, and evidence collection. The same pattern then applies to Patient and every other resource approved for the final M3 scope, such as Condition, Encounter, and Appointment.

The AllergyIntolerance example does not limit the overall test scope to allergies.

## 2. Responsibility model

| Work | Primary owner | QA responsibility | Completion expectation |
|---|---|---|---|
| Mapper unit tests | Developer who implements the mapper | Define/review fixtures, expected outputs, edge cases, and field assertions | Mapper pull request includes passing tests for every implemented rule. |
| Service/client unit tests | Developer who implements the service/client | Review authorization, refresh, retry, pagination, partial-result, and logging cases | Service/client pull request proves its decisions without live network access. |
| Controller-slice tests | Developer who implements the controller | Review statuses, serialization, authorization, and error-envelope coverage | Controller pull request includes passing slice tests. |
| OpenAPI contract tests | Backend and frontend developers maintain their producers; QA coordinates | Ensure both sides validate against the same approved contract/version | Every implemented endpoint and frontend mock validates in CI. |
| WireMock integration tests | QA, with implementation support from developers | Create failure stubs, integration scenarios, and expected results | Real Spring wiring passes success and Cerner-failure scenarios offline. |
| Frontend-to-backend E2E tests | QA with frontend/backend contributors | Select and automate only critical user workflows | Two or three stable tests prove the user-visible boundaries. |
| Live sandbox smoke | QA coordinates; an authorized team member may execute | Maintain checklist, schedule, sanitized evidence, and follow-up | One pass per workflow weekly and within the week before sign-off. |
| Defect regression tests | Developer who fixes the defect | Confirm the test reproduces the defect before the fix and passes afterward | A defect fix is incomplete without a regression test at the lowest useful level. |
| Traceability and final sign-off | QA | Maintain results/evidence and issue the disposition | Every approved requirement has evidence and all release gates pass. |

Developers are responsible for testing the production code they create. QA does not replace developer unit or controller testing. QA establishes the overall strategy, supplies/reviews test data and expected results, tests higher-level boundaries and failure behavior, and independently evaluates whether the evidence is sufficient for sign-off.

For the first AllergyIntolerance mapper, QA and the assigned developer should pair to implement the first few tests and agree on the reusable pattern.

## 3. Testing rule

Test each scenario at the lowest level that can prove it. Repeat a scenario at a higher level only when the higher level proves a new boundary.

Examples:

- Unit test: missing allergy severity maps according to the approved rule.
- Controller slice: the response uses the approved JSON field name and status code.
- Contract test: the response conforms to the authoritative OpenAPI schema.
- WireMock integration: the application survives a slow or malformed Cerner response.
- E2E: the user sees a reconnect or partial-results state.
- Live smoke: the current Cerner sandbox still behaves like the stubs.

Do not repeat every mapper edge case through controller, integration, and E2E tests.

## 4. Expected tests by level

### 4.1 Mapper and service unit tests

Create field-specific mapper tests for every resource in the approved M3 scope. At minimum, cover:

- A complete valid resource maps every approved output field.
- The entire result is compared structurally with its paired expected-output fixture.
- Missing optional fields produce the approved absent, `null`, or empty representation.
- Missing or malformed required/core fields are rejected or isolated deterministically.
- Unknown codes, statuses, or severity values follow the approved fallback rule without inventing clinical meaning.
- FHIR date/date-time values preserve the instant and approved precision; contract-required date-times normalize to UTC.
- Multiple codings, reactions, participants, or other repeated elements preserve approved cardinality.
- Excluded states such as `entered-in-error` do not appear in active output.
- Inactive states follow the documented include/exclude rule.
- Empty Bundles produce successful empty results.
- Source system, source record identity, version, timestamps, and required provenance are retained.
- Patient and source-tenant references cannot cross the authorized server-controlled link.
- Repeat mapping is deterministic and supports the approved scoped identity/idempotency rule.
- Unsupported modifiers, oversized/deep JSON, and unsafe references are rejected without leaking values.
- Tokens, identifiers, clinical payloads, and secrets do not appear in exceptions or logs.

Shared service/client unit tests must additionally cover:

- Retrieval uses only server-controlled patient context and approved scope.
- Missing, expired, insufficient-scope, and rejected authorization states remain distinct.
- Expired token performs only the approved bounded refresh/retry behavior.
- Refresh failure stops without a retry loop.
- Timeout, transient-server retry, and rate-limit decisions follow the approved bounded policy.
- Pagination follows valid same-source next links and detects loops.
- Duplicate records across pages follow the approved scoped identity rule.
- Later-page failure produces the approved partial-result domain state.
- Mixed valid/malformed entries follow the approved isolation or total-failure policy.

Planning range: approximately 10–20 unit tests per resource workflow, adjusted for actual mapping complexity.

### 4.2 Spring Boot controller-slice tests

Use controller-slice tests with a mocked service. Each Cerner-backed endpoint must cover, as applicable:

- Valid authorized request returns HTTP 200 and the approved camelCase fields.
- Missing CareConnect login returns HTTP 401.
- Authenticated caller without patient permission returns HTTP 403 and does not call the service.
- Unknown local patient returns HTTP 404 and does not call Cerner.
- Invalid path/query input returns HTTP 400 when defined by the approved contract.
- Source authorization expiry maps to the approved status and error code.
- Source unavailability maps to the approved envelope and `retryable` value.
- Empty results serialize as a successful empty response.
- Partial results serialize records and approved `sourceStatus` behavior.
- Internal projections, raw payloads, tokens, and unapproved PHI fields are not exposed.
- Every success and error response used by the slice tests validates against OpenAPI 1.0.

Planning range: approximately 6–10 slice tests per endpoint/workflow.

### 4.3 OpenAPI contract tests

Contract tests protect the boundary between the CareConnect backend and frontend. They are separate from WireMock integration tests.

Validate:

- Every implemented Cerner-backed success response.
- Every approved authorization/error envelope.
- Empty and partial-result responses.
- CamelCase field names and required/optional field behavior.
- Approved source values, including `CERNER`.
- `sourceRecordId` and date/date-time formats.
- The standard error fields: `code`, `message`, `source`, and `retryable`.
- Frontend mock fixtures and backend responses against the same contract path, version, and checksum.

Do not finalize paths, DTO shapes, error-code names, exception mappings, or `sourceStatus` assertions until `contracts/unified-health-data.openapi.yaml` version 1.0 is approved.

### 4.4 WireMock integration tests

Use `@SpringBootTest` with the Cerner FHIR and OAuth addresses pointed to WireMock. Test the real application wiring without relying on the live sandbox.

Required shared scenarios:

- Successful token and FHIR retrieval.
- Successful empty searchset Bundle.
- Expired token followed by successful approved refresh and retry.
- Refresh failure such as `invalid_grant`.
- Cerner authorization denial or insufficient scope.
- Response delay beyond the configured timeout.
- Transient upstream server failure and bounded retry.
- Malformed JSON or FHIR body returns a clean application error, not a stack trace.
- HTTP 429 rate limiting follows the approved `Retry-After`/retry rule.
- Multi-page Bundle returns all approved de-duplicated records.
- Invalid, looping, or cross-source next links are rejected.
- First page succeeds and a later page fails, producing the approved partial result.
- Mixed valid and malformed Bundle entries follow the approved policy.
- Integration responses validate against OpenAPI 1.0.

Planning range: approximately 6–10 core WireMock tests per workflow. Put behavior shared by every resource in the common Cerner client/service suite rather than copying it into every resource suite. Add resource-specific integration cases only when the resource behaves differently.

### 4.5 Frontend-to-backend E2E tests

Keep E2E coverage limited to critical user-visible workflows:

1. A clinician logs in, opens a patient, and sees normalized Cerner records with a Cerner source label.
2. With the Cerner connection expired, the UI shows the approved reconnect state instead of a misleading empty list.
3. With Cerner unavailable, the UI shows data from available sources and an accessible partial-results notice.

For the first workflow, use AllergyIntolerance. Repeat for another resource only when it introduces a distinct critical user behavior.

Planning range: two or three E2E tests per workflow. If this count grows, move scenarios to unit, slice, contract, or integration coverage.

### 4.6 Live Cerner sandbox smoke tests

For each approved workflow:

- Use an approved synthetic sandbox patient.
- Complete the real SMART-on-FHIR authorization flow.
- Perform retrieval only; do not write to Cerner.
- Confirm the response/display matches current sandbox behavior and the sanitized fixture assumptions.
- Record UTC date/time, tester, candidate commit/build, synthetic patient alias, resource/search, expected and actual summary, pass/fail, and sanitized evidence.
- Remove tokens, authorization codes, cookies, stable identifiers, and sensitive headers from evidence.
- Update affected fixtures and their metadata if the real sandbox response legitimately changes.

Run once per week while integration is active and again within the week before sign-off.

## 5. Resource coverage matrix

Complete this table when the final M3 resource scope is approved. A resource is not test-complete until every applicable column has passing evidence.

| Resource/workflow | Mapper unit | Service/client unit | Controller slice | Contract | WireMock integration | E2E if distinct | Live smoke | Status |
|---|---|---|---|---|---|---|---|---|
| AllergyIntolerance | Required; first reference workflow | Required | Required | Required | Required | Three critical workflows | Required | Planned |
| Patient | Required | Shared + resource-specific | If endpoint is in scope | If endpoint is in scope | Resource-specific happy path | Only if distinct | Required if in scope | Scope confirmation pending |
| Condition | Required if approved | Shared + resource-specific | If endpoint is in scope | If endpoint is in scope | Resource-specific happy path | Only if distinct | Required if in scope | Scope confirmation pending |
| Encounter | Required if approved | Shared + resource-specific | If endpoint is in scope | If endpoint is in scope | Resource-specific happy path | Only if distinct | Required if in scope | Scope confirmation pending |
| Appointment | Required if approved | Shared + resource-specific | If endpoint is in scope | If endpoint is in scope | Resource-specific happy path | Only if distinct | Required if in scope | Scope confirmation pending |
| Additional approved M3 resource | Required | Shared + resource-specific | Required when exposed | Required when exposed | As behavior requires | Only if distinct | Required if in scope | TBD |

“Shared + resource-specific” means common OAuth, timeout, retry, pagination, and error behavior is proven once in the shared client/service suite; the resource adds only tests needed for a distinct request, parsing, or mapping behavior.

## 6. Test and fixture conventions

- Tag or name every automated test with at least one `M3-REQ-*` identifier.
- Include the scenario ID when practical, for example `M3-SC-MAP-001`.
- Use one fixture for one primary purpose.
- Pair source and expected files by base name, such as `bundle-three-allergies.json` and `bundle-three-allergies.expected.json`.
- Compare expected JSON or objects structurally; assert every approved output field.
- Use deterministic clocks and stable synthetic identifiers.
- Keep unit, slice, contract, integration, and E2E automation independent of the live sandbox.
- Follow `fixtures-README.md` for directory layout, sanitization, metadata, and review.

## 7. Pull-request definition of done

A Cerner implementation pull request is test-complete only when:

- Applicable requirement and scenario IDs are identified.
- Developer-owned unit and controller-slice tests are included and passing.
- New or changed fixtures and expected outputs are reviewed and sanitized.
- Every implemented mapping field has an assertion, preferably through recursive expected-output comparison.
- Failure behavior and security/privacy boundaries are covered at the lowest useful level.
- A regression test accompanies each defect fix.
- Contract-dependent behavior matches the approved OpenAPI version, or is clearly blocked rather than invented.
- Relevant traceability rows identify the tests and current result.
- No test is disabled, ignored, dependent on execution order, or dependent on the live sandbox.
- The relevant CI checks pass.

## 8. M3 sign-off gates

- Every approved M3 requirement has passing automated evidence or a documented manual test with evidence.
- Every critical scenario passes, including success, empty result, expired token with successful refresh, refresh failure, authorization denial, timeout, malformed response, and partial results.
- JaCoCo reaches at least 80% line and 70% branch coverage for the mapping package and at least 70% line coverage across Cerner integration code overall.
- Every implemented endpoint passes contract validation.
- Frontend mocks and backend responses validate against the same OpenAPI contract/checksum.
- No Critical or High defects remain open.
- Three consecutive relevant CI runs pass on the sign-off candidate.
- A live Cerner sandbox smoke test passed within the prior week.
- The evidence package contains the test summary, completed traceability matrix, coverage report, CI links, E2E evidence, smoke record, and defect list.

Coverage numbers do not replace meaningful assertions. QA review must confirm that every expected clinical and provenance field is actually checked.

## 9. Related artifacts

- [M3 test plan](m3-test-plan.md)
- [M3 scenario catalog](m3-scenario-catalog.md)
- [M3 traceability matrix](m3-traceability-matrix.md)
- [Fixture guide](fixtures-README.md)
