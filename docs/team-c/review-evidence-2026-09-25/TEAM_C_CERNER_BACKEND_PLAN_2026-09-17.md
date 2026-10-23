# Cerner backend: plan and first delivery

## Plan
1. Refresh Team C's base and inspect the shared EHR work. Preserve existing work.
2. Build a pure Java Patient/Appointment mapper with no database or network side effects.
3. Use a trusted local-patient/source-endpoint/external-patient link. Reject unsafe identity and time input.
4. Add synthetic tests, run them, and check the normal backend build.
5. Hand off the caller contract and remaining integration work for review.

## Scope
This first delivery is the mapping layer, not OAuth, a sync engine, or a public API.
Base: origin/team-c-develop at 87f42ff13b8e243e5f2191be72a2ec4c3a14f7b5.
The shared EHR schema exists on feature/b-ehr-identity-reconciliation-schema, not this base.
Its mapper uses LocalDateTime and does not enforce this patient link. This module leaves that work intact.

## Caller contract
Use `new CernerResourceMapper(clock)`, then `patient(json, trustedLink)` or
`appointment(json, trustedLink)`. Obtain PatientLink from a server-controlled crosswalk
AFTER checking the caller's access to the local patient. It is not authorization by itself.
`Projection.fields()` returns a defensive JSON copy for an INTERNAL service boundary.
Do not return the source projection directly to the UI or log it: it includes PHI and internal comments.
The constructor accepts only HTTPS source bases without query, user info, fragment or dot segments.
Only exact relative and same-base absolute Patient references match; no links are fetched.

The output keeps tenant-scoped sourceKey, opaque sourceVersion, sourceUpdatedAt, and fetchedAt.
The persistence owner must upsert by scoped identity (and local link as needed), never by name.
The mapper does not itself prevent duplicate database rows or reconcile a changed crosswalk.

## Implemented rules
- Patient identity, official/usual current name choice, joined given names, partial birth dates.
- Selected demographics and language remain source values; no local Patient mutation or locale change.
- Appointment patient binding, exact source status, paired times, UTC instants, positive supplied duration.
- Allow missing time pairs only for proposed/cancelled/waitlist. Hide entered-in-error in active lists.
- Preserve service codes, participants, reasons, separate notes and requested periods in an internal projection.
- Drop unrelated photos, contacts, contained resources, narrative and arbitrary extensions.
- Preserve absent/null/empty source fields as supplied. Reject malformed core fields with value-free errors.

## Still needed before deployment
- Team review, then connect to Rashaad/Tiffany's approved Cerner client and server-side RBAC.
- Agree database/schema integration and upsert behavior with the shared EHR owner.
- Full FHIR validation, HTTP byte limits before parsing, optional-field issue reporting, contact/address selection.
- Partial name-period handling (currently conservatively excluded), source merge/link review.
- HTTP errors, pagination and partial-sync handling; secure sandbox and end-to-end tests.
- A role-filtered response model and UI localization. No EHR write-back in this slice.

## References
- Existing TeamC_Patient_Appointment_Mapping_2026-09-17.docx and TDD addendum.
- https://hl7.org/fhir/R4/patient.html
- https://hl7.org/fhir/R4/appointment.html

## Test command
From backend/core using JDK 17: `mvn -Dtest=CernerResourceMapperTest test`.

## Validation and handoff (September 17, 2026)
- 48/48 synthetic JUnit tests passed on Java 17, including nine added review cases.
- The standard Maven test lifecycle now passes after repairing four incomplete jars
  in the local Maven cache. No repository build policy or gate was weakened.
- Full production and test compilation passed. This was a focused test run, not the full suite.
- Secure sandbox, persistence, UI, and remote CI results remain separate checks.

## Review fixes
- Reject dot-only IDs so URI resolution cannot escape the resource's source key.
- Reject unsupported implicitRules and nonempty modifierExtension at any depth.
- Reject malformed participant containers, null links, year zero and timestamps without seconds.
- Bound JSON traversal at 32 nested levels, 10,000 nodes and 100,000 characters per string.
  These are mapper guardrails, not an HTTP request byte limit or full FHIR validator.
- Redact PatientLink string output; source fields remain restricted internal PHI.
- Use Google Java formatting and braces, with regression tests for the safety changes.

To repeat the focused test, obtain JUnit console standalone 1.12.1 from Maven Central,
set `JAVA_HOME` to JDK 17 and `JUNIT_CONSOLE_JAR` to that jar, then run
`bash backend/core/scripts/test-cerner-mapping.sh` from the repository root.
The script uses Jackson 2.18.3 from the local Maven cache and writes XML reports under
`backend/core/target/cerner-mapping-tests/reports`.

Example service call (the caller supplies an already authorized crosswalk):
```java
var mapper = new CernerResourceMapper(Clock.systemUTC());
var link = new CernerResourceMapper.PatientLink(localPatientId, trustedSourceBase, externalPatientId);
var patientProjection = mapper.patient(patientJson, link);
var appointmentProjection = mapper.appointment(appointmentJson, link);
// Pass to a reviewed persistence adapter; do not serialize the internal projection to the UI.
```

Suggested next review: Terence explains the mapping and tests; Tiffany checks the
source rules and negative cases; Rashaad checks the client-to-mapper call boundary.
This is a suggested review split, not an assignment made on their behalf.

## Final focused quality review
The configured Java analyzers ran against the backend. The new Cerner production
classes have no Checkstyle, PMD quickstart, or SpotBugs findings after fixes.
Repository-wide findings still exist; report generation succeeding is not a claim
that the whole repository passes its merge policy. No scan rules were disabled.

The latest inspected PR #79 remained open at 6161f846. Its GitHub quality-gate
check reported SUCCESS, while the supplied historical artifact said BLOCKED.
That mismatch is not resolved by this mapper PR and must not be treated as approval.

The new branch is intended for a draft PR into team-c-develop. Required independent
review, secure integration tests and final merge approval remain outstanding.
