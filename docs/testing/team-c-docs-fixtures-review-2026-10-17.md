# Team C docs and fixture review

October 17, 2026, Eastern Time. Prepared for Terence Boyce with Codex assistance.
Scope: WBS 4.2.7, 4.2.9, 4.2.10, and 4.2.11.
Code reviewed: `110120478aa68c83b37f2e4942ddf002636bee0f` on `team-c-develop`.

## Overlap and old claims

| Local material | Finding | Action |
| --- | --- | --- |
| Six allergy JSON fixtures and six metadata files | Already tracked in Team C | Compare bytes; keep shared files and authorship. |
| October 9 fixed expected outputs and standalone checker | Expected outputs and fixture checks were absent from Team C | Keep the fixed JSON and move the checks into a normal JUnit test. Do not copy compiled files or the local runtime script. |
| September 29 and October 4 design and baseline drafts | Some useful detail was absent, but their branch/model claims are old | Fold useful guidance into this report and the four baseline docs. Keep the local drafts intact. |
| M1 trace drafts | A 26-row trace is already tracked | Link that trace; avoid another copy with old status text. |
| October 13 M3 trace | Says PR #330 is not merged | Update the date row and link exact fixture tests. |
| October 9 shared-storage porting guide | Describes a different shared branch model | Do not publish its scalar-ID/String-payload instructions as Team C facts. Team C currently has entity links, Map payloads, and LocalDateTime fetch times. |

PRs #157, #158, #201, #330, and #331 are merged. PR #148 was closed;
its mapper branch later reached Team C through PR #346. Presence in Git does
not prove live service wiring, database safety, or release acceptance.

## 4.2.7: repository, build, and CI

The current branch contains the Patient/Appointment mapper and storage prototype,
the allergy mapper/controller tests, and the calendar fix. The allergy route is
off unless `careconnect.cerner.allergies.enabled=true`. Enabling it still needs
real `CernerAllergyService` and `CernerAccessPolicy` beans.

The October 13 report records earlier failing broad suites. Its counts describe
that run, not this commit. This change runs focused offline tests only. It does
not prove a full release build, deployment, branch rules, or three green CI runs.
See [the dated WBS review](team-c-wbs-review-2026-10-13.md) for the prior results.

## 4.2.9: mapping and source history

Use the server-owned vendor patient ID. The pure allergy mapper requires an exact
`Patient/{id}` reference. That guard does not prove that a real request resolves
the correct local patient, source, grant, or tenant. Name and date of birth alone
must not establish identity.

| Source value | Current allergy output | Limit |
| --- | --- | --- |
| Resource ID | `sourceRecordId` | Missing ID skips the record. |
| Source name | `CERNER` | Approve its relation to the shared registry name `ORACLE_HEALTH`. |
| Substance text and first code | `substanceText`, `substanceCode` | Coding system and later codes are not in the DTO. |
| Status | First clinical and verification code | Entered-in-error is excluded. |
| Reaction | Text, or first coding display | Missing reactions yield an empty list. |
| Severity | First known mild/moderate/severe value | Unknown values become null. |
| Recorded date | UTC timestamp or partial date string | Calendar-invalid months and days are rejected after PR #330. |
| Source update/version | Not in the DTO | Do not replace these with recorded date or fetch time. |

The fixed expected-output file was recorded on October 9. It is a provisional
compatibility baseline, not an approved FHIR profile or public API contract.
Fixture metadata belongs to its original author; this run does not verify the
capture process or fetch a live sandbox response.

The Team C `EhrRawPayload` currently stores Patient/Source entity references,
a Map payload, a required external resource ID, and a `LocalDateTime` fetch time.
`CernerStorageAdapter` finds and saves one matching raw Appointment row. It
does not establish immutable version history. Its Patient review returns proposed
fields/conflicts in memory. Do not describe it as the shared reconciler's
approved persistence flow. Review model differences with the shared owners
before porting code from another branch.

## 4.2.10: trust boundaries and accessible states

