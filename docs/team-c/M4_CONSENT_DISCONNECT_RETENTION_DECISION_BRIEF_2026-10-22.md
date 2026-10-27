# M4 decision brief: consent, disconnect, and retention

Prepared October 22, 2026 (America/New_York). Author role: Team C Technical Architect.
Audience: Jonathan, Tiffany, Ian/Team B, and shared architecture owners.
Status: draft for decisions. No policy has been selected by this brief.
Supports WBS 4.2.9–11 and later handoff checks for 4.5.4/4.5.6.

## Decision requested

Agree on what happens to Cerner links, records, access, and audit data after disconnect. Also agree on retention and purge rules for the new normalized Condition and Encounter records. Keep CR-2 single-record sharing as a separate change until its scope and access rules are approved.

Team C can document the facts and options. Team B, shared architecture owners, and the Team Lead must coordinate the policy decision. Tiffany confirms the tests and final evidence needed. No source data, runtime code, schema, WBS values, or labor entries were changed for this brief.

## Exact sources and new branch change

| Reference | Reviewed state | What it means |
| --- | --- | --- |
| Shared branch | `team-c-develop` at `21d5a521e87f70eb9c304bd5d993d24cdad9adad` | Baseline used by the initial inventory and evidence table. |
| Earlier Cerner review | `feature/team-c-cerner-qa-implementation` at `9ef50e4c` | Source used for the October 22 updates to PRs #395/#396. |
| Current Cerner reference | Same feature branch at `0c991bb525fefbdbbed478441450f56fe828d4e9` | Freshly fetched for this brief. PR #391 is still open. |
| New since `9ef50e4c` | Commits `dc69ca53`, `fd5d695b`, `0c991bb5` | Patient/Appointment API routes, callback/filter-chain tests, service-contract tests, and expected outputs were added. The earlier statement that controllers are absent is now dated history. |
| Current branch CI | [Feature CI](https://github.com/umgc/2026_fall_careconnect/actions/runs/39815432431) and [quality gate](https://github.com/umgc/2026_fall_careconnect/actions/runs/39815432440) report success at `0c991bb5` | These are reported branch checks. No local tests were rerun. Do not carry the earlier 231-test count forward as this newer run's count. |

The latest controller exposes Patient and Appointment reads and calls the existing patient-access policy. Code presence does not confirm final endpoint/contract acceptance. Donald's remaining-test role comes from Tiffany's earlier follow-up; ask Tiffany/Donald to confirm what remains after these new commits. Production ownership still needs Team Lead/backend confirmation; Git authorship alone is not an owner assignment. See [new controller][new-controller].

Final release testing must use the resulting `team-c-develop` SHA after PR #391 is reviewed and merged.

## What the current code does

| Area | Observed behavior at `0c991bb5` | Decision gap |
| --- | --- | --- |
| Cerner disconnect | The controller calls OAuth disconnect. The service deletes `ORACLE_HEALTH` credential rows and records a disconnect event. It does not invoke crosswalk/raw/normalized purge. [Controller][oauth-controller], [service][oauth] | Credential deletion is current behavior, not an approved full data-deletion policy. |
| Read permission | Cerner resolves the caller and patient user, then delegates to `AuthorizationService.requirePatientAccess`. [Policy][policy], [authorization][authorization] | This is patient relationship access, not an explicit one-record CR-2 grant. Decide how any new grant fits without changing existing access by accident. |
| Existing consent | `consent_grants` has patient/grantee, scope, status and lifecycle times. The model contains no source/type/record key. The active query checks revoke and expiry. [Model][grant], [query][grant-query] | A new record-share design needs an approved stable record reference and scope. |
| Grant refresh and AI | Existing AI grant refresh resets grant/expiry times. Effective AI access can fall back to a care-circle link when no grant history exists. [Consent service][consent] | Do not reuse those rules unchanged for a fixed 90-day single-record share. Review compatibility explicitly. |
| Raw data | Cerner raw-save helpers find a matching patient/source/type/external ID row and upsert it. [Clinical service][clinical], [Patient/Appointment service][patient-appointment] | This differs from append-only source history. Decide the clock and lifecycle rules for refreshed copies and raw/normalized pairs. |
| Retention worker | Targets raw payloads, resolved conflicts, source identity, retrieval audit, coverage and visit rows. Defaults require both age and elapsed-time conditions; unknown DOB is kept. [Worker][retention] | Normalized Condition and Encounter tables are not targets. Appointment rows are not targets either; include them in shared review. |
| Shared source purger | Deletes mirror, raw, identity, conflicts and crosswalk rows. It does not list Condition, Encounter or Appointment tables. [Purger][purger] | Simply calling this helper would not establish complete Cerner cleanup. Review transaction order and all applicable tables. |
| Audit | Cerner OAuth disconnect uses the EHR audit service; that service writes through the shared logger and is fail-soft. [Audit service][audit] | Decide required metadata, failure handling, retention, and evidence for each lifecycle event. |

The retention facts above describe code and configured defaults. This brief does not decide legal applicability, retention periods, or deployed settings.

## Choices for shared review

Each row is open. Options describe tradeoffs; none is approved or implemented by this brief.

| Decision | Options to review | Effect to resolve | Decision owners |
| --- | --- | --- | --- |
| D1 — Meaning of disconnect | Stop future vendor fetch only; or stop fetch plus access to retained copies; or stop fetch and delete agreed stored copies. | The UI label, API behavior, cached reads and user expectation must agree. State which owner/caregiver/admin paths remain available. | Team B, shared architecture, Jonathan; Tiffany validates tests. |
| D2 — Crosswalk lifecycle | Delete the source link; or retain an explicitly inactive link with approved metadata. | Prevent an old link from becoming active by accident. Relink must verify source identity and must not revive old shares without the agreed rule. | Team B/shared identity owners and Team Lead. |
| D3 — Normalized retention | Align with approved raw-record retention; or approve a distinct mapped-record rule; or delete applicable records at unlink where policy permits. | Specify Condition, Encounter and Appointment clocks, minimum metadata, legal holds if applicable, and what happens when raw data expires first. | Team B/shared architecture; obtain policy authority as needed. |
| D4 — Source deletion/status | Mark unavailable; or remove selected current copies; or keep prior copies under an approved history rule. | A missing row in a partial/page-failed fetch is not proof of deletion. Specify complete-sync evidence and entered-in-error handling. | Source owners plus Team B/shared architecture. |
| D5 — Consent after disconnect | Revoke applicable source/record grants; or suspend access with retained grant history; or another explicitly approved lifecycle. | Grant validity and record availability are separate checks. Define whether relink restores anything, and preserve existing unrelated grants. | Shared consent owners, Team B and Team Lead. |
| D6 — Future CR-2 record grant | Extend the shared consent model with a precise record reference; or approve another coordinated shared design. | Scope must bind owner, recipient, source, resource type and record. An update must not restart the proposed 90-day term; patient-wide AI/caregiver access must not leak unrelated records. | PM/affected leads approve scope; shared consent/architecture owners design. |
| D7 — Audit and metadata | Retain only agreed lifecycle metadata after clinical purge; decide event retention and failure/retry behavior. | Record who/what/when/outcome without tokens or clinical payloads. Do not silently erase required audit history or assume a fail-soft event proves durable receipt. | Team B/shared audit and security/privacy reviewers. |
| D8 — Atomic cleanup and races | One transaction for related local changes; or a tracked cleanup workflow with agreed access behavior while pending. | Define rollback, retries, repeat disconnect, in-flight imports, late writes and stale cache/index handling. Vendor calls and database commits need an agreed failure path. | Backend/shared architecture owners; Tiffany and PostgreSQL test owner. |

## Approval fields that must be filled

For each D-row, record the chosen option or exact alternative, tables/endpoints affected, access behavior, retention clock/period, exception handling, schema/contract impact, owner, reviewer, decision date and evidence link. Leave unknowns explicit. A general PR approval does not silently select all options.

| Decision group | Named decision owner | Decision / conditions | Approved source/version | Follow-up owner/date |
| --- | --- | --- | --- | --- |
| D1–D2 disconnect and crosswalk | Pending shared/Team Lead confirmation | Pending | Pending | Pending |
| D3–D4 retention and source lifecycle | Pending Team B/shared architecture confirmation | Pending | Pending | Pending |
| D5–D6 consent and CR-2 scope | Pending shared consent/PM/affected leads | Pending | Pending | Pending |
| D7 audit | Pending shared audit/security owner | Pending | Pending | Pending |
| D8 transaction/race behavior | Pending backend/shared architecture owner | Pending | Pending | Pending |

## Tests required once the behavior is approved

These are proposed verification cases, not executed results or new official requirement IDs. Tiffany should map them to the controlled M4 scenarios.

| Case | Check | Evidence needed |
| --- | --- | --- |
| V1 — Auth and scope | Anonymous caller, wrong patient/source/record/recipient, owner and valid caregiver. Exercise real filters and service policy, not only controller mocks. | Exact SHA, API/security test results and synthetic identities. |
| V2 — Disconnect | Check credential, crosswalk, raw and every normalized store against D1–D3. Read through every applicable API/cache/index path after disconnect. | PostgreSQL before/after counts using synthetic data; response evidence. |
| V3 — Relink | Repeat disconnect; relink same source patient; attempt different source patient; check old grants and cached data against D2/D5. | Identity and lifecycle assertions; no name/DOB matching. |
| V4 — Retention boundary | Just before/at/after chosen time and age boundary; unknown DOB; disabled purge; raw and normalized records with different update times. | Fixed-clock tests plus PostgreSQL purge results and reference integrity checks. |
| V5 — Vendor removal | Complete fetch omits record, incomplete fetch omits record, entered-in-error resource, temporary source failure. | Source fixtures plus approved availability/deletion assertions. |
| V6 — Record grant, if CR-2 approved | Registered email lookup; view-only one-record access; wrong record/source/recipient denied; revoke; expiry boundary; update does not extend term. | Authenticated API and frontend/contract tests against approved shared model. |
| V7 — Consent compatibility | Existing AI_RETRIEVAL, MEDICARE_VIEW and EHR_IMPORT behavior stays within approved rules. Review AI care-circle fallback and grant refresh. | Focused regression tests and shared consent reviewer decision. |
| V8 — Cleanup failure/race | Database failure, repeat request, concurrent read/import, late write and relink during cleanup. | PostgreSQL rollback/concurrency results and no unintended restored access. |
| V9 — Audit/data minimization | Event scope and outcome follow D7; no tokens/raw patient content in errors or audit; audit failure follows chosen rule. | Sanitized event assertions and named security/privacy review. |
| V10 — Final workflow | Frontend, E2E, approved contract, secure-sandbox and accessibility checks use the post-merge candidate. | Test Lead disposition, candidate SHA and immutable artifacts. |

## Next actions

1. Terence gives this brief to Jonathan and Tiffany for routing to Ian/Team B and shared architecture/consent owners. No message was sent by this task.
2. Jonathan confirms named decision owners and the current Patient/Appointment implementation/test owners after the latest commits.
3. Shared owners fill D1–D8. Terence updates the inventory/evidence table from accepted decisions and notes the newer branch SHA.
4. Backend owners implement only approved rules; Donald/Tiffany confirm the remaining test split and execute the agreed cases.
5. After #391 merge, capture the resulting team-c-develop SHA, run the final required checks, and record named acceptance before closing handoff tasks.

## Checks and limits

Read AGENTS.md, START_HERE.md, Project-Planning.md and USING_WITH_OPENAI_CODEX.md. M4 follows the user's current confirmation; old M3 guide wording does not change this scope.

Fetched the current Cerner feature ref, inspected its three new commits and relevant consent, access, storage, purge and audit files. Live GitHub reads confirmed PR #391 open and both current-head checks successful. Each pinned source path below was verified in Git. During preparation, no app tests, database queries, live vendor calls, WBS edits or external messages were performed. The user later authorized publishing this documentation in its own PR; that publication does not select a policy or establish sign-off.

Related review work: [PR #391](https://github.com/umgc/2026_fall_careconnect/pull/391), [inventory #395](https://github.com/umgc/2026_fall_careconnect/pull/395), [evidence #396](https://github.com/umgc/2026_fall_careconnect/pull/396), [CR-2 #305](https://github.com/umgc/2026_fall_careconnect/issues/305). Shared baseline source: https://github.com/umgc/2026_fall_careconnect/tree/21d5a521e87f70eb9c304bd5d993d24cdad9adad

## Pinned code evidence

[oauth]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/CernerOAuthService.java
[oauth-controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/controller/CernerOAuthController.java
[policy]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerAccessPolicy.java
[authorization]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/security/AuthorizationService.java
[grant]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ConsentGrant.java
[consent]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/consent/ConsentService.java
[grant-query]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/repository/ConsentGrantRepository.java
[retention]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/EhrRetentionWorker.java
[purger]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/EhrSourceDataPurger.java
[raw]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ehr/EhrRawPayload.java
[condition]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ehr/EhrConditionRecord.java
[encounter]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ehr/EhrEncounterRecord.java
[clinical]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerConditionEncounterService.java
[patient-appointment]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerPatientAppointmentService.java
[new-controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerPatientAppointmentController.java
[audit]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/EhrAuditService.java
