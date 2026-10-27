# Current FHIR storage inventory for Team B review

Reviewed October 22, 2026 (America/New_York). Author role: Team C Technical Architect.
Status: review draft. Related work: CR-2 / issue #305 and WBS 4.2.9, 4.2.10, 4.2.11.

## What this review establishes

This review has two explicit code references: the shared-branch baseline and the unmerged PR #391 implementation described below. The baseline is a code-based map of FHIR storage on `team-c-develop`, at commit `21d5a521e87f70eb9c304bd5d993d24cdad9adad`. It covers the Epic, Medicare, athenahealth, and Cerner paths found in this branch. A configured fetch path is not proof that a vendor has granted access or that a live record has been fetched. Team owners must confirm enabled settings, granted scopes, and actual resource use in the target environment.

No schema, service, consent, or source data was changed. No live patient data was read. This draft does not approve CR-2, establish a release candidate, or close Team B's prerequisite. It gives Team B a concrete inventory to check.

The older October 21 plan used a different commit. This review uses a fresh remote-head check and a clean worktree. The original local Docker checkout is preserved.

## PR #391 implementation branch — October 22 follow-up

This section adds Tiffany's implementation from `feature/team-c-cerner-qa-implementation` at `0c991bb525fefbdbbed478441450f56fe828d4e9`. [PR #391][qa-pr] remains open. It is not part of the `21d5a521` shared-branch baseline below. Both branch refs and PR status were checked again for this update. The sections headed **Shared-branch baseline** keep their original scope; their inactive-client and blocked-pagination findings must not be applied to PR #391.

Tiffany's follow-up, supplied by the user October 22, confirms the ownership and pending policy decisions recorded here. That follow-up is a coordination source, not approval of a deletion policy or final QA sign-off.

### Added resource and storage paths

| Resource or boundary | PR #391 implementation | Persistence and limits | Pinned evidence |
| --- | --- | --- | --- |
| SMART connection and access | Discovery, Authorization Code/S256 PKCE, patient context, encrypted access/refresh tokens, expiry/refresh and reauthorization; real access policy uses CareConnect patient-access rules. | Uses `ORACLE_HEALTH`, `ehr_credentials`, `ehr_patient_crosswalk`, and audit events. Feature-gated wiring exists; deployment and secure-sandbox use still need proof. | [OAuth][qa-oauth], [link service][qa-link], [policy][qa-policy], [bean configuration][qa-config] |
| AllergyIntolerance | Production service/access-policy wiring replaces the interface-only gap. Trusted pagination is implemented; it is no longer simply blocked. | Validated original allergy JSON is upserted in `ehr_raw_payload`; normalized response fields are returned. No dedicated normalized allergy table is added. | [Allergy service][qa-allergy], [paged client][qa-http] |
| Patient | Live service foundation performs direct Patient retrieval with trusted crosswalk/SMART context, raw storage and demographic mapping. | Upserts `ehr_source_identity`; rejects unsafe/missing source recency and avoids direct local Patient overwrite. A feature-gated provisional Patient GET endpoint now exists; its response carries source record ID and source update time. Identity rows have no direct raw-row FK; provenance uses the raw patient/source/type/external-ID tuple. | [Patient/Appointment service][qa-patient-appointment], [controller][qa-patient-controller] |
| Appointment | Live service foundation adds bounded date-window search, trusted pagination, patient-participant checks and stale-data protection. | Upserts raw data and `ehr_appointment_record`, with a raw-row link. A feature-gated provisional Appointment GET endpoint now exists and requires start/end instants with start before end. Final contract/date-window policy remains pending. | [Patient/Appointment service][qa-patient-appointment], [HTTP client][qa-http], [controller][qa-patient-controller] |
| Condition | Canonical model, repository, mapper, retrieval service and provisional controller endpoint. | `ehr_condition_record`: patient/source/external condition ID, raw row ID, source version/update time, clinical/verification status, codes/categories/severity/body sites, onset/abatement/date precision and references. | [Clinical service][qa-clinical], [Condition model][qa-condition], [controller][qa-controller] |
| Encounter | Canonical model, repository, mapper, retrieval service and provisional controller endpoint. | `ehr_encounter_record`: patient/source/external encounter ID, raw row ID, source version/update time, status/class/types, period/precision, participants, provider/location and reason/diagnosis/appointment references. | [Clinical service][qa-clinical], [Encounter model][qa-encounter], [controller][qa-controller] |

