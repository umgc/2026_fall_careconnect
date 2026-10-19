# Team C personal WBS review

> Historical October 13 review. PRs #330 and #331 have since merged into Team C. Read [the October 17 update](team-c-docs-fixtures-review-2026-10-17.md) for current branch facts. Counts and pending labels below retain their original date; they are not a current release decision.

Prepared October 13, 2026, Eastern Time, for Terence Boyce.

The source is the connected `Team_Charlie_Integrated_Work_Plan_and_EVM.xlsx` workbook. `WBS & Assignments` is authoritative. Both WBS tabs list the same 11 personal tasks and the same completion values. Review baseline: `team-c-develop` at `4e5266e925c3e9cb764958fa415ec32372b9442e`.

Review code and documents are in [PR #331](https://github.com/umgc/2026_fall_careconnect/pull/331), a draft against `team-c-develop`. The separate Cerner fixes are in PR #330. Neither PR is merged.

## Work completed for review

The saved language-switch test is now in this review branch. It uses the real locale provider and language picker. It switches the same mounted screen from English to Spanish, back to English, then to the system locale. It checks visible text, saved preferences, and the absence of widget exceptions. Mock preferences keep the test offline. The three focused localization suites passed all 89 tests on October 13.

The [M3 trace matrix](m3-traceability-matrix.md) now names the existing allergy tests and separates their limited scope from full integration. A passing mock-based controller test cannot prove Spring Security, a database, a live source call, or release approval.

## Personal task checks

Percentages below are the workbook values read before this work. They are not new acceptance decisions.

| WBS | Work | Workbook | Evidence and remaining work | Finding |
| --- | --- | --- | --- | --- |
| 4.1.6 | String extraction | 100% | Both tabs carry the prior Done state. The original named extraction scope is not supplied in the task row and was not re-proved. The new language tests do not prove all strings were extracted. | Not verified in this review; prior status retained |
| 4.2.5 | i18n tests, review, PR integration | 75% | 89 focused tests pass, including the saved visible-text switch test. This branch provides reviewable code. Non-author review and merge remain open. | Partly met |
| 4.2.6 | Quality and review | 25% | This task review and the M3 trace identify evidence and gaps. Required independent reviews, acceptance, and dependency 4.1.5 remain open. | Partly met |
| 4.2.7 | Repository, build, CI assessment | 75% | Current code, clean baseline, executed checks, workflows, and live GitHub state are recorded. Detailed protection settings are not available to this account. See the validation report below. | Partly met |
| 4.2.8 | Architecture and handoff analysis | 100% | The two-document localization audit is merged through PR #79. It does not accept Cerner integration. | Met for audit scope |
| 4.2.9 | Data mapping and provenance | 50% | Current allergy fields, patient binding, source identity, and date rules are reviewed below. Verified vendor responses/profiles and storage validation are absent. | Partly met |
| 4.2.10 | Trust boundaries and accessibility | 75% | Design review below names each boundary and the needed proof. Independent security, privacy, accessibility, and test review remain open. | Partly met |
| 4.2.11 | TDD and test-plan baseline | 75% | Existing M1 baseline has all 26 work-package trace rows. This addendum links current M3 code and exact tests. Controlled SRS/API links and Test Lead review remain open. | Partly met |
| 4.5.4 | Deliverable handoff | 25% | A receiving checklist is prepared below. The full final package, receipt, and dependency 2.5 disposition are not verified. | Partly met |
| 4.5.6 | Final check and handoff | 25% | Release precheck is prepared. Final release, sign-offs, and delivery receipt remain open. | Partly met |
| 4.5.7 | Draft lessons | 100% | The saved `Handoff_and_Lessons.md` contains eight lessons and next actions. Later lessons are in `Lessons_and_Handoff_Update.md`. This is separate from the final retrospective. | Met for draft scope |

Earlier baseline/design work is under [PR #157](https://github.com/umgc/2026_fall_careconnect/pull/157). The local M1 draft and its 26-row trace are earlier evidence, not a merged Team C baseline or proof of Test Lead acceptance. This document adds current review findings rather than replacing that history.

## Mapping review for 4.2.9

| Input or rule | Current code | Evidence limit or action |
| --- | --- | --- |
| Source record ID | `Allergy.sourceRecordId` retains the FHIR ID; source is `CERNER` | Approve source/tenant keys and payload-history storage. |
| Patient binding | `map` requires `Patient/` plus the server-supplied patient ID | Real service must resolve trusted patient/source identity. A name and date of birth are not sufficient. |
| Substance | Text and the first coding code are kept | Coding system/version and multiple coding rules need approval. |
| Status and severity | Entered-in-error records are excluded; unknown severity becomes null | Vendor profiles and approved canonical rules remain needed. |
| Dates | Offset date-times become UTC; year/month/day strings retain precision | Baseline regex accepts impossible calendar values. [PR #330](https://github.com/umgc/2026_fall_careconnect/pull/330) adds calendar validation and three regression tests; all 13 mapper tests pass. This candidate is not merged or vendor-approved. |
| Missing or malformed data | Invalid entries may be skipped; missing reaction produces an empty list | Approve rejection, omission, and partial-result rules. |
| Provenance and persistence | Output keeps source and record ID | No PostgreSQL persistence, raw-payload history, tenant isolation, or encryption validation is proved by the mapper. |

Patient/Appointment prototype PR #148 is closed without a merge. Storage PR #158 is open and targets the mapper branch. Those PRs do not establish integration into `team-c-develop`.

## Boundary review for 4.2.10

| Boundary | Observed implementation | Acceptance check still needed |
| --- | --- | --- |
| Client to API | Provisional controller rejects absent principal and invalid local ID | Real Spring Security filter-chain and cross-patient denial tests. |
| API to source identity | `CernerAccessPolicy` and `CernerAllergyService` are interfaces | Production beans, trusted crosswalk, tenant scope, and conflict handling. |
| Source token and transport | Not implemented by these interfaces or mapper | Secret handling, refresh limit, retry limit, timeout, pagination, and retrieval-only proof. |
| Source to storage | Pure mapper returns provisional records | Approved canonical schema, database tests, encryption-at-rest policy, retention and restore checks. |
| Data to user interface | Language picker has widget evidence | Integrated success, empty, error, reconnect and partial states; manual keyboard and screen-reader evidence. |

The standalone allergy controller tests use mocked service and policy objects. They do not run the security filter chain. No production implementation of either interface was found in this baseline. PR #330 keeps this unfinished route off by default until both real beans are configured. Its five configuration tests pass. Enabling without either bean still fails.

## Quality and handoff checks

| Required evidence | Current disposition | Owner/action |
| --- | --- | --- |
| Release commit and approved scope | Not verified as accepted | Team Lead must name and accept the release candidate. |
| Controlled requirements and OpenAPI checksum | Not verified | Integration owners and Test Lead must approve the shared model and contract. |
| Current automated results | Local results are recorded; full release gates remain open | Review the validation report and open defects. |
| Mapping, security and accessibility review | Not verified | Independent reviewers must record decisions on this packet. |
| Live sandbox proof | Missing from this run | Authorized integration owner must provide sanitized synthetic retrieval evidence. |
| Final documents and transition notes | Draft preparation only | Reconcile the approved TDD, test plan/report, user and operations guides, known gaps, and setup steps to the accepted commit. |
| Receiving party and full package receipt | Not verified | Team Lead must name the destination and receiving party; final submission needs a receipt. |
| Dependencies 4.1.5 and 2.5 | Acceptance not verified | Record their disposition before closing quality/handoff tasks. |

Do not mark the eight open work packages 100% from this review packet alone. Review decisions must state the reviewer, date, scope, accepted evidence, and any remaining action. No sign-off or merge is requested by this document.

## Labor and progress

The live log contains eight October 9 entries at 1.5 hours each, totaling 12 hours. They remain October 9 work. No new October 13 personal work duration was supplied. Test runtimes and this agent session are not added as personal labor.

The workbook Dashboard was set to Week 7 at the read. Submission Check reported FAIL with 61 exceptions: 11 hierarchy, 13 task controls, and 37 labor entries. These are shared workbook findings. This personal task pass does not repair unrelated team rows or prove whole-workbook readiness.

## Validation report

- Focused localization: 89 passed, including visible-text switching on the same mounted screen.
- Full baseline backend: 7,244 tests, 1 failure, 56 errors, no skips. The 56 context errors were caused by the missing Cerner service bean. The separate assertion failure is `SsmPropertySourceInitializerTest.shouldLoadAllParametersWhenAllSsmCallsSucceed`: expected 12 parameters but received 13.
- PR #330 candidate: all 54 focused allergy/configuration tests pass. The wider selected startup run has 110 tests, no assertion failures, and 56 context errors. It gets past the missing Cerner bean, then fails on the existing H2 filtered unique-index schema patch. This does not prove full application startup.
- Broad frontend run stopped after 43:45 with 3,519 passed, 6 skipped, and 220 failed. It is incomplete and failing, not a completed full-suite result. Many failing widget fixtures lacked localization setup. No whole-frontend regression pass is claimed. The web release build passed (318.9 seconds). It reported WASM dry-run compatibility warnings; no WASM support or runtime smoke pass is claimed.
- Checkstyle reports 46,964 warning findings and zero error-severity findings. Its configured gate checks error severity; a successful gate does not mean no findings.
- Live Team C head had no candidate check runs. The branch was marked protected, but its exposed required-status list was empty and enforcement was off. Detailed protection lookup returned HTTP 404 to this account, so detailed rules remain Not verified.
- PR #330 is open as a draft against `team-c-develop`, with head `c6cb34ce2418d22f79f69013d750c4de1e911267`. Its GitHub quality gate was still running at the first read. No merge or reviewer acceptance is claimed.

These local results are an assessment, not a passing release report. Raw logs and JUnit summaries are retained in the course output folder.
