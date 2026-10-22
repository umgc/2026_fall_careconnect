# Milestone 4 Team C Scenario Catalog

**Owner:** Team C QA Lead (Tiffany Obi)  
**Status:** Working execution catalog; contract-dependent assertions remain provisional  
**Scope:** M3 carryover plus M4 WBS 4.10-4.13  
**Result vocabulary:** Not Run, Pass, Fail, Blocked, or Not Applicable

## 1. Conventions

- **P0:** Blocks M4 sign-off. **P1:** Required for normal sign-off. **P2:** Useful regression or exploratory depth.
- Test each scenario at the lowest useful level and repeat it higher only when the higher level proves a new boundary.
- Developers own mapper/service unit tests and controller-slice tests. QA owns fixture governance, WireMock failure coverage, critical E2E coordination, smoke testing, traceability, and sign-off reporting.
- Exact public paths, response fields, source labels, error codes, and partial-result assertions remain provisional until the unified health-data OpenAPI contract is approved.
- Every automated test must reference its `M3-REQ-*` or `M4-REQ-*` requirement and should include the scenario ID where practical.
- All data must be synthetic. Cerner testing is retrieval-only and must not perform write-back.

## 2. Cerner resource scenarios

| Scenario ID | Requirements | Level | Pri. | Owner | Fixture/data | Expected result | Latest result |
|---|---|---|---|---|---|---|---|
| M4-SC-CER-PAT-001 | M3-REQ-01, 03, 16; M4-REQ-02 | Unit/service | P0 | Backend + QA review | `cerner/fhir/patient/patient-complete.json` | Direct trusted `Patient/{id}` retrieval maps approved source identity fields, retains raw source data, and never establishes identity from demographics alone. | Partly covered; final expected output and approval pending |
| M4-SC-CER-PAT-002 | M3-REQ-02, 06, 16 | Unit | P0 | Backend | `patient-missing-optional-fields.json` | Optional omissions do not fabricate values. Missing source recency follows the approved reconciliation rule. | Partly covered; recency rule pending |
| M4-SC-CER-PAT-003 | M3-REQ-03, 16 | Service/integration | P0 | Backend + QA | Wrong-patient derived fixture | A response that differs from the crosswalk/SMART patient context is rejected before persistence. | Focused service/transport baseline exists |
| M4-SC-CER-CON-001 | M3-REQ-01, 02, 17; M4-REQ-02 | Unit | P0 | Backend + QA review | `condition/bundle-one-condition.json` plus candidate expected output | Complete Condition maps code/text, statuses, category, onset/abatement, encounter, recorder, precision, source, and source record identity. | Pass against candidate output; approval pending |
| M4-SC-CER-CON-002 | M3-REQ-06, 17 | Unit/service | P0 | Backend | Missing-optional and entered-in-error fixtures | Missing optionals use approved null/empty rules; entered-in-error is retained for audit and hidden or excluded as approved. | Provisional baseline implemented |
| M4-SC-CER-CON-003 | M3-REQ-07-09, 17; M4-REQ-03 | Integration | P0 | QA + Backend | Empty, paging, malformed, OAuth and WireMock fixtures | Empty, pagination, timeout, malformed, 401/refresh, refresh failure, 429, and later-page failure produce bounded approved outcomes. | Happy path/refresh and HTTP safety covered; remaining Spring cases Not Run |
| M4-SC-CER-ALG-001 | M3-REQ-01, 02, 04; M4-REQ-02 | Unit | P0 | Backend + QA review | Allergy complete/expected fixture pair | Complete allergy maps substance, status, reaction, severity, recorded date, source, and source record identity. | Focused mapper baseline passes |
| M4-SC-CER-ALG-002 | M3-REQ-04, 06 | Unit | P0 | Backend | Empty, missing reaction, entered-in-error, inactive, text-only fixtures | Empty is successful; missing reaction is empty; entered-in-error is excluded; inactive and unknown severity follow approved rules. | Partly covered; lifecycle approval pending |
| M4-SC-CER-ALG-003 | M3-REQ-05, 07-09; M4-REQ-03 | Integration | P0 | QA + Backend | OAuth, paging, malformed and failure fixtures | Token refresh is bounded; timeout, rate limit, malformed data and unsafe pagination produce safe, deterministic outcomes. | HTTP-level baseline passes; full Spring/WireMock matrix Not Run |
| M4-SC-CER-ENC-001 | M3-REQ-01, 02, 18; M4-REQ-02 | Unit | P0 | Backend + QA review | `encounter/bundle-one-encounter.json` plus candidate expected output | Complete Encounter maps status, class/type, period, participants, provider, locations, reasons, diagnoses, appointments and provenance. | Pass against candidate output; approval pending |
| M4-SC-CER-ENC-002 | M3-REQ-06, 18 | Unit/service | P0 | Backend | Missing-optional and empty fixtures | Optional omissions remain null/empty without fabricated clinical meaning; malformed required linkage is rejected. | Provisional baseline implemented |
| M4-SC-CER-ENC-003 | M3-REQ-07-09, 18; M4-REQ-03 | Integration | P0 | QA + Backend | Paging, empty, malformed, OAuth and WireMock fixtures | Trusted pages combine safely; loops/unsafe links fail; 401 refreshes once; other failures follow approved behavior. | Trusted paging and refresh covered; remaining Spring cases Not Run |
| M4-SC-CER-APT-001 | M3-REQ-01, 02, 19; M4-REQ-02 | Unit/service | P0 | Backend + QA review | `appointment/bundle-one-appointment.json` | Complete appointment maps source facts and normalizes instants to UTC without losing source identity. | Focused baseline passes; expected output pending |
| M4-SC-CER-APT-002 | M3-REQ-06, 19 | Unit/service | P0 | Backend | `bundle-proposed-no-times.json` | Proposed appointment remains proposed and permits absent confirmed start/end; wrong patient linkage is rejected. | Focused baseline passes |
| M4-SC-CER-APT-003 | M3-REQ-03, 08, 19; M4-REQ-03 | HTTP/integration | P0 | QA + Backend | Appointment date-window and paging fixtures | Search is patient-bound and uses a closed `-date-or-req-period` range; paging is trusted and bounded; empty results succeed. | Transport baseline passes; Spring/WireMock and date-policy approval pending |
| M4-SC-CER-APT-004 | M3-REQ-12, 19 | Service/persistence | P0 | Backend | Duplicate/newer/older derived fixtures | Duplicate imports upsert; older or unversioned data cannot replace newer canonical or raw data. | Focused baseline passes |

