# M4 handoff package index

Snapshot: 2026-10-22 14:42:21 EDT. Prepared for Terence Boyce, Technical Architect.
Supports WBS 4.5.4 Deliverable Handoff and 4.5.6 Final Check Handoff.
Status: preparation draft; not a delivered or accepted package.

## Package purpose and boundary

Use this index to find the code, documents, checks and decisions needed for handoff. It is a link index, not a release archive or a submitted assignment. Each code/document link is pinned to a reviewed commit. Live PR links show later review activity. Recheck states and select accepted versions before delivery.

The shared app baseline remains `team-c-develop` at `21d5a521e87f70eb9c304bd5d993d24cdad9adad`. Cerner implementation reference is `feature/team-c-cerner-qa-implementation` at `0c991bb525fefbdbbed478441450f56fe828d4e9`. The final release-testing commit is **pending**: use the resulting team-c-develop SHA after PR #391 review/merge, as confirmed by the Team Lead/QA.

This index does not select a deletion/retention policy, approve CR-2, replace Tiffany's QA plan, change WBS percentages/hours, or prove delivery. Terence's inventory, consent/retention analysis and evidence work remain separate from Tiffany's implementation and Donald's testing.

## Review package contents

| Item | Pinned artifact | Purpose / acceptance still needed |
| --- | --- | --- |
| Cerner implementation | [PR #391](https://github.com/umgc/2026_fall_careconnect/pull/391); [source at current reference](https://github.com/umgc/2026_fall_careconnect/tree/0c991bb525fefbdbbed478441450f56fe828d4e9) | Five-resource implementation and tests. Team C review/merge; post-merge regression/acceptance pending. |
| Storage inventory | [Inventory][inventory]; [PR #395](https://github.com/umgc/2026_fall_careconnect/pull/395) | Stores, keys, raw/normalized paths and gaps. Ian/Team B coverage review pending. |
| Requirements/evidence table | [Evidence matrix][evidence]; [PR #396](https://github.com/umgc/2026_fall_careconnect/pull/396) | Task proof, test links and reviewer gates. Team Lead/QA acceptance pending. |
| Consent/disconnect/retention brief | [Decision brief][decisions]; [PR #399](https://github.com/umgc/2026_fall_careconnect/pull/399) | Eight open shared decisions and proposed tests. Team B/shared architecture/Team Lead dispositions pending. |
| QA baseline | [M4 plan][qa-plan], [scenario catalog][qa-scenarios], [trace][qa-trace] | Tiffany confirms approved scope, controlled references, test owners and final candidate. |
| Final test report | [M4 summary template][qa-summary] | Not an executed release report. Populate exact candidate, counts, failures, defects, reviews and final disposition. |
| Localization/accessibility | [M4 checklist][qa-l10n] | Current functional/manual, translation, keyboard/screen-reader/RTL evidence remains pending as applicable to approved scope. |
| Sandbox/fixture evidence | [Secure-sandbox checklist][qa-smoke], [fixture register][qa-fixtures] | Approved synthetic-only retrieval, sanitized results and no-write-back evidence needed. Fixtures alone do not prove live interoperability. |
| Setup and operations | [Backend][backend], [environment][environment], [PostgreSQL][database], [frontend][frontend], [Cerner configuration][configuration] | Receiver must verify setup against the accepted candidate and chosen environment. No secret values belong in this package. |

## PR state snapshot

All four PRs were read live for this index. Open/ready status is not approval or merge.

| PR | State | Draft? | Head | Check summary |
| --- | --- | --- | --- | --- |
| #391 | OPEN | No | `0c991bb5` | quality-gate: SUCCESS; Feature Branch — Build & Test: SUCCESS |
| #395 | OPEN | No | `76a4c53a` | quality-gate: SUCCESS; Feature Branch — Build & Test: SUCCESS |
| #396 | OPEN | No | `fa8a253d` | quality-gate: SUCCESS; Feature Branch — Build & Test: SUCCESS |
| #399 | OPEN | No | `8d98babf` | quality-gate: IN_PROGRESS; Feature Branch — Build & Test: SUCCESS |

PR #391's branch CI/quality checks are evidence for its feature head, not final integration tests. The earlier 231-test count applies to `9ef50e4c`; it is not assigned to `0c991bb5`. Documentation-PR checks do not prove application behavior. Link final artifacts after the post-merge candidate is chosen.

## Known gaps and dated evidence

| Gap | Action / routing | State |
| --- | --- | --- |
| Patient/Appointment controller notes in #395/#396 | Those documents reviewed `9ef50e4c`, before the newer controllers/tests. [Controller at 0c991bb5][controller] now exists. Add a dated follow-up when reconciling final artifacts; do not rebuild it from the old gap list. | Code now present; final contract/test acceptance and owner confirmation pending. |
| Disconnect and crosswalk | Current Cerner disconnect removes OAuth credentials only. Team B/shared architecture/Team Lead must settle delete/deactivate and retained-data accessibility. | Decision pending in #399. |
| Normalized retention/purge | Condition/Encounter are outside the shared retention worker; Appointment also needs shared lifecycle review. Agree raw/normalized handling and source-deletion behavior. | Decision pending; no new policy chosen. |
| Consent/CR-2 | Distinguish existing relationship/import/AI grants from proposed single-record sharing. Obtain scope, shared model and access rules. | Approval/design pending. |
| Contract and canonical model | Attach controlled SRS/TDD/OpenAPI versions/checksums and mapping approval. | Controlled acceptance references pending. |
| Final app proof | Frontend, integration/E2E, contract, secure sandbox, security/privacy/accessibility and regression checks need current results. | Final candidate and results pending. |
| Localization evidence | Confirm original string-extraction scope and reconcile earlier visible-text switch test evidence with current code. | Review pending; old completion bands unchanged. |
| WBS dependencies and dates | Jonathan resolves dependency 2.5 for 4.5.4 and 4.1.5 for quality review; confirm October 31 versus November 4 dates from the plan. | No live workbook verification in this task. |

## Setup and receiving checklist

These are preparation checks, not proof that setup ran.

- [ ] Team Lead identifies the accepted commit, app/platform scope and release/package version.
- [ ] Receiver records JDK/Maven, Flutter, PostgreSQL and operating-system versions required by that candidate's setup guides.
- [ ] Authorized environment owner supplies profile/database/token-encryption/OAuth configuration through the team's approved secret channel; package includes names and instructions only.
- [ ] Receiver confirms Cerner registration, FHIR base, redirect URI, scopes and feature flags against [configuration][configuration] and the candidate's properties. Do not use stale README port values as accepted deployment settings.
- [ ] Receiver builds and starts the accepted app in the agreed environment; records sanitized startup/smoke evidence.
- [ ] QA runs the approved synthetic user journeys and checks denied/expired/disconnected states.
- [ ] Known defects, accepted limits, rollback/restore steps and support contacts are attached and reviewed.

## Handoff gates

| Gate | Required entry/evidence | Proposed routing | Current state |
| --- | --- | --- | --- |
| H1 — Scope and schedule | Approved scope, deadline, dependencies, platform, receiving package | Jonathan/PM | Pending |
| H2 — Candidate | Reviewed/merged PR #391; resulting team-c-develop SHA and approved artifact versions | Jonathan/Team C | Pending |
| H3 — Shared policies | Decisions from #399, affected contracts/models and follow-up owners | Ian/Team B, shared owners, Team Lead | Pending |
| H4 — QA and independent review | Candidate-specific results, defect dispositions, security/privacy/accessibility and Test Lead decision | Tiffany and assigned reviewers | Pending |
| H5 — Package check | Accepted manifest, setup/user/operations notes, known gaps, readable links and access permissions | Terence/document owner/receiver | Draft index only |
| H6 — Delivery and receipt | Named receiver, approved channel, delivery date, package version, acknowledgement link and conditions | Jonathan names receiver; receiver confirms | Pending; nothing delivered by this task |

Do not close 4.5.4 or 4.5.6 from this index alone. Closure needs the applicable gate evidence and receiving-party confirmation.

## Final delivery record — fill after approval

| Field | Value |
| --- | --- |
| Final package/version | Pending |
| Accepted team-c-develop SHA | Pending |
| Approved document versions/checksums | Pending |
| Test Lead disposition and result links | Pending |
| Known defects / accepted limitations | Pending |
| Receiver and role | Pending Team Lead confirmation |
| Delivery channel and access check | Pending |
| Delivered by / date | Pending |
| Receiver acknowledgement and date | Pending |
| Accepted scope / conditions | Pending |
| WBS 2.5 dependency disposition | Pending |
| 4.5.4 / 4.5.6 closure approval | Pending |

## Local working files and provenance

The course copies below are working artifacts, not proof of upload or acceptance:

- Storage inventory v2 (course-local copy; use [pinned inventory][inventory] for shared review)
- Evidence matrix v2 (course-local copy; use [pinned matrix][evidence] for shared review)
- Decision brief, original local version (course-local copy; use [published brief][decisions] for shared review); the pinned #399 version adds a publication note.
- `input/M4_Final/M4_Remaining_Work_Plan_2026-10-21.md` remains the dated plan; it is not rewritten by this index.
- Local Python/SQLite demo remains in `input/M4_Final`. Its October 21 17-test result is prototype evidence only, not the CareConnect build or final package.

The companion [artifact manifest](M4_Handoff_Artifact_Manifest_2026-10-22.json) records this published index checksum, the original course-local snapshot checksums, pinned source paths and PR/check states captured when the index was prepared. Course-local files are not included in this PR. It is not a release checksum or delivery receipt. Regenerate the final manifest after accepted versions are selected.

## Validation and limits

Read Project-Planning.md and USING_WITH_OPENAI_CODEX.md; applied the session's M4 course rules. Checked live PR states, inspected setup/config and QA source paths, verified pinned Git objects and local links, and generated a SHA-256 manifest. No app tests, database/vendor calls, external messages, release, WBS edit or course submission were performed during preparation. The user later authorized publishing the index and manifest in a documentation PR; publication is not package delivery or acceptance.

## Pinned sources

[qa-plan]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-test-plan.md
[qa-trace]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-traceability-matrix.md
[qa-summary]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-test-summary.md
[qa-scenarios]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-scenario-catalog.md
[qa-l10n]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-localization-qa-checklist.md
[qa-smoke]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/cerner-secure-sandbox-smoke-checklist.md
[qa-fixtures]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/cerner-fixture-capture-register.md
[backend]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/README.md
[environment]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/README-ENV.md
[database]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/pg_docker/README.md
[frontend]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/frontend/README.md
[configuration]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/config/CernerProperties.java
[controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerPatientAppointmentController.java
[inventory]: https://github.com/umgc/2026_fall_careconnect/blob/76a4c53a1aa0b573b63d79acb7acceec9686aab9/docs/team-c/FHIR_STORAGE_INVENTORY_2026-10-22.md
[evidence]: https://github.com/umgc/2026_fall_careconnect/blob/fa8a253d2c4f4d147cbc000b102e3b04273ab792/docs/team-c/M4_REQUIREMENTS_EVIDENCE_MATRIX_2026-10-22.md
[decisions]: https://github.com/umgc/2026_fall_careconnect/blob/8d98babfb64ce714cdf3f41dfdf134ccc421888e/docs/team-c/M4_CONSENT_DISCONNECT_RETENTION_DECISION_BRIEF_2026-10-22.md
