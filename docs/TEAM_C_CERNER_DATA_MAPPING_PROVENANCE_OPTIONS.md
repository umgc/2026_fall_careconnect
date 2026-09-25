# Team C Cerner Data Mapping and Provenance Options

**WBS:** C1.4.3  
**Assessment date:** 2026-09-03  
**Prepared for:** Terence Boyce, Technical Lead  
**Dependency:** C1.4.2 Cerner API feasibility spike

## Status and decision boundary

**Recommended WBS status: Blocked.** This document supplies a decision framework and preliminary mapping for the current CareConnect schema, but C1.4.2 has not provided a verified Cerner sandbox response, tenant-specific resource inventory, profiles, identifiers, or scopes. The repository contains no verified Cerner/Oracle Health client, endpoint, SMART configuration, or captured synthetic resource bundle. Therefore the mapping is not represented as confirmed.

## Recommended architecture decision

Use a two-stage ingestion design:

1. Preserve a minimal, encrypted raw FHIR envelope for replay/audit with source system, tenant, resource type, logical ID, version ID, last-updated time, retrieval time, request correlation ID, and payload hash.
2. Transform only approved fields into CareConnect's normalized PostgreSQL entities through versioned mapping rules.

This option is preferred over direct resource-to-table writes because it preserves provenance, supports idempotent replay and mapping changes, and prevents vendor payloads from silently overwriting locally authored data.

## Preliminary resource-to-model map

| Candidate Cerner FHIR resource | Current CareConnect target | Primary match key | Mapping notes / unresolved decisions |
|---|---|---|---|
| `Patient` | `Patient`, `User`, embedded `Address` | approved external patient identifier + source namespace | Do not match on name/DOB alone. Confirm which Cerner identifier system is stable. Local `dob` is a string and needs date normalization rules. |
| `AllergyIntolerance` | `Allergy` / `patient_allergy` | source namespace + resource logical ID/version | Map code/display, category/type, criticality/severity, reactions, onset/recorded date, clinical status. Local enums require an explicit fallback and review queue. |
| `MedicationRequest` and/or `MedicationStatement` | `Medication` / `patient_medication` | resource type + logical ID/version | Confirm whether orders, patient-reported statements, or both are in scope. Map medication coding, dose, frequency, route, prescriber, dates, and status without conflating order and adherence. |
| `Observation` | `Vital` / `vitals` for approved vital profiles | logical ID/version; dedupe by patient + code + effective time only as a secondary check | Preserve coded value, units, reference range, interpretation, method, performer, and effective/issued times. Current `Vital.value` is a string, so numeric comparability needs normalized helper fields or a staging layer. |
| `Condition` | no confirmed direct clinical-condition entity | logical ID/version | Do not force conditions into `RiskType` or `SymptomEntry`. Add a dedicated normalized model or keep staged until product scope is approved. |
| `Practitioner` / `PractitionerRole` / `Organization` | `Provider` / `providers` | source namespace + practitioner/role logical ID | Current provider model is flat. Preserve practitioner, role, and organization relationships in staging until cardinality is resolved. |
| `Encounter` | no confirmed direct encounter entity | logical ID/version | Needed if provenance must link observations/conditions to visits. Do not map to scheduled visits without an explicit equivalence decision. |
| `Provenance` | new provenance metadata / audit record | target reference + recorded time + agent/source | Prefer native FHIR Provenance when supplied; otherwise synthesize ingestion provenance without implying clinical authorship. |

## Provenance fields required for every imported record

- `source_system` and `source_tenant` (no credentials or secrets).
- `fhir_base_url_identifier` or approved environment code.
- `resource_type`, `resource_id`, `version_id`, and `last_updated`.
- Patient linkage method and the external identifier system/value used.
- Retrieval timestamp, correlation ID, requesting service identity, and SMART scopes.
- Raw payload hash, mapping-rule version, mapped timestamp, and mapped-by service version.
- Disposition: created, updated, unchanged, rejected, quarantined, or deleted/tombstoned.
- Original clinical author/performer and source Provenance reference when present.
- Consent/purpose-of-use decision and minimum-necessary field set applied.

## Comparison and idempotency rules

1. Primary identity: `(source tenant, resource type, logical ID)`.
2. Version comparison: prefer FHIR `meta.versionId`; use `meta.lastUpdated` and payload hash only when version IDs are absent or unreliable.
3. Never use mutable display text as an identity key.
4. Never merge patients solely by demographic similarity. Uncertain linkage enters a manual review queue.
5. Preserve source coding systems and codes; normalized display text is secondary.
6. Treat deletion/history according to the verified Cerner capability statement and retention policy; do not hard-delete local clinical provenance on a missing search result.
7. Locally authored and externally sourced values remain distinguishable. Conflict policy must identify source priority per field and keep both values when clinical reconciliation is required.

## Options considered

| Option | Advantages | Risks | Decision |
|---|---|---|---|
| Direct write to existing tables | Fastest prototype | Loses source fidelity; brittle enum/date conversion; weak replay and conflict handling | Reject for production |
| Raw encrypted FHIR only | Maximum fidelity and fastest ingestion | Poor application query ergonomics; shifts mapping cost downstream | Use only for spike/archive |
| Raw envelope plus normalized projection | Traceable, replayable, supports current UI and later mapping changes | More storage and implementation work | **Recommended** |

## Dependency closure required from C1.4.2

- Verified sandbox access path and synthetic-data-only test account.
- Capability statement and exact supported profiles/versions.
- Approved resource/search scope, compartments, pagination, history, and deletion behavior.
- Example redacted/synthetic bundles for every in-scope resource.
- Identifier systems and patient-linkage approach.
- SMART authorization model and granted scopes.
- Rate limits, bulk/export availability, and error behavior.

After those inputs are attached, the mapping table must be validated against real synthetic responses and reviewed by Backend, Security/Privacy, and Test roles before C1.4.3 is marked **Complete**.

## Repository evidence reviewed

- `backend/core/src/main/java/com/careconnect/model/Patient.java`
- `backend/core/src/main/java/com/careconnect/model/Allergy.java`
- `backend/core/src/main/java/com/careconnect/model/Medication.java`
- `backend/core/src/main/java/com/careconnect/model/SymptomEntry.java`
- `backend/core/src/main/java/com/careconnect/model/Vital.java`
- `backend/core/src/main/java/com/careconnect/model/Provider.java`
- `backend/core/src/main/java/com/careconnect/controller/PatientController.java`
- `backend/core/src/main/java/com/careconnect/controller/AllergyController.java`
- `backend/core/src/main/java/com/careconnect/controller/MedicationController.java`

No Cerner-specific implementation or verified sandbox evidence was found in the inspected checkout.
