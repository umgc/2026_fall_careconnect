# M1 trace review

Reviewed October 13, 2026, for WBS 4.2.11.

This retains all 26 rows from the earlier personal M1 design/test baseline. The last column below is historical September 3 evidence, not a new test result. Earlier drafts are part of [PR #157](https://github.com/umgc/2026_fall_careconnect/pull/157); Test Lead acceptance and controlled requirement links remain open.

Use the [current WBS review](team-c-wbs-review-2026-10-13.md) for executed checks, current design and review gates, and the [M3 trace](m3-traceability-matrix.md) for current named allergy methods. Historical Not Run or Blocked labels below are retained to avoid inventing acceptance of other team members' work. The trace structure is present; approval and complete execution remain partly met.

| WBS | Requirement / acceptance focus | Design or control link | Planned verification and evidence | Current evidence state |
|---|---|---|---|---|
| C1.1.1 | Scope, objectives, MVP, success measures | Project Plan/SRS controlled scope | Document review against approved charter; unresolved items listed | Not Run — approved source not verified |
| C1.1.2 | RACI, decision rights, cadence, separation of duties | Team governance/RACI | Roster and reviewer-independence inspection | Not Run — roster/reviewer unavailable |
| C1.1.3 | WBS, schedule, estimates, RAID, change/communication/buffer | Integrated management baseline | Cross-document consistency and due-date check | Not Run — authoritative package not verified |
| C1.2.1 | Each member builds/runs locally with evidence | Developer setup/runbooks | Per-member clean setup, build, launch, screenshot, and version evidence | Not Run for team |
| C1.2.2 | Reproducible build, tests/failures, protections, CI gaps | `TEAM_C_REPOSITORY_BUILD_CI_BASELINE.md` | Clean-clone Flutter/Maven builds; full tests; live branch-rule capture | In Progress — macOS build Pass; 88 focused tests Pass |
| C1.2.3 | AWS inventory, access/cost/secrets/gaps | AWS architecture and inventory | Read-only account inventory; IAM/cost alarm/config review without credentials | Not Run |
| C1.2.4 | Component/data flow, l10n gaps, full handoff inventory | `TEAM_C_FRONTEND_ARCHITECTURE_AUDIT.md` | Artifact review; reproduce catalog scan/generation/focused tests | Pass locally — independent acceptance pending |
| C1.3.1 | Stakeholder evidence, backlog, decisions, roles, allocation | Backlog/decision log | Meeting-record review; trace each decision to owner/milestone | Not Run |
| C1.3.2 | Provisional SMART/Cerner requirements and acceptance criteria | SRS Cerner TBD section | Requirements inspection for testability, assumptions, and TBD markers | Blocked — Cerner program/client confirmation missing |
| C1.3.3 | l10n, WCAG, security, privacy, reliability, performance requirements | localization audit and NFR catalog | Requirement quality review; no orphan/ambiguous NFRs | In Progress — architecture evidence exists |
| C1.3.4 | RTM with no orphaned committed requirements | This matrix plus controlled RTM | Automated/manual bidirectional trace review | In Progress — M1 WBS linked here; requirement IDs/source approval pending |
| C1.4.1 | Cerner sandbox, auth, endpoints/resources, quotas | interface inventory | Verify official capability/config in sandbox; retain synthetic evidence | Blocked — no verified sandbox access |
| C1.4.2 | Repeatable synthetic Cerner connectivity/retrieval spike | connector spike design | Contract/integration test for authorization and resource retrieval | Blocked — connector and credentials absent |
| C1.4.3 | Mapping, provenance, comparison keys | `TEAM_C_CERNER_DATA_MAPPING_PROVENANCE_OPTIONS.md` | Mapping contract tests using confirmed synthetic bundles; replay/conflict tests | Blocked — preliminary design only |
| C1.4.4 | Threat model, minimization, RBAC, accessible states | `TEAM_C_CERNER_TRUST_BOUNDARY_ACCESSIBILITY_DESIGN.md` | Negative auth/scope tests; logging/storage review; keyboard/AT state tests | In Progress — initial design exists; dependency/review pending |
| C1.5.1 | l10n tooling and ARB workflow validated | localization audit; `l10n.yaml`; ARB catalogs | Generate localization; parity scan; focused tests | Pass locally — 88 focused tests on 2026-09-03 |
| C1.5.2 | Deferred-item disposition confirmed | decision log / localization backlog | Team/client approval record and backlog state inspection | Not Run — approval evidence absent |
| C1.5.3 | Four named workflows fully localized | Flutter workflow implementation | Widget/integration tests per workflow and non-English screenshots | Not Run — audit says migration remains open |
| C1.5.4 | Locale-switch regression and missing-string scan | localization test plan | blocking parity scan; locale-switch tests; RTL/manual review | In Progress — focused picker/locale tests Pass; broader gate open |
| C1.5.5 | Reviewed code merged, dev deployed, smoke-tested, demonstrated | CI/CD and demo runbook | remote PR/merge evidence; deployment ID; smoke checklist; demo evidence | Not Run — no current remote/deployment proof |
| C1.6.1 | Consistent Project Plan/SRS with real M1 content | controlled document set | cross-artifact terminology, scope, date, WBS, risk, and TBD review | Not Run |
| C1.6.2 | Initial design plus executable test strategy; every M1 requirement linked | this baseline and linked design artifacts | Test Lead review; execute applicable suites; reconcile results/defects | In Progress — baseline created; review/execution incomplete |
| C1.6.3 | Accurate programmer/operations/user procedures | repository guides and runbooks | clean-user procedure test; verify commands, APIs, and limitations | Not Run |
| C1.6.4 | Actual results, executors, defects, accessibility/WCAG evidence | test report/VPAT | reconcile raw results to report; audit executor, date, environment, defects | Not Run |
| C1.6.5 | Fresh accurate marketing/usage cuts | approved demo script and evidence list | feature-by-feature claim verification against working build | Not Run |
| C1.6.6 | Package QA, sign-off, filenames, logs, on-time submission | submission checklist | independent cross-artifact review and destination readback | Not Run |
