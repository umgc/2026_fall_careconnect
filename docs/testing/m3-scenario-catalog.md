# Milestone 3 Cerner Scenario Catalog

**Status:** Working QA baseline; contract-dependent assertions remain provisional
**Example workflow:** AllergyIntolerance
**Rule:** Test at the lowest useful level; repeat higher only to prove a new boundary.

## Conventions

- Priority: **P0** blocks sign-off; **P1** is required for normal sign-off; **P2** is useful regression/depth.
- Automation: **Now** can be authored without the approved API contract; **After contract** requires OpenAPI 1.0; **Manual** is sandbox-only.
- Expected results intentionally use semantic language where the endpoint shape or error code is unresolved.
- Every automated test name/tag must include at least one `M3-REQ-*` ID. Use the scenario ID as a second identifier when practical.
- When an unresolved decision affects a scenario, the test or fixture metadata must cite the dependency and temporary assumption from the test plan; update the assertion when the decision is approved.

## Provisional walkthrough interfaces

The M3 AllergyIntolerance reference workflow illustrates frontend/backend `GET /api/patients/{patientId}/allergies` and Cerner FHIR `GET /AllergyIntolerance?patient={cernerPatientId}`. The catalog uses those interactions to define scenarios, but the paths, parameters, normalized JSON fields, exception classes, error-code names, and `sourceStatus` values are examples—not final contracts. Replace them only with values approved in `contracts/unified-health-data.openapi.yaml` 1.0 and the approved Cerner client design.

The dependency and temporary-assumption register in Section 12 of [m3-test-plan.md](m3-test-plan.md) governs provisional scenarios. Semantic tests may proceed now where practical; exact contract and normalization assertions remain pending their authoritative approvals.

## A. Mapping and normalization

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-MAP-001 | M3-REQ-01, 02, 04, 12 | Unit | P0 | A complete AllergyIntolerance maps every approved field: substance text/code, clinical status, verification status, reaction manifestations, severity, recorded date, `source: CERNER`, and `sourceRecordId`. A recursive comparison asserts every field in the paired expected output. | After canonical approval |
| M3-SC-MAP-002 | M3-REQ-01, 02 | Unit | P0 | Multiple codings and reaction manifestations preserve approved cardinality and do not collapse distinct source facts. | After canonical approval |
| M3-SC-MAP-003 | M3-REQ-02 | Unit | P0 | Offset date-times normalize to the contract-required UTC representation without changing the instant. Partial FHIR dates retain approved precision and are not fabricated. | Now; finalize expected JSON after contract |
| M3-SC-MAP-004 | M3-REQ-04, 06 | Unit | P0 | An AllergyIntolerance with no reaction maps to an empty reaction list, not an error. Other missing optional fields follow the approved absent/null/empty rule; no clinical values are invented. | Now; finalize output after canonical approval |
| M3-SC-MAP-005 | M3-REQ-06 | Unit | P0 | Missing/malformed resource type, logical ID, required patient linkage, or invalid core date/code container is rejected or isolated with a value-free diagnostic. | Now |
| M3-SC-MAP-006 | M3-REQ-03, 04, 12 | Unit | P0 | AllergyIntolerance for a different patient or source tenant is rejected; names/demographics are never used as an implicit match. | Now |
| M3-SC-MAP-007 | M3-REQ-12 | Unit | P0 | Two uncertain possible matches remain separate source records; mapper does not reconcile them. | After reconciliation approval |
| M3-SC-MAP-008 | M3-REQ-01, 12 | Unit | P1 | Reprocessing the same scoped source record is deterministic and supports approved idempotent upsert identity. | After model approval |
| M3-SC-MAP-009 | M3-REQ-06 | Unit | P1 | Narrative, photos, arbitrary extensions, unsupported modifier extensions, and unrelated fields are excluded or rejected according to the approved allowlist/safety rule. | Now |
| M3-SC-MAP-010 | M3-REQ-06 | Unit | P1 | Oversized/deep source JSON is rejected at approved HTTP/parser limits without logging payload contents. | Now |
| M3-SC-MAP-011 | M3-REQ-02, 04 | Unit | P0 | A substance containing text but no coding preserves the text and leaves the approved code field empty; it does not invent a code. | After canonical approval |
| M3-SC-MAP-012 | M3-REQ-04 | Unit | P0 | Verification status `entered-in-error` is excluded from the returned allergy records. | Now |
| M3-SC-MAP-013 | M3-REQ-04 | Unit | P1 | An inactive allergy is retained and marked inactive or excluded exactly as the team-approved rule specifies. This expected result remains an open decision until recorded. | After decision |
| M3-SC-MAP-014 | M3-REQ-02, 04 | Unit | P0 | An unknown severity maps to `null` and emits a value-safe warning; it does not throw or expose clinical data in logs. | After canonical/logging approval |
| M3-SC-MAP-015 | M3-REQ-04 | Unit | P0 | An empty AllergyIntolerance searchset Bundle produces a successful empty list. | Now |

