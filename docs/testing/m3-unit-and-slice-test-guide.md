# M3 Cerner AllergyIntolerance: Unit and Slice Test Guide

**Audience:** Team C developers and QA
**Status:** Provisional. Paths, error codes and output shapes depend on OpenAPI 1.0 approval.
**Source documents:** `m3-test-plan.md`, `m3-scenario-catalog.md`, `m3-expected-test-coverage.md`, `m3-traceability-matrix.md`, `fixtures-README.md`

## 1. Purpose

This guide explains the first unit and controller-slice tests for the AllergyIntolerance reference workflow. It also explains how to extend them to other resources. The rule from the test plan applies: prove each scenario at the lowest level that can prove it.

## 2. Artifacts

All paths are under `backend/core/src`.

| Artifact | Path | Role |
|---|---|---|
| Mapper (provisional) | `main/java/com/careconnect/integration/cerner/CernerAllergyMapper.java` | Pure FHIR Bundle to normalized records. No network or database. |
| Service interface | `.../CernerAllergyService.java` | Boundary mocked in slice tests. Defines `UnknownPatientException` and `CernerSourceException`. |
| Access policy | `.../CernerAccessPolicy.java` | Decides whether a user may view a patient. Mocked in slice tests. |
| Controller (provisional) | `.../CernerAllergyController.java` | `GET /v1/api/cerner/patients/{patientId}/allergies` |
| Unit tests | `test/java/com/careconnect/integration/cerner/CernerAllergyMapperTest.java` | Level 1 |
| Slice tests | `test/java/com/careconnect/integration/cerner/CernerAllergyControllerTest.java` | Level 2 |

The mapper and controller are placeholders so the tests could run. Replace them with the real WBS 4.7 and 4.8 implementations, and keep the test cases.

## 3. Conventions

- **Tags:** put the requirement ID in `@Tag("M3-REQ-xx")`.
- **Display names:** use `M3-SC-MAP-xxx: ...` for unit tests and `CTL: ...` for slice tests.
- **Offline only:** no live network, no database, synthetic data only (`TESTING_NORMS.md`).
- **Slice style:** standalone `MockMvc` with Mockito mocks. This is fast and needs no Spring context or security filter chain.
- **Values in errors:** exception messages and error bodies must not contain patient IDs, tokens or clinical values.

## 4. Scenario coverage

### Unit tests (mapper)

| Scenario | Requirement | Test |
|---|---|---|
| MAP-001 | REQ-01, 02, 04, 12 | Complete resource maps every field. |
| MAP-003 | REQ-02 | Offset date-time normalizes to UTC; partial dates are kept; invalid dates return null. |
| MAP-004 | REQ-04, 06 | No reaction gives an empty list; optional fields are null. |
| MAP-005 | REQ-06 | Malformed entries are skipped; an invalid Bundle is rejected. |
| MAP-006 | REQ-03, 04, 12 | A different patient is rejected without leaking IDs. |
| MAP-008 | REQ-01, 12 | Mapping is deterministic. |
| MAP-011 | REQ-02, 04 | Text without coding keeps the text and leaves the code null. |
| MAP-012 | REQ-04 | `entered-in-error` is excluded. |
| MAP-014 | REQ-02, 04 | Unknown severity gives null without throwing. |
| MAP-015 | REQ-04 | An empty Bundle gives an empty list. |

### Controller-slice tests

| Case | Status | Requirement |
|---|---|---|
| Authorized request returns camelCase fields and `source: CERNER` | 200 | REQ-04 |
| No login | 401, service not called | REQ-09 |
| No patient permission | 403, service not called | REQ-03 |
| Unknown local patient | 404 | n/a |
| Non-numeric patient id | 400, no collaborators called | n/a |
| Cerner authorization expired | 409, `retryable=false`, `source=CERNER` | REQ-09 |
| Cerner unavailable | 502, `retryable=true`, no stack trace | n/a |
| Empty result | 200, empty list | REQ-04 |

The error envelope fields are `code`, `message`, `source` and `retryable`, as the coverage guide requires. The 409 and 502 status codes are working assumptions.

## 5. Deferred scenarios

| Scenario | Reason |
|---|---|
| MAP-002, MAP-007, MAP-009, MAP-010, MAP-013 | Waiting on canonical model, reconciliation or inactive-state decisions (MAP-009, MAP-010 not yet written). |
| SVC-001 to SVC-011 | Need the real Cerner client/service. |
| Contract (CON), WireMock (INT), E2E, smoke | Different levels; need OpenAPI 1.0 and the integration branch. |
| Frontend unit/widget tests | Flutter code, owned by the frontend developers. |

## 6. How to extend

1. Add the new resource's fixture and expected output (see `fixtures-README.md`).
2. Copy the mapper test pattern: build a Bundle, map it, and compare the whole result structurally.
3. Add slice tests only for new HTTP behavior, such as status codes, serialization and the error envelope.
4. Update `m3-traceability-matrix.md` with the test names and results.
5. After OpenAPI 1.0 approval, replace the provisional paths, codes and statuses, and add schema validation.

## 7. Running the tests

```powershell
cd backend/core
./mvnw test "-Dtest=CernerAllergy*Test"
```

The JaCoCo report is written to `backend/core/target/site/jacoco/index.html`.
