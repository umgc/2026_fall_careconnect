# Cerner M3 Test Fixture Guide

## Checked-in compatibility baseline — October 17, 2026

`CernerAllergyFixtureCompatibilityTest` uses all six existing allergy JSON files
and `backend/core/src/test/resources/cerner/expected/allergy-mapper.json`.
That fixed baseline was recorded on October 9. It checks mapper output, unchanged
input, and wrong-patient rejection without a source call or database. It does
not approve the public API or verify the original sandbox captures. Existing
fixture metadata and authorship are unchanged. See [the review](team-c-docs-fixtures-review-2026-10-17.md).

The existing `cerner/expected/allergy-mapper.json` path is a compatibility artifact consumed by the current test. New paired expected outputs should use the standard top-level `expected/<resource>/` layout below. Move or split the compatibility artifact only in the same change that updates its consuming test; do not duplicate two files and allow them to drift.

As of October 21, `expected/condition/bundle-one-condition.expected.json` and
`expected/encounter/bundle-one-encounter.expected.json` are executable **candidate** outputs, not
approved contract artifacts. Their sidecars record `approvalStatus: candidate` and no contract
reference. They make the current mapper/DTO assumptions reviewable and must be revised or promoted
only after the canonical-model and OpenAPI owners approve those assumptions.

## Fixture root

Place backend M3 fixtures under the repository's Spring Boot test-resource root:

```text
backend/core/src/test/resources/
  cerner/
    fhir/
      allergyintolerance/
        bundle-three-allergies.json
        bundle-empty.json
        bundle-missing-reaction.json
        bundle-entered-in-error.json
        bundle-malformed.json
        bundle-page-1-with-next-link.json
      patient/
        ...
      condition/
        ...
      encounter/
        ...
      appointment/
        ...
    oauth/
      token-success.json
      token-error-invalid-grant.json
  expected/
    allergyintolerance/
      bundle-three-allergies.expected.json
      ...
  wiremock/
    mappings/
    __files/
```

Create a fixture before implementation only when it has an assigned requirement/scenario and an immediate mapper/client pairing plan. Record the planned consumer in metadata, then replace it with the exact test method when implementation lands. Avoid unused speculative fixtures and empty placeholder directories. Java test helpers should follow `TESTING_NORMS.md` and live under `backend/core/src/test/java/com/careconnect/testsupport/fixtures` when shared.

## Purpose by directory

| Directory | Contents |
|---|---|
| `cerner/fhir/` | Synthetic or sanitized FHIR R4 resources and searchset Bundles received from the Cerner boundary |
| `cerner/oauth/` | Synthetic OAuth token success/error bodies with unmistakably fake tokens and identifiers |
| `expected/` | Paired canonical mapper outputs; API outputs are not final until OpenAPI 1.0 approval |
| `wiremock/mappings/` | WireMock stub definitions for success and failure flows |
| `wiremock/__files/` | Response bodies returned by WireMock stubs |

JSON files contain request/response bodies that application or test code parses. Sidecar `.meta.yaml` files contain human-readable fixture provenance, sanitization, scenario IDs, and consumers; they are not expected application responses and are not sent to Cerner or CareConnect.

## Five-resource fixture backlog

Create only the files consumed by an implemented test or prepared for an immediate developer/QA pairing session. The minimum planned set is:

| Resource/boundary | First fixtures to capture or synthesize | Expected-output status |
|---|---|---|
| Patient | complete authorized read; missing optional fields; wrong patient/resource type | Pair mapper inputs after canonical field rules are approved. |
| AllergyIntolerance | current complete, empty, missing reaction, entered-in-error, text-only, malformed, and paging cases | Current compatibility expectation exists; split into same-base-name pairs when mapper contract is approved. |
| Condition | complete result; empty Bundle; missing optional onset/encounter; unknown status/category; malformed entry; two-page search | Complete-result candidate pair exists; approval and remaining pairs are pending. |
| Encounter | complete result; empty Bundle; missing participant/end; malformed period/linkage; two-page search | Complete-result candidate pair exists; approval and remaining pairs are pending. |
| Appointment | complete result; proposed/no-times; empty Bundle; bounded date search; two-page search | Existing compatibility fixture is limited; paired canonical output remains pending. |
| OAuth | token success with unmistakably fake token; `invalid_token`; `invalid_grant`; insufficient scope; denied/invalid launch | Behavioral assertions rather than normalized clinical output. |
| Transport | timeout; 429 with `Retry-After`; 5xx then success/failure; malformed JSON; cross-host/looping next link | Behavioral assertions rather than normalized clinical output. |

## Naming convention

Use lowercase kebab-case and encode resource, condition, and sequence:

```text
cerner/fhir/allergyintolerance/bundle-three-allergies.json
cerner/fhir/allergyintolerance/bundle-empty.json
cerner/fhir/allergyintolerance/bundle-missing-reaction.json
cerner/fhir/allergyintolerance/bundle-entered-in-error.json
cerner/fhir/allergyintolerance/bundle-malformed.json
cerner/fhir/allergyintolerance/bundle-page-1-with-next-link.json
cerner/oauth/token-success.json
cerner/oauth/token-error-invalid-grant.json
expected/allergyintolerance/bundle-three-allergies.expected.json
wiremock/mappings/allergy-search-success.json
wiremock/__files/allergy-search-page-2-timeout.json
```

Pair each FHIR input and canonical expected output using the same base name, with `.expected` added only to the output. One fixture should have one primary purpose, and filenames must describe the case rather than a patient.

