# Milestone 3 — Software Test Plan Input: Team E (Echo) Test Requirements

**Prepared by:** Quinton Coleman (Requirements Traceability Owner) · **Date:** 2026-09-28 · **Status:** Draft for team review · **Updated 2026-10-03:** STP-M3-E-14 now states the agreed unlink rule; added STP-M3-E-31 (connect flow). Both close gaps found by WBS 6.4.31 (Blue Button requirements-to-screen traceability)

**Purpose.** Kris relayed a request (9/27) for Team E's M3 test requirements for the Software Test
Plan. This lists, for each Team E M3 feature, what must be tested, at which level, by which
verification package, and what counts as a pass. Acceptance criteria are quoted from the
*WBS & Assignments* sheet of `Team_Echo_Integrated_Work_Plan_and_EVM.xlsx`; package owners are from
the *Level 3 Assignment Register*. Please correct anything that has changed.

**Test levels:** U = unit, C = contract, I = integration (real database/API), E2E = end-to-end through
the UI, A = accessibility review, P = performance/reliability, S = security/negative test.

## 1. Requirements by feature

### 6.2.35 FHIR Retrieval Orchestration (build: 3.1.1 Max)
*Criteria: "Production-quality retrieval orchestration handles pagination, partial failure and backoff."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-01 | Retrieval follows every `next` link until the bundle ends, across at least 3 pages | I | All pages retrieved, no duplicates, count matches the sandbox fixture |
| STP-M3-E-02 | A failed page does not lose the pages already retrieved; the failure is reported | I | Partial result stored, error surfaced, retry scheduled |
| STP-M3-E-03 | HTTP 429/5xx responses back off before retrying and stop after the configured limit | U/I | Observed delays grow; no more than the limit of attempts |

### 6.2.36 Visit & Financial Normalization (build: 3.1.2 Kris)
*Criteria: "Visit and financial resources normalize to the shared contract with test coverage."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-04 | Each visit/claim fixture maps to the shared canonical contract field by field | U/C | Every mapped field equals the expected value; unmapped fields listed, not dropped silently |
| STP-M3-E-05 | Missing or malformed source fields do not crash normalization | U | Record flagged or skipped with a logged reason |

### 6.2.37 Persistence & Tenant Isolation (build: 3.1.3 Abel)
*Criteria: "Medicare data persists with tenant isolation proven by negative tests."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-06 | Records written for org A cannot be read, updated or deleted through org B's session | S/I | Every cross-tenant attempt returns 403/404 and changes nothing |
| STP-M3-E-07 | Every Medicare row stores `org_id` and every query filters on it | I | Schema check plus query review; no unscoped query |

### 6.2.38 Sync, Retry & Idempotency (build: 3.1.4 Shayne · verify: **3.6.4 Quinton**)
*Criteria: "Repeated syncs are idempotent and transient failures retry safely."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-08 | Running the same sync twice produces identical stored data | I/P | Row counts and checksums equal after run 1 and run 2 |
| STP-M3-E-09 | A sync interrupted mid-way and restarted completes without duplicates | P | No duplicate rows; final state equals an uninterrupted run |
| STP-M3-E-10 | Transient failures (timeouts, 5xx) retry; permanent ones (4xx) do not | U/P | Retry count per failure type matches the policy |
| STP-M3-E-11 | Sync time and error rate for a representative patient are recorded as a baseline | P | Baseline recorded in the test report for regression comparison |

### 6.2.39 Consent Refresh, Revoke & Disconnect (build: 3.1.5 Rich)
*Criteria: "A user can refresh, revoke and disconnect Medicare access, with data handling defined for each."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-12 | Refresh renews the token without re-consent while consent is valid | I | New token stored, no user prompt |
| STP-M3-E-13 | Revoke stops all further retrieval immediately | I/S | Next sync makes no Blue Button call |
| STP-M3-E-14 | Disconnect (unlink) applies the agreed data rule (Rich, 10/3; SRS v1.4 Addendum A, A1-Q1). Deleted before the confirmation: the Medicare token and connection, the Medicare crosswalk row, Medicare rows in the raw payload, source identity, coverage and visit tables, and identity conflicts that came from Medicare. Kept: the CareConnect account and all non-Medicare data, demographic values reconciliation already applied to the patient record, and the retrieval audit log (7-year / age-25 rule). A patient who stays linked follows the #214 retention rule | I | After unlink, each deleted table has no Medicare rows for the patient, the kept data is unchanged, and the confirmation appears only after the deletes commit. Until the 6.2.39 disconnect endpoint exists, everything stays under #214 (TD-030) |

### 6.2.40 Accessible Medicare Data Views (build: 3.1.6 Crystal · verify: 3.6.3 Rich, **3.6.1 Quinton**)
*Criteria: "Medicare data views are implemented and pass an accessibility review."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-15 | Views meet WCAG 2.2 AA: screen-reader labels, 4.5:1 contrast, 200% text, no colour-only meaning | A | Review checklist passes with TalkBack/VoiceOver evidence |
| STP-M3-E-16 | A patient can sign in, open their Medicare data and read a claim/visit end to end | E2E | Flow completes on Android and web |
| STP-M3-E-31 | A patient can connect Medicare end to end: Connect Medicare Account → sandbox consent → callback → Linked confirmation. Cancelling at Medicare or a token-exchange error leaves the account Unlinked with no stored token (FR-MCR-01, 02, 04, 05, 08) | E2E/I | Linked state and confirmation shown on success; on cancel and on error no token is stored and the account stays Unlinked |

