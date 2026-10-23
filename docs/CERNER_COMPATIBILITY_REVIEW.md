# Cerner compatibility review and local prototype

Date: September 24, 2026 (America/New_York)

## Result and scope

The two reported gaps are present in the shared mapper. The local prototype blocks a wrong-patient appointment before storage. It also keeps the UTC instant when filling the shared date columns. It keeps the original JSON, including its date offsets, in the shared raw-payload entity.

This is an isolated review and prototype. It has no client, controller, bean registration, or live calls. It does not change a schema or the main checkout. No one has been contacted. No changes have been pushed. The user chose to keep current CareConnect values when demographics differ.

The starting repo is `/Volumes/TerenceB/SWEN670/src/2026_fall_careconnect`. Its existing edits were left in place. The detached worktree is `/Volumes/TerenceB/SWEN670/sandbox/cerner-compatibility-2026-09-24`.

## Source evidence

Both branches were fetched from origin for this review:

| Source | Commit | Use |
| --- | --- | --- |
| `feature/team-c-cerner-resource-mapping` | `29b94dd2a467443b5ce65e4f95b6f7346fb56b29` | Existing Cerner mapper and 57 test cases; worktree base |
| `feature/b-ehr-identity-reconciliation-schema` | `75b5f75505f6cb4e8c73070efe9d85ec41d7699b` | Shared entities, repositories, mapper, sync code, and SQL constraints |
| `team-c-develop` | `87f42ff13b8e243e5f2191be72a2ec4c3a14f7b5` | Shared Team C branch; does not contain the newer shared EHR layer |
| `feature/e-ehr-api` | `c998aec5854ad5661c49b9c1c9e41db15a3df6ae` | Checked; has the older uppercase `model/EHR` path, not the new shared layer |

The shared Java files listed in `CERNER_SHARED_INPUTS.txt` are copied without edits into this worktree. They are review inputs, not a proposed merge of that branch. SQL files were read from the pinned commit; no schema patches were copied or changed. The prototype uses the real Patient entity and shared repository types; there are no replacement domain classes.

Main source files, under `backend/core/src/main/java/com/careconnect/`:

- `service/cerner/CernerResourceMapper.java`: patient checks, source key, UTC projection, partial birth dates.
- `service/ehr/EhrAppointmentMapper.java`: `dateTime` calls `OffsetDateTime.parse(raw).toLocalDateTime()`. That drops the offset without a UTC conversion. `map` accepts any supplied local Patient and does not inspect patient actors.
- `service/ehr/EhrAppointmentSyncService.java`: gets the crosswalk, stores raw data first, then maps and upserts. It does not add a patient-actor check. It uses the server's local clock for `fetched_at`.
- `model/ehr/` and `repository/ehr/`: exact entities, columns, and lookup methods used below.
- `service/ehr/CernerStorageAdapter.java`: new, unregistered prototype.

The two SQL patches at the shared commit define unique keys for source identities, pending conflicts, crosswalks, raw payloads, and appointments. They do not prove those constraints are installed in a running database.

## Field map

Scope: Patient and Appointment fields handled by the existing Cerner mapper, plus the shared mapper's derived fields. This is not a claim that all Oracle resource types or extensions are mapped. Paths in `payload` below are JSON keys within `EhrRawPayload.payload`, column `ehr_raw_payload.payload` (JSONB).

**Patient rows below are the proposed persistence contract.** The prototype returns a read-only review in memory; it does not save Patient raw rows, source identities, or conflicts. Appointment rows are exercised through mocked shared repositories.

### Source and identity

