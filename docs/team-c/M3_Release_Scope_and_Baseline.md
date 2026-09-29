# Team C M3 Release Scope and Baseline

Prepared: September 27, 2026 (America/New_York).  
Architecture owner: Technical Architect.  
Technical Lead and QA/Test Lead: Tiffany.  
Team Lead: Jonathan Barreto.  
Owner update: September 27, 2026 (America/New_York).  
Status: **Task 1 planning record prepared. Final release commit and readiness remain Not verified.**

## 1. Scope decision

The intended M3 release includes Team C's Cerner integration and language work, plus the operations, tests, and documents needed to support them. Use the saved WBS C3.1–C3.5 as the scope source. Do not reduce that scope just because a local prototype covers less.

**Scope decision confirmed for this plan:** Include the Cerner prototype in the intended M3 scope and list its remaining integration gaps as required work.

This means bringing the needed mapper and adapter work into the app through review. It does not mean shipping the isolated sandbox as a second product or accepting all its copied dependencies as the final design.

The WBS says its three-tranche language schedule is a proposal, not an instructor-confirmed schedule. This record adopts it as the local planning basis. Later team/client changes must be recorded; none were verified in this task.

Source: [CareConnect WBS v2](</Volumes/TerenceB/SWEN670/input/Project_Materials/CareConnect WBS v2 Doc.docx>), Team C scope text and tables 69–73. Read with [M3 gap review](</Volumes/TerenceB/SWEN670/output/M3/M3_Design_and_Test_Gap_Review.md>).

## 2. Branch and commit plan

**Intended integration branch for this plan: `team-c-develop`.** Saved Team C review logs name this target. No branch was created, switched, merged, reset, or pushed.

| Role | Branch or reference | Exact commit | What it means |
| --- | --- | --- | --- |
| App and document starting snapshot | feature/team-c-local-work-review-20260925 | 50d30281d8c3058351b602d949dc37bf39aba807 | Main local checkout inspected; clean. This is an input to integration, not the final M3 release. |
| Cerner prototype input | feature/team-c-cerner-storage-review-20260925 | ec569449652c6e9328d95d9148b9354a901d2d77 | Separate local checkout inspected; clean. Required work must be reviewed and integrated. |
| Cached integration-target reference | origin/team-c-develop | 87f42ff13b8e243e5f2191be72a2ec4c3a14f7b5 | Locally stored reference only. It was not refreshed and may be stale. Do not use it as proof of the current remote tip. |
| Final M3 release commit | Pending integrated team-c-develop state | **Not assigned / Not verified** | Record the exact combined commit after integration and before release tests. |
| Build and configuration | Pending | **Not verified** | Record the build ID, environment, schema version, and non-secret settings used for the release tests. |

Naming a starting commit does not make it a release candidate. Neither inspected checkout contains a verified combined M3 release. A final hash cannot be supplied honestly from this review alone.

Evidence: local read-only Git checks on September 27; [saved Team C target-branch log](</Volumes/TerenceB/SWEN670/src/2026_fall_careconnect/docs/team-c/review-evidence-2026-09-25/Cerner_Backend_Review_PR_Work_Log_2026-09-17.md>). That log is dated September 17; its PR/CI state is historical.

Checkouts:

- [Main app and documents](</Volumes/TerenceB/SWEN670/src/2026_fall_careconnect/>)
- [Cerner prototype](</Volumes/TerenceB/SWEN670/sandbox/cerner-compatibility-2026-09-24/>)

## 3. Required scope, owners, and present evidence

All rows below remain in the planning scope. Status is based on the saved gap review and limited local checks, not a new full feature audit. “Not verified” means proof has not been established here; it does not mean no one has done the work.

Owner roles come from the WBS. Names come from [roles.xlsx](</Volumes/TerenceB/SWEN670/input/Project_Materials/roles.xlsx>), Sheet1 A13:C18, and the Technical Architect's role clarifications on September 27. The clarifications take precedence over shorthand in the sheet.

