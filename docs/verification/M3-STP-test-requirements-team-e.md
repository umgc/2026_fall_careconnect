# Milestone 3 — Software Test Plan Input: Team E (Echo) Test Requirements

**Prepared by:** Quinton Coleman (Requirements Traceability Owner) · **Date:** 2026-09-28 · **Status:** Draft for team review
**Revised by:** Kristopher Bickmore (Testing Lead) · **Dates:** 2026-09-30 and 2026-10-03 · read against the *WBS & Assignments*
sheet of the Team Echo work plan (file dated 2026-09-30), the Software Test Plan (Team Echo sections) revision 0.22 and
SRS 1.4 Integrated. §9 lists what changed.

**Purpose.** This document lists what has to be tested for each Team E Milestone 3 work package, at which level, and
what counts as a pass. It is input to the Software Test Plan and is not the plan itself. Package names, owners and
acceptance criteria are quoted from the *WBS & Assignments* sheet.

**How rows are identified.** This document uses the identifiers Team Echo already works with and introduces none:

- A test requirement is identified by what it traces to. That is the SRS 1.4 requirement (FR-MCR-nn, NFR-xx-nn, BR-nn)
  where one exists, and otherwise the WBS package, written as "WBS 6.2.nn, no SRS requirement".
- A test case is identified by its permanent Test Plan identifier. SRS-issued cases (TC-20.n, TC-21.n, TC-22.n, TC-24.n)
  are referenced, never reissued. Repository cases use TC-<SUBSYSTEM>-nnn. The status shown is the case's planning
  status in revision 0.22: Ready, Planned, Blocked or Deferred.
- "None" means no case has been designed yet. The Testing Lead reserves an identifier in the Test Plan when the case is
  designed. Nobody coins one here, and no requirement ID is coined to close a trace gap.
- Results (Pass / Fail / Blocked / Not Executed) are recorded only in the Test Report, with a named executor, date,
  environment and evidence.

**Test levels:** U = unit, C = contract, I = integration (real database/API), W = widget, E2E = end-to-end through
the UI, A = accessibility review, P = performance/reliability, S = security/negative test.

## 1. Retrieval, mapping and storage

### 6.2.35 Blue Button Retrieval Orchestration (owner Max · supporting Kris)
*Criteria: "Every approved Blue Button resource type is retrieved with pagination, rate-limit handling, retry, backoff and
observable partial-failure behavior."*

TC-MCR-FHIR-001…015 came with PR #208 (merged). 016…034 are on PR #223, which is still open.

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-13, FR-MCR-14 (component level) | Retrieval follows every `next` link to the end, across at least 3 pages, for each approved resource type | I | All pages retrieved, no duplicates, count matches the fixture; a page that omits `Bundle.total` still yields its entries | TC-MCR-FHIR-001…005 Ready (§3.12, stand-in server). 010–012 Ready (DEF-MCR-03). 033 Ready: an OperationOutcome entry on a later page is skipped. Screen level: TC-21.1, TC-21.2 Blocked (§3.8.4). |
| FR-MCR-15 | The approved resource type set is retrieved in full | I | Every resource type on the approved list is requested and returned | None. The approved set is unconfirmed (OQ-06), and FR-MCR-15 has no acceptance criterion. |
| WBS 6.2.35, no SRS requirement | A failed page does not lose the pages already retrieved, and the failure is observable | I | Pages retrieved before the failure are kept and the failure is surfaced to the caller | TC-MCR-FHIR-008, 014 Ready (DEF-MCR-01). 016, 022, 024 and 028…030 Ready. |
| FR-MCR-23, FR-MCR-24; NFR-DEG-02 | A rate-limit or unavailable response is retried with backoff and gives up after the permitted attempts | U/I | Up to [PROPOSED: 3] attempts with [PROPOSED: exponential backoff starting at 2 s]; then stored records are shown with ERR-MCR-03 | TC-MCR-FHIR-009, 017, 021, 023 Ready (DEF-MCR-02). Retry-After: 018, 019, 025, 026 Ready, question D18. 034 Planned (DEF-MCR-06: a dropped connection is sent up to twelve times). Screen level: TC-21.9, TC-21.10 Blocked. |
| FR-MCR-09 | A token Medicare rejects is not retried | I/S | One attempt, surfaced as an authentication failure, on the first page or a later one | TC-MCR-FHIR-013, 027, 031 Ready (DEF-MCR-05). Screen level: TC-20.13, TC-20.14 Blocked. |
| WBS 6.2.35, no SRS requirement | Retrieval works against the real CMS sandbox, not only the stand-in | I | Same results as the stand-in cases | None. Sandbox access is OQ-03; the client registration and API version are question D19. |