The first mapper pairing should implement MAP-001, MAP-004, MAP-005, MAP-006, and MAP-011–015, agree on fixture loading and recursive expected-output comparison, then apply that pattern to the remaining approved resources. Existing Patient/Appointment mapper tests on the Team C feature branch are useful evidence for the pattern but do not satisfy the planned AllergyIntolerance cases. The 15 mapping scenarios fall within the recommended range of 10–20 unit tests per workflow.

## B. Service, OAuth, and retrieval behavior

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-SVC-001 | M3-REQ-03, 04 | Unit | P0 | Authorized request builds an AllergyIntolerance search using server-controlled patient context and approved scope; client input cannot replace patient context. | Now |
| M3-SC-SVC-002 | M3-REQ-09 | Unit | P0 | Distinct missing, expired, insufficient-scope, and upstream-rejected authorization states map to distinct domain outcomes. | Final names after contract |
| M3-SC-SVC-003 | M3-REQ-05 | Unit | P0 | Expired token triggers one approved refresh action, then retries the original retrieval once with the new token. | After refresh policy |
| M3-SC-SVC-004 | M3-REQ-05 | Unit | P0 | Refresh denial/invalid refresh token stops retrieval and returns the approved reauthorization outcome; no loop occurs. | After refresh policy |
| M3-SC-SVC-005 | M3-REQ-05, 12 | Unit | P0 | Token, authorization code, verifier, secret, and clinical payload are absent from exceptions and logs. | Now |
| M3-SC-SVC-006 | M3-REQ-07 | Unit | P1 | Timeout and transient-server retry counts/backoff follow approved bounded policy; non-retryable failures are not retried. | After retry policy |
| M3-SC-SVC-007 | M3-REQ-07 | Unit | P1 | HTTP 429 honors valid `Retry-After` within configured bounds and stops at the retry limit. | After retry policy |
| M3-SC-SVC-008 | M3-REQ-08 | Unit | P0 | Multi-page search follows only valid same-source next links, collects all valid records, and prevents pagination loops. | Now; output after contract |
| M3-SC-SVC-009 | M3-REQ-08 | Unit | P0 | Duplicate record across pages is handled by approved scoped source identity without duplicate normalized output. | After model approval |
| M3-SC-SVC-010 | M3-REQ-08 | Unit | P0 | Later-page timeout/error after valid earlier pages produces approved partial-result state and retains successful records. | Final assertion after contract |
| M3-SC-SVC-011 | M3-REQ-06, 08 | Unit | P0 | Mixed Bundle entries isolate malformed entries while preserving valid entries only if approved policy permits; otherwise the request fails deterministically. | After partial policy |
| M3-SC-SVC-012 | M3-REQ-04 | Unit | P0 | Empty FHIR searchset Bundle returns a successful empty domain result, not a fabricated record or server error. | Now |

## C. Controller and OpenAPI contract

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-CTL-001 | M3-REQ-04, 10 | Controller slice | P0 | Valid authorized request returns HTTP 200 and the exact approved camelCase allergy fields, including patient identifier, substance, source, and source record identity; internal/raw fields are not leaked. | After contract |
| M3-SC-CTL-002 | M3-REQ-09, 10 | Controller slice | P0 | Missing CareConnect login token returns HTTP 401 with the approved common error envelope. | After contract |
| M3-SC-CTL-003 | M3-REQ-03, 09, 10 | Controller slice | P0 | Authenticated caller without permission for the patient returns HTTP 403 and does not call the Cerner service. | After contract |
| M3-SC-CTL-004 | M3-REQ-04, 10 | Controller slice | P0 | Unknown local patient returns HTTP 404 in the approved error envelope and does not call Cerner. | After contract |
| M3-SC-CTL-005 | M3-REQ-09, 10 | Controller slice | P0 | Source-auth-expired domain failure maps to the approved status and error code. `SOURCE_AUTH_EXPIRED` is illustrative until OpenAPI 1.0 approves it. | After contract |
| M3-SC-CTL-006 | M3-REQ-07, 10 | Controller slice | P0 | Source-unavailable domain failure maps to the approved envelope with `retryable: true`; exception and field names remain contract-dependent. | After contract |
| M3-SC-CTL-007 | M3-REQ-08, 10 | Controller slice | P0 | Partial domain result serializes records and `sourceStatus` exactly as approved. | After contract |
| M3-SC-CTL-008 | M3-REQ-10 | Controller slice | P1 | Invalid path/query parameters are rejected with the common error envelope and no Cerner call. | After contract |
| M3-SC-CON-001 | M3-REQ-10 | Contract | P0 | Every success example and actual endpoint response validates against `contracts/unified-health-data.openapi.yaml` 1.0. | After contract |
| M3-SC-CON-002 | M3-REQ-09, 10 | Contract | P0 | Every error/authorization/partial-result response validates against the same contract. | After contract |
| M3-SC-CON-003 | M3-REQ-10 | Contract | P0 | Frontend mock fixtures validate against the exact contract version/checksum used by backend tests. | After contract |
| M3-SC-CON-004 | M3-REQ-10 | Contract | P0 | Contract enumerates only approved source values (`MEDICARE`, `EPIC`, `CERNER`, `ATHENA`) and requires `sourceRecordId`, UTC dates, and the common error fields. | After contract |