## 3. Cerner authorization, API, and user-workflow scenarios

| Scenario ID | Requirements | Level | Pri. | Owner | Fixture/data | Expected result | Latest result |
|---|---|---|---|---|---|---|---|
| M4-SC-AUTH-001 | M3-REQ-05, 09, 20; M4-REQ-03 | Unit/integration | P0 | Backend + QA | OAuth success, invalid grant, expired token | S256 PKCE, audience, persona, FHIR host and approved read scopes remain consistent; secrets never appear in output or logs. | Unit baseline passes; secure smoke pending |
| M4-SC-AUTH-002 | M3-REQ-05, 09 | Integration | P0 | QA | WireMock 401 then token success/failure | One successful refresh retries once; refresh denial stops and requires reconnection without a loop. | Success baseline passes; failure case Not Run at Spring level |
| M4-SC-CTL-001 | M3-REQ-03, 09, 10; M4-REQ-04 | Controller slice | P0 | Backend | Mocked service/policy | 200, 400, 401, 403, 404 and source failures serialize through the approved common envelope without internal IDs. | Condition/Encounter provisional slices pass; contract pending |
| M4-SC-CONTRACT-001 | M3-REQ-10; M4-REQ-04 | Contract | P0 | QA + Frontend + Backend | Approved OpenAPI and response fixtures | Every backend response and frontend fixture validates against the same immutable contract version/checksum. | Blocked: authoritative contract not found |
| M4-SC-PARTIAL-001 | M3-REQ-08, 10, 11; M4-REQ-03, 04 | Integration/E2E | P0 | QA + Backend + Frontend | Multi-source controlled failure | Available source data remains visible with the approved partial-result/source-status representation. | Blocked: contract and policy pending |
| M4-SC-E2E-001 | M3-REQ-11; M4-REQ-02, 14 | E2E | P0 | QA + Frontend + Backend | Controlled backend/WireMock | User connects Cerner, opens a patient and views approved Cerner records with source attribution. | Not Run |
| M4-SC-E2E-002 | M3-REQ-09, 11 | E2E | P0 | QA + Frontend + Backend | Expired/failed refresh | UI presents reconnect behavior rather than an empty clinical result. | Not Run |
| M4-SC-SMOKE-001 | M3-REQ-14, 20; M4-REQ-02, 15 | Manual smoke | P0 | QA coordinator | Known secure-sandbox synthetic patient | Connect and retrieve each in-scope resource without write-back; record sanitized evidence and fixture drift. | Not Run |