The branch's clinical/raw writers look up matching source/patient/type/external-ID rows and upsert them; this is not immutable append-only history. The raw save helpers set `photo_stripped=false` and serialize resource JSON. Do not transfer another source's binary-removal guarantees to these writers without review. See [allergy][qa-allergy], [clinical][qa-clinical], and [Patient/Appointment][qa-patient-appointment] services.

### New controller and test evidence at `0c991bb5`

The [Patient/Appointment controller][qa-patient-controller] uses `careconnect.cerner.patient-appointment.enabled=true`. It provides GET `/v1/api/cerner/patients/{patientId}` and GET `/v1/api/cerner/patients/{patientId}/appointments?start=...&end=...`. It checks the principal and patient-access policy before retrieval. Returned views exclude internal database/raw-payload IDs. This is provisional API code, not proof of a deployed endpoint or accepted OpenAPI contract.

The [seven controller-slice tests][qa-patient-controller-test] cover Patient success, Appointment success/empty results, invalid range, denied access, invalid patient ID and expired authorization. The [service contract test][qa-patient-contract-test] checks preservation of external source ID and normalized identity. [Security filter-chain tests][qa-security-test] add Patient/Appointment route coverage. These files were inspected, not rerun for this document update.

Earlier missing-controller statements described `9ef50e4c`; the current findings above supersede that gap. The shared-branch baseline below remains unchanged.

### Disconnect and retention decisions remain open

Current Cerner disconnect removes stored OAuth credentials only. It does **not** remove the crosswalk, raw payloads, or normalized records. Document this as current behavior; do not infer that it is the approved final policy. See [disconnect controller][qa-oauth-controller] and [OAuth service][qa-oauth].

Team B, shared architecture owners, and the Team Lead must decide:

- Whether disconnect deletes or deactivates the crosswalk.
- Whether stored clinical records are deleted, retained, or made inaccessible.
- How consent, auditing and retention apply after disconnect.
- How to handle records Cerner no longer returns.

