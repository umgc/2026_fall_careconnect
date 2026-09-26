# Milestone 3 Cerner Scenario Catalog

**Status:** Draft
**Example workflow:** AllergyIntolerance
**Rule:** Test at the lowest useful level; repeat higher only to prove a new boundary.

## Conventions

- Priority: **P0** blocks sign-off; **P1** is required for normal sign-off; **P2** is useful regression/depth.
- Automation: **Now** can be authored without the approved API contract; **After contract** requires OpenAPI 1.0; **Manual** is sandbox-only.
- Expected results intentionally use semantic language where the endpoint shape or error code is unresolved.
- Every automated test name/tag must include at least one `M3-REQ-*` ID. Use the scenario ID as a second identifier when practical.

## A. Mapping and normalization

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-MAP-001 | M3-REQ-01, 02, 12 | Unit | P0 | Valid synthetic AllergyIntolerance with coding, clinical/verification status, patient reference, onset/recorded date, reactions, and source metadata maps to approved canonical fields; source identity and provenance remain available. | After canonical approval |
| M3-SC-MAP-002 | M3-REQ-01, 02 | Unit | P0 | Multiple codings and reaction manifestations preserve approved cardinality and do not collapse distinct source facts. | After canonical approval |
| M3-SC-MAP-003 | M3-REQ-02 | Unit | P0 | Offset date-times normalize to the contract-required UTC representation without changing the instant. Partial FHIR dates retain approved precision and are not fabricated. | Now; finalize expected JSON after contract |
| M3-SC-MAP-004 | M3-REQ-06 | Unit | P1 | Missing optional fields map as absent/null/empty exactly as the approved rule specifies; no placeholder clinical values are invented. | Now; finalize output after contract |
| M3-SC-MAP-005 | M3-REQ-06 | Unit | P0 | Missing/malformed resource type, logical ID, required patient linkage, or invalid core date/code container is rejected or isolated with a value-free diagnostic. | Now |
| M3-SC-MAP-006 | M3-REQ-03, 12 | Unit | P0 | AllergyIntolerance for a different patient or source tenant is rejected; names/demographics are never used as an implicit match. | Now |
| M3-SC-MAP-007 | M3-REQ-12 | Unit | P0 | Two uncertain possible matches remain separate source records; mapper does not reconcile them. | After reconciliation approval |
| M3-SC-MAP-008 | M3-REQ-01, 12 | Unit | P1 | Reprocessing the same scoped source record is deterministic and supports approved idempotent upsert identity. | After model approval |
| M3-SC-MAP-009 | M3-REQ-06 | Unit | P1 | Narrative, photos, arbitrary extensions, unsupported modifier extensions, and unrelated fields are excluded or rejected according to the approved allowlist/safety rule. | Now |
| M3-SC-MAP-010 | M3-REQ-06 | Unit | P1 | Oversized/deep source JSON is rejected at approved HTTP/parser limits without logging payload contents. | Now |

The first mapper pairing should implement MAP-001, MAP-004, MAP-005, MAP-006, and MAP-009, agree on fixture loading and comparison style, then apply that pattern to the remaining approved resources. Existing Patient/Appointment mapper tests on the Team C feature branch are useful evidence for the pattern but do not satisfy the planned AllergyIntolerance cases.

## B. Service, OAuth, and retrieval behavior

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-SVC-001 | M3-REQ-03 | Unit | P0 | Authorized request builds a Cerner search using server-controlled patient context and approved scope; client input cannot replace patient context. | Now |
| M3-SC-SVC-002 | M3-REQ-04 | Unit | P0 | Distinct missing, expired, insufficient-scope, and upstream-rejected authorization states map to distinct domain outcomes. | Final names after contract |
| M3-SC-SVC-003 | M3-REQ-05 | Unit | P0 | Expired token triggers one approved refresh action, then retries the original retrieval once with the new token. | After refresh policy |
| M3-SC-SVC-004 | M3-REQ-05 | Unit | P0 | Refresh denial/invalid refresh token stops retrieval and returns the approved reauthorization outcome; no loop occurs. | After refresh policy |
| M3-SC-SVC-005 | M3-REQ-05, 12 | Unit | P0 | Token, authorization code, verifier, secret, and clinical payload are absent from exceptions and logs. | Now |
| M3-SC-SVC-006 | M3-REQ-07 | Unit | P1 | Timeout and transient-server retry counts/backoff follow approved bounded policy; non-retryable failures are not retried. | After retry policy |
| M3-SC-SVC-007 | M3-REQ-07 | Unit | P1 | HTTP 429 honors valid `Retry-After` within configured bounds and stops at the retry limit. | After retry policy |
| M3-SC-SVC-008 | M3-REQ-08 | Unit | P0 | Multi-page search follows only valid same-source next links, collects all valid records, and prevents pagination loops. | Now; output after contract |
| M3-SC-SVC-009 | M3-REQ-08 | Unit | P0 | Duplicate record across pages is handled by approved scoped source identity without duplicate normalized output. | After model approval |
| M3-SC-SVC-010 | M3-REQ-08 | Unit | P0 | Later-page timeout/error after valid earlier pages produces approved partial-result state and retains successful records. | Final assertion after contract |
| M3-SC-SVC-011 | M3-REQ-06, 08 | Unit | P0 | Mixed Bundle entries isolate malformed entries while preserving valid entries only if approved policy permits; otherwise the request fails deterministically. | After partial policy |
| M3-SC-SVC-012 | M3-REQ-03 | Unit | P1 | Empty FHIR searchset Bundle returns a successful empty domain result, not a fabricated record or server error. | Now |