### 6.2.36 Blue Button Resource Mapping & Normalization (owner Camilla · supporting Max)
*Criteria: "The mapping matrix covers every approved Blue Button resource and field, its normalized destination,
provenance, display rule and associated test identifier; representative mappings are implemented and reviewed."*

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-13, FR-MCR-14 | Each mapped field lands in its normalized destination as the matrix states | U/C | Every mapped field equals the expected value; an unmapped field is listed, not dropped silently | None. The criterion puts a test identifier on every matrix row. The Testing Lead issues those identifiers in the Test Plan once the matrix exists. |
| WBS 6.2.36, no SRS requirement | Each normalized value records its provenance (source and retrieval time) | U/C | Provenance is present and correct for every mapped field | None. |
| WBS 6.2.36, no SRS requirement | Missing or malformed source fields do not crash normalization | U | The record is flagged or skipped with a logged reason, and the log carries no PHI | None. |

### 6.2.37 Persistence, Tenant Isolation & Secure Sharing (owner Max · supporting Rich)
*Criteria: "Normalized Medicare data persists with tenant isolation and least-privilege sharing controls demonstrated
through negative tests."*

**Conflict with SRS 1.4.** SRS §1.2 puts "caregiver delegation and sharing controls beyond … FR-MCR-16–FR-MCR-18" out of
scope for this increment, and it numbers no sharing requirement. The work plan schedules sharing in this package. The
Requirements Owner has to settle this; until then the sharing rows trace only to the WBS (Test Plan question D14).

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-19 | Retrieved records survive an app restart | I | Records present after restart | TC-21.3 Blocked (§3.8.4). |
| FR-MCR-16, FR-MCR-17; NFR-SEC-05 | Another patient or an unassigned caregiver cannot read a patient's Medicare data. Each request goes to the API directly, bypassing the UI | S/I | Every request returns the baselined reject status (SRS 1.4 has "[PROPOSED: 404]", not yet baselined) and no record fields | TC-24.1…24.3 Blocked (§3.8.5). Component level, PR #238 (open), §3.15: TC-MCR-AUTHZ-001…013 Ready; 014…016 Planned (HTTP; DEF-MCR-07: a refusal returns 500, not 404); 017…026 Planned (persistence). 007 and 008 are characterization cases until OQ-11 is answered. |
| FR-MCR-18, FR-EHR-10 | Every stored and returned record is scoped to the requesting user's organization | S/I | A user in organization 1 receives zero records scoped to organization 2; no query is unscoped | TC-24.4 Blocked. **Also blocked on Test Plan question D8:** the SRS requires an organization identifier, but ece73995 removed `orgId` and PR #209's `ehr_` tables have none. |
| WBS 6.2.37, no SRS requirement | A caregiver can read only the records the patient selected. The request goes to the API directly | S/I | An unselected record returns the reject status and no fields. The reject status (403 vs 404) is undecided; FR-MCR-17 proposes 404 so that a record's existence is not disclosed | None at API level. TC-MCR-AUTHZ covers access to a patient's data as a whole, not to selected records. |
| WBS 6.2.37, no SRS requirement | Revoking a share removes access at once and is audited | S/I | The next request fails and an audit row is written | TC-MCR-AUTHZ-019 Planned covers a revoked MEDICARE_VIEW grant at persistence level. No case checks the audit row. |
| WBS 6.2.37, no SRS requirement | A patient shares selected records with a caregiver, who sees only those; after the revoke, none | E2E | Flow completes end to end | TC-E2E-004 Blocked (§3.13). |

