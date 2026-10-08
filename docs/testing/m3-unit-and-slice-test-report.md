# M3 Cerner AllergyIntolerance: Unit and Slice Test Report

**Date:** 2026-10-07
**Module:** `backend/core`
**Command:** `./mvnw test "-Dtest=CernerAllergy*Test,AllergyControllerTest"`
**Result:** BUILD SUCCESS
**Duration:** 1 min 44 s

## 1. Summary

| Metric | Value |
|---|---|
| Tests run | 46 |
| Failures | 0 |
| Errors | 0 |
| Skipped | 0 |

Maven reported only the total. Per-class counts below are from counting `@Test` methods, and they add up to 46.

| Suite | Level | Tests |
|---|---|---|
| `CernerAllergyMapperTest` | Unit | 9 |
| `CernerAllergyControllerTest` | Controller slice | 8 |
| `AllergyControllerTest` (existing) | Controller slice | 29 |

## 2. Requirement evidence

| Requirement | Evidence | Status |
|---|---|---|
| M3-REQ-01 | MAP-001, MAP-008 | Covered at unit level |
| M3-REQ-02 | MAP-001, 003, 011, 014 | Covered at unit level |
| M3-REQ-03 | MAP-006; slice 403 | Covered at unit and slice level |
| M3-REQ-04 | MAP-001, 004, 006, 011, 012, 014, 015; slice 200 and empty | Covered at unit and slice level |
| M3-REQ-06 | MAP-004, 005 | Covered at unit level |
| M3-REQ-09 | Slice 401 and Cerner authorization expired | Covered at slice level only; service-level cases (SVC-002) pending |
| M3-REQ-05, 07, 08, 10, 11, 12, 14 | n/a | Not covered here; other test levels and pending dependencies |

## 3. Scenario results

### Mapper (all passed)

MAP-001, 003, 004, 005, 006, 008, 011, 012, 014, 015.

### Controller slice (all passed)

200, 401, 403, 404, 400, Cerner authorization expired (409), Cerner unavailable (502), empty result.

## 4. Coverage observations (JaCoCo)

An attached JaCoCo page for the existing `AllergyController` shows nearly all lines covered. The gaps are:

| Lines | Gap |
|---|---|
| 242 | The "patient not found" branch in `hasAccessToPatient` is not tested. |
| 255, 259 | The `CAREGIVER` and `FAMILY_MEMBER` access paths are not tested. |
| 266 | The fallthrough for an unrecognized role is not tested. |
| 268 | The catch-all (`catch (Exception e)`) in `hasAccessToPatient` is not tested. |

These are authorization branches, so they are worth tests. I did not check the coverage numbers for the new Cerner classes against the exit target (80% line and 70% branch for mapping code, 70% line for integration code). Open `target/site/jacoco/index.html` to check.

## 5. Not covered

- OpenAPI contract validation, because OpenAPI 1.0 is not approved.
- WireMock integration, E2E, and the live sandbox smoke test.
- Service/client unit scenarios (SVC-001 to SVC-011).
- Frontend unit and widget tests.
- Scenarios blocked on decisions: MAP-002, 007, 009, 010, 013.

## 6. Risks and caveats

- The mapper, controller, status codes and response shape are provisional. Tests must be revised after contract approval.
- Slice tests use standalone MockMvc, so they do not exercise Spring Security filters or `@RequirePermission`.
- A security-related coverage gap exists in the existing `AllergyController` (section 4).

## 7. Sign-off status

This is partial evidence only. M3 sign-off requires the full set of levels, contract validation, a smoke test, and three consecutive green CI runs. No open defects were found in this run.