### 6.2.41 Cross-Source Reconciliation & Deduplication (build: 3.2.1 Max, 3.2.2 Kris, 3.2.3 Camilla · verify: **3.2.4 Quinton**)
*Criteria: "Duplicate records across sources are reconciled per the agreed rules with test evidence."*

| ID | Test requirement | Level | Pass criterion | Status |
|---|---|---|---|---|
| STP-M3-E-17 | Identity fields: newest source wins, ties keep the existing value, DOB waits for patient confirmation | U/C | Contract suite + TC-EHR-REC-001..012 pass | **Passed 10/2 (33/33: contract 18/18 incl. TC-EHR-REC-032/033, verification 15/15)** — see `3.2.4-reconciliation-verification.md` |
| STP-M3-E-18 | Two adapters racing on one field converge on the newest value against the real database | C/I | Contract suite passes against PostgreSQL; fails with the row lock stubbed out | Runs locally only: `JpaContractPostgresTest` (#209) is opt-in via `EHR_IT_JDBC_URI` and CI skips it; not yet run on this branch, so no result recorded |
| STP-M3-E-19 | Duplicate visit/claim records across sources are detected and merged per the agreed rules | U/I | Merged record matches the rule; audit trail kept | Blocked on 3.2.2 |
| STP-M3-E-20 | Medication conflicts are flagged for caregiver review and never auto-resolved (FR-EHR-07) | U/E2E | Conflict appears for review; medication list unchanged until a caregiver acts | Blocked on 3.2.2/3.2.3 |
| STP-M3-E-21 | The user review workflow lets the user accept or reject each flagged conflict | E2E | Each choice is applied and audited | Blocked on 3.2.3 |

### 6.2.42 Medication Photo Capture (build: 3.4.1–3.4.4 Camilla/Max/Crystal · verify: 3.4.5 Crystal, **3.6.1 Quinton**)
*Criteria: "Medication photo capture works end to end and stores images securely."* Detailed requirements
and test cases are in *Team_Echo_Handoff_1.10_Requirements_and_Test_Cases.docx* (14 requirements, 17 tests).

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-22 | Capture → label extraction → review/correct → confirm creates a medication with the right type | E2E | Saved medication matches the confirmed values; types use backend names (KI-05, OTC fix) |
| STP-M3-E-23 | Unreadable images give an accessible error and a manual-entry path | A/E2E | Error announced by screen reader; manual path completes |
| STP-M3-E-24 | Images are stored encrypted, visible only to the owner, and disposed of per policy | S | Unauthorised read fails; disposal job removes images on schedule |

### 6.2.43 Secure Sharing Controls (build: 3.3.1–3.3.3 Rich/Camilla · verify: 3.3.4 Kris, **3.6.1 Quinton**)
*Criteria: "Sharing controls enforce least privilege and are covered by negative tests."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-25 | A caregiver sees only the records the patient selected | S/I | Unselected records return 403 |
| STP-M3-E-26 | Revoking a share removes access immediately and is audited | S/I | Next request fails; audit row written |
| STP-M3-E-27 | Patient shares data with a caregiver and the caregiver reads it in-app | E2E | Flow completes end to end |

### 6.2.44 Operational Readiness: Logging, Monitoring, Runbook (build: 3.5.4 Shayne · verify: **3.6.4 Quinton**)
*Criteria: "Logging, monitoring and a runbook exist so the system can be operated by someone who did not build it."*

| ID | Test requirement | Level | Pass criterion |
|---|---|---|---|
| STP-M3-E-28 | Health check reports unhealthy when the database or Blue Button is unreachable | P | Status flips within the configured interval and recovers |
| STP-M3-E-29 | Logs contain no PHI and carry a correlation ID per request | S | Log scan finds no PHI patterns; IDs present |
| STP-M3-E-30 | Someone who did not build the system can follow the runbook to restart and diagnose | P | Dry run by a teammate succeeds; gaps logged |

## 2. End-to-end suite (3.6.1, Quinton)

Built from STP-M3-E-16, 22, 27, 31 (connect flow) and the reconciliation review flow (21) once their features land. Order
of work follows predecessor completion: 3.1.6 → 3.2.3 → 3.3.3 → 3.4.3.

## 3. Entry and exit criteria (proposed)

- **Entry:** the feature is merged to `team-e-develop` and its unit tests pass in CI.
- **Exit:** every STP-M3-E requirement for the feature has a linked test and a recorded result; any
  failure has an issue with an owner; open questions (e.g. reconciliation Q1–Q3) have a decision.

## 4. Traceability

Each STP-M3-E ID should be added to the M3 RTM against its SRS requirement ID (REQ-nnnn) once the
Requirements Owner assigns them, and to the test report with its result.