| Input or trusted value | Exact entity property and table.column | Rule |
| --- | --- | --- |
| Configured source code | `EhrSource.code` → `ehr_source.code` | Lookup existing source; do not create it from resource data |
| Source display name, FHIR version, active flag | `EhrSource.displayName/fhirVersion/active` → `ehr_source.display_name/fhir_version/active` | Server-managed values; prototype requires active R4 |
| Trusted local patient | `EhrPatientCrosswalk.patient` → `ehr_patient_crosswalk.patient_id` | Must match supplied, authorized Patient.id |
| Trusted source | `EhrPatientCrosswalk.source` → `ehr_patient_crosswalk.source_id` | Must match selected source |
| Patient.id | `EhrPatientCrosswalk.externalPatientId` → `ehr_patient_crosswalk.external_patient_id` | Compare with an existing link; never establish a link by matching names |
| Appointment patient actor | Same crosswalk as above | Require expected relative or same-base absolute Patient reference; reject another patient even if one actor matches |
| Configured FHIR base and tenant | No dedicated column | Trusted configuration; one source ID must mean one base/tenant. Do not share one source ID across tenants with overlapping resource IDs |
| Resource type and id | `EhrRawPayload.resourceType/externalResourceId` → `ehr_raw_payload.resource_type/external_resource_id` | Used with patient_id and source_id as the raw row key |
| Local patient/source | `EhrRawPayload.patient/source` → `ehr_raw_payload.patient_id/source_id` | Values from the trusted crosswalk |
| Complete original JSON | `EhrRawPayload.payload` → `ehr_raw_payload.payload` | Preserve arrays, codes, extensions, offsets, and meta; do not store the UTC-normalized clone |
| Serialized UTF-8 size | `EhrRawPayload.payloadSizeBytes` → `ehr_raw_payload.payload_size_bytes` | JSON serialization size, not original HTTP byte size |
| Fetch time | `EhrRawPayload.fetchedAt` → `ehr_raw_payload.fetched_at` | Prototype uses injected UTC clock |
| meta.versionId | `payload.meta.versionId` | Opaque value; no dedicated version column and no numeric sorting |
| meta.lastUpdated | `payload.meta.lastUpdated`; normalized columns below | Keep source value plus UTC derived value |
| meta.profile/tag/security and other unmapped metadata | `payload.meta.*` | Raw only; no claim of profile or security-label enforcement |
| Mapper sourceKey, sourceBase, externalPatientId | In-memory Cerner projection only | No dedicated columns; raw row's source ID plus resource type/id provides stored scope |

### Patient demographics

All scalar candidates below target `EhrSourceIdentity` (`ehr_source_identity`), never direct writes to `Patient`. Each source snapshot links through `patient_id`, `source_id`, and `raw_payload_id`; `fetchedAt` maps to `fetched_at`.

| Cerner Patient field | Exact target | Handling |
| --- | --- | --- |
| name[].given | `firstName` → `first_name`; full `payload.name` | Existing mapper joins given names from its selected current name |
| name[].family | `lastName` → `last_name`; full `payload.name` | Existing mapper prefers official, then usual, then other current names; old names excluded from display |
| name[].use/period/text/prefix/suffix | `payload.name` only | Retain full source name even when no scalar target exists |
| birthDate, full YYYY-MM-DD | `dateOfBirth` → `date_of_birth`; `payload.birthDate` | Real LocalDate candidate; current Patient.dob stays unchanged |
| birthDate, YYYY or YYYY-MM | `payload.birthDate`; no precision column | Keep exact text and in-memory YEAR/MONTH precision; leave typed candidate null. Never invent January 1 or day 1 |
| telecom[] phone | Candidate `phone` → `phone`; full `payload.telecom` | No agreed selection rule for several values, rank, use, or periods. Prototype keeps array for review |
| telecom[] email | Candidate `email` → `email`; full `payload.telecom` | Same manual selection boundary |
| address[].line[0] / line[1] | Candidate `addressLine1/addressLine2` → `address_line1/address_line2` | Full array retained; selection of current/home address requires agreement |
| address[].city/state/postalCode | Candidate `city/state/postalCode` → `city/state/postal_code` | Same selection boundary |
| address[].country/use/type/period/text and extra lines | `payload.address` only | No matching source-identity columns |
| identifier[] | `payload.identifier` only | Never replace the trusted external ID with an MRN chosen from this list |
| gender | `payload.gender` only | No gender column on shared source identity. No direct update to `Patient.gender` |
| communication[] | `payload.communication` only | No shared scalar language column |
| active | `payload.active` only | Do not disable a local account from this field |
| deceasedBoolean/deceasedDateTime | Same keys in `payload` only | Do not infer local account actions |
| link[] | `payload.link` only | No automatic merge or crosswalk change |
| meta.lastUpdated | `sourceUpdatedAt` → `source_updated_at` | Normalize to UTC if a source snapshot is later saved |
| photo, extensions, narrative, and all other accepted source fields | Original Patient JSON in the review; proposed `payload` | No scalar target; raw data still needs an approved retention and access policy |