### 6.2.38 Sync, Retry & Idempotency (owner Max · supporting Kris)
*Criteria: "Repeated synchronizations are idempotent; transient failures retry safely; duplicate writes and unrecoverable
failures are observable."*

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| WBS 6.2.38, no SRS requirement | Running the same sync twice produces identical stored data | I | Row counts and checksums are equal after run 1 and run 2 | None. The sync code does not exist yet (§3.12.5). |
| WBS 6.2.38, no SRS requirement | A sync interrupted mid-way and restarted completes without duplicates | I/P | No duplicate rows; the final state equals an uninterrupted run | None. |
| FR-MCR-23, FR-MCR-09; NFR-DEG-02 | Retry follows the policy for each response type: a rate limit or unavailable response retries, and a rejected token (401) or other permanent 4xx does not | U/I | Retry count per response type matches the policy. The SRS sets the policy for rate limiting (FR-MCR-23) and an unavailable API (NFR-DEG-02); PR #223 also retries every 5xx (question D18) | Component level only: TC-MCR-FHIR-009, 017, 020, 023 Ready; 013, 027 Ready. |
| WBS 6.2.38, no SRS requirement | A duplicate write and an unrecoverable failure are both observable | I | Each produces a log entry or metric that names it, with no PHI | None. |

### 6.2.39 Consent Lifecycle: Refresh, Revoke & Disconnect (owner Max · supporting Rich)
*Criteria: "A user can refresh authorization, revoke access and disconnect Medicare; each action has defined token and
retained-data behavior and passes security review."*

**What unlink deletes is not settled.** SRS 1.4 FR-MCR-11 says unlink deletes the stored access token and *all* stored
Medicare data before the confirmation, and its data dictionary and retention table mark every Medicare row "Deleted on
unlink". SRS v1.4 Addendum A, A1-Q1 (Rich, 2026-10-03; draft under review, issue #239) proposes this instead:

- **Deleted before the confirmation:** the Medicare token and connection; the Medicare crosswalk row; Medicare rows in
  the raw payload, source identity, coverage and visit tables; identity conflicts that came from Medicare.