Raw FHIR rows use `EhrRawPayload`, already in the shared retention framework. The new normalized Condition and Encounter tables are **not** included in [the branch's retention worker][qa-retention]. Their retention/purge rule requires Team B/shared-architecture approval. Options to review include matching raw-payload retention, removing records during source unlinking, and handling source deletions. These are options, not selected policies; Team C must not choose a new rule alone.

### Ownership, test evidence, and review gates

- Tiffany's earlier follow-up assigned remaining Patient/Appointment tests to Donald. The newer branch now contains [controller-slice tests][qa-patient-controller-test], [service tests][qa-patient-test] and a [service contract test][qa-patient-contract-test]. Tiffany/Donald should confirm remaining coverage; do not assign duplicate implementation work.
- Production Patient/Appointment controller code is present. Ongoing implementation ownership remains **owner pending Team Lead/backend confirmation**. Test assignment alone does not establish that owner.
- [Feature Branch CI][qa-ci] and [quality gate][qa-quality] passed for `0c991bb5`. The earlier 231-test result belongs to `9ef50e4c`, not this newer SHA. Current check conclusions were read from GitHub; no new test count is asserted. The workflow runs changed-file checks; this is not a full release test result. No tests were rerun locally for this documentation update.
- Final testing must use the resulting `team-c-develop` commit **after PR #391 is reviewed and merged**. The implementation SHA is a reference, not the final release-testing commit.
- Remaining gates: Team C review/merge of #391; Ian/Team B review of #395; Team Lead/QA review of #396; controller ownership; approved retention/disconnect/deletion rules; unified OpenAPI and canonical-model approval; frontend, E2E, contract and secure-sandbox testing before sign-off. [M4 QA summary][qa-summary] remains a pending execution/sign-off record.

Tiffany confirms she has not taken on Terence's storage inventory, consent analysis, retention analysis, or evidence matrix. Keep those documentation/review tasks with Terence and coordinate policy decisions with the shared owners; avoid duplicating her implementation work.

## Shared-branch baseline: resource coverage

The lists below come from fetch and sync code, not from UI category labels. All source owners should report any additional deployed paths absent from this branch.

| Source/path | Resource types handled by the path | Storage and current limit | Evidence |
| --- | --- | --- | --- |
| Medicare / Blue Button | Patient, Coverage, ExplanationOfBenefit | Raw history plus identity, coverage, and visit rows. Reads use the newest raw copy per external ID. Cache refresh is due after one day. | [MedicareRecordCache][cache], [MedicareService][medicare] |
| Epic | Patient; AllergyIntolerance, Condition, MedicationRequest, MedicationStatement, Observation, DiagnosticReport, Immunization, Procedure, DocumentReference, Encounter, CarePlan, Goal, CareTeam, FamilyMemberHistory, Coverage, Device | `ehr_resource` mirror; raw history when patient/source IDs resolve; selected types also produce search/index events. Feature flag and granted scopes limit actual fetches. | [EpicSyncService][epic] |
| athenahealth | Patient; AllergyIntolerance, Condition, MedicationRequest, Observation, DiagnosticReport, Immunization, Procedure, Encounter, CarePlan, Goal, CareTeam, FamilyMemberHistory, Coverage, Device | Mirror plus raw history on content change. Each type requires its system read scope. DocumentReference is excluded; MedicationStatement is not offered by this path. No Ask AI indexing in this sync service. | [AthenaSyncService][athena] |
| Shared appointment sync | Appointment | Raw row upsert plus `ehr_appointment_record`. The reviewed main-source search found no caller of this sync service; do not count it as a live import. | [EhrAppointmentSyncService][appointments] |
| Cerner appointment prototype | Appointment | Explicitly constructed adapter, not a registered component. Uses the shared raw and appointment tables. No HTTP or account-link flow here. | [CernerStorageAdapter][cerner] |
| Cerner Patient review | Patient | Projection and proposed identity conflicts stay in memory. This adapter does not save the Patient body or conflicts and does not write canonical patient values. | [CernerStorageAdapter][cerner], [CernerResourceMapper][mapper] |
| Cerner allergy boundary | AllergyIntolerance inside a searchset Bundle | Inactive HTTP client and pure mapper; list response has no repository write. Controller is feature-gated and relies on service/policy interfaces. No production implementations found in the reviewed main Java source. | [CernerAllergyHttpClient][allergyclient], [CernerAllergyMapper][allergymapper], [CernerAllergyController][allergycontroller] |

Bundle is a transport envelope in these flows, not proof of a separate stored clinical record. Resource names used only in interface comments or category mappings are not added to this inventory as consumed types.

## Shared-branch baseline: stores, identity, and provenance

| Store | Key and content | Time/history rules | Evidence |
| --- | --- | --- | --- |
| `ehr_source` | Source code, display name, FHIR version, enabled flag. Seed codes include MEDICARE, EPIC, ATHENAHEALTH, ORACLE_HEALTH. A seed is not a working connector. | Shared audit timestamps. | [EhrSource][source], [SchemaPatchRunner][patches] |
| `ehr_patient_crosswalk` | Internal `patient_id`, `source_id`, external patient ID; link state and credential fields also exist for Medicare. Unique source/external and patient/source pairs. Pending links can have no external ID. Medicare token/refresh-token fields are String columns without an encryption converter on this entity; verify storage protection separately from Epic encrypted credential fields. | Link lifecycle is distinct from record retention. Do not match patients by name and date of birth. | [EhrPatientCrosswalk][crosswalk], [MedicareConnectionService][medconnect] |
| `ehr_raw_payload` | Row ID, patient/source IDs, resource type, external record ID, JSONB payload, UTF-8 size, `photo_stripped`. | `retrieved_at` is separate from `created_at`/`updated_at`. Raw record ID alone is not globally unique. Writers differ on append versus overwrite; see below. | [EhrRawPayload][raw] |
| `ehr_resource` | Unique user/source/type/FHIR-ID tuple; status, title, occurred-at string, content hash, full JSON mirror. This store uses a user ID, while canonical tables use a patient ID. | `last_synced_at` and `created_at`. This is a current mirror, not the raw history table. | [EhrResource][mirror] |
| `ehr_source_identity` | Patient/source pair; given/family name, full DOB, phone/email, address, member ID, gender, managing organization, language. | Source update instant plus shared audit timestamps. Medicare cache updates the existing identity row. | [EhrSourceIdentity][identity], [MedicareRecordCache][cache] |
| `ehr_coverage_record` | Patient/source/external coverage ID; subscriber ID, beneficiary, network, payor, status, coverage type, end date. | Source update instant plus audit timestamps. | [EhrCoverageRecord][coverage] |
| `ehr_visit_record` | Patient/source/external visit ID from ExplanationOfBenefit; service date, facility, care team, diagnosis, procedure, prescription, disposition, referral, accident, status, visit type, notes. | Source update instant plus audit timestamps. | [EhrVisitRecord][visit] |
| `ehr_appointment_record` | Patient/source/external appointment ID; optional raw-row link, start/end, status, provider/location/service/reason. | Source created/updated times plus audit timestamps. Prototype use must not be called deployed ingestion. | [EhrAppointmentRecord][appointmentmodel], [EhrAppointmentMapper][appointmentmapper] |
| `ehr_identity_conflict` / `ehr_identity_field_provenance` | Field-level conflict values and resolution; selected field source and timestamp. Conflict values contain patient information. | Pending conflicts are not aged out by the retention worker. Field provenance is deliberately retained. | [EhrIdentityConflict][conflicts], [EhrRetentionWorker][retention], [EhrSourceDataPurger][purger] |
| `ehr_audit_event` | Retrieval outcome/count/actor/time and hashed event details through EhrAuditService. Keep payloads and tokens out of audit details. | The retention worker targets this store; a complete cross-app access-log review is still needed. | [EhrAuditEvent][audit], [EhrAuditService][accessaudit], [EhrRetentionWorker][retention] |
| `ehr_credentials` | User/source, FHIR patient ID/base URL, encrypted token fields, scopes, expiry/state. Record field names only; never copy token values into a review. | Epic disconnect deletes its credential rows. | [EhrCredential][credentials], [EpicOAuthService][epicoauth] |
| Search/index copies | Epic creates transactional index events and retrieval chunks for supported clinical types. These are extra copies to include in lifecycle review. | Epic disconnect removes indexed sources before mirror rows. Outbox/in-flight behavior still needs a live check. | [EpicSyncService][epic], [EpicResourceChunker][chunker] |

## Shared-branch baseline: how each source writes data

**Medicare.** The cache reads stored raw rows newest-first, then selects one per external ID. It appends a raw row only if parsed JSON changed. Patient photos are removed before serialization. It also maps Patient to identity, Coverage to coverage, and ExplanationOfBenefit to visits. Source metadata is retained in raw JSON. Refresh uses the last successful/empty retrieval audit event; a newly emptied cache forces a full fetch. This is cache freshness, not a retention period. See [cache][cache] and [EhrService][ehrservice].

**Epic.** Full sync can use `$everything`, direct Patient read, and typed searches. Delta sync uses a watermark and safety margin. It mirrors only its allowlisted types and applies the status gate. Each resource is saved in its own transaction. The raw write appends a row whenever `upsertAndEmit` reaches it; the method has no unchanged-body early return before that save. Raw writes are skipped when canonical patient/source IDs are missing. The raw writer removes a top-level photo, but the mirror serializes the original resource first. Thus the raw table's stripping flag does not prove the mirror is free of inline binary. See [Epic sync][epic].

**athenahealth.** Each type needs a granted system scope. MedicationRequest also uses `intent=order`. Both mirror and raw JSON pass through `InlineBinary.strip`: Patient.photo and attachment data with a contentType are removed. Raw history is appended only when the hash changes; the mirror's last-sync time moves on each save. A complete type fetch prunes missing mirror records; an incomplete fetch does not. Pruning does not delete old raw history. See [athena sync][athena] and [InlineBinary][binary].

**Cerner/shared Appointment.** Both existing writers look up a matching raw row and overwrite it, unlike the append-only pattern above. The Cerner prototype validates the trusted source/patient link before writes and rejects a stale or unknown version over a timestamped record. It preserves original JSON and maps UTC-normalized times into the appointment. The shared sync uses its mapper directly and does not provide the same prototype checks. The code contains both `client/ehr/EhrApiClient` and `service/ehr/EhrApiClient`; the shared appointment service imports the former, while Epic/athena clients implement the latter. Do not assume those clients are wired into appointment sync. See [prototype][cerner], [shared sync][appointments], and the two interfaces [old][oldclient]/[current][newclient].

**Cerner allergy fields.** The mapper returns source, source record ID, substance text/code, clinical and verification status, severity, recorded date, and reaction text. It rejects another patient's reference and excludes entered-in-error records. The HTTP client rejects a next-page link instead of returning a partial list. No persistent allergy store was found in this path. See [allergy mapper][allergymapper] and [client][allergyclient].

## Shared-branch baseline: retention, delete, unlink, and relink

These are code findings, not legal advice or proof that a job ran in deployment.

| Path | Observed behavior | Review needed |
| --- | --- | --- |
| Scheduled retention | Worker defaults to 7 years and age 25; both conditions must hold. Unknown/unreadable DOB is retained. Targets raw payloads, resolved conflicts, identity snapshots, retrieval audit, coverage, and visits. Years at or below zero disables purge. | Team B must confirm chosen policy, deployed settings, and execution evidence. Mirror, appointment, credential, consent, and search stores are not all covered by this worker. [Worker][retention] |
| Medicare disconnect | Revokes source token where available; transaction deletes raw, identity, coverage, visits, conflicts, and crosswalk. Retrieval audit remains. Cache handles relink after payloads were removed. | Confirm retention-versus-unlink decision and run source-specific lifecycle tests. [Connection][medconnect], [cache][cache] |
| athena disconnect | Transaction calls shared purger for mirror, raw, identity, conflicts, and crosswalk; may revoke import consent when no Epic connection remains. Audit and already applied demographics/provenance stay. | Shared purger does not delete coverage, visit, appointment, or retrieval-index rows. Confirm which are applicable to each caller. [Connection][athenaconnect], [purger][purger] |
| Epic disconnect | Controller deletes credentials, revokes import consent, then removes Epic index sources and mirror rows. | No raw-payload/crosswalk deletion found in this call chain. Confirm intended policy and canonical cleanup. The controller is not one shared transaction around all steps. [Controller][epiccontroller], [OAuth][epicoauth], [sync][epic] |
| Source record removed/invalidated | athena prunes mirror rows only after a complete fetch. Epic skips disallowed resources; its sync path does not establish a full missing-record purge. Medicare incremental cache keeps prior records not replaced by new results. | Define and test vendor deletion/status handling for every source, including raw history and search copies. [Status gate][status], [sync][epic], [cache][cache], [athena][athena] |
| Record-scoped CR-2 grants | Existing consent model has patient/grantee scope and lifecycle fields; this branch has AI_RETRIEVAL, MEDICARE_VIEW, EHR_IMPORT. | No source/type/record key in this model. Settle one shared model before adding sharing. Grant expiry must be checked on reads; a cleanup schedule alone is not authorization. [ConsentGrant][consent] |

## Shared-branch baseline: schema and environment limits

Entities and `SchemaPatchRunner` are the main schema evidence. The canonical SQL file says it is a reference, not an executed migration. Flyway is disabled in the main properties. The main properties also set `ddl-auto=none`, despite nearby comments describing update-based deployment; profile settings and deployment must be checked before claiming tables or constraints exist. No PostgreSQL catalog or deployed profile was inspected here. See [properties][properties], [schema reference][schema], and [runner][patches].

The canonical schema explicitly leaves organization/tenant scoping unresolved. Source codes identify systems; they do not prove tenant isolation. Team B and affected leads must define organization rules before cross-user sharing.

## Team B review and next actions

| Priority | Proposed contact | Decision or evidence requested |
| --- | --- | --- |
| 1 | Ian Ard / Team B (`@ianscottard`) | Check this inventory against Team B's prerequisite. Name missing stores/types and the owner of each gap. Confirm retention and unlink rules. |
| 1 | Jonathan Barreto / Team C (`@jonathanbarreto37`) | Confirm the post-#391 integration baseline and production Patient/Appointment controller owner. Wiring exists in #391; route storage and policy questions to shared owners. |
| 1 | Epic and athena owners, routed by their leads | Confirm actual granted types and enabled settings; resolve Epic canonical cleanup, binary handling, and deletion/status behavior. |
| 1 | Medicare / shared-schema owner | Confirm append-history policy, cache behavior, source identity rules, and all required indexes/FKs in PostgreSQL. |
| 2 | Crystal Schelmety / PM (`@cschel`) and affected leads | Record CR-2 scope/deadline and shared consent decisions. This inventory does not approve the pilot. |
| 2 | Tiffany / Test Lead, plus security/privacy reviewers | Coordinate Donald's remaining Patient/Appointment tests, current PostgreSQL/lifecycle checks, independent reviewers and acceptance criteria. |

Names/handles for PM, Team B lead, and Team C lead are supported by `.github/CODEOWNERS` and issue #305. Other owner assignments need lead confirmation.

Suggested review result: list each finding as accepted, needs correction, or needs another team's evidence. Record reviewer, date, reviewed commit, issue/PR link, owner, and due date. Only mark the prerequisite complete after Team B confirms coverage and any required fixes.

## Checks performed and limits

- Fetched the remote branch explicitly into its tracking ref and verified the reviewed commit against the remote head.
- Searched main Java, resource/schema, and related test paths for FHIR fetch, save, purge, and access paths. Read the source files linked below.
- Checked main-source callers to distinguish Cerner prototypes from wired services.
- Read issue #305's current discussion for Team B's request and PM's conditional pilot recommendation.
- Verified local existence of each linked source file and checked this documentation diff for whitespace errors.
- No app tests, database queries, vendor calls, or deployed UI checks were run. Existing tests are listed below as follow-up targets, not fresh passing results.

Relevant test targets: `MedicareRecordCacheTest`, `MedicareRecordCachePostgresTest`, `EpicSyncServiceCanonicalWriteTest`, `EpicSyncServiceDeltaTest`, `AthenaSyncServiceTest`, `EhrRetentionWorkerTest`, `EhrRetentionQueriesPostgresTest`, `EhrSourceDataPurgerTest`, `EhrSourceDataPurgerPostgresTest`, `CernerStorageAdapterTest`.

## Pinned evidence

[cache]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/MedicareRecordCache.java
[medicare]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/MedicareService.java
[epic]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EpicSyncService.java
[athena]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/athena/AthenaSyncService.java
[appointments]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrAppointmentSyncService.java
[cerner]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/CernerStorageAdapter.java
[mapper]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/cerner/CernerResourceMapper.java
[allergyclient]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/integration/cerner/CernerAllergyHttpClient.java
[allergymapper]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/integration/cerner/CernerAllergyMapper.java
[allergycontroller]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/integration/cerner/CernerAllergyController.java
[source]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrSource.java
[patches]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java
[crosswalk]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrPatientCrosswalk.java
[medconnect]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/MedicareConnectionService.java
[raw]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrRawPayload.java
[mirror]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrResource.java
[identity]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrSourceIdentity.java
[coverage]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrCoverageRecord.java
[visit]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrVisitRecord.java
[appointmentmodel]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrAppointmentRecord.java
[appointmentmapper]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrAppointmentMapper.java
[conflicts]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrIdentityConflict.java
[retention]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrRetentionWorker.java
[purger]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrSourceDataPurger.java
[audit]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrAuditEvent.java
[accessaudit]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrAuditService.java
[credentials]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ehr/EhrCredential.java
[epicoauth]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EpicOAuthService.java
[chunker]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ai/indexing/chunker/EpicResourceChunker.java
[ehrservice]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrService.java
[binary]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/athena/InlineBinary.java
[oldclient]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/client/ehr/EhrApiClient.java
[newclient]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrApiClient.java
[athenaconnect]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/athena/AthenaConnectionService.java
[epiccontroller]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/controller/EpicOAuthController.java
[status]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/service/ehr/EhrStatusGate.java
[consent]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/java/com/careconnect/model/ConsentGrant.java
[properties]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/resources/application.properties
[schema]: https://github.com/umgc/2026_fall_careconnect/blob/21d5a521e87f70eb9c304bd5d993d24cdad9adad/backend/core/src/main/resources/db/migration/V2609261500__create_ehr_canonical_schema.sql

Review request: https://github.com/umgc/2026_fall_careconnect/issues/305

[qa-oauth]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/CernerOAuthService.java
[qa-oauth-controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/controller/CernerOAuthController.java
[qa-link]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/CernerPatientLinkService.java
[qa-policy]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerAccessPolicy.java
[qa-config]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerIntegrationConfiguration.java
[qa-allergy]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerAllergyService.java
[qa-http]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerFhirBundleHttpClient.java
[qa-clinical]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerConditionEncounterService.java
[qa-patient-appointment]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/DefaultCernerPatientAppointmentService.java
[qa-controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerClinicalController.java
[qa-condition]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ehr/EhrConditionRecord.java
[qa-encounter]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/model/ehr/EhrEncounterRecord.java
[qa-retention]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/service/ehr/EhrRetentionWorker.java
[qa-http-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/CernerFhirBundleHttpClientIntegrationTest.java
[qa-allergy-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/DefaultCernerAllergyServiceTest.java
[qa-clinical-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/DefaultCernerConditionEncounterServiceTest.java
[qa-patient-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/DefaultCernerPatientAppointmentServiceTest.java
[qa-matrix]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-traceability-matrix.md
[qa-summary]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-test-summary.md
[qa-plan]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/docs/testing/m4-test-plan.md
[qa-pr]: https://github.com/umgc/2026_fall_careconnect/pull/391
[qa-ci]: https://github.com/umgc/2026_fall_careconnect/actions/runs/39815432431
[qa-quality]: https://github.com/umgc/2026_fall_careconnect/actions/runs/39815432440

[qa-patient-controller]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/main/java/com/careconnect/integration/cerner/CernerPatientAppointmentController.java
[qa-patient-controller-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/CernerPatientAppointmentControllerTest.java
[qa-patient-contract-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/integration/cerner/CernerPatientAppointmentServiceTest.java
[qa-security-test]: https://github.com/umgc/2026_fall_careconnect/blob/0c991bb525fefbdbbed478441450f56fe828d4e9/backend/core/src/test/java/com/careconnect/config/SecurityConfigFilterChainTest.java