| Role | Named owner | Basis |
| --- | --- | --- |
| Team Lead | Jonathan Barreto | Confirmed role assignment |
| Technical Architect | Technical Architect | Confirmed role assignment |
| Technical Lead and QA/Test Lead | Tiffany | Confirmed role assignment |
| UI/UX Developer | Rashid | Confirmed name and role assignment |
| Backend Developer | Sahil | Roles sheet |
| Backend Support Developer | Donald | Roles sheet and role clarification |
| Business Lead | Zack | Roles sheet and role clarification |
| Documentation Lead | Zack | Confirmed role assignment |
| AWS/DevOps Lead | Donald | Confirmed role assignment |

Tiffany holds the Technical Lead and Test Lead roles. The Technical Architect provides architecture support. Named roles do not prove task completion. The task tables use the confirmed role assignments.

**Cerner team:** Tiffany and Rashid work on Cerner, with the Technical Architect providing architecture support. Sahil and Donald provide backend support for Cerner. This team supports all Cerner-related work below, including operations, tests, and documents. Donald retains AWS/DevOps ownership; Tiffany retains technical and test leadership. Individual Cerner task splits are not specified by this role update.

| WBS | Required outcome | Execution owner role | Present evidence/status |
| --- | --- | --- | --- |
| C3.1.1 | Fetch the agreed synthetic Cerner records; handle pages, rate limits, and safe errors. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Open: full client and app flow not proved. |
| C3.1.2 | Map records without losing source values or their source trail. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Partial: saved mapper tests; release integration open. |
| C3.1.3 | Store data with tenant/user limits, constraints, encryption, migrations, and rollback. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Partial: prototype models and mock stores; real schema and rollback proof open. |
| C3.1.4 | Handle retries, timeouts, partial runs, and repeat requests without duplicate stored records. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Partial: focused mock tests; real database and job flow open. |
| C3.1.5 | Show connection state; renew, revoke, and disconnect access. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Not verified: full grant lifecycle proof needed. |
| C3.1.6 | Show Cerner data with role checks, source labels, accessible layout, and all stated UI states. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) | Not verified: linked app journey needed. |
| C3.2.1 | Wire the 12 named final-tranche language workflows listed below. | Rashid (UI/UX) | Not verified: current per-workflow completion evidence needed. |
| C3.2.2 | Run locale regression across the full wired catalog in at least two non-English locales. | Tiffany (QA/Test Lead) | Not verified: current catalog-wide results needed. |
| C3.2.3 | Check text growth, right-to-left layout where used, and screen-reader locale behavior. | Tiffany (QA/Test Lead) | Not verified: release-level evidence needed. |
| C3.3.1 | Document repeatable environments, infrastructure, access, network paths, and cost controls. | Donald (AWS/DevOps) | Not verified: current release setup proof needed. |
| C3.3.2 | Build, scan, test, package, and deploy through gates that block critical failures. | Donald (AWS/DevOps) | Gap: reviewed local gate policy uses report_only. |
| C3.3.3 | Keep Cerner, database, and AWS settings outside code; control and rotate secrets. | Donald (AWS/DevOps) | Not verified: release configuration and safe-log checks needed. |
| C3.3.4 | Provide safe logs, metrics, health checks, alerts, and correlation IDs. | Donald (AWS/DevOps) | Not verified: integration/job evidence needed. |
| C3.3.5 | Rehearse data-store restore and rollback. | Donald (AWS/DevOps) | Not verified: drill records needed. |
| C3.4.1 | Test connect, import, view, disconnect, and the localized catalog end to end. | Tiffany (QA/Test Lead) | Not verified: focused mapper tests do not meet this. |
| C3.4.2 | Pass security, privacy, access-denial, scan, encryption, and data-minimization checks. | Tiffany (QA/Test Lead) | Not verified: full release checks needed. |
| C3.4.3 | Have non-authors check each shipped screen with automation, contrast, keyboard, TalkBack, and VoiceOver. | Tiffany (QA/Test Lead) | Not verified: per-screen records needed. |
| C3.4.4 | Measure import, display, job, and API targets under defined load and failures. | Tiffany (QA/Test Lead) | Not verified: agreed targets and run results needed. |
| C3.4.5 | Pass the cumulative suite or approve exceptions; leave no open Severity 1 defects. | Tiffany (QA/Test Lead) | Not verified: final test/defect review needed. |
| C3.5.1 | Update the Project Plan and SRS, including delivered/deferred scope and tracked changes. | Zack (Documentation) | Not verified: M3 package not audited in full. |
| C3.5.2 | Match the TDD and test plan to the actual M3 release. | Tiffany (Technical Lead + QA/Test Lead); Technical Architect (architecture support) | Partly met: six areas in the saved gap review. |
| C3.5.3 | Update developer and operations guides for build, setup, deploy, diagnosis, and recovery. | Zack (Documentation) + Donald (AWS/DevOps) | Not verified: M3 guide walkthrough needed. |
| C3.5.4 | Align the User Guide, Test Report, and VPAT with the working build and known limits. | Zack (Documentation) + Tiffany (QA/Test Lead) | Not verified: release-linked records needed. |
| C3.5.5 | Refresh marketing and usage videos using the complete core flows and synthetic data. | Zack (Documentation) | Not verified: M3 cuts not checked here. |
| C3.5.6 | Check the package, versions, evidence, contributions, signoff, and submission completeness. | Jonathan Barreto (Team Lead) | Not verified: final package check needed. |