- **Kept:** the CareConnect account and all non-Medicare data; demographic values reconciliation already applied to
  the patient record; the retrieval audit log, under the 7-year / age-25 rule. A patient who stays linked follows the
  same retention rule (#214).

Until the addendum is baselined, the SRS cases keep the SRS expected result, and the difference is Test Plan question
D21. Two points need an answer before a pass criterion can be written against the addendum. First, it does not say what
happens to `ehr_identity_field_provenance` rows whose winning source was Medicare. Second, the coverage and visit tables
(`ehr_coverage_record`, `ehr_visit_record`) exist only on `feature/e-ehr-api-and-canonical-schema`, with no migration,
and the token is held on the crosswalk row there. No unlink endpoint exists yet (6.2.39, TD-030).

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-03, FR-MCR-12 | Refresh renews authorization without re-consent while it is valid, and not past the maximum token lifetime | I | A new token is stored with no user prompt; after the maximum lifetime the patient must re-authenticate | None. The maximum lifetime is unconfirmed (OQ-05), and FR-MCR-12 has no acceptance criterion. |
| FR-MCR-09 | A revoked or rejected token stops all further retrieval | I/S | Link state reads Unlinked, ERR-MCR-05 offers re-link, and no further Blue Button call is made | TC-20.13, TC-20.14 Blocked (§3.8.3). Component level: TC-MCR-FHIR-013, 027, 031 Ready. |
| FR-MCR-10, FR-MCR-11 | Unlink deletes the stored token and the stored Medicare data before confirming | I | Per SRS 1.4: no token record and no Medicare record exist when the unlink confirms, and reopening shows the unlinked state. If Addendum A1-Q1 is baselined (D21): each table on its delete list has no Medicare row for the patient, each item on its keep list is unchanged, and the confirmation appears only after the deletes commit | TC-20.15…20.17 Blocked (§3.8.3): no unlink endpoint exists. |
| BR-04; NFR-SEC-02 | A token is never returned to a client or written to a log, and it is encrypted at rest | S | Response and log scans find no token; the stored value is not plaintext | None. No custody mechanism has been selected (§3.8.6). |

## 2. Screens and accessibility

### 6.2.40 Medicare UI Screen Suite (owner Camilla · supporting Rich)
*Criteria: "Connect and consent, connection status, Medicare overview, resource-detail, reconciliation review, and
revoke/disconnect screens are implemented against the shared contract and pass code review."*

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-01…06 | Connect and consent: the flow goes to Medicare-hosted authentication, never asks for the Medicare password, and handles denial and cancel | W/I | As SRS 1.4 Table 27 states | TC-20.1…20.8 Blocked (§3.8.3). |
| FR-MCR-07, FR-MCR-08 | A timeout at Medicare's authentication endpoint, or an error from the token exchange, ends linking | I (fault injection) | ERR-MCR-01 or ERR-MCR-02 is shown, the account stays Unlinked and no token is stored | TC-20.9…20.12 Blocked. |
| FR-MCR-01…05 | A patient connects Medicare end to end: Connect Medicare Account, sandbox consent, callback, confirmation | E2E | "Medicare account connected" is shown and the link state stays Linked across sign-out and sign-in; a denial at Medicare leaves the account Unlinked with no stored token. The error paths stay with TC-20.9…20.12, because a live sandbox cannot force them | TC-E2E-010 Blocked (§3.13): waits on 6.2.26 and 6.2.40. |
| FR-MCR-04 | Connection status shows the link state and confirms a successful link | W | Confirmation shown when Linked | TC-20.5 Blocked. |
| FR-MCR-13, FR-MCR-14, FR-MCR-21 | Overview and resource detail show visits and claims with provider, date and amount, and when they were retrieved | W/I | As SRS 1.4 Table 32 states | TC-21.1, TC-21.2, TC-21.6 Blocked (§3.8.4). |
| FR-MCR-10, FR-MCR-11 | Revoke/disconnect screen unlinks and shows no Medicare data afterwards | W | Unlinked state with no previously retrieved Medicare data (what is retained depends on D21; see 6.2.39) | TC-20.15…20.17 Blocked. |
| FR-MCR-13, FR-MCR-14 | A patient signs in, opens their Medicare data and reads one claim, on Android and web | E2E | Flow completes end to end | TC-E2E-001 Blocked (§3.13). |

The reconciliation review screen is covered under 6.2.41 and its states under 6.2.43.

### 6.2.42 Medicare Navigation & Static Screen Shell (owner Crystal · supporting Camilla)
*Criteria: "The Medicare navigation entry, routes, screen containers, headings and mock-data placeholders compile and
follow the approved component conventions; no OAuth, API, persistence or mapping logic is included."*

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| WBS 6.2.42, no SRS requirement | The navigation entry and each route open their screen container | W | Every route renders its container and heading | None. |
| WBS 6.2.42, no SRS requirement | The shell makes no network, OAuth or persistence call | W | No HTTP client or repository is invoked while navigating the shell | None. |
| NFR-ACC-01 | Headings and the navigation entry have an accessible name and role | W/A | Semantics expose each heading as a heading and the entry as a button or link | None. |

### 6.2.43 UI States & WCAG 2.1 AA Baseline (owner Camilla · supporting Rich)
*Criteria: "Loading, no-data, partial-data, API-error, expired-authorization, reauthorization and disconnected states are
implemented; each new screen has criterion-specific WCAG 2.1 A/AA evidence or a linked defect."*

Every shipped screen needs its loading, empty, error and offline states covered, and a backend failure that leaves a
blank screen is a defect. This package's list has no offline state, so the offline row is added from the SRS.

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| FR-MCR-25, FR-MCR-27 | Loading state | W | Visible for the whole wait, on linking and on first retrieval | TC-20.18, TC-21.12 Blocked. |
| FR-MCR-28 | No-data state | W | Explicit empty state when a linked account has no records | TC-21.13 Blocked. |
| WBS 6.2.43, no SRS requirement | Partial-data state | W | TBD: no requirement says what a partial result shows | None. The expected result is undefined. |
| FR-MCR-20, FR-MCR-24; NFR-ACC-04 | API-error state, never blank | W | Stored records show with ERR-MCR-03, or ERR-MCR-03 alone when nothing is stored; the error text names what failed and what to do | TC-21.4, TC-21.5, TC-21.10, TC-21.11 Blocked. |
| FR-MCR-09 | Expired-authorization and reauthorization states | W/I | ERR-MCR-05 with a re-link control; no call is made with the rejected token | TC-20.13, TC-20.14 Blocked. |
| FR-MCR-10, FR-MCR-11 | Disconnected state | W | Unlinked with no previously retrieved Medicare data (retention depends on D21) | TC-20.17 Blocked. |
| FR-MCR-26, FR-MCR-29 | Offline state | W | ERR-MCR-04 and no redirect when linking; stored records with an offline indicator when viewing | TC-20.19, TC-21.14 Blocked. |
| NFR-ACC-01, 02, 04…09 | Each new screen meets WCAG 2.1 A/AA: name, role and state; focus on return from Medicare; error identification; 4.5:1 contrast; 200% text; keyboard operable; no meaning by colour alone | A | Criterion-specific evidence per screen from a TalkBack and a VoiceOver walkthrough. Each record names the build, screen, tester, device or browser, tool or assistive-technology version, result and defect ID | None: the screens do not exist (§3.8.6). |

## 3. Reconciliation

### 6.2.41 User-Assisted Reconciliation (owner Camilla · supporting Max)
*Criteria: "Potential duplicate or conflicting records are detected, presented with source and provenance context, and can
be confirmed, separated or deferred by the user without silent data loss."*

**Conflict with SRS 1.4.** Cross-source duplicate detection is FEAT-03 (FR-XSRC-01…09, cases TC-22.1…22.12), which SRS
1.4 Table 5 defers. The work plan schedules it here for Milestone 3. The Requirements Owner has to settle which one
governs (Test Plan question D15).

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| WBS 6.2.41; reconciliation README decisions of 2026-09-26, no SRS requirement | Identity fields: the newest source wins, a tie keeps the existing value, and a date of birth waits for patient confirmation; a snapshot with a missing patient, source, timestamp or field map is refused | U/C | The cases below pass | TC-EHR-REC-001…031 Ready (§3.10). 029 and 030 need an independent re-run for DEF-EHR-REC-01. 010–012 are characterization cases until question D9 is answered. |
| WBS 6.2.41, no SRS requirement | Two adapters racing on one field converge on the newest value against the real database | C/I | The contract suite passes against PostgreSQL and fails with the row lock removed | TC-EHR-REC-013…028 on PostgreSQL through JpaContractPostgresTest; TC-EHR-PROV-003, 004 Ready (§3.11). These are skipped in CI because no workflow sets `EHR_IT_JDBC_URI`. |
| FR-XSRC-01…08 (deferred); WBS 6.2.41 | Potential duplicate records across sources are detected and presented with source and provenance context | U/I/W | As SRS 1.4 Table 37 states | TC-22.1…22.12 Deferred (§3.8.7). |
| WBS 6.2.41, no SRS requirement | The user can confirm, separate or defer each flagged record without silent data loss | E2E | Each choice is applied and audited; a deferred item stays flagged | TC-E2E-002 Blocked. Its steps in `flows.dart` still say accept and reject, not confirm, separate and defer; see §8. |
| FR-EHR-07 (SRS 1.4 FEAT-14, Team B) | Medication conflicts go to caregiver review and are never overwritten silently | U/E2E | The conflict appears for review and the medication list is unchanged until a caregiver acts | None. Team B and Team E must agree whose tests cover FR-EHR-07. |

## 4. Integration and operations

### 6.2.44 M3 Integration, Observability & Runbook (owner Shayne · supporting Max, Kris)
*Criteria: "The M3 Blue Button vertical slice runs end to end in the test environment; failures are logged and monitorable;
a draft runbook enables another team member to operate the flow."*

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| WBS 6.2.44; FR-MCR-01…05, FR-MCR-13, FR-MCR-14 | The vertical slice (link, retrieve, store, display) runs end to end in the test environment | E2E | The journey completes against the deployed test environment | TC-E2E-010 (link) and TC-E2E-001 (retrieve and display) Blocked. Both take their backend from BACKEND_URL; no run against the test environment is planned yet. |
| NFR-AR-04 | The health check reports unhealthy when the database or Blue Button is unreachable, and recovers | P | Status flips within the configured interval and recovers | None. |
| BR-04; WBS 6.2.44 | Logs and error responses carry no PHI and no token, and each request has a correlation ID | S | A log scan finds no PHI patterns and no token; every request has an ID | None. Test Plan §11 already records that BluebuttonController logs the beneficiary's FHIR id and echoes the exception in its 502 body. |
| WBS 6.2.44, no SRS requirement | Someone who did not build the flow can operate it from the runbook | P | A dry run by a teammate succeeds, and gaps are logged | None. |

## 5. Other Milestone 3 test areas

These have Test Plan cases in Milestone 3 but no row in the *WBS & Assignments* sheet.

### KI-05 Medication type parity (PRs #153 and #207, both merged)
KI-05 comes from the handoff analysis. It was a prerequisite for medication photo capture (handoff item 1.10), and SRS 1.4
gives it no FEAT, FR or AC.

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| KI-05, no SRS requirement | The frontend MedicationType holds exactly the backend's five constant names | U/C | Names are identical on both sides | TC-MED-TYPE-001, 002, 007 Ready (§3.9). |
| KI-05 | Every type survives the wire both ways, and a legacy OTC reads as OVER_THE_COUNTER | U | Round trip unchanged; a full backend row parses intact | TC-MED-TYPE-003…006, 014…016 Ready. |
| KI-05 | The backend accepts every name the app sends and rejects OTC | U/C | Accepts the five names; rejects OTC | TC-MED-TYPE-011, 012, 013, 019 Ready. |
| KI-05; DEF-MED-01 | The add form posts the backend name, never OTC | W/I | Captured POST carries OVER_THE_COUNTER | TC-MED-TYPE-018 Ready. PR #207, the DEF-MED-01 fix, merged on 2026-09-30. |
| KI-05; DEF-MED-02 | The type dropdown offers all five types and fits at 320 logical px with text at 100% and 200% | W/A | All five selectable, no overflow | TC-MED-TYPE-008, 021 Ready. 021 needs an independent re-run after the DEF-MED-02 fix. |
| KI-05 | The remove control and the caregiver card treat each type correctly | W | As §3.9.3 states | TC-MED-TYPE-009, 010, 017, 020, 022 Ready. 009 and 010 are characterization cases until question D5 is answered. |
| KI-05 | A screen reader reads the type names intelligibly, and a live backend accepts a saved medication of each type | A/I | TalkBack and VoiceOver walkthrough; live POST succeeds | None (§3.9.5). |

### EHR canonical schema and reconciliation persistence (PR #209, merged)
PR #209 cites internal WBS 1.4.3. The workbook gives that number to 6.2.12, Data Mapping & Provenance Options, which is a
Milestone 1 package. SRS 1.4 numbers no canonical-schema requirement.

| Traces to | What must be shown | Level | Pass criterion | Test cases (Test Plan rev 0.22) |
|---|---|---|---|---|
| WBS 6.2.12 (internal 1.4.3), no SRS requirement | The seven `ehr_` tables, their constraints and seed sources are built on a fresh boot, a repeat boot and an upgrade, without data loss | I/manual | Every required patch applies; existing patients keep their data | TC-EHR-SCH-001, 009…011 Planned (§3.11). |
| WBS 6.2.12 | Constraints reject invalid rows | I | Each invalid insert fails | TC-EHR-CONF-001…005 Ready, 006 Planned; TC-EHR-SCH-002…005 Planned. |
| WBS 6.2.12 | The provenance store locks per field and creates provenance on first touch | I | As §3.11.3 states | TC-EHR-PROV-001…005 Ready. |
| WBS 6.2.12 | The patient field accessor maps fields and dates, and every patient has a baseline | I | As §3.11.3 states | TC-EHR-PACC-001…006 Ready, 007…010 Planned (DEF-EHR-REC-03, D9); TC-EHR-SCH-008 Planned (DEF-EHR-REC-02). |
| WBS 6.2.12 | Raw payloads are stored as jsonb and round-trip unchanged | I | As §3.11.3 states | TC-EHR-RAW-001…003 Ready. |
| WBS 6.2.12; regression | The Patient response change breaks no screen or authorization rule | API/W, manual | Only `createdAt`/`updatedAt` are added; screens render; another patient's record is still refused | TC-EHR-SCH-012…014, 016, 017 Planned; 015 Blocked. |
| FR-EHR-10 | EHR records are isolated by organization | S/I | Cross-organization reads return nothing | None: Test Plan question D8. |

## 6. No longer in Milestone 3

- **Medication photo capture (handoff item 1.10).** The workbook replaced the Milestone 3 photo-capture row with 6.2.42,
  and no row in any milestone now carries it. PR #215 (open) implements it. The Test Plan holds its component cases at
  §3.14 (TC-MED-PHOTO), with question D17 asking for a work package and a requirement. The photo-capture journey,
  TC-E2E-003, is Deferred.
- **Performance baseline.** Response-time, pagination, throughput and retry targets are 6.2.47, Performance & Load
  Validation, owned by Kris in Milestone 4.

## 7. Verification ownership, entry and exit

- **Who verifies.** The workbook has no Milestone 3 verification packages. Verification is 6.3.2, Verification &
  Acceptance (Kris). Accessibility evidence is 6.3.7 (Rich, who verifies independently of Camilla's code). Defect retest
  is 6.2.46 (Kris). All three are Milestone 4 rows. The package numbers PRs #206, #208 and #212 use (3.2.4, 3.6.4,
  3.6.1) do not appear in the workbook.
- **Separation of duties.** Kris is a supporting member on 6.2.35, 6.2.38 and 6.2.44. Any code Kris writes there is
  executed and signed off by another tester.
- **Entry.** The feature is merged to `team-e-develop` and its unit tests pass in CI.
- **Exit.** Every row for the package has at least one Test Plan case. Each case has a Test Report entry with an actual
  result, a status (Pass / Fail / Blocked / Not Executed), execution date, a named executor, environment and evidence.
  A skipped case is Not Executed, never Pass. Every failure has an issue with an owner. Integration, system,
  regression and accessibility signoff comes from a tester who did not build the feature. Open questions that change an
  expected result have a decision: Test Plan D8 (organization scoping), D9 (reconciliation behaviours), D13
  (requirements for the journeys), D14 (sharing) and D21 (what unlink deletes).
- **Traceability.** Rows trace to SRS 1.4 IDs where they exist. The REQ-nnnn form belongs to Team Charlie's SRS only.
  Test cases trace through Test Plan Table 7-1 and the Test Report. This document feeds 6.4.31, Blue Button
  Requirements-to-Screen Traceability, which needs a planned test identifier for every resource and screen.

## 8. What this changed in the Test Plan

**Revision 0.16 (2026-09-30)**

1. §3.10, §3.12, §3.13, Tables 2.9-1, 2.9-2, 7-1 and A-1 now trace to 6.2.41, 6.2.35 and 6.2.44 instead of the
   PRs' 3.2.4, 3.6.4 and 3.6.1. Build-package references (3.1.x to 3.5.x) now name 6.2.35, 6.2.37, 6.2.38, 6.2.41 and
   6.2.44.
2. §3.13 and question D12 trace the journeys to their rescoped packages: 6.2.40 (TC-E2E-001), 6.2.41 (002) and
   6.2.37 (004). The suite as a whole traces to 6.2.44.
3. TC-E2E-003 was Blocked on photo capture, which is no longer in any milestone. It is now Deferred (milestone TBD).
4. TC-E2E-002 now reads confirm, separate or defer. flows.dart still says accept and reject; that is logged in §11 for
   the PR #212 author.
5. §3.10.5 and §11 no longer say the Testing Lead builds reconciliation. §11 records Kris as a supporting member of
   6.2.35, 6.2.38 and 6.2.44.
6. §3.11 and Table 7-1 record that WBS 1.4.3 is the work plan's 6.2.12, a Milestone 1 package.
7. §11 records that 6.2.36 needs a Test Plan identifier on every mapping-matrix row.
8. Two SRS/WBS conflicts became plan questions: D14 (6.2.37 sharing against SRS §1.2) and D15 (6.2.41 cross-source
   reconciliation against the FEAT-03 deferral).

Revision 0.16 also added three §11 gaps: the PRs' package numbers and flows.dart wording, the Testing Lead's supporting
roles, and the mapping-matrix identifiers. No Test Plan identifier was added, renumbered, reused or retired.

**Revision 0.22 (2026-10-03, PR #241)**

1. §3.13 reserves TC-E2E-010, the connect journey, Blocked on 6.2.26 and 6.2.40. It is in `flows.dart`, so
   TC-E2E-005…009 check it.
2. Question D21 records that Addendum A1-Q1 differs from FR-MCR-11 on what unlink deletes. TC-20.16 and TC-20.17 keep
   the SRS expected result until the addendum is baselined.

## 9. Revision notes

**2026-09-30 (Testing Lead)**

- **Row identifiers.** The STP-M3-E numbers are withdrawn. They were not a Team Echo identifier scheme. Rows are now
  identified by their SRS requirement or WBS package, and test cases by their Test Plan identifiers.
- **WBS.** Packages, owners and criteria were re-read from the *WBS & Assignments* sheet. 6.2.35–6.2.44 have been
  renamed and rescoped there:
  - Sharing merged into 6.2.37.
  - 6.2.40 is now the screen suite.
  - 6.2.41 is now user-assisted reconciliation.
  - 6.2.42 replaced photo capture.
  - 6.2.43 replaced sharing with UI states and WCAG 2.1 AA.
  - 6.2.44 adds the end-to-end vertical slice.

  The internal 3.x.x build and verify packages are not in the workbook and were removed.
- **Screen states.** Now under 6.2.43 and traced to the SRS cases that already cover them. The offline state was added,
  and partial-data has no expected result yet. No Test Plan change was needed for this.
- **New sections.** KI-05 and the EHR canonical schema were added (§5), and photo capture and the performance baseline
  moved to §6.
- **Corrections.**
  - WCAG 2.2 AA became 2.1 AA.
  - Retry rules now follow FR-MCR-23 and FR-MCR-09: 429 retries, 401 does not.
  - Disconnect deletes the data (FR-MCR-11).
  - The "Passed 9/28 (28/28)" result claim was removed; results belong in the Test Report.
  - The REQ-nnnn trace was replaced with SRS 1.4 IDs.

**2026-10-03 (Testing Lead, PR #241)**

- **Repository copy.** This text replaces the 2026-09-28 draft that merged with PR #206, so the repository and the Test
  Plan read the same requirements.
- **Unlink (6.2.39).** Added the Addendum A1-Q1 proposal next to FR-MCR-11, with the questions it leaves open, as Test
  Plan question D21. 6.2.40 and 6.2.43 point to it.
- **Connect (6.2.40).** Added the FR-MCR-07/08 error paths (TC-20.9…20.12) and the end-to-end connect journey
  (TC-E2E-010). 6.2.44 lists TC-E2E-010 as the link step of the vertical slice.
- **Statuses.** Every case cell now reads as of Test Plan revision 0.22:
  - 6.2.35 and 6.2.38: the PR #223 cases.
  - 6.2.37: the PR #238 cases.
  - The merged state of PRs #207 and #209.
- **Question numbers.** The 6.2.37 sharing conflict is D14 and the 6.2.41 conflict is D15. The earlier text gave D13 for
  sharing.
