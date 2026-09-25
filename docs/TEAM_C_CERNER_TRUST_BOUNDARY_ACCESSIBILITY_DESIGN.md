# Team C Cerner Trust-Boundary and Accessibility Design

**WBS:** C1.4.4  
**Assessment date:** 2026-09-03  
**Prepared for:** Terence Boyce, Technical Lead  
**Dependency:** C1.4.2 Cerner API feasibility spike

## Status and scope

**Recommended WBS status: In Progress.** This document provides the requested initial threat model, minimum-necessary rules, server-side authorization boundary, encryption-at-rest policy, and accessible connection states. It remains pending validation against the actual Cerner authorization/data scope from C1.4.2 and independent security, privacy, accessibility, and Test Lead review.

## Proposed trust boundaries and data flow

```text
User + assistive technology
  -> CareConnect Flutter UI (untrusted presentation/client state)
  -> CareConnect backend API (authentication, authorization, consent, audit)
  -> server-side Cerner connector (token custody, scope enforcement, rate limits)
  -> Cerner/Oracle Health authorization + FHIR endpoints
  -> encrypted ingestion envelope / quarantine
  -> validated normalized PostgreSQL projection
  -> authorized CareConnect API response
```

Rules:

- The Flutter client must never receive or persist a Cerner client secret or refresh token.
- The backend is the authoritative patient-context, RBAC, consent, and purpose-of-use boundary.
- A successful OAuth/SMART connection does not itself authorize access to a CareConnect patient record.
- Imported content is untrusted until schema/profile validation, patient linkage, code/unit validation, and provenance checks succeed.
- No production PHI is permitted in developer logs, screenshots, test fixtures, workbooks, or issue descriptions.

## Initial threat model

| Threat | Example | Required control | Verification evidence |
|---|---|---|---|
| Token theft | Access/refresh token exposed to client, logs, or source control | Server-side token custody; encrypted secret store; log redaction; rotation and revocation | secret scan; log tests; token-store review |
| Broken object-level authorization | User changes a patient ID and retrieves another patient's FHIR data | Resolve authenticated user server-side; authorize patient linkage/role/consent on every request | negative API tests for patient, caregiver, family, admin roles |
| Scope escalation | Connector requests broader SMART scopes than needed | Allowlisted minimum scopes per approved use case; reject unexpected scope grants | authorization-request snapshot and scope tests |
| Patient mis-linkage | Cerner Patient matched by name/DOB only | Verified identifier namespace; quarantine ambiguous matches; independent review | linkage test set including collisions and missing identifiers |
| Payload tampering/replay | Modified or repeated bundle creates incorrect data | TLS; resource version/hash; idempotency key; signed audit trail; mapping version | replay, duplicate, and integrity tests |
| Unsafe mapping | Unit, status, or code is coerced incorrectly | Preserve source codes/units; validate profiles; quarantine unmapped/invalid values | mapping contract tests and review queue evidence |
| Excess PHI retention | Raw bundles or logs persist indefinitely | Minimum fields; explicit retention schedule; encrypted raw envelope; deletion/tombstone procedure | retention configuration and deletion tests |
| Insecure local cache | Clinical data left in unencrypted client storage | Do not cache unless required; encrypt approved local database/queue with platform-protected keys | storage inspection and key-deletion tests |
| Availability/rate-limit failure | Cerner outage or throttling blocks app | bounded retries, backoff, circuit breaker, stale-data label, non-destructive recovery | timeout, 429, 5xx, and offline tests |
| Accessibility failure | Status conveyed only by color or focus is lost after OAuth return | semantic status, visible text, focus restoration, keyboard/screen-reader testing | widget/semantic/manual AT evidence |

## PHI and data-minimization policy

1. Retrieve only resources and fields explicitly tied to approved M1 use cases.
2. Request the narrowest SMART scopes; separate read and write capabilities. M1 should default to read-only unless write-back is explicitly approved.
3. Use synthetic sandbox records for development and test.
4. Do not place resource bodies, tokens, demographics, clinical text, or identifiers in ordinary application logs. Log correlation IDs, outcome codes, and pseudonymous internal references.
5. Preserve raw responses only when replay/audit value is approved; encrypt them and apply a defined short retention period.
6. Return minimum UI view models rather than forwarding raw FHIR bundles to the client.
7. Keep locally authored and externally sourced data distinguishable, including provenance and last-updated time.
8. Apply consent and caregiver/family access checks before retrieval and again before returning data.