## 4. Batch-5 localization scenarios

Run each applicable row for Social Feed, Gamification, USPS Mail Digest, Caregiver Shift Scheduling, and HHAExchange submission.

| Scenario ID | Requirements | Level | Pri. | Owner | Fixture/data | Expected result | Latest result |
|---|---|---|---|---|---|---|---|
| M4-SC-L10N-001 | M4-REQ-05-10 | Static/generation | P0 | Frontend + QA | All ARB catalogs | Catalogs parse, approved keys/placeholders match `app_en.arb`, and clean `flutter gen-l10n` succeeds. | Not Run for release candidate |
| M4-SC-L10N-002 | M4-REQ-05-09, 11 | Unit/widget | P1 | Frontend | Workflow widget fixtures | Headings, actions, dialogs, validation, loading, empty, error, tooltip and semantic text use generated localization. | Not Run for release candidate |
| M4-SC-L10N-003 | M4-REQ-11 | Unit/widget/manual | P1 | Frontend + QA | English, Spanish, unsupported locale | Locale selection persists; supported locale renders; stale/unsupported locale follows approved fallback. | Not Run |
| M4-SC-L10N-004 | M4-REQ-11 | Unit/widget | P1 | Frontend | Parameter/plural/date/number cases | Parameters, plural forms, dates, times and numbers render correctly without raw keys or placeholder leakage. | Not Run |
| M4-SC-L10N-005 | M4-REQ-11 | Widget/manual | P1 | QA + UI/UX | Narrow/standard viewport, text scaling | Long translations and scaled text remain readable with no clipping, hidden controls or inaccessible scrolling. | Not Run |
| M4-SC-L10N-006 | M4-REQ-12 | Widget/manual accessibility | P1 | QA + UI/UX | Arabic or Urdu; patient/caregiver workflows | Direction, reading order, directional icons, focus order, semantics and layout are usable in RTL. | Not Run |
| M4-SC-L10N-007 | M4-REQ-13 | Human review | P0 | Qualified reviewer + QA tracking | Sensitive medical/safety/privacy/legal strings | Review status, reviewer, date, disposition and evidence are recorded; unreviewed sensitive copy is not called complete. | Not Run |
| M4-SC-L10N-008 | M4-REQ-14 | Regression | P1 | Frontend + QA | Existing affected suites | Localization changes preserve supported workflow behavior. | Not Run for release candidate |

## 5. Release, evidence, and demonstration scenarios

| Scenario ID | Requirements | Level | Pri. | Owner | Fixture/data | Expected result | Latest result |
|---|---|---|---|---|---|---|---|
| M4-SC-REL-001 | M4-REQ-14, 15 | Regression/coverage | P0 | Developers + QA | Release-candidate commit | Required suites pass; mapping and integration coverage meet approved thresholds; exclusions are justified. | Not Run |
| M4-SC-REL-002 | M3-REQ-15; M4-REQ-15 | CI | P0 | Team lead + QA | Integration branch | Three consecutive CI runs pass on the same candidate without unexplained flakiness. | Not Run |
| M4-SC-REL-003 | M4-REQ-15 | Defect review | P0 | QA + Team lead | Defect register | No Critical or High defects remain open; accepted lower defects have owners and plans. | Not Run |
| M4-SC-DEMO-001 | M4-REQ-16 | Rehearsal | P1 | Team lead + QA | Synthetic demo data and fallback | Presenter handoffs, timing, environment, stable paths and sandbox-independent fallback complete successfully. | Not Run |
| M4-SC-SIGN-001 | M3-REQ-15; M4-REQ-15 | Sign-off | P0 | QA Lead | Complete evidence package | Traceability, results, coverage, CI, contract, smoke, accessibility, translation review and defects support Pass, Conditional Pass or Fail. | Not Run |

## 6. Execution record rules

For each execution, record the tested commit, environment, date/time, tester, scenario/test IDs, result, evidence link, defect ID, and retest result. Never change `Not Run` to `Pass` from code inspection alone.
