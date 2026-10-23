# Milestone 3 Cerner Traceability Matrix

**Status:** Working QA baseline, refreshed October 17, 2026. Local unit/slice evidence is separate from sign-off candidate validation.
**Source of requirement definitions:** [m3-test-plan.md](m3-test-plan.md)
**Scenario details:** [m3-scenario-catalog.md](m3-scenario-catalog.md)

Use one row per requirement. Replace planned scenario IDs with exact test class/method names as implementation lands and attach immutable CI/evidence links. Do not mark a row passing based only on planned scenarios.

| Requirement ID | Description | Test identifiers | Level(s) | Expected result | Latest result | Evidence link |
|---|---|---|---|---|---|---|
| M3-REQ-01 | Map approved Cerner resources to the canonical model. | CernerAllergyMapperTest.completeResourceMapsAllFields, deterministic | Unit | Every approved field maps deterministically and retains source identity/provenance. | Partly met: offline mapping assertions exist; approved canonical model and resource scope remain open. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-02 | Normalize codes, cardinalities, and dates without inventing values. | CernerAllergyMapperTest.partialDatePreserved, completeResourceMapsAllFields, validCalendarDatesPreserved, invalidCalendarDatesRejected, invalidRecordedDateEntryIsolated | Unit | Approved normalization rules are applied while absent or unknown clinical facts remain absent/unknown. | Partly met: PR #330 is merged. Calendar regressions reject impossible months/days and retain valid precision. Model approval remains open. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-03 | Enforce server-controlled patient/source context. | CernerAllergyFixtureCompatibilityTest.wrongPatientRejectedWithoutIdentifierLeak; CernerAllergyMapperTest.otherPatientRejected; CernerAllergyControllerTest.forbidden | Unit, slice, smoke | Requests cannot override authorized patient/source context or retrieve another patient's data. | Partly met: pure mapper and mocked-policy denial assertions exist. Trusted service identity and real security-chain checks are not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-04 | Retrieve and map AllergyIntolerance records, including empty results. | CernerAllergyFixtureCompatibilityTest.fullOutputMatchesFixedExpectation; CernerAllergyMapperTest.completeResourceMapsAllFields, textWithoutCoding, enteredInErrorExcluded, unknownSeverityNull, emptyBundle; CernerAllergyControllerTest.ok, empty | Unit, slice, integration, E2E, smoke | Authorized retrieval returns correctly mapped allergies; an empty Bundle returns a successful empty result. | Partly met: offline mapper and standalone controller cases exist. Live retrieval, contract, integration, E2E and smoke remain open. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-05 | Bound token refresh and protect token material. | SVC-003–005; INT-003, 004 | Unit, integration | Expiry follows the approved bounded refresh path, refresh failure stops cleanly, and secrets are never exposed. | Missing implementation/evidence for real bounded refresh and token handling. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-06 | Handle missing and malformed source data safely. | CernerAllergyMapperTest.noReactionYieldsEmptyList, malformedEntriesIsolated | Unit, integration | Optional omissions follow approved defaults; malformed core data is rejected or isolated without fabricated meaning. | Partly met: omission and malformed-entry assertions exist; approved core-data policy and integration are not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-07 | Bound timeouts, retries, and rate-limit behavior. | CernerAllergyControllerTest.sourceUnavailable; SVC-006, 007; INT-006, 007 | Unit, slice, integration | Calls terminate within policy, retry only eligible failures, honor approved rate limits, and avoid retry loops. | Partly met: mocked source-error response assertion exists. Real timeout, retry and rate-limit behavior is not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-08 | Handle pagination, duplicates, and partial results. | SVC-008–011; CTL-007; INT-008, 009; E2E-003 | Unit, slice, integration, E2E | Valid pages are collected without loops/duplicates; later failures follow the approved partial-result behavior. | Missing executed pagination/duplicate/partial-result evidence. Contract decisions remain open. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-09 | Handle distinct source authorization failures. | CernerAllergyControllerTest.unauthenticated, forbidden, sourceAuthExpired | Unit through smoke | Each authorization state produces its approved outcome, including reconnect behavior, without appearing as empty data. | Partly met: standalone error responses are asserted. Real OAuth refresh/scope handling and security-chain behavior are not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-10 | Serialize and validate all API responses against one OpenAPI contract. | CernerAllergyControllerTest.ok, notFound, badRequest; CON-001–004 | Slice, contract, integration | Backend responses and frontend fixtures validate against the same approved OpenAPI version/checksum. | Partly met: provisional HTTP assertions exist. Shared approved OpenAPI/checksum and schema validation are not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-11 | Complete critical frontend/backend retrieval workflows without write-back. | E2E-001–003 | E2E | Users can view success, reconnect, and partial-result states; no EHR write is offered or sent. | Not verified: integrated retrieval-only success, reconnect and partial-result UI flows were not run. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-12 | Retain provenance and keep uncertain matches separate. | CernerAllergyFixtureCompatibilityTest.mappingLeavesInputUnchanged; CernerAllergyMapperTest.completeResourceMapsAllFields, otherPatientRejected, deterministic | Unit, integration as needed | Original source identity/provenance is retained and uncertain records are not automatically merged. | Partly met: source identity and pure mapper binding assertions exist. Raw payload/history storage and approved reconciliation are not verified. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-13 | Preserve existing health-data behavior. | Existing AllergyControllerTest; REG-001 plus impacted suites | Unit, widget, API | Existing health-data workflows remain passing after Cerner integration changes. | Not verified as a release gate: full-suite assessment is recorded in the linked report; focused cases alone do not prove all impacted workflows. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-14 | Verify current live-sandbox interoperability weekly and before sign-off. | SMK-001–003 | Manual smoke | A documented synthetic, retrieval-only sandbox check passes with sanitized evidence. | Not verified: no current live-sandbox smoke was run. | [October 13 review](team-c-wbs-review-2026-10-13.md) |
| M3-REQ-15 | Meet coverage, CI, contract, defect, and evidence gates. | All P0/P1 scenarios and evidence register | All | Every sign-off threshold is met and the evidence package supports the final QA disposition. | Not verified: approved candidate, coverage gates, three passing CI runs, critical defects, and QA sign-off remain open. | [October 13 review](team-c-wbs-review-2026-10-13.md) |

See [the October 17 review](team-c-docs-fixtures-review-2026-10-17.md) for fixed-fixture results and current merge status. October 13 evidence links retain their original test dates.

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