Source locators: C3.1 is table 69; C3.2 table 70; C3.3 table 71; C3.4 table 72; C3.5 table 73 in the WBS. Each table starts with a header row. The estimates in that source are not a new schedule or commitment.

The 12 workflows named in C3.2.1 are: EVV Dashboard, Visit Schedule, Wearables, Smart Devices, Fall Alert, Add Patient, Family, Social Feed, Gamification, USPS Mail Digest, Caregiver Shift Scheduling, and Submit to HHAExchange.

C3.2.2 also requires regression across the full wired catalog, described in the WBS as roughly 22 workflows. Do not treat the 12 new workflows as the full regression scope. Confirm the exact catalog and test locales before execution.

## 4. Required Cerner integration work

The prototype is included as work to finish. The owners below need proof against the final combined commit.

| Gap | Work needed | Proof needed | Owner role |
| --- | --- | --- | --- |
| Shared EHR dependencies | Replace the isolated copied-input arrangement with the agreed shared code and schema. Review the 17 input files as other team members' work. | Reviewed dependency source and compatible migrations. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) |
| Client and routes | Wire the vendor client, HTTP routes, grant flow, time bounds, and paging to the app. | Connect-to-import-to-view test using the agreed synthetic tenant/resources. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) |
| Actor and patient access | Enforce caller permissions, tenant limits, patient links, revoke, and disconnect across the full path. | Allowed and denied cases, including unrelated patients and revoked links. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) |
| Durable storage | Implement the agreed migrations, constraints, source history, retention, and Patient conflict handling. | Real database results, repeat/concurrent import checks, rollback, and recovery. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support); Donald (AWS/DevOps) |
| App wiring and jobs | Register the required services and transaction boundaries; finish sync, retry, and partial-failure behavior. | Full app wiring tests and safe recovery after failed writes. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) |
| UI and language | Build role-scoped data views and the required loading, empty, error, refresh, and offline states. | Screen, locale, device, keyboard, and screen-reader results. | Tiffany + Rashid; Technical Architect (architecture support); Sahil + Donald (backend support) |
| Release operations | Make critical gates block; document and prove configuration, safe logs, alerts, restore, and rollback. | Release pipeline evidence and rehearsed operating steps. | Donald (AWS/DevOps); Tiffany + Rashid (Cerner); Technical Architect (architecture support); Sahil (backend support) |