## Server-side RBAC boundary

- Use the authenticated identity from the backend security context; never trust a role or patient ID asserted only by the client.
- Patient: own linked record only.
- Caregiver: only actively linked patients, within approved permissions and consent.
- Family member: read-only minimum view where a current grant permits it.
- Admin: administrative access does not automatically grant unrestricted clinical-content access; privileged clinical support must be explicit and audited.
- Connector service identity: may call only approved Cerner endpoints/scopes and must still bind each request to an authorized CareConnect user/purpose.
- All create/update/delete/import decisions require an auditable actor, patient context, source, outcome, and correlation ID.

The current repository already demonstrates server-side patient-access checks in `PatientController`, `MedicationController`, `AllergyController`, `AuthorizationService`, and permission annotations. These patterns are evidence to reuse; they are not proof that a future Cerner connector is protected until its endpoints use and test them.

## Encryption-at-rest policy

- Cerner OAuth client secrets and refresh tokens: managed secret/parameter store or encrypted token store; never plain environment files in source control.
- Raw FHIR envelopes and normalized PostgreSQL data: encrypted storage volumes plus field-level authenticated encryption for approved high-risk secrets/tokens; keys separated from data and rotated.
- Object storage: private buckets, server-side encryption with managed keys, blocked public access, least-privilege policies, and lifecycle retention.
- Client-side cache: avoid by default; when required, use the repository's encrypted local database/secure-storage patterns and platform-protected keys.
- Backups, exports, and test snapshots inherit the same encryption, access, retention, and deletion controls.
- TLS is required in transit. Encryption at rest does not replace RBAC, consent, audit, minimization, or redaction.

Repository patterns reviewed include `TokenCryptor` (AES-GCM for sensitive tokens), `SsmParameterService` SecureString handling, encrypted form values, encrypted transcript/local-database tests, and encrypted archival configuration. These are reusable patterns, not a completed Cerner storage implementation.

## Accessible Cerner connection states

Every state must have a text heading, concise explanation, programmatic status, keyboard-reachable actions, visible focus, sufficient contrast, and no color-only meaning.

| State | Required UI and behavior | Accessibility checks |
|---|---|---|
| Not connected | Explain purpose/data requested; primary “Connect to Cerner” action; privacy link | logical heading order; button name; 200% zoom/reflow |
| Authorization in progress | Non-blocking progress text; cancel/back path; no indefinite spinner without text | live region is polite; reduced-motion behavior |
| Consent/scope review | Plain-language resource list, read/write distinction, data-use summary | grouped controls; labels/instructions; no preselected optional consent |
| Connected | Account/facility label, last successful sync, approved scope summary, disconnect action | status announced once; action names are specific |
| Syncing | Progress/status text without stealing focus | live-region throttling; background updates do not reset focus |
| Success/new data | Summary count, timestamp, provenance/source label, review action | success not color-only; screen-reader reading order |
| Partial/invalid data | Explain quarantined items and safe next step without exposing PHI | error summary links to details; readable codes/messages |
| Expired/re-authentication | State what expired, preserve user work, clear reconnect action | focus moves to heading; timeout is not silent |
| Permission denied | Explain missing role/consent and escalation path without revealing hidden data | no resource existence leak; consistent error semantics |
| Offline/rate limited/service unavailable | Last-known-data label, retry timing, manual retry | no rapid announcements; retry control remains operable |
| Disconnect confirmation | Explain impact, token revocation, retained local data, and reversibility | explicit dialog title; initial focus; escape/cancel; destructive action distinct |

Manual evidence should include keyboard-only navigation, VoiceOver or equivalent screen reader, 200% zoom, text-size scaling, light/dark contrast, error recovery, and representative RTL behavior where localized text is supported.

## Completion gate

C1.4.4 can move to **Complete** after:

1. C1.4.2 supplies the actual Cerner authorization model, scopes, endpoints, and resource list.
2. Backend/API contracts map every connector endpoint to server-side authorization, consent, audit, and throttling controls.
3. Security/privacy reviewers approve token custody, retention, logging, encryption, and threat mitigations.
4. Frontend/Test reviewers approve the state model and attach keyboard, screen-reader, reflow, contrast, failure-state, and focus evidence.
5. Reviewer name and review date are recorded; the author does not self-review.