For conflict records, `EhrIdentityConflict` maps to `ehr_identity_conflict`: `patient/source` → `patient_id/source_id`; `fieldName` → `field_name`; `canonicalValue/incomingValue` → `canonical_value/incoming_value`; `status` → `status`; `detectedAt` → `detected_at`; `resolvedAt/resolvedBy` → `resolved_at/resolved_by`. New proposals use PENDING and leave both resolution fields null.

The prototype compares selected first name, last name, and birth-date text with `Patient.firstName`, `Patient.lastName`, and `Patient.dob`. It returns pending conflict proposals, including a partial date that differs from a full local date. It does not save these conflicts. Contact and address arrays remain review items; automatic scalar selection and conflict storage are still pending. This is conservative: it may ask for review of a partial date that agrees with the known month.

### Appointments

Scalar targets below are properties of `EhrAppointmentRecord`, table `ehr_appointment_record`.

| Cerner Appointment field | Exact target | Handling |
| --- | --- | --- |
| id | `externalAppointmentId` → `external_appointment_id` | Keyed with patient_id and source_id |
| Trusted patient/source | `patient/source` → `patient_id/source_id` | From link lookup, not source demographics |
| Original resource row | `rawPayload` → `raw_payload_id` | Points to the reused raw row |
| status | `status` → `status` | Cerner mapper checks its known statuses |
| start/end | `startTime/endTime` → `start_time/end_time` | UTC LocalDateTime for this prototype; raw values retain original offsets |
| participant[].actor.reference/display (Practitioner) | `providerName` → `provider_name` | Shared mapper takes first relative `Practitioner/` display; other references and all actors stay in payload |
| participant[].actor.reference/display (Location) | `location` → `location` | Shared mapper takes first relative `Location/` display; absolute references are raw-only for this display rule |
| serviceType[0].coding[0].display | `serviceType` → `service_type` | Exact shared extraction rule; all concepts and codes stay in payload |
| reasonCode[0].text, else first coding display | `reason` → `reason` | All reasons stay in payload |
| created | `sourceCreatedAt` → `source_created_at` | UTC conversion; prototype requires an offset-bearing full timestamp if present |
| meta.lastUpdated | `sourceUpdatedAt` → `source_updated_at` | UTC conversion |
| minutesDuration | `payload.minutesDuration` only | Existing mapper checks positive integer; no duration column |
| participant (types, actor IDs, status, required, period) | `payload.participant` | Full list retained; identity check happens before storage |
| specialty/appointmentType | Same keys in `payload` | No scalar columns |
| reasonReference | `payload.reasonReference` | No scalar column |
| description/comment/patientInstruction | Same keys in `payload` | No scalar columns; do not expose as logs or general API output |
| cancelationReason/requestedPeriod | Same keys in `payload` | Preserve source spelling and values |
| identifier, extensions, and other accepted fields | Original keys in `payload` | Raw only |
| Mapper hiddenFromActiveList | No column | Must derive from status = entered-in-error; no UI filtering is wired by this prototype |

## Retention and update rules

