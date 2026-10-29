# Cerner Fixture Capture Register

**Owner:** Team C QA Lead
**Scope:** Synthetic, read-only Patient, Condition, AllergyIntolerance, Encounter, and provisional Appointment data
**Rule:** A planned row is not evidence. Mark it captured only after the sanitized fixture, metadata, consumer test, and review are linked.

## Capture and review status

| Fixture/case | Requirement/scenario | Origin | Sanitization/review | Expected output | Consumer test | Status |
|---|---|---|---|---|---|---|
| Allergy complete/active/confirmed | M3-REQ-04; M3-SC-MAP-001 | Existing fixture set | Metadata exists; reviewer fields must be completed | Compatibility expectation exists; canonical paired output pending | `CernerAllergyFixtureCompatibilityTest`, mapper tests | Partly complete |
| Allergy empty Bundle | M3-REQ-04; M3-SC-MAP-015 | Existing fixture set | Metadata exists; reviewer fields must be completed | Semantic empty result | Mapper/controller tests | Partly complete |
| Allergy missing reaction | M3-REQ-04, 06; M3-SC-MAP-004 | Existing fixture set | Metadata exists; reviewer fields must be completed | Compatibility expectation exists | Mapper/compatibility tests | Partly complete |
| Allergy entered in error | M3-REQ-04; M3-SC-MAP-012 | Existing fixture set | Metadata exists; reviewer fields must be completed | Excluded result | Mapper/compatibility tests | Partly complete |
| Allergy text-only substance | M3-REQ-04, 06; M3-SC-MAP-011 | Existing fixture set | Metadata exists; reviewer fields must be completed | Compatibility expectation exists | Mapper/compatibility tests | Partly complete |
| Allergy malformed entry/body | M3-REQ-06; M3-SC-MAP-005, M3-SC-INT-005 | Synthetic/derived | Required | Behavioral assertion; canonical policy pending | Mapper + WireMock integration | Mapper case partly complete; integration open |
| Allergy page 1/page 2/loop | M3-REQ-08; M3-SC-SVC-008–010 | Synthetic/derived | Required | Combined expected result after policy approval | Shared client + WireMock integration | Not captured |
| Patient complete read | M3-REQ-16; M3-SC-PAT-001 | Sanitized derivative of open-sandbox capture | Metadata added; second reviewer pending | Pending canonical rules | Planned Patient mapper/integration | Captured; review/test pending |
| Patient missing optional fields | M3-REQ-06, 16; M3-SC-PAT-002 | Derived from reviewed Patient fixture | Metadata added; second reviewer pending | Pending canonical rules | Planned Patient mapper | Captured; review/test pending |
| Patient identity mismatch | M3-REQ-03, 16; M3-SC-PAT-003 | Synthetic | Required | Behavioral rejection | Patient service/integration | Not captured |
| Condition complete search Bundle | M3-REQ-17; M3-SC-CONDITION-001 | Sanitized derivative of open-sandbox capture | Metadata added; second reviewer pending | Pending canonical rules | Planned Condition mapper/integration | Captured; review/test pending |
| Condition empty/missing optional fields | M3-REQ-06, 17; M3-SC-CONDITION-002–003 | Derived/synthetic | Metadata added; second reviewer pending | Pending canonical rules | Planned Condition mapper/integration | Captured; review/test pending |
| Condition unknown status/malformed entry | M3-REQ-06, 17; M3-SC-CONDITION-002–003 | Derived/synthetic | Required | Pending isolation policy | Condition mapper/integration | Not created |
| Condition entered in error | M3-REQ-06, 17; M3-SC-CONDITION-004 | Sanitized derivative of direct open-sandbox read | Metadata added; second reviewer pending | Approved exclusion/isolation rule pending | Planned Condition mapper | Created; structure test passing, mapper test pending |
| Condition two-page search | M3-REQ-08, 17; M3-SC-CONDITION-003 | Synthetic from reviewed shape | Required | Combined expected result | Shared client + Condition integration | Not captured |
| Condition gateway timeout | M3-REQ-07, 17; M3-SC-INT-006 | Live observation plus synthetic transport stub | Unfiltered and two high-volume category searches returned 504 for open-patient-b; do not commit gateway identifiers | Behavioral retryable/unavailable assertion | Shared client + WireMock integration | Observed; deterministic stub/test open |
| Encounter complete search Bundle | M3-REQ-18; M3-SC-ENCOUNTER-001 | Sanitized derivative of open-sandbox capture | Metadata added; second reviewer pending | Pending canonical rules | Planned Encounter mapper/integration | Captured; review/test pending |
| Encounter empty/missing optional fields | M3-REQ-06, 18; M3-SC-ENCOUNTER-002–003 | Derived/synthetic | Metadata added; second reviewer pending | Pending canonical rules | Planned Encounter mapper/integration | Captured; review/test pending |
| Encounter paging | M3-REQ-08, 18; M3-SC-ENCOUNTER-003 | Sanitized derivative of open-sandbox pages | Metadata added; second reviewer pending | Pending ordering/duplicate policy | Shared client + Encounter integration | Two-page fixture pair created; client test pending |
| Encounter malformed entry | M3-REQ-06, 18; M3-SC-ENCOUNTER-002–003 | Derived/synthetic | Required | Pending isolation policy | Encounter mapper/integration | Not created |
| Appointment complete bounded search | M3-REQ-19; M3-SC-APPOINTMENT-001, 003 | Sanitized derivative of open-sandbox bounded search | Metadata added; second reviewer pending | Pending canonical rules | Planned Appointment mapper/integration | Captured; review/test pending |
| Appointment proposed/no times | M3-REQ-19; M3-SC-APPOINTMENT-002 | Synthetic derivative; source patient returned no proposed record | Metadata added; second reviewer pending | Pending approved provisional rule | Planned Appointment mapper/storage | Created; review/test pending |
| Appointment empty | M3-REQ-19; M3-SC-APPOINTMENT-004 | Synthetic from reviewed shape | Metadata added; second reviewer pending | Semantic empty result | Planned Appointment integration | Created; review/test pending |
| Appointment paging | M3-REQ-08, 19; M3-SC-APPOINTMENT-004 | Sanitized derivative of open-sandbox pages | Metadata added; second reviewer pending | Pending ordering/duplicate policy | Shared client + Appointment integration | Two-page fixture pair created; client test pending |
| OAuth success/expired/invalid grant/insufficient scope | M3-REQ-05, 09, 20; M3-SC-AUTH-001–003 | Fully synthetic only | Required; tokens must be unmistakably fake | Behavioral assertions | Auth service + WireMock integration | Not created |
| Timeout/429/5xx/malformed/next-link failures | M3-REQ-06–09 | Fully synthetic | Required | Behavioral assertions | Shared client + WireMock integration | Not created |

## Per-capture record

Copy this block into the fixture sidecar or pull-request evidence:

```yaml
requirements: []
scenarios: []
origin: sanitized-secure-sandbox-capture # or synthetic / derived
capturedAtUtc:
sandboxPersona: provider # or patient
requestPattern: # no token, launch value, real identifier, or session value
httpStatus:
bundleEntryCount:
nextLinkPresent:
derivedFrom:
changes: []
reviewedBy:
reviewedAtUtc:
consumers: []
```

## QA completion rule

A fixture responsibility is complete only when the JSON has one clear purpose, the sidecar identifies its source and sanitization, secrets/identifiers have been reviewed, the expected behavior is explicit, an automated test consumes it, and the traceability matrix links the resulting evidence.
