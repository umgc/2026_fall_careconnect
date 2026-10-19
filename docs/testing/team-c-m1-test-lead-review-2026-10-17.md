# M1 design and test packet for Test Lead review

October 17, 2026, Eastern Time. WBS 4.2.11. Prepared for Terence Boyce with Codex assistance.

## Review baseline

Team C code baseline: `36dbdf13bad976418ceade39878c540bbe989856` (merge of PR #347).
This packet keeps the 26 historical M1 work packages. They cover the team, not just Terence.
The live workbook assigns Terence four open M1 assessment/design tasks, one open M2 task,
one open M3 task, and two open M4 tasks.

The C1 IDs below are the historical WBS labels. They are not controlled SRS requirement IDs.
The code-based [M3 trace](m3-traceability-matrix.md) is a separate working QA baseline.
No approval of a resource set, interface, or release is implied by using it.

## Design and test basis

| Area | Implemented design or boundary | Executable proof | Limits |
| --- | --- | --- | --- |
| Locale picker | LocaleProvider, generated AppLocalizations and LanguagePicker | `language_picker_test.dart`: WBS-4.2.5 changing language updates visible text without restarting; plus locale provider and localization suites | English, Spanish, and system-default test scope. No whole-app translation claim. |
| Allergy mapping | Pure CernerAllergyMapper with server-supplied patient reference | CernerAllergyMapperTest; CernerAllergyFixtureCompatibilityTest | Fixed synthetic compatibility checks, not vendor/profile approval. |
| Provisional route | CernerAllergyController, off unless enabled; service and access-policy interfaces | CernerAllergyControllerTest; CernerAllergyControllerConfigurationTest | Mocks and route-registration checks do not run the full real security chain. |
| Patient/Appointment storage | CernerResourceMapper and CernerStorageAdapter prototype | CernerResourceMapperTest; CernerStorageAdapterTest | Mock repositories; no PostgreSQL rollback/concurrency or encryption proof. |
| H2 test-schema rules | Candidate nullable generated keys enforce pending-only question and active-only consent uniqueness | SchemaPatchRunnerH2HeldItemTest; SchemaPatchRunnerH2ConsentTest | In-memory compatibility checks; PostgreSQL SQL is unchanged. |
| Email test setup | Existing Gmail status endpoint, synthetic JWT actor, distinct target patients | EmailOAuthFlowE2ETest | Real controller/access and signed-state behavior, with mocked Google exchange and credential store. No real OAuth provider check. |
| Build and test environment | Flutter frontend; JDK 17 Spring backend; report-only CI quality policy | October 17 validation report and saved run logs | Full failures and missing admin evidence must stay visible. |

Use [the task validation report](team-c-task-validation-2026-10-17.md) for commands,
versions, counts, fixes, and exact before/after results. Planned cases are not pass evidence.

## All 26 M1 work packages

The design and planned method columns retain the existing M1 trace. The final column is
this review's limited evidence check. For rows not executed, the finding is Not verified.

| WBS | Requirement / acceptance focus | Design or control link | Planned verification and evidence | October 17 evidence state |
| --- | --- | --- | --- | --- |
| C1.1.1 | Scope, objectives, MVP, success measures | Project Plan/SRS controlled scope | Document review against approved charter; unresolved items listed | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.1.2 | RACI, decision rights, cadence, separation of duties | Team governance/RACI | Roster and reviewer-independence inspection | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.1.3 | WBS, schedule, estimates, RAID, change/communication/buffer | Integrated management baseline | Cross-document consistency and due-date check | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.2.1 | Each member builds/runs locally with evidence | Developer setup/runbooks | Per-member clean setup, build, launch, screenshot, and version evidence | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.2.2 | Reproducible build, tests/failures, protections, CI gaps | `TEAM_C_REPOSITORY_BUILD_CI_BASELINE.md` | Clean-clone Flutter/Maven builds; full tests; live branch-rule capture | Partly met: clean-checkout build/test assessment is recorded in the October 17 validation report. Failures remain evidence, not a passing release. Detailed branch-rule access is not verified. |
| C1.2.3 | AWS inventory, access/cost/secrets/gaps | AWS architecture and inventory | Read-only account inventory; IAM/cost alarm/config review without credentials | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.2.4 | Component/data flow, l10n gaps, full handoff inventory | `TEAM_C_FRONTEND_ARCHITECTURE_AUDIT.md` | Artifact review; reproduce catalog scan/generation/focused tests | Met for audit scope: PR #79 merged. No new whole-app architecture or accessibility acceptance is claimed. |
| C1.3.1 | Stakeholder evidence, backlog, decisions, roles, allocation | Backlog/decision log | Meeting-record review; trace each decision to owner/milestone | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.3.2 | Provisional SMART/Cerner requirements and acceptance criteria | SRS Cerner TBD section | Requirements inspection for testability, assumptions, and TBD markers | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.3.3 | l10n, WCAG, security, privacy, reliability, performance requirements | localization audit and NFR catalog | Requirement quality review; no orphan/ambiguous NFRs | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.3.4 | RTM with no orphaned committed requirements | This matrix plus controlled RTM | Automated/manual bidirectional trace review | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.4.1 | Cerner sandbox, auth, endpoints/resources, quotas | interface inventory | Verify official capability/config in sandbox; retain synthetic evidence | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.4.2 | Repeatable synthetic Cerner connectivity/retrieval spike | connector spike design | Contract/integration test for authorization and resource retrieval | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.4.3 | Mapping, provenance, comparison keys | `TEAM_C_CERNER_DATA_MAPPING_PROVENANCE_OPTIONS.md` | Mapping contract tests using confirmed synthetic bundles; replay/conflict tests | Partly met: Patient/Appointment and allergy code are merged; fixed fixture outputs and offline tests exist. Verified vendor profiles, approved mapping rules, and real storage checks remain open. |
| C1.4.4 | Threat model, minimization, RBAC, accessible states | `TEAM_C_CERNER_TRUST_BOUNDARY_ACCESSIBILITY_DESIGN.md` | Negative auth/scope tests; logging/storage review; keyboard/AT state tests | Partly met: merged boundary guidance, route gate and wrong-patient tests exist. Real security/consent, storage/encryption, and manual accessibility review remain open. |
| C1.5.1 | l10n tooling and ARB workflow validated | localization audit; `l10n.yaml`; ARB catalogs | Generate localization; parity scan; focused tests | Partly met: flutter pub get and gen-l10n succeeded; 89 focused locale/picker/catalog tests passed on October 17. This does not prove every translation or workflow. |
| C1.5.2 | Deferred-item disposition confirmed | decision log / localization backlog | Team/client approval record and backlog state inspection | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.5.3 | Four named workflows fully localized | Flutter workflow implementation | Widget/integration tests per workflow and non-English screenshots | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.5.4 | Locale-switch regression and missing-string scan | localization test plan | blocking parity scan; locale-switch tests; RTL/manual review | Met for the tested English/Spanish/system-default picker scope: 89 focused tests passed. LanguagePicker test WBS-4.2.5 checks visible text and saved preferences. RTL/device-wide scope is not verified. |
| C1.5.5 | Reviewed code merged, dev deployed, smoke-tested, demonstrated | CI/CD and demo runbook | remote PR/merge evidence; deployment ID; smoke checklist; demo evidence | Partly met: PR #331 independently approved and merged; PR #347 also approved and merged. Deployment, smoke, and demo evidence are not established by those merges. |
| C1.6.1 | Consistent Project Plan/SRS with real M1 content | controlled document set | cross-artifact terminology, scope, date, WBS, risk, and TBD review | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.6.2 | Initial design plus executable test strategy; every M1 requirement linked | this baseline and linked design artifacts | Test Lead review; execute applicable suites; reconcile results/defects | Partly met: all 26 M1 rows remain linked to design and test methods. Controlled SRS links and Test Lead decision remain open. |
| C1.6.3 | Accurate programmer/operations/user procedures | repository guides and runbooks | clean-user procedure test; verify commands, APIs, and limitations | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.6.4 | Actual results, executors, defects, accessibility/WCAG evidence | test report/VPAT | reconcile raw results to report; audit executor, date, environment, defects | Partly met for test reporting: dated runs and failure inventories exist. Manual accessibility/VPAT and full release acceptance are not verified. |
| C1.6.5 | Fresh accurate marketing/usage cuts | approved demo script and evidence list | feature-by-feature claim verification against working build | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |
| C1.6.6 | Package QA, sign-off, filenames, logs, on-time submission | submission checklist | independent cross-artifact review and destination readback | Not verified in this run. The dated M1 baseline retains prior evidence; no new execution or approval is claimed for this work package. |

## Test Lead decisions needed

| Decision | Proposed review action | Status |
| --- | --- | --- |
| Controlled requirements | Name the approved SRS version and map each applicable requirement to design, exact test method, and result. Record gaps rather than inventing IDs. | Not reviewed |
| M1 trace acceptance | Check all 26 rows and record exceptions, reviewer, date, and accepted scope. | Not reviewed |
| Current test failures | Review the current failure inventory and assign each open defect an owner and disposition. A passing small suite does not accept a failing broad suite. | Not reviewed |
| Cerner contract/model | Name the approved resource set, patient/source rules, schema, error contract, and API checksum. | Not reviewed |
| Test levels | Keep offline mapper proof apart from HTTP contract, real security, database, live sandbox, and UI/assistive-technology proof. | Not reviewed |
| Closure of 4.2.11 | Record Test Lead acceptance of the design/test baseline. General PR approval alone is not a named Test Lead decision. | Not reviewed |

This packet is ready to inspect. It has not been sent as a message to the Test Lead,
and no decision has been entered on the Test Lead's behalf.
