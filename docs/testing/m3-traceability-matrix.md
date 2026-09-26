# Milestone 3 Cerner Traceability Matrix

**Status:** Draft structure; evidence columns must be completed against the sign-off candidate.
**Source of requirement definitions:** [m3-test-plan.md](m3-test-plan.md)
**Scenario details:** [m3-scenario-catalog.md](m3-scenario-catalog.md)

Use one row per requirement. Add test class/method names and immutable CI/evidence links as implementation lands. Do not mark a row complete based only on planned scenarios.

| Requirement | Planned scenario coverage | Primary level(s) | Owner | Implementation/evidence | Status |
|---|---|---|---|---|---|
| M3-REQ-01 Mapping | MAP-001, 002, 008 | Unit | Developer + QA pairing/review | Existing Team C feature branch covers Patient/Appointment projection only; allergy evidence pending | Partial |
| M3-REQ-02 Normalization | MAP-001, 002, 003, 004 | Unit | Developer + QA | Expected normalized allergy JSON awaits canonical model/OpenAPI | Blocked by approval |
| M3-REQ-03 Authorized retrieval/patient context | SVC-001, 012; INT-001; E2E-001; SMK-001, 003 | Unit, integration, E2E, smoke | Developer + QA | M2 sandbox evidence is historical input; M3 candidate evidence pending | Planned |
| M3-REQ-04 Authorization states | SVC-002; CTL-002; INT-002; E2E-002; SMK-002 | Unit through smoke | Developer + QA | Exact API codes await OpenAPI 1.0 | Blocked by approval |
| M3-REQ-05 Token refresh | SVC-003, 004, 005; INT-003, 004 | Unit, integration | Developer + QA | Refresh support/policy not observed in baseline | Blocked by policy |
| M3-REQ-06 Missing/malformed data | MAP-004, 005, 009, 010; SVC-011; INT-005 | Unit, integration | Developer + QA | General cases can begin; final behavior awaits approved policies | Partial |
| M3-REQ-07 Timeout/rate limit/retries | SVC-006, 007; CTL-003; INT-006, 007 | Unit, slice, integration | Developer + QA | Retry/timeout policy pending | Blocked by policy |
| M3-REQ-08 Pagination/partial results | SVC-008–011; CTL-004; INT-008, 009; E2E-003 | Unit through E2E | Developer + QA | Exact `sourceStatus` and partial semantics await OpenAPI | Blocked by approval |
| M3-REQ-09 Controller/API serialization | CTL-001–005; CON-001, 002, 004; INT-001, 010 | Slice, contract, integration | Developer + QA | Endpoint/controller not observed; OpenAPI absent | Blocked by implementation/approval |
| M3-REQ-10 Shared contract validation | CON-001–003; INT-010 | Contract, integration | QA coordinates | Authoritative contract absent | Blocked by approval |
| M3-REQ-11 Frontend/backend workflow | E2E-001–003 | E2E | QA + frontend/backend | Frontend feature exists on separate branch; unified path pending | Blocked by integration |
| M3-REQ-12 Provenance/reconciliation | MAP-001, 006–008; SVC-005 | Unit/integration as needed | Developer + QA | Draft feature-branch models exist; approval pending | Blocked by approval |
| M3-REQ-13 Regression | REG-001 plus impacted existing suites | Unit/widget/API | Developers + QA | Select impacted suites when merge candidate exists | Planned |
| M3-REQ-14 Live smoke | SMK-001–003 | Live smoke | QA coordinates | Weekly and recent pre-sign-off record pending | Planned |
| M3-REQ-15 Quality gates/sign-off | All P0/P1 scenarios plus coverage/CI/defect evidence | All | QA | Coverage report, three CI links, contract report, defect list, smoke record pending | Planned |

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
