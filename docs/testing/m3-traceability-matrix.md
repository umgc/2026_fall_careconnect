# Milestone 3 Cerner Traceability Matrix

**Status:** Draft structure; evidence columns must be completed against the sign-off candidate.
**Source of requirement definitions:** [m3-test-plan.md](m3-test-plan.md)
**Scenario details:** [m3-scenario-catalog.md](m3-scenario-catalog.md)

Use one row per requirement. Replace planned scenario IDs with exact test class/method names as implementation lands and attach immutable CI/evidence links. Do not mark a row passing based only on planned scenarios.

| Requirement ID | Description | Test identifiers | Level(s) | Latest result | Evidence link |
|---|---|---|---|---|---|
| M3-REQ-01 | Map approved Cerner resources to the canonical model. | MAP-001, 002, 008 | Unit | Partial: Patient/Appointment feature-branch tests exist; allergy tests pending. | TBD |
| M3-REQ-02 | Normalize codes, cardinalities, and dates without inventing values. | MAP-001–004, 011, 014 | Unit | Blocked by canonical model approval. | TBD |
| M3-REQ-03 | Enforce server-controlled patient/source context. | MAP-006; SVC-001; CTL-003; SMK-003 | Unit, slice, smoke | Planned. | TBD |
| M3-REQ-04 | Retrieve and map AllergyIntolerance records, including empty results. | MAP-001, 004, 006, 011–015; SVC-001, 012; CTL-001, 004; INT-001; E2E-001; SMK-001 | Unit, slice, integration, E2E, smoke | Planned; exact output awaits canonical model/OpenAPI. | TBD |
| M3-REQ-05 | Bound token refresh and protect token material. | SVC-003–005; INT-003, 004 | Unit, integration | Blocked by refresh policy. | TBD |
| M3-REQ-06 | Handle missing and malformed source data safely. | MAP-004, 005, 009, 010; SVC-011; INT-005 | Unit, integration | Partial: general cases can begin. | TBD |
| M3-REQ-07 | Bound timeouts, retries, and rate-limit behavior. | SVC-006, 007; CTL-006; INT-006, 007 | Unit, slice, integration | Blocked by retry/timeout policy. | TBD |
| M3-REQ-08 | Handle pagination, duplicates, and partial results. | SVC-008–011; CTL-007; INT-008, 009; E2E-003 | Unit, slice, integration, E2E | Blocked by OpenAPI partial-result semantics. | TBD |
| M3-REQ-09 | Handle distinct source authorization failures. | SVC-002; CTL-002, 003, 005; CON-002; INT-002–004; E2E-002; SMK-002 | Unit through smoke | Blocked by OpenAPI authorization codes/states. | TBD |
| M3-REQ-10 | Serialize and validate all API responses against one OpenAPI contract. | CTL-001–008; CON-001–004; INT-001, 010 | Slice, contract, integration | Blocked: authoritative OpenAPI 1.0 not observed. | TBD |
| M3-REQ-11 | Complete critical frontend/backend retrieval workflows without write-back. | E2E-001–003 | E2E | Blocked by integrated UI/API. | TBD |
| M3-REQ-12 | Retain provenance and keep uncertain matches separate. | MAP-001, 006–008; SVC-005 | Unit, integration as needed | Blocked by canonical/reconciliation approval. | TBD |
| M3-REQ-13 | Preserve existing health-data behavior. | REG-001 plus impacted existing suites | Unit, widget, API | Planned. | TBD |
| M3-REQ-14 | Verify current live-sandbox interoperability weekly and before sign-off. | SMK-001–003 | Manual smoke | Planned. | TBD |
| M3-REQ-15 | Meet coverage, CI, contract, defect, and evidence gates. | All P0/P1 scenarios and evidence register | All | Planned. | TBD |

## Sign-off evidence register

| Evidence | Required value | Candidate value/link | Verified by/date |
|---|---|---|---|
| Sign-off commit | Immutable SHA | TBD | TBD |
| OpenAPI contract | Version 1.0 path and checksum | TBD | TBD |
| Mapping coverage | >= 80% line, >= 70% branch | TBD | TBD |
| Cerner integration coverage | >= 70% line | TBD | TBD |
| Consecutive CI runs | Three passing runs on candidate | 1. TBD; 2. TBD; 3. TBD | TBD |
| Endpoint contract validation | Every implemented M3 endpoint | TBD | TBD |
| Frontend fixture validation | Same contract/checksum as backend | TBD | TBD |
| Critical scenarios | 100% passing | TBD | TBD |
| Critical/High defects | Zero open | TBD | TBD |
| Live sandbox smoke | Recent passing record | TBD | TBD |
| Retrieval-only/no write-back review | Confirmed | TBD | TBD |
| Final QA disposition | Pass / conditional pass / fail | TBD | Tiffany Obi / TBD |

## Change control

When OpenAPI 1.0 and the canonical model are approved:

1. Record their immutable commit/checksum above.
2. Replace every contract-dependent TBD with exact assertions.
3. Add any newly approved resource requirements and scenarios without reusing IDs.
4. Link each automated test method, fixture, and CI result.
5. Record approval of any changed requirement; do not silently weaken a P0 scenario.