Every important input that exercises normalization must have a paired expected canonical output once the canonical model is approved. Not every boundary fixture produces normalized JSON: malformed bodies, OAuth failures, timeouts, rate limits, and transport failures instead require a named behavioral or error assertion in the consuming test and traceability matrix. Pagination may use multiple page fixtures with one combined expected output when the scenario validates the assembled result. Document any pairing exception in fixture metadata; do not leave an input's expected behavior implicit.

If sequence matters, use zero-padded page/attempt numbers. Do not put a real patient ID, environment hostname, username, date of birth, medical record number, token fragment, or person name in a filename.

## Fixture metadata

Each fixture must be associated with:

- one or more `M3-REQ-*` requirements;
- one or more `M3-SC-*` scenarios;
- synthetic vs. sanitized-capture origin;
- capture/sanitization date and sandbox name when applicable;
- source capture/fixture from which a hand-edited case was derived;
- a short list of fields or behavior changed during sanitization/hand editing;
- reviewer; and
- the test(s) that consume it.

Prefer a sidecar `<fixture>.meta.yaml` when metadata would make the JSON invalid. Example:

```yaml
requirements: [M3-REQ-01, M3-REQ-04]
scenarios: [M3-SC-MAP-001, M3-SC-MAP-004]
origin: synthetic
capturedAt: null
derivedFrom: null
changes:
  - authored as a minimal synthetic missing-reaction case
reviewedBy: TBD
consumers:
  - TBD test method
```

Use [fixture-meta-template.yaml](fixture-meta-template.yaml) when creating a new sidecar so the five-resource fixture set records the same fields consistently.

Do not add contract-dependent expected API JSON before OpenAPI 1.0 approval. A source FHIR fixture may be created now; its expected canonical file should be added or updated after the canonical model is approved and pinned.

## Synthetic data and sanitization rules

Synthetic authoring is preferred. A sandbox capture may be committed only after all of the following are removed or replaced:

- access/refresh/ID tokens, authorization codes, PKCE verifier/challenge, client secret, cookies, and API keys;
- `Authorization`, `Cookie`, `Set-Cookie`, request IDs, correlation IDs, and identifying gateway headers;
- real or stable patient/person identifiers, MRNs, account/provider identifiers, names, addresses, telecom values, and free text;
- environment-specific URLs or query values that could identify a session or tenant; and
- any field not needed by the scenario.

Use reserved hosts such as `example.test`, clearly fake opaque IDs, and stable synthetic dates. Never paste secrets into a fixture temporarily. Review the staged diff and search for token/header patterns before commit.

Suggested review checks:

```bash
rg -n -i 'authorization|bearer|refresh_token|client_secret|code_verifier|set-cookie' \
  backend/core/src/test/resources/cerner \
  backend/core/src/test/resources/expected \
  backend/core/src/test/resources/wiremock
git diff --cached -- backend/core/src/test/resources
```

Matches in intentional synthetic OAuth field names still require a human value review.

## Sandbox capture workflow

1. Use the approved secure sandbox and a known synthetic patient. Keep the provider or patient persona consistent across authorization, token, audience, and FHIR base.
2. Send a read-only request for one resource case. For Appointment, include an approved bounded date or request-period range.
3. Record the HTTP status, UTC capture time, persona/base alias, resource/search pattern, Bundle entry count, and whether a next link was present. Never record a bearer value.
4. Save a working copy outside Git, remove headers/tokens/cookies and replace stable patient, provider, tenant, request, and free-text identifiers not required by the case.
5. Validate that the sanitized JSON still parses and retains the exact structure needed by the scenario.
6. Save the JSON in the resource directory and add the `.meta.yaml` sidecar. A second reviewer verifies sanitization before commit.
7. Pair with an expected output only after the canonical rule is approved. Name the consuming test and traceability row before merging.

## Expected-output rules

- Expected files assert only approved behavior; they must not turn a draft mapping document into a contract.
- Preserve source values and provenance where the approved model requires them.
- Do not invent missing clinical facts or silently coerce malformed core data.
- Use stable clocks/instants for generated timestamps.
- API-facing names must be camelCase after OpenAPI approval.
- UTC/date precision, null/absent/empty behavior, ordering, duplicate handling, error envelope, and `sourceStatus` must match the approved contract/policies.
- Compare JSON structurally. Ignore ordering only where the approved contract declares ordering irrelevant.

## WireMock guidance

- Match only the headers and query parameters needed to prove behavior; never store a real bearer token.
- Use synthetic placeholder bearer values and verify sensitive values are not logged.
- Model pagination with explicit page bodies and next links on the same approved source base.
- Use scenarios/sequential responses for `401 -> refresh -> 200` and bounded retry tests.
- Use deterministic delays just above the configured client timeout; keep the suite fast.
- Test `429` with valid/invalid `Retry-After`, bounded retries, and eventual success/failure as approved.
- Keep partial-result stubs separate from total-failure stubs.

## Review checklist

- [ ] Fixture is synthetic or has documented sanitization/review.
- [ ] Requirement and scenario IDs are recorded.
- [ ] No secrets, token fragments, real identifiers, or unnecessary free text exist.
- [ ] Resource type and FHIR Bundle structure match the intended case.
- [ ] Expected output is approved, deterministic, and structurally compared.
- [ ] Input has a paired expected output, or metadata names the behavioral/error assertion and explains why normalized output does not apply.
- [ ] Contract-dependent fields cite the approved OpenAPI commit/checksum.
- [ ] At least one named automated test consumes the fixture.
- [ ] No live network call is required outside the documented manual smoke test.

Track planned and completed fixture work in [cerner-fixture-capture-register.md](cerner-fixture-capture-register.md). Use [cerner-secure-sandbox-smoke-checklist.md](cerner-secure-sandbox-smoke-checklist.md) for the separate manual live check.
