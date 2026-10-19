# Epic sync: importing the full resource set (demographics, meds, observations…)

_Finding + fix documented 2026-09-16, **verified against a live resync** the same day. Explains why an
Epic-linked patient showed only `AllergyIntolerance` and `Immunization` in `ehr_resource`, what the
sync rework fixed, and what remains gated on the Epic app registration (not on our code)._

## In plain terms

When a user connects Epic, `EpicSyncService.syncNow` reads FHIR resource types for the linked patient,
filters them, and mirrors them into `ehr_resource` (which then feeds Ask AI's
`retrieval_index_chunk`). For the connected sandbox user (user 1 = patient@careconnect.com / "Mary
Johnson", Epic patient **Camila Lopez** `erXuFYUfucBZaryVksYEcMg3`), only **AllergyIntolerance** and
**Immunization** were showing up.

Investigation (live DB + `ehr_audit_event` + a live resync with added logging) showed several distinct
causes. The sync code had real gaps (now fixed), **but the headline missing resources — Observation and
MedicationRequest — are blocked by the Epic app registration, not by our code.**

## Verified live outcome (after the fix + a re-consent)

`ehr_resource` for user 1 now holds **Patient, AllergyIntolerance, Immunization**. Per-type reality
from the resync log:

| Resource type | What Epic returned | Stored | Explanation |
|---|---|---|---|
| Patient | `EPIC_READ` OK (1) | ✅ | demographics read added (was never fetched before) |
| AllergyIntolerance | `{AllergyIntolerance=1, OperationOutcome=1}` | ✅ (1) | real data; `OperationOutcome` stripped |
| Immunization | `{Immunization=1, OperationOutcome=1}` | ✅ (1) | real data; `OperationOutcome` stripped |
| Condition | `{OperationOutcome=1}` (200) | — | authorized, but **no data** for this patient |
| DocumentReference | `{OperationOutcome=1}` (200) | — | authorized, but **no data** for this patient |
| **Observation** | **403** `insufficient_scope` | — | **Epic app not authorized for this service** |
| **MedicationRequest** | **403** `insufficient_scope` | — | **Epic app not authorized for this service** |
| MedicationStatement / DiagnosticReport / Procedure | scope not granted | — | not enabled on the Epic app |
| (`Patient/$everything`) | **404** | — | not supported in this Epic sandbox; typed fallback carried the sync |

The 403s carry Epic's reason in the response header (empty body):
`WWW-Authenticate: Bearer error="insufficient_scope", error_description="The access token provided is
valid, but is not authorized for this service"`. The granted `scope` string *does* list
`patient/Observation.read` and `patient/MedicationRequest.read` — Epic still forbids the call because
those **APIs aren't enabled on the app registration**. Epic returns the requested scope in the token
but enforces the enabled-API list at call time.

## What the fix changed (code)

Approach: **`$everything` primary + typed per-type fallback**, keeping the status gate, granular
indexing, and scope handling.

### `EpicFhirClient.java`
- Added `read(userId, resourceType, fhirId)` — a single-resource `GET {base}/{type}/{id}` (no
  `patient` search param) for the **demographics read**. Audited as `EPIC_READ`.
- Added diagnostics that made the above table possible: an INFO line per fetch
  (`… -> N entries, types={…}`) so an "OK but stored nothing" case is visible, and on a 4xx the
  response **body + `WWW-Authenticate` header** are logged (a bare Epic "403" otherwise hides the
  `insufficient_scope` reason).

### `EpicSyncService.java` — reworked `syncNow`
1. **Primary `$everything` pass** (one call → demographics + compartment). Non-fatal when unsupported
   (here it 404s; the typed fallback runs).
2. **Explicit Patient read** if `$everything` didn't supply the Patient — this is what now lands
   demographics.
3. **Typed fallback**, driven by a `REQUIRED_SEARCH_PARAMS` map. `Observation` sweeps the US Core
   categories (`laboratory`, `vital-signs`, `social-history`, `core-characteristics`) — correct for
   when the app *is* authorized (Epic R4 Observation search requires `category`).
4. A shared **`mirror(...)`** helper that **skips any entry whose `resourceType` ≠ the expected type**
   (drops the informational `OperationOutcome`, so counts are honest) and **dedupes** by `type|fhirId`
   across both passes.

### Files touched
- `backend/core/src/main/java/com/careconnect/service/ehr/EpicSyncService.java`
- `backend/core/src/main/java/com/careconnect/service/ehr/EpicFhirClient.java`

Status: compiles (`./mvnw -o compile`); existing EHR unit tests pass; verified by a live
`GET /api/epic/resync`.

## Operational notes (from the live run)
- **Refresh tokens expire.** The stored Epic access token was long expired and the refresh token was
  dead (`invalid_grant` → the credential auto-flips to `NEEDS_REAUTH`). Recovery is a browser
  re-consent: `GET /api/epic/authorize?returnMode=web` → open the `authUrl` → Epic sandbox login
  (Camila Lopez: `fhircamila` / `epicepic1`) → the callback stores fresh tokens **and auto-triggers the
  sync**. A dead refresh token makes a resync return `{"stored":0,"ok":true}` because per-type failures
  are swallowed inside `syncNow` — check `ehr_credentials.status` / `last_error`.

## What's still needed — Epic app registration (no code)
To import Observation, MedicationRequest (and MedicationStatement / DiagnosticReport / Procedure),
on **fhir.epic.com** for app client_id `06bcba2f-c60b-443e-90a2-57ddf8c73463`:
1. Enable those R4 APIs on the app (Observation = Labs **and** Vitals, MedicationRequest, etc.).
2. **Disconnect + reconnect** so Epic issues a token authorized for those services.
3. Re-run `GET /api/epic/resync`. The Observation `category` sweep will then return labs/vitals; the
   rest will store.

## Verify end-to-end
```bash
# 1. start backend (Norton truststore + env)
cd backend/core && ./run-local-bedrock.ps1        # port 8081

# 2. login -> JWT
curl -s -X POST http://localhost:8081/v1/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"patient@careconnect.com","password":"password"}'

# 3. synchronous resync (surfaces top-level errors; per-type detail is in the backend log)
curl -s -H "Authorization: Bearer <JWT>" http://localhost:8081/api/epic/resync

# 4. confirm the mirror
psql -h localhost -p 5433 -U postgres -d careconnect -c \
  "SELECT resource_type, count(*) FROM ehr_resource WHERE user_id=1 GROUP BY 1 ORDER BY 1;"
psql -h localhost -p 5433 -U postgres -d careconnect -c \
  "SELECT resource_type, event_type, outcome, event_time FROM ehr_audit_event \
   WHERE event_type IN ('EPIC_FETCH','EPIC_READ','EPIC_EVERYTHING','EPIC_SYNC') \
   ORDER BY event_time DESC LIMIT 40;"
```

## Appendix — dev DB / pgAdmin access

The `careconnect` DB is the **Docker** Postgres on host port **5433** (`pg_docker/.env`), not the
native `postgresql-x64-18` service that owns **5432**. A pgAdmin "password authentication failed"
usually means it was pointed at 5432 (a different server, no `careconnect` DB).

- pgAdmin server: Host `localhost`, Port **5433**, Maintenance DB `careconnect`, User `postgres`,
  Password `changeme`.
- CLI (host): `PGPASSWORD=changeme "/c/Program Files/PostgreSQL/18/bin/psql.exe" -h localhost -p 5433 -U postgres -d careconnect`
- CLI (container): `docker exec -it postgres_container psql -U postgres -d careconnect`
