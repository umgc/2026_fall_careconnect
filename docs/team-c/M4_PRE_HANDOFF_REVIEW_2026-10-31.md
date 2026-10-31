# Team C M4 pre-handoff review

Reviewed October 31, 2026 (Eastern time). Prepared by Terence Boyce.
Status: review preparation. Release approval, final QA and delivery remain open.

## Scope and source

The live Team Charlie WBS was read in Excel on October 31. It names Terence on M4 tasks 4.5.4, 4.5.6 and 4.5.7, and in the shared owner cell for 4.5.1 in Latest WBS row 56. The official 4.5.1 row names Tiffany. Generic supporting text "Team C" is not a new personal assignment.

This review uses team-c-develop at `a9ddb659ba3597c964b81007f7ef6a954489410c`. This is a reviewed source version, not a QA-selected release candidate. The October 22 documents remain dated records. This report supersedes their current-state claims only where the findings below say so.

## Task decisions

| WBS | Work prepared or checked | What remains |
| --- | --- | --- |
| 4.5.1 Cerner testing and error handling | Reviewed current CI, test files and local backend regression. Repaired an audio test regression that blocks a clean macOS run. | Independent review and merge of this test change; agreed Cerner contract, PostgreSQL, end-to-end, secure-sandbox and localized error checks; Tiffany's final QA decision. |
| 4.5.4 Deliverable Handoff | Refreshed the source/test/design index and prepared review materials with hashes. | Dependency 2.5, accepted versions, named receiver and channel, approved delivery and receipt. |
| 4.5.6 Final Check Handoff | Checked the source version, CI scope, design PR status and unresolved gates below. | Final candidate selection, remaining results and defect decisions, QA/package approval and receiver confirmation. |
| 4.5.7 Draft lessons learned | WBS already says Done/100%. Draft refresh adds source-version, portable-test and receipt lessons. | Keep the draft criterion complete; do not treat it as final retrospective or release approval. |

Related older work packages 4.2.6, 4.2.7 and 4.2.9–11 support this handoff. Their original milestone labels, owners, hours and percentages are not reclassified here.

## Current integration CI