## C. Controller and OpenAPI contract

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-CTL-001 | M3-REQ-03, 09 | Controller slice | P0 | Authorized success returns the approved status and camelCase normalized response; internal projection/raw PHI fields are not leaked. | After contract |
| M3-SC-CTL-002 | M3-REQ-04, 09 | Controller slice | P0 | Each approved authorization failure produces its distinct status/error code in the common error envelope. | After contract |
| M3-SC-CTL-003 | M3-REQ-07, 09 | Controller slice | P1 | Timeout, rate-limit, and upstream-unavailable domain outcomes serialize with correct `source` and `retryable`. | After contract |
| M3-SC-CTL-004 | M3-REQ-08, 09 | Controller slice | P0 | Partial domain result serializes records and `sourceStatus` exactly as approved. | After contract |
| M3-SC-CTL-005 | M3-REQ-09 | Controller slice | P0 | Invalid path/query parameters are rejected with the common error envelope and no Cerner call. | After contract |
| M3-SC-CON-001 | M3-REQ-09, 10 | Contract | P0 | Every success example and actual endpoint response validates against `contracts/unified-health-data.openapi.yaml` 1.0. | After contract |
| M3-SC-CON-002 | M3-REQ-09, 10 | Contract | P0 | Every error/authorization/partial-result response validates against the same contract. | After contract |
| M3-SC-CON-003 | M3-REQ-10 | Contract | P0 | Frontend mock fixtures validate against the exact contract version/checksum used by backend tests. | After contract |
| M3-SC-CON-004 | M3-REQ-09 | Contract | P0 | Contract enumerates only approved source values (`MEDICARE`, `EPIC`, `CERNER`, `ATHENA`) and requires `sourceRecordId`, UTC dates, and the common error fields. | After contract |

## D. WireMock integration

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-INT-001 | M3-REQ-03, 09 | Integration | P0 | `@SpringBootTest` retrieves a one-page synthetic AllergyIntolerance Bundle from WireMock through real app wiring and returns the approved API response. | After endpoint + contract |
| M3-SC-INT-002 | M3-REQ-04 | Integration | P0 | Cerner 401 invalid/expired token traverses HTTP client, auth service, and API error translation correctly. | After endpoint + contract |
| M3-SC-INT-003 | M3-REQ-05 | Integration | P0 | Sequential stub: retrieval 401, refresh success, retrieval 200; exactly one refresh and two retrieval calls occur. | After refresh policy |
| M3-SC-INT-004 | M3-REQ-05 | Integration | P0 | Sequential stub: retrieval 401 and refresh failure; no second refresh or unbounded retrieval occurs. | After refresh policy |
| M3-SC-INT-005 | M3-REQ-06 | Integration | P0 | Malformed JSON, wrong resource type, missing required linkage, and mixed Bundle entries produce approved isolation/error behavior. | After policy |
| M3-SC-INT-006 | M3-REQ-07 | Integration | P1 | Delayed response exceeds configured timeout and returns the approved retryable outcome within a bounded test duration. | After endpoint + policy |
| M3-SC-INT-007 | M3-REQ-07 | Integration | P1 | 429 with `Retry-After` and eventual success/failure follows configured call count and response behavior. | After policy |
| M3-SC-INT-008 | M3-REQ-08 | Integration | P0 | Two-page Bundle follows next link and returns complete de-duplicated results. | After endpoint |
| M3-SC-INT-009 | M3-REQ-08 | Integration | P0 | First page succeeds and second page fails; response matches approved partial-result contract. | After contract |
| M3-SC-INT-010 | M3-REQ-09, 10 | Integration/contract | P0 | Captured integration responses validate against OpenAPI 1.0. | After contract |

## E. End-to-end, regression, and live smoke

| ID | Requirement | Level | Pri. | Scenario and expected result | Automation |
|---|---|---:|---:|---|---|
| M3-SC-E2E-001 | M3-REQ-03, 11 | E2E | P0 | Authorized user opens health data and sees synthetic Cerner allergy records with source attribution; no write action is offered or sent. | After UI/API integration |
| M3-SC-E2E-002 | M3-REQ-04, 11 | E2E | Reauthorization-required state is distinguishable from CareConnect access denial and offers only the approved recovery action. | After contract/UI |
| M3-SC-E2E-003 | M3-REQ-08, 11 | E2E | Partial-source state displays successful records plus an accessible, non-misleading status indication. | After contract/UI |
| M3-SC-REG-001 | M3-REQ-13 | Unit/widget/API regression | P1 | Existing non-EHR health and allergy workflows continue to pass after unified data integration. | With implementation |
| M3-SC-SMK-001 | M3-REQ-14 | Live smoke | P0 | Valid SMART authorization with S256 PKCE and synthetic patient context retrieves an AllergyIntolerance searchset Bundle (or approved scoped resource) with HTTP 200. | Manual weekly/pre-sign-off |
| M3-SC-SMK-002 | M3-REQ-04, 14 | Live smoke | P0 | Expired token returns HTTP 401 `invalid_token`; no sensitive token is retained in evidence. Refresh is checked only if the approved sandbox workflow supports it. | Manual weekly/pre-sign-off |
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