- Missing fields mean “not supplied.” Explicit JSON null stays distinct in the raw source. Neither clears a local Patient value.
- Patient review keeps the full original resource in memory. The mapper's field projection also keeps absence/null for its selected fields. A durable Patient raw row and source identity write are proposed, not built here.
- A partial birth date stays as source text. The shared LocalDate column cannot hold its precision. Keep the precision in the projection or derive it from raw text during review. A new precision column would need team agreement.
- Appointment imports are full snapshots. On an accepted update, a missing optional scalar becomes null in that source's appointment row. It does not update a local Patient. The latest raw snapshot shows what was supplied.
- Only the latest raw row is retained by the current shared upsert design. A second import replaces it; older offsets, fields, and source versions are not an archive. An append-only history table or versioned raw key needs team agreement.
- The prototype rejects an incoming appointment whose lastUpdated is older than an existing source_updated_at. It also rejects a missing incoming timestamp when the saved row has one. It does not sort opaque version IDs. Equal timestamps are accepted; detecting two different bodies with the same version remains a team decision.
- Existing CareConnect demographics remain authoritative until review. Do not auto-fill even blank local values. Proposed source values can be reviewed without changing canonical fields. Pending conflicts must be upserted by patient/source/field if durable review is added; repeated sync must not stack prompts.
- No payload or conflict values belong in logs. Synthetic fixtures use `.invalid` hosts. The prototype's review string is redacted. The returned entity objects still contain source data and must not become public responses.

## Adapter design and reuse

`CernerStorageAdapter` uses the actual shared `EhrSourceRepository`, `EhrPatientCrosswalkRepository`, `EhrRawPayloadRepository`, and `EhrAppointmentRecordRepository`. It uses their current keys and entities. It also calls the actual shared `EhrAppointmentMapper` on a UTC-normalized copy after the existing Cerner mapper validates identity and times.

The steps are: find an active configured source; load the trusted link; validate and snapshot input; normalize a private mapping copy; map and check scalar lengths; reject stale updates; upsert original raw JSON; upsert appointment with the existing row ID. The raw resource is never replaced by the normalized clone.

It does **not** call `EhrAppointmentSyncService`: that service writes raw data before the validation hook needed here and calls its mapper directly. The small prototype repeats that orchestration while reusing the shared repository storage contract. A future shared “validate then map” hook could remove that duplication. This adapter is not an `EhrApiClient` and is not registered with the client registry.

The import method has `@Transactional`, but there is no Spring bean or proxy in this experiment. Tests use repository mocks. Before wiring, the team must confirm one transaction spans both saves, rollbacks work, and concurrent imports handle unique-key races. Sequential mock tests do not prove database idempotency or crash safety.

## Team decisions and pending checks

1. Agree on UTC semantics for existing LocalDateTime columns, or change them to an instant-aware type. Existing wall-clock rows need a migration rule before mixing them with new UTC rows.
2. Agree on one source identity per tenant/base. A vendor-wide source code alone cannot isolate two tenants with overlapping IDs.
3. Choose durable source-version history, handling for equal-version/different-body data, and retention limits. Raw upsert currently loses prior versions.
4. Choose contact/address selection, missing-field rules for source identity updates, pending-conflict updates, and which roles may resolve them.
5. Review partial created timestamps, absolute provider/location references, long text, source profiles, data-absent extensions, and the payload size limit. The prototype does not prove full FHIR conformance.
6. Before any live use, wire server-side patient authorization, approved credentials, scoped endpoints, a bounded fetch/parser, transaction management, and filtered response DTOs. Conduct secure end-to-end tests with the team.

No shared schema change, client wiring, or secure end-to-end run is included in this local result.

## Test evidence

See `CERNER_COMPATIBILITY_TEST_RESULTS.md` for the exact command and captured results. The test fixtures are synthetic, in `backend/core/src/test/resources/cerner-compatibility/`. The new test suite includes two characterization tests that show the shared mapper's current gaps. Those tests passing means the gaps are confirmed, not fixed in the shared branch.