[Develop Merge CI run 41163636591](https://github.com/umgc/2026_fall_careconnect/actions/runs/41163636591) passed for the reviewed source SHA. Job steps were inspected to confirm that the test/build steps ran rather than being skipped.

| Area | Recorded result |
| --- | --- |
| Backend Full Verify | 9,077 tests, zero failures/errors, 80 skipped. Thus 8,997 passed. |
| Backend line coverage | 86.1%, above the configured 80% baseline. |
| Frontend unit/widget shards | 3,377 + 3,362 + 3,194 + 3,185 = 13,118 passed; ten skipped across four shards. |
| Frontend line coverage | 70.5%, above the configured 70% baseline. |
| Web build | Successful. |

These are GitHub run results, not local frontend results. The workflow explicitly excludes E2E and integration scope. Passing CI does not close those gates. The quality policy still uses `report_only`; a successful quality job does not mean every security or quality finding is resolved.

The branch-protection endpoint returned 404 and the effective branch-rule endpoint returned an empty list to this account. This does not prove that required reviews or bypass rules are absent. Maintainer confirmation remains needed.

## Local backend regression and repair

A clean Java 17/Maven run on the unmodified reviewed SHA executed 9,077 tests: one failure, zero errors and 80 skipped. The failure was `KvsAudioTranscodeServiceTest.toWav_transcoderFails_throwsWithExitCodeAndOutput`. Java on this macOS host returned a different diagnostic from the text the test expected.

PR [#429](https://github.com/umgc/2026_fall_careconnect/pull/429) is merged, but the newer clip/window API brought back an executable-dependent fixture. This change restores its deterministic process failure approach for the current `KvsAudioClip` and list-based command API. It checks the input argument, exit code, output text and temporary-output cleanup. Production audio code and the newer clip-window assertions are unchanged.

The repaired source passed 12 targeted tests (11 audio tests and one database-isolation test), with zero failures, errors or skips. Checkstyle reported zero violations. The full suite was not rerun after this test-only fix. The initial failure is retained as evidence, not relabeled as a passing baseline. Neither this fixture nor the CI build proves real ffmpeg conversion or clinical workflow behavior.

## Storage and trust-boundary updates

Read these facts at the reviewed source SHA:

- `EhrRetentionWorker` now lists `ehr_condition_record`, as well as medication and observation projections. Earlier inventory text saying Condition is absent is stale.
- The worker does not list `ehr_encounter_record` or `ehr_appointment_record`. Do not assume that Condition coverage establishes their cleanup.
- `CernerOAuthService.disconnect` removes Oracle Health credentials and records an audit event. It does not call the shared source purger.
- `EhrSourceDataPurger` deletes mirror/raw/identity/conflict/crosswalk rows. It has no explicit Condition/Encounter/Appointment deletion in this source.
- PR [#483](https://github.com/umgc/2026_fall_careconnect/pull/483) merged unique Cerner bean wiring and authenticated allergy transport. Code presence and focused tests are distinct from a secure deployed smoke test.
- [CR-2 issue #305](https://github.com/umgc/2026_fall_careconnect/issues/305) is closed with an October 30 Eastern-time "Implementation complete" comment. The older blanket description of CR-2 as merely proposed is stale. That closure does not itself fill every policy, controlled-document or acceptance field in Team C's decision register.

No retention period, deletion behavior, consent model or organization boundary is chosen by this review. Shared owners must record the accepted behavior and its test evidence. No production data or credentials were accessed.

## Technical design and test-plan handoff

PR [#448](https://github.com/umgc/2026_fall_careconnect/pull/448) contains the repository-wide and Team C M4 TDDs and their source manifest. It is open, mergeable and approved by cschel at the review check. Its documents are pinned to October 27 source `d730b752`. Its successful documentation checks do not test today's application state.

Use this report as the dated source delta for the newer retention, Cerner wiring and test-fixture changes. Review and merge #448 through the normal team process. Then reconcile controlled SRS, API and mapping versions with the Test Lead.

The current `docs/testing/m4-test-summary.md` still says **Not Run**, with release candidate **TBD**. It remains the QA owner's decision record. This review neither fills a release disposition nor appoints a final candidate.

## Final gates kept open

| Gate | Evidence still needed | Route |
| --- | --- | --- |
| Candidate | Accepted commit, scope and build/config version | Team Lead and QA |
| Design/API/model | Controlled versions, checksums and mapping acceptance | Shared owners and Test Lead |
| Cerner workflow | Required contract, PostgreSQL, paging, secure sign-in and end-to-end results | Assigned developers/test owners |
| Privacy/accessibility | Independent scoped review and manual interface evidence | Named reviewers |
| Defects/skips | Disposition and retest evidence, including reasons for required skipped cases | QA and owners |
| Source policy | Recorded disconnect, retained access and normalized-store decisions | Shared architecture/Team B/Team Lead |
| Handoff | Dependency 2.5, accepted package, receiver/channel, delivery and receipt | Team Lead and receiver |

## Draft lessons refresh

1. Pin tests and source to the same commit. A later sync can replace a previously merged fix.
2. Control subprocess outcomes in unit tests. Host-specific error text is not a stable fixture.
3. Read CI job steps as well as the green badge. Record skipped tests and excluded workflow areas.
4. Date storage findings. A shared retention change can make an older gap list wrong.
5. Preserve authorship and task scope. Team-level work is not proof that each named peer completed it.
6. Keep preparation, approval, delivery and receipt as separate events. A ZIP or merged index is not a handoff receipt.
7. Treat a closed change request as new evidence to reconcile, not automatic acceptance of every related policy.
8. Keep AI-assisted elapsed time separate from the user's personal labor hours.

## Source map

The companion JSON manifest records paths and SHA-256 hashes for the reviewed implementation and test-plan sources. It also identifies the local test patch separately. Use the original source SHA to reproduce the baseline, then apply the reviewed test change. No historical result is carried forward as a new pass.