| Boundary | Existing evidence | Required proof |
| --- | --- | --- |
| Client to API | Mock-policy controller tests and route gate | Real security-filter checks, local patient access, and consent. |
| API to source | Service/access interfaces | Real beans, trusted crosswalk, source grants, bounded retries and paging. |
| Mapper input | Fixed-fixture output, unchanged input, wrong-patient rejection | Approved resource/profile rules and real service identity binding. |
| Storage | Prototype and mock tests | PostgreSQL rollback/replay/concurrency, binary removal, retention, encryption, and tenant scope. |
| Data to UI | Earlier locale widget checks | Integrated loading, empty, denied, reconnect, partial, and retry states. |

For each UI state, record keyboard reach, focus order, visible focus, status
announcements, screen-reader output, zoom, and text that does not rely on color.
No manual accessibility or live security check was run here. Keep source tokens
on the server and keep patient values out of errors and evidence logs.

## 4.2.11: design and test trace

Keep the [26-row M1 trace](team-c-m1-trace-review-2026-10-13.md) as dated history.
Use the [M3 trace](m3-traceability-matrix.md) for current named tests. The new
`CernerAllergyFixtureCompatibilityTest` adds these links:

| Test method | Cases | Requirement | Evidence scope |
| --- | ---: | --- | --- |
| `fullOutputMatchesFixedExpectation` | 6 | M3-REQ-04 | All DTO fields, nulls, and array order. |
| `mappingLeavesInputUnchanged` | 6 | M3-REQ-12 | Input JSON is unchanged. |
| `wrongPatientRejectedWithoutIdentifierLeak` | 5 | M3-REQ-03 | Every nonempty fixture rejects another patient without IDs in the error. |

Run from the repository root with JDK 17 and Maven:

```sh
mvn -f backend/core/pom.xml -B -ntp \
  -Dtest=CernerAllergyFixtureCompatibilityTest,CernerAllergyMapperTest,CernerAllergyControllerTest,CernerAllergyControllerConfigurationTest,CernerResourceMapperTest,CernerStorageAdapterTest test
```

The fixtures live under `backend/core/src/test/resources/cerner/fhir/allergyintolerance/`.
Their fixed outputs are in `backend/core/src/test/resources/cerner/expected/allergy-mapper.json`.
Controlled SRS IDs, an approved API checksum, Test Lead review, and release
acceptance remain open. A plan or a Git merge does not prove those checks passed.

## Validation and disposition

On October 17 at 10:23 EDT, Maven 3.9.9 completed the command above with
**122 tests passed, zero failures, zero errors, and zero skips**. This includes
17 new fixture cases, 13 allergy mapper cases, eight controller cases, five route
configuration cases, 57 Patient/Appointment mapper cases, and 22 storage mock
cases. Checkstyle reported zero violations. Maven ran on Homebrew Java 25.0.1
and compiled to Java release 17. This run does not prove runtime use on JDK 17.

All 12 existing fixture/metadata files matched the local review copies byte for
byte. The expected-output file also matches the October 9 copy; its SHA-256 is
`c6a8f49bee3ab5ae8297c865987292cafa34987a69517f1f20ef2d157b05b510`.
New report and baseline links resolve. `git diff --check` passed.

| WBS | Evidence added or refreshed | Finding |
| --- | --- | --- |
| 4.2.7 | Current merge facts, focused Maven results, dated broad-suite limits | Partly met; full release/CI acceptance not verified. |
| 4.2.9 | Fixed field outputs and current model limits | Partly met; vendor/model approval and real storage proof not verified. |
| 4.2.10 | Wrong-patient checks and current route/boundary guidance | Partly met; real security and manual accessibility proof not verified. |
| 4.2.11 | Named fixture tests linked to M3 requirements; existing M1 trace reused | Partly met; controlled requirement and Test Lead approval not verified. |

No WBS percentages or reviewer decisions were changed. This work does not
assign approval or close the shared release gates.