Evidence: [prototype review](</Volumes/TerenceB/SWEN670/sandbox/cerner-compatibility-2026-09-24/docs/CERNER_COMPATIBILITY_REVIEW.md>), [prototype test record](</Volumes/TerenceB/SWEN670/sandbox/cerner-compatibility-2026-09-24/docs/CERNER_COMPATIBILITY_TEST_RESULTS.md>), and [M3 gap review](</Volumes/TerenceB/SWEN670/output/M3/M3_Design_and_Test_Gap_Review.md>).

The saved 79-test result is useful focused proof. It is not a full M3 result. It skipped Checkstyle and did not prove real database transactions, Spring wiring, or live Cerner access. No new tests were run for this scope record.

## 5. Deferred and unresolved scope

No new WBS requirement is removed by this document.

- **Prior handoff deferrals:** The WBS names new Dashboards/Welcome-page UI text and the Email Verification widget as two deferred areas pending final implementation. Their current disposition still needs confirmation. Do not confuse the first item with the explicitly included EVV Dashboard workflow.
- **Cerner resource set:** Patient and Appointment have useful local evidence. The full confirmed synthetic resource set, tenant, and access scopes remain open. Do not silently reduce the WBS to those two resources.
- **Language choices:** The WBS requires at least two non-English test locales. Name the chosen locales and full workflow list before tests begin.
- **Secondary React/Vite UI:** The older frontend audit describes a separate preview. This plan uses the primary Flutter app as the working UI assumption; a claim that the preview ships in M3 needs an explicit scope update.
- **Dates and people:** Named owners are listed in section 3. Documentation and AWS/DevOps assignments are confirmed. Confirm the delivery date with the team.

Sources: WBS Team C scope and C1.5.2; [dated frontend audit](</Volumes/TerenceB/SWEN670/src/2026_fall_careconnect/docs/TEAM_C_FRONTEND_ARCHITECTURE_AUDIT.md>). The audit is older evidence, not a fresh UI completion check.

## 6. How the team can close the baseline decision

This document supplies the scope list, intended branch, exact local input commits, role owners, and integration gaps. It does not claim the final release baseline is fixed.

To finish the release-baseline decision:

1. Confirm the current team-c-develop tip and any newer team work through a fresh repository review. Preserve the local snapshots above.
2. Confirm the resource set, locales, deferred items, and delivery date. Jonathan leads the team review, with Tiffany covering technical and test decisions and the Technical Architect covering architecture.
3. Have the required changes reviewed and combined into the intended branch. That is a separate code/integration task.
4. Record the exact combined commit, build ID, schema version, and test configuration. Use that same baseline in the TDD and test plan.
5. Freeze that candidate for tests. If code changes, record the new commit and rerun affected checks.

M3 is ready for release assessment only when C3.4.5 is supported: the cumulative suite passes or exceptions are approved, and no Severity 1 defects remain open. Final package signoff stays with Jonathan Barreto as Team Lead. Tiffany holds the separate Technical Lead and QA/Test Lead roles.

## 7. Guides and checks for this record

Read: [AGENTS.md](</Volumes/TerenceB/SWEN670/AGENTS.md>), [START_HERE.md](</Volumes/TerenceB/SWEN670/START_HERE.md>), [Project-Planning.md](</Volumes/TerenceB/SWEN670/notes/project-guides/Project-Planning.md>), [M3.md](</Volumes/TerenceB/SWEN670/notes/project-guides/M3.md>), and [USING_WITH_OPENAI_CODEX.md](</Volumes/TerenceB/SWEN670/notes/project-guides/USING_WITH_OPENAI_CODEX.md>).

The prototype-scope question was answered before this file was written. The WBS rows were read directly from the DOCX text, with table locators; no layout verification was claimed. Local branch names, commits, and clean status were checked. Evidence links and saved text were checked.

The initial task created this planning document. The September 27 owner update changed only this document to record the supplied names and confirmed role assignments. Repository state and test results were not rechecked for this owner update. Source files, prior reports, code, Git state, and external notes were left unchanged. No build, test, remote refresh, team message, upload, or submission was performed.
