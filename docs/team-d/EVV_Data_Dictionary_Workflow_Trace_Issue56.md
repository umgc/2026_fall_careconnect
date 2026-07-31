# CareConnect — EVV Data Dictionary & Workflow Trace

**Issue:** #56 | **Team:** D | **Sprint:** 1 | **Course:** SWEN 670  
**Author:** Chris Garcia | **Date:** June 25, 2026 | **Status:** Draft

---

## Table of Contents

- [CareConnect — EVV Data Dictionary \& Workflow Trace](#careconnect--evv-data-dictionary--workflow-trace)
  - [Table of Contents](#table-of-contents)
  - [1. Purpose](#1-purpose)
  - [2. EVV Data Dictionary](#2-evv-data-dictionary)
    - [2.1 Core Visit Fields (EvvRecord)](#21-core-visit-fields-evvrecord)
    - [2.2 Check-In and Check-Out Location Fields](#22-check-in-and-check-out-location-fields)
    - [2.3 EOR (End of Review) Approval Fields](#23-eor-end-of-review-approval-fields)
    - [2.4 Correction Fields](#24-correction-fields)
    - [2.5 Record Status Transitions](#25-record-status-transitions)
    - [2.6 Offline Sync Status Transitions](#26-offline-sync-status-transitions)
  - [3. EVV Workflow Trace](#3-evv-workflow-trace)
    - [3.1 Standard Online Workflow](#31-standard-online-workflow)
    - [3.2 Offline Workflow](#32-offline-workflow)
    - [3.3 Correction Workflow](#33-correction-workflow)
    - [3.4 EOR (End of Review) Approval Workflow](#34-eor-end-of-review-approval-workflow)
    - [3.5 Submission Stage (HHAExchange / External Aggregator)](#35-submission-stage-hhaexchange--external-aggregator)
  - [4. State-Specific HHAExchange Eligibility Rules](#4-state-specific-hhaexchange-eligibility-rules)
  - [5. Identified Gaps and Open Items](#5-identified-gaps-and-open-items)
  - [6. REST API Endpoint Reference](#6-rest-api-endpoint-reference)
  - [7. Source File Reference](#7-source-file-reference)

---

## 1. Purpose

This document serves as the authoritative reference for the Electronic Visit Verification (EVV) module in CareConnect. It defines every data field captured, persisted, corrected, and submitted during a caregiver visit, and traces the full workflow from visit start through external aggregator submission. It is intended for developers, QA engineers, and compliance reviewers working on the CareConnect platform.

---

## 2. EVV Data Dictionary

### 2.1 Core Visit Fields (EvvRecord)

These fields are persisted in the `evv_record` database table and form the primary audit record for every visit.

| Field | DB Column | Type | Required | Description |
|---|---|---|---|---|
| `id` | `id` | Long (PK) | Yes | Auto-generated unique record identifier |
| `patient` | `patient_id` | FK → Patient | Yes | The patient receiving care at this visit |
| `serviceType` | `service_type` | String | Yes | Type of care service delivered (e.g., Personal Care, Skilled Nursing) |
| `individualName` | `individual_name` | String | Yes | Patient full name — snapshotted at time of visit for immutable audit |
| `caregiverId` | `caregiver_id` | Long (FK) | Yes | ID of the caregiver performing the visit |
| `caregiverName` | `caregiver_name` | String | No | Caregiver full name — snapshotted at visit time for immutable audit trail |
| `scheduledVisitId` | `scheduled_visit_id` | Long (FK) | No | Optional link to a pre-scheduled visit record |
| `dateOfService` | `date_of_service` | LocalDate | Yes | Calendar date on which the visit occurred |
| `timeIn` | `time_in` | OffsetDateTime | Yes | Timestamp when the caregiver checked in (with timezone offset) |
| `timeOut` | `time_out` | OffsetDateTime | Yes | Timestamp when the caregiver checked out (with timezone offset) |
| `locationLat` | `location_lat` | Double | No | **Legacy:** latitude for backward compatibility with older records |
| `locationLng` | `location_lng` | Double | No | **Legacy:** longitude for backward compatibility with older records |
| `locationSource` | `location_source` | String (`gps\|manual`) | No | **Legacy:** how location was captured (GPS or manual entry) |
| `status` | `status` | String | Yes | Current review status: `UNDER_REVIEW`, `APPROVED`, or `REJECTED` |
| `stateCode` | `state_code` | String (2-char) | Yes | US state where care was delivered (e.g., `MD`, `VA`, `DC`) |
| `deviceInfo` | `device_info` | JSONB | No | JSON blob of device metadata at time of check-in (OS, model, etc.) |
| `isOffline` | `is_offline` | Boolean | Yes | `true` if the visit was recorded while the device had no network connection |
| `syncStatus` | `sync_status` | String | No | Offline sync state: `PENDING`, `SYNCED`, or `FAILED` |
| `lastSyncAttempt` | `last_sync_attempt` | OffsetDateTime | No | Timestamp of the most recent sync attempt for offline records |
| `createdAt` | `created_at` | OffsetDateTime | Yes | Timestamp when the record was first created in the system |
| `updatedAt` | `updated_at` | OffsetDateTime | Yes | Timestamp of the most recent update to this record |

---

### 2.2 Check-In and Check-Out Location Fields

Separate check-in and check-out locations are stored in the `evv_record_location` table (managed by `EvvLocationService`) and loaded as transient fields on the `EvvRecord` object at query time. They are **not** directly persisted in the `evv_record` table.

| Transient Field | Type | Source Table | Description |
|---|---|---|---|
| `checkinLocationLat` | Double | `evv_record_location` | Latitude at time of check-in |
| `checkinLocationLng` | Double | `evv_record_location` | Longitude at time of check-in |
| `checkinLocationSource` | String | `evv_record_location` | How check-in location was captured: `GPS`, `PATIENT_ADDRESS`, or `MANUAL` |
| `checkoutLocationLat` | Double | `evv_record_location` | Latitude at time of check-out |
| `checkoutLocationLng` | Double | `evv_record_location` | Longitude at time of check-out |
| `checkoutLocationSource` | String | `evv_record_location` | How check-out location was captured: `GPS`, `PATIENT_ADDRESS`, or `MANUAL` |

---

### 2.3 EOR (End of Review) Approval Fields

These fields track the supervisor approval workflow that certain records require before submission.

| Field | DB Column | Type | Description |
|---|---|---|---|
| `eorApprovalRequired` | `eor_approval_required` | Boolean | Flags that this record must be reviewed by a supervisor before submission |
| `eorApprovedBy` | `eor_approved_by` | Long (FK) | ID of the supervisor who granted EOR approval |
| `eorApprovedAt` | `eor_approved_at` | OffsetDateTime | Timestamp when EOR approval was granted |
| `eorApprovalComment` | `eor_approval_comment` | String | Optional comment left by the approver during EOR review |

---

### 2.4 Correction Fields

When a submitted EVV record contains an error, a correction workflow creates a new record that links back to the original. These fields track that relationship.

| Field | DB Column | Type | Description |
|---|---|---|---|
| `isCorrected` | `is_corrected` | Boolean | `true` if this record was created as a correction of a prior record |
| `originalRecordId` | `original_record_id` | Long (FK) | ID of the original record this corrects. The original is automatically marked `REJECTED`. |
| `correctionReasonCode` | `correction_reason_code` | String | Short code identifying the reason for the correction |
| `correctionExplanation` | `correction_explanation` | String | Free-text explanation of what was incorrect and why |
| `correctedBy` | `corrected_by` | Long (FK) | ID of the user who submitted the correction |
| `correctedAt` | `corrected_at` | OffsetDateTime | Timestamp when the correction was created |

---

### 2.5 Record Status Transitions

Every EVV record moves through a defined set of statuses. The table below describes each status and the action that triggers it.

| Status | Trigger | Description |
|---|---|---|
| `UNDER_REVIEW` | Record created (online or offline) or correction submitted | Default starting status. Record awaits supervisor review before approval or rejection. |
| `APPROVED` | Supervisor calls `review(approve=true)` | Record is verified and eligible for submission to external aggregators. |
| `REJECTED` | Supervisor calls `review(approve=false)`, or **any** record replaced by a correction (regardless of current status) | Record has been found invalid. If replaced by a correction, the original is automatically rejected. Note: the correction workflow has no status guard — records in `UNDER_REVIEW`, `APPROVED`, or `REJECTED` status can all be corrected and will be set to `REJECTED`. |

---

### 2.6 Offline Sync Status Transitions

| `syncStatus` | Trigger | Description |
|---|---|---|
| `PENDING` | `createOfflineRecord()` called; device had no connectivity | Record is queued in `evv_offline_queue` awaiting upload when connectivity returns. |
| `SYNCED` | `markSynced()` called after successful upload | Record has been successfully transmitted to the server. |
| `FAILED` | `markSyncFailed()` called after a failed upload attempt | Upload attempt was made but failed. `lastSyncAttempt` is updated. Will retry. |

---

## 3. EVV Workflow Trace

### 3.1 Standard Online Workflow

This is the primary caregiver workflow when the device has network connectivity.

1. Caregiver opens the EVV module and taps **Start Visit**.
2. Caregiver selects the **Patient** and **Service Type**.
3. Caregiver selects a **Check-in Location**: GPS (device captures lat/lng) or Patient Address (pulled from patient profile).
4. Frontend calls `POST /v1/api/evv/records` → `EvvController` routes to `EvvService.createRecord()`.
5. `EvvService` snapshots the patient's full name and the caregiver's full name for the immutable audit trail.
6. Record is saved to `evv_record` with `status = UNDER_REVIEW`. Check-in location is saved to `evv_record_location`.
7. Caregiver performs care. When done, taps **Ready to Check Out**.
8. Caregiver selects a **Check-out Location** and reviews the **Visit Summary**.
9. Caregiver taps **Complete Visit**. Check-out location is saved. If linked to a scheduled visit, that visit is marked `COMPLETED`.
10. Audit log entry is created with `CREATED` event, including all location data and device info.
11. Supervisor reviews the record and calls `APPROVED` or `REJECTED` via the review API.
12. Approved records are eligible for EDI export and submission to the external aggregator (HHAExchange — VA only).

---

### 3.2 Offline Workflow

When the caregiver's device has no network connectivity, a separate offline-first path is used.

- Caregiver completes the visit identically to the online workflow from the UI perspective.
- Frontend detects no connectivity and calls `POST /v1/api/evv/records/offline` instead.
- `EvvService.createOfflineRecord()` creates the record with `isOffline = true` and `syncStatus = PENDING`.
- The record is simultaneously added to the `evv_offline_queue` table with `operationType = CREATE` and `priority = 1`.
- Audit event `OFFLINE_CREATED` is logged with device ID captured from the `X-Device-ID` request header.
- When connectivity is restored, the caregiver opens **Offline Sync** and taps **Sync**.
- The offline queue is processed. On success, `markSynced()` sets `syncStatus = SYNCED` and `isOffline = false`.
- On failure, `markSyncFailed()` sets `syncStatus = FAILED` and records `lastSyncAttempt` for retry logic.

---

### 3.3 Correction Workflow

When a record contains an error, a correction replaces it with a new reviewed record.

> ⚠️ **Important:** `EvvService.correctRecord()` has **no status guard**. A correction can be submitted against a record in **any** status — `UNDER_REVIEW`, `APPROVED`, or `REJECTED`. The original record is unconditionally set to `REJECTED` regardless of its current state. See `EvvService.java:365` — `markRejected()` is called with no preceding status check. This means the `UNDER_REVIEW → REJECTED (via correction)` and `REJECTED → REJECTED (via correction)` paths are valid in the current implementation, even though they are not reflected in the status transition table in Section 2.5.

- Supervisor or caregiver identifies an error in any EVV record.
- A correction request is submitted via `POST /v1/api/evv/records/correct` with the original record ID, changed fields, a reason code, and an explanation.
- `EvvService.correctRecord()` creates a **new** `EvvRecord` with `isCorrected = true`, `originalRecordId` set, and `status = UNDER_REVIEW`.
- The **original** record is automatically set to `status = REJECTED` regardless of its current status.
- An `EvvCorrection` record is saved linking both records, storing original values vs. corrected values for audit.
- Corrections require approval (`approvalRequired = true` on `EvvCorrection`).
- A supervisor calls `approveCorrection()` or `rejectCorrection()` to finalize.
- On approval, the corrected record is set to `APPROVED`. Audit event `CORRECTION_APPROVED` is logged.
- On rejection, the corrected record is set to `REJECTED`. Audit event `CORRECTION_REJECTED` is logged.

---

### 3.4 EOR (End of Review) Approval Workflow

Certain records are flagged as requiring EOR (End of Review) supervisor approval before they can proceed. This is a secondary approval layer on top of the standard review.

- A record is flagged with `eorApprovalRequired = true` at creation or via an update.
- Supervisors retrieve pending EOR approvals via `GET /v1/api/evv/records/pending-eor-approvals`.
- Supervisor reviews and calls `POST /v1/api/evv/records/eor-approve` with an optional comment.
- `EvvService.approveEor()` stores `eorApprovedBy`, `eorApprovedAt`, and `eorApprovalComment`.
- Audit event `EOR_APPROVED` is logged. The record may then proceed through the standard review workflow.

---

### 3.5 Submission Stage (HHAExchange / External Aggregator)

After a record is `APPROVED`, it is eligible for submission to the state EVV aggregator. The current implementation uses an outbox pattern via the `evv_outbox` table.

> ⚠️ **Important:** HHAExchange submission is currently scoped to **Virginia (VA) records only**. Maryland (MD) and Washington DC (DC) records are captured and reviewed within CareConnect but are **not** currently forwarded to the aggregator. See Section 4 and Section 5 for details.

- Approved records are written to `evv_outbox` with `status = READY`.
- `EvvOutboxProcessor` polls the outbox on a schedule, fetching records with `status = READY` and `attempts < 3`.
- The processor submits to HHAExchange via `HhaExchangeBatchSubmissionService.submitBatch()`.
- On success, the outbox entry is marked `SENT`.
- On failure, `attempts` is incremented. After 3 failures, the record stops retrying and requires manual intervention.
- EDI files can also be generated on-demand from the frontend for manual submission or archival.

---

## 4. State-Specific HHAExchange Eligibility Rules

CareConnect currently supports EVV visits in three jurisdictions. The `stateCode` field (2-character US state abbreviation) on each record determines which eligibility rules apply.

| State | HHAExchange Submission | Known Rules | Gaps / Notes |
|---|---|---|---|
| **MD** | ❌ Not currently implemented | Standard EVV lifecycle (capture, review, approval) is supported. EOR approval may be required for certain service types. | HHAExchange batch submission is NOT wired for MD. Only VA records are forwarded to the aggregator. State-specific field validation rules not documented. **Owner: Team D.** |
| **VA** | ✅ Active | Only state currently connected to HHAExchange. Only `APPROVED` VA records are eligible for submission via `submitBatch()`. Manual submission and payload preview/download are also available. | Aggregator credentials and field mapping to VA-specific codes not yet confirmed. EDI transaction set (e.g. 837P) not confirmed with aggregator. **Owner: Team D.** |
| **DC** | ❌ Not currently implemented | Standard EVV lifecycle (capture, review, approval) is supported. | HHAExchange batch submission is NOT wired for DC. Submission frequency and correction window rules not documented. **Owner: Team D.** |

> **Note:** The `stateCode` field is designed to be extensible. No model changes are required to support new states — only new aggregator configuration and rule documentation.

---

## 5. Identified Gaps and Open Items

The following gaps were identified during the code review and documentation process. Each has an assigned owner and a proposed next action.

| # | Gap Description | Area | Owner | Next Action |
|---|---|---|---|---|
| 1 | State-specific HHAExchange eligibility rules for MD, VA, and DC are not fully documented. Submission field mapping to aggregator codes is incomplete. | Submission / Compliance | Team D | Review HHAExchange API documentation and document field mapping per state in Sprint 2. |
| 2 | The `evv_outbox` table did not exist at application startup (`BadSqlGrammarException` observed in logs), requiring a schema patch (V55b) to create it. This suggests the outbox feature was added after initial schema migration. | Database / Schema | Team D | Confirm V55b patch is applied in all environments. Add integration test to verify outbox table exists on startup. |
| 3 | No GPS reason codes (`NoGpsReason` enum) are documented. When GPS is unavailable, the reason is recorded but the set of valid values and their meanings are not captured. | Data Dictionary | Team D | Extract and document all `NoGpsReason` enum values from the codebase in the next sprint. |
| 4 | Correction reason codes (`correctionReasonCode`) are stored as free-form strings with no enforced value set. This may cause inconsistent data in aggregator submissions. | Data Quality | Team D | Define and enforce an enum or validation list for correction reason codes. Document supported values. |
| 5 | The maximum supported offline window and retry backoff strategy for `syncStatus = FAILED` records are not defined or documented. | Offline / Sync | Team D | Define maximum offline duration and retry policy. Document in this artifact in Sprint 2. |
| 6 | EOR approval trigger conditions — which service types or state codes require `eorApprovalRequired = true` — are not documented. | Compliance / Workflow | Team D | Review `EvvService` and business rules with team lead to document EOR trigger conditions. |
| 7 | `DEFAULT_USER_ID = 1L` is hardcoded in `EvvController` for all audit log actor IDs. Every audit event records `actor = User #1` regardless of which authenticated user performed the action, breaking audit trail integrity. | ⚠️ Security / Audit | Team D — flag to Team Lead | Replace `DEFAULT_USER_ID` with `securityUtil.resolveCurrentUser().getId()` in all `EvvController` service calls. This is a correctness bug. |
| 8 | **HHAExchange VA-only constraint undocumented — and submission count is misreported** | Documentation / ⚠️ Bug | Code silently scopes HHAExchange submission to VA-only records but this restriction does not appear in the SRS or TDD. Additionally, `POST /records/submit-to-hhaexchange` always returns `{"submitted": recordIds.size()}` — the size of the **input list**, not the number of records actually forwarded. A batch of 10 IDs (5 VA, 5 MD) returns `submitted: 10` even though only 5 were transmitted. Any monitoring or UI built on this response will silently show wrong totals. **Evidence:** `EvvController.java` — `recordIds.size()` is returned rather than the actual filtered count from `submitBatch()`. | Team D — flag to Team Lead | Fix `submitToHhaExchange()` to return the actual count of records forwarded rather than the input list size. Document the VA-only constraint explicitly. Confirm with team lead if MD/DC submission is planned and update SRS accordingly. |

---

## 6. REST API Endpoint Reference

All endpoints are under base path `/v1/api/evv`. All require a valid JWT. Role enforcement is applied by `AuthorizationService`.

| Method | Path | Description | Required Role | Notes |
|---|---|---|---|---|
| `GET` | `/records` | List all EVV records with optional filters | ADMIN or CAREGIVER | Query params: `status` (optional), `caregiverId` (optional). Returns all records if no filters provided. Served by `EvvQueryController`. |
| `POST` | `/records` | Create a new EVV record (online) | ADMIN or CAREGIVER | Saves record, locations, and logs `CREATED` audit event |
| `POST` | `/records/{id}/review` | Approve or reject a record | ADMIN or CAREGIVER | On approval, queues record for submission via `EvvSubmissionService` |
| `POST` | `/records/offline` | Create an EVV record while offline | ADMIN or CAREGIVER | Requires `X-Device-ID` header. Adds to `evv_offline_queue`. |
| `POST` | `/records/correct` | Submit a correction for an existing record | ADMIN or CAREGIVER | Original record is automatically `REJECTED` |
| `POST` | `/records/eor-approve` | Grant EOR approval for a flagged record | ADMIN or CAREGIVER | Sets `eorApprovedBy`, `eorApprovedAt`, `eorApprovalComment` |
| `GET` | `/records/search` | Search EVV records with filters | Any authenticated user | Patients are automatically filtered to their own records only |
| `GET` | `/records/pending-eor-approvals` | List records awaiting EOR approval | ADMIN or CAREGIVER | |
| `GET` | `/corrections/pending` | List pending correction approvals | ADMIN or CAREGIVER | |
| `POST` | `/corrections/{id}/approve` | Approve a correction | ADMIN or CAREGIVER | Sets corrected record to `APPROVED` |
| `GET` | `/offline/queue` | View caregiver offline queue | ADMIN or CAREGIVER | |
| `POST` | `/offline/sync` | Trigger sync of offline records | ADMIN or CAREGIVER | Calls `EvvOfflineSyncService.syncCaregiverOfflineData()` |
| `GET` | `/offline/status` | View offline queue sync status | ADMIN or CAREGIVER | |
| `GET` | `/records/hhaexchange-eligible` | List VA `APPROVED` records eligible for HHAExchange | ADMIN or CAREGIVER | VA state only — other states excluded by design |
| `POST` | `/records/hhaexchange-payload` | Preview HHAExchange JSON payload for given record IDs | ADMIN or CAREGIVER | Does not submit — for audit/debugging only |
| `POST` | `/records/hhaexchange-payload-json` | Download HHAExchange payload as a JSON file | ADMIN or CAREGIVER | Returns attachment with filename `hhaexchange-payload.json` |
| `POST` | `/records/submit-to-hhaexchange` | Manually trigger HHAExchange batch submission | ADMIN or CAREGIVER | Only VA `APPROVED` records are forwarded; others silently excluded. ⚠️ Returns `submitted: recordIds.size()` (input count) not actual forwarded count — see Gap #8. |
| `POST` | `/locations` | Save or update a check-in or check-out location | ADMIN or CAREGIVER | Upsert operation. Supports GPS coordinates or patient address snapshot. Served by `EvvLocationController`. |
| `GET` | `/locations/records/{evvRecordId}` | Get all locations for an EVV record | ADMIN or CAREGIVER | Returns both check-in and check-out locations for the record. |
| `GET` | `/locations/records/{evvRecordId}/{role}` | Get a specific location by role | ADMIN or CAREGIVER | Role values: `CHECK_IN` or `CHECK_OUT`. |
| `DELETE` | `/locations/records/{evvRecordId}/{role}` | Delete a check-in or check-out location | ADMIN or CAREGIVER | Requires `DELETE_PATIENTS` permission. Returns `204 No Content`. |

---

## 7. Source File Reference

The following source files were reviewed to produce this document.

| File | Purpose |
|---|---|
| `backend/core/src/main/java/com/careconnect/model/evv/EvvRecord.java` | Primary data model — all persisted and transient fields |
| `backend/core/src/main/java/com/careconnect/service/evv/EvvService.java` | Business logic for all EVV operations |
| `backend/core/src/main/java/com/careconnect/controller/EvvController.java` | Core REST API endpoints, role enforcement, HHAExchange submission |
| `backend/core/src/main/java/com/careconnect/controller/EvvQueryController.java` | List/filter EVV records endpoint (`GET /v1/api/evv/records`) |
| `backend/core/src/main/java/com/careconnect/controller/EvvLocationController.java` | Check-in/check-out location management endpoints (`/v1/api/evv/locations`) |
| `frontend/lib/features/evv/readme.md` | Frontend EVV user-facing workflow documentation |

---

*CareConnect | Team D | SWEN 670 | Document version 3.0 | June 29, 2026*