# Medicare (Blue Button 2.0) read endpoints — frontend contract

WBS 1.4.1–1.4.2, issue #132. Read-only. Fixture-backed today, live CMS later.

## Why this exists

The frontend needs a real endpoint to build against while the live Blue Button client is still
in progress, and a demo should not depend on CMS sandbox availability. These three routes run
the same retrieval path the live client will run: read a FHIR `searchset` Bundle, walk
`entry[].resource`, apply the status gate, return what survives.

## Routes

All three require an authenticated caller (`/v1/api/medicare/**` is `.authenticated()` in
`SecurityConfig`). All three answer with the same envelope.

| Method | Path | Returns |
|---|---|---|
| GET | `/v1/api/medicare/patient` | beneficiary demographics (`Patient`) |
| GET | `/v1/api/medicare/coverage` | Medicare enrollment, one entry per part (`Coverage`) |
| GET | `/v1/api/medicare/visits` | claims history (`ExplanationOfBenefit`) |

## Envelope

```json
{
  "source": "MEDICARE",
  "mode": "mock",
  "synthetic": true,
  "total": 2,
  "resources": [ ... ]
}
```

- `synthetic` is `true` whenever the payload is fixture data rather than a real beneficiary's
  record. Surface it, or gate on it. A caller rendering claims or clinical history should not
  have to read config to know which it is holding.
- `total` is the count **after** the status gate, so it always matches `resources.length`.
- A single-valued read still returns a list. A missing resource is `total: 0` with an empty
  array, never a null element, so the frontend parses one shape for all three routes.

## What is stable and what is not

**Stable:** the routes, the envelope fields, and the auth requirement. Bind to these now.

**Not yet stable:** the contents of `resources`. Those are raw FHIR R4 today. They become mapped
views once `BlueButton_FHIR_to_UI_Mapping.docx` is confirmed. That change is confined to
`MedicareResponseMapper` and does not move the routes or the envelope.

The mapping document is the field contract, not this file and not the Figma. Codes stay as
`CodeableConcept` passthrough when the mapping is applied, per issue #132, so diagnosis and
procedure codes survive rather than being flattened to a display string.

## Configuration

```properties
careconnect.medicare.enabled=false   # default OFF, per environment
careconnect.medicare.mode=mock       # mock | live
```

Off by default on purpose: mock mode serves fabricated clinical and claims data, which must
never reach a real patient context. Enabled in the `dev` and `test` profiles. Override with
`CARECONNECT_MEDICARE_ENABLED` / `CARECONNECT_MEDICARE_MODE`.

When Medicare is disabled, or when `mode` has no registered source, the routes answer
`503` with `{"error": "medicare_unavailable", ...}` rather than an empty `200`. Setting
`mode=live` before a live source exists is therefore a 503 on the route, not a failed startup.

## Out of scope on this branch

- **Persistence.** Issue #132 has an open blocking decision between `medicare_connection` /
  `medicare_records` (SRS §9.2) and the WBS 1.4.3 canonical tables. Nothing here writes, and
  ADR-08 forbids this source from writing the golden `patient` record regardless.
- **OAuth and token lifecycle.** The live path owns that. The token never reaches the frontend:
  the connect screen starts the CMS round trip, the backend holds the token, and the client only
  ever sees mapped JSON (`NFR-SEC-03`).
- **The `EhrApiClient` interface.** Two incompatible versions exist on unmerged branches
  (Team Bravo's `client.ehr`, Team Delta's `service.ehr`). `MedicareSource` is Team Echo's own
  port with matching method names so adopting whichever lands is one small adapter.
