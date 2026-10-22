# Milestone 4 Team C Traceability Matrix

**Owner:** Team C QA Lead (Tiffany Obi)  
**Status:** Working matrix; update at each evidence review and release-candidate run  
**Result vocabulary:** Not Run, Pass, Fail, Blocked, or Not Applicable

Contract-dependent rows remain provisional until the unified health-data OpenAPI contract is approved. M3 requirement identifiers and evidence remain in [m3-traceability-matrix.md](m3-traceability-matrix.md); this matrix records the M4 completion view.

| Requirement ID | Description | Test/scenario identifiers | Level | Expected result | Latest result | Evidence |
|---|---|---|---|---|---|---|
| M4-REQ-01 | Carry unresolved M3 requirements into M4 without weakening safety boundaries. | All open `M3-REQ-*`; M4-SC-SIGN-001 | All | Every open M3 row has an M4 owner, scenario and final disposition; synthetic-only, retrieval-only and no-write-back remain enforced. | In Progress | [M3 matrix](m3-traceability-matrix.md), [M4 plan](m4-test-plan.md) |
| M4-REQ-02 | Complete approved read-only Patient, Condition, AllergyIntolerance, Encounter and provisional Appointment workflows. | M4-SC-CER-PAT-001-003; CON-001-003; ALG-001-003; ENC-001-003; APT-001-004; E2E-001; SMOKE-001 | Unit through smoke | All five resources pass approved mapping, retrieval, provenance, authorization and user-workflow checks. | Partly Met | [Scenario catalog](m4-scenario-catalog.md); focused Cerner tests on `0deee2ab`; final contract/E2E/smoke pending |
| M4-REQ-03 | Verify deterministic Cerner authorization and failure handling. | M4-SC-CER-*-003; AUTH-001-002; PARTIAL-001 | Unit/integration/E2E | Denial, expiry, refresh failure, timeout, malformed data, 429, upstream failure, pagination and partial results follow bounded approved behavior. | Partly Met | Focused HTTP/service/WireMock baseline; remaining Spring and partial-result cases Not Run |
| M4-REQ-04 | Validate backend and frontend against one OpenAPI contract. | M4-SC-CTL-001; CONTRACT-001; PARTIAL-001 | Slice/contract/integration | Every success, error and partial response plus frontend fixture validates against one version/checksum. | Blocked | `contracts/unified-health-data.openapi.yaml` not found at plan baseline |
| M4-REQ-05 | Localize complete Social Feed workflow. | M4-SC-L10N-001-008, Social Feed checklist rows | Static/unit/widget/manual | Complete workflow text, layout, semantics and supported-locale behavior pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-06 | Localize complete Gamification workflow. | M4-SC-L10N-001-008, Gamification checklist rows | Static/unit/widget/manual | Complete workflow text, parameters/plurals, layout, semantics and supported-locale behavior pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-07 | Localize complete USPS Mail Digest workflow. | M4-SC-L10N-001-008, USPS checklist rows | Static/unit/widget/manual | Connection, digest, detail, date/count, error and accessibility text pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-08 | Localize complete Caregiver Shift Scheduling workflow. | M4-SC-L10N-001-008, Shift Scheduling checklist rows | Static/unit/widget/manual | Calendar, recurrence, validation, conflicts, date/time, RTL and semantics pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-09 | Localize complete HHAExchange submission workflow. | M4-SC-L10N-001-008, HHAExchange checklist rows | Static/unit/widget/manual | Eligibility, selection, warnings, progress, success/failure and accessibility text pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-10 | Enforce ARB validity, parity and clean generation. | M4-SC-L10N-001 | Static/generation | All approved catalogs parse, have approved key/placeholder parity and generate successfully from a clean checkout. | Not Run | Parity report and CI link TBD |
| M4-REQ-11 | Verify locale selection, fallback, formatting, layout and absence of raw keys/literals. | M4-SC-L10N-002-005 | Unit/widget/manual | Supported and unsupported locale behavior, plural/formatting and representative layouts pass. | Not Run | [Localization checklist](m4-localization-qa-checklist.md) |
| M4-REQ-12 | Verify representative RTL patient and caregiver workflows. | M4-SC-L10N-006 | Widget/manual accessibility | Direction, reading/focus order, icons, semantics and layout pass in an approved RTL locale. | Not Run | RTL screenshots/checklist TBD |
| M4-REQ-13 | Record qualified review for sensitive translations. | M4-SC-L10N-007 | Human review | Reviewer, locale, scope, date, disposition and evidence are recorded; unresolved review blocks completion. | Not Run | Translation review record TBD |
| M4-REQ-14 | Preserve Cerner, localization and shared health-data behavior. | M4-SC-L10N-008; REL-001 | Unit/widget/API/regression | All affected suites pass on the release candidate with no unexplained regression. | Not Run for release candidate | Focused Cerner suite passed on `0deee2ab`; full candidate run TBD |
| M4-REQ-15 | Produce complete sign-off evidence. | M4-SC-REL-001-003; SIGN-001; SMOKE-001 | All | Traceability, coverage, CI, contract, E2E, smoke, localization, accessibility and defects support a defensible disposition. | Not Run | [M4 summary](m4-test-summary.md) |
| M4-REQ-16 | Demonstrate agreed M4 journeys in a stable rehearsed environment. | M4-SC-DEMO-001 | Rehearsal/manual | Demo order, presenters, timing, synthetic data, fallback and handoffs pass rehearsal. | Not Run | Demo rehearsal record TBD |

## Evidence register

| Evidence item | Required value | Candidate/link | Verified by/date |
|---|---|---|---|
| Release-candidate commit | Immutable SHA | TBD | TBD |
| Approved OpenAPI | Path, version and checksum | TBD | TBD |
| Mapping coverage | At least 80% line and 70% branch | TBD | TBD |
| Cerner integration coverage | At least 70% line | TBD | TBD |
| Consecutive CI | Three passing candidate runs | 1. TBD; 2. TBD; 3. TBD | TBD |
| Contract validation | Every implemented endpoint and frontend fixture | TBD | TBD |
| Critical scenarios | 100% passing | TBD | TBD |
| Critical/High defects | Zero open | TBD | TBD |
| Live sandbox smoke | Passing within final sign-off window | TBD | TBD |
| Localization parity/generation | Approved parity and clean generation | TBD | TBD |
| RTL/accessibility | Representative patient and caregiver evidence | TBD | TBD |
| Sensitive translation review | Qualified review or recorded blocker | TBD | TBD |
| Demo rehearsal | Passing result and fallback | TBD | TBD |
| Final QA disposition | Pass / Conditional Pass / Fail | TBD | Tiffany Obi / TBD |

## Update rules

1. Link exact test methods or report identifiers rather than general folders when evidence exists.
2. Record the tested commit and date with every result.
3. Do not label candidate expected outputs or provisional API shapes as approved.
4. A manual result requires tester, environment, steps and sanitized evidence.
5. A failed test remains failed until a linked retest passes; do not overwrite defect history.