The eight slice scenarios fall within the recommended range of 6–10 tests per workflow. Contract validation remains a distinct level even when invoked by a slice test because it protects a different boundary.

## D. WireMock integration

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-INT-001 | M3-REQ-04, 10 | Integration | P0 | Token stub succeeds and the FHIR stub returns `bundle-three-allergies.json`; the real Spring wiring returns exactly three normalized allergy records. | After endpoint + contract |
| M3-SC-INT-002 | M3-REQ-09 | Integration | P0 | Cerner HTTP 401 invalid/expired token traverses the HTTP client, auth service, and approved API error translation correctly. | After endpoint + contract |
| M3-SC-INT-003 | M3-REQ-05, 09 | Integration | P0 | WireMock scenario returns FHIR 401, refresh success, then FHIR 200; exactly one bounded refresh occurs and no retry loop occurs. Verify the token endpoint is called exactly twice when the approved implementation uses the illustrated initial-token-plus-refresh flow; otherwise use the approved call count. | After refresh policy |
| M3-SC-INT-004 | M3-REQ-05, 09 | Integration | P0 | Refresh endpoint returns `invalid_grant`; retrieval stops and returns the approved source-authorization-expired outcome. `SOURCE_AUTH_EXPIRED` remains illustrative until contract approval. | After refresh policy/contract |
| M3-SC-INT-005 | M3-REQ-06 | Integration | P0 | Malformed JSON, wrong resource type, missing required linkage, and mixed Bundle entries produce approved isolation/error behavior. | After policy |
| M3-SC-INT-006 | M3-REQ-07 | Integration | P1 | Delayed response exceeds configured timeout and returns the approved retryable outcome within a bounded test duration. | After endpoint + policy |
| M3-SC-INT-007 | M3-REQ-07 | Integration | P1 | 429 with `Retry-After` and eventual success/failure follows configured call count and response behavior. | After policy |
| M3-SC-INT-008 | M3-REQ-08 | Integration | P0 | Two-page Bundle follows next link and returns complete de-duplicated results. | After endpoint |
| M3-SC-INT-009 | M3-REQ-08 | Integration | P0 | First page succeeds and second page fails; response matches approved partial-result contract. | After contract |
| M3-SC-INT-010 | M3-REQ-10 | Integration/contract | P0 | Captured integration responses validate against OpenAPI 1.0. | After contract |

These ten cases fall within the recommended range of 6–10 WireMock integration tests per workflow.

## E. End-to-end, regression, and live smoke

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-E2E-001 | M3-REQ-04, 11 | E2E | A clinician logs in, opens a patient, and sees the allergy list with a Cerner source label; no write action is offered or sent. | After UI/API integration |
| M3-SC-E2E-002 | M3-REQ-09, 11 | E2E | With the Cerner connection expired, the screen shows the approved reconnect message instead of a misleading empty allergy list. | After contract/UI |
| M3-SC-E2E-003 | M3-REQ-08, 11 | E2E | With Cerner unavailable, the screen continues to show available Medicare data and an accessible partial-results notice. | After contract/UI |
| M3-SC-REG-001 | M3-REQ-13 | Unit/widget/API regression | P1 | Existing non-EHR health and allergy workflows continue to pass after unified data integration. | With implementation |
| M3-SC-SMK-001 | M3-REQ-04, 14 | Live smoke | P0 | Using a known synthetic sandbox patient, valid SMART authorization retrieves the AllergyIntolerance workflow and the displayed records match the real sandbox response. Record date, tester, synthetic patient alias, result, and sanitized screenshot/log. | Manual weekly/pre-sign-off |
| M3-SC-SMK-002 | M3-REQ-09, 14 | Live smoke | P0 | Expired token returns HTTP 401 `invalid_token`; no sensitive token is retained in evidence. Refresh is checked only if the approved sandbox workflow supports it. | Manual weekly/pre-sign-off |
| M3-SC-SMK-003 | M3-REQ-03, 14 | Live smoke | P1 | Synthetic Patient, Condition, Encounter, Appointment, and other final-scope reads remain available as applicable; no write is attempted. | Manual after scope approval |

## Live smoke record template

```text
Date/time (UTC):
Executor:
Candidate commit/build:
OpenAPI version/checksum:
Oracle Health sandbox:
Synthetic patient alias (no real identifier):
Resource/search tested:
Expected result:
Actual HTTP/result summary:
Pass/fail:
Sanitized evidence link:
Defect ID (if any):
Confirmed no write-back: yes/no
Confirmed secrets/tokens removed: yes/no
```
