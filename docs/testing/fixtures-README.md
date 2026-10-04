# Cerner M3 Test Fixture Guide

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

Create files only when a test consumes them. Avoid empty placeholder directories. Java test helpers should follow `TESTING_NORMS.md` and live under `backend/core/src/test/java/com/careconnect/testsupport/fixtures` when shared.

## Purpose by directory

| Directory | Contents |
|---|---|
| `cerner/fhir/` | Synthetic or sanitized FHIR R4 resources and searchset Bundles received from the Cerner boundary |
| `cerner/oauth/` | Synthetic OAuth token success/error bodies with unmistakably fake tokens and identifiers |
| `expected/` | Paired canonical mapper outputs; API outputs are not final until OpenAPI 1.0 approval |
| `wiremock/mappings/` | WireMock stub definitions for success and failure flows |
| `wiremock/__files/` | Response bodies returned by WireMock stubs |

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
