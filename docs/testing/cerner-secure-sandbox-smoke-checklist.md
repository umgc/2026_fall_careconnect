# Cerner Secure Sandbox Smoke Checklist

**Owner:** Team C QA Lead
**Frequency:** Weekly while integration is active and once within the week before sign-off
**Boundary:** Synthetic data, read-only retrieval, sanitized evidence, no write-back

## Verified environment references

- Oracle Health service-root documentation: <https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/srv_root_url.html>
- Patient FHIR base: `https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d`
- Patient SMART discovery: `{patientBase}/.well-known/smart-configuration`
- Patient authorization endpoint: `https://authorization.cerner.com/tenants/ec2458f2-1e24-41c8-b71b-0e701af7583d/protocols/oauth2/profiles/smart-v1/personas/patient/authorize`
- Patient token endpoint: `https://authorization.cerner.com/tenants/ec2458f2-1e24-41c8-b71b-0e701af7583d/hosts/fhir-myrecord.cerner.com/protocols/oauth2/profiles/smart-v1/token`
- Deployed staging entry point: `https://staging.d2rx8or1jgx2rw.amplifyapp.com/`
- Backend callback: `https://lvg02g7m6j.execute-api.us-east-1.amazonaws.com/api/oracle-health/callback`

The supported release workflow is Patient/Online: a patient starts in deployed CareConnect and authorizes access to their own records. Keep the patient authorization endpoint, token endpoint host, audience, issuer and FHIR base consistent. Never mix a provider token or `fhir-ehr-code.cerner.com` host with this patient workflow. Provider/Code Console launch may be executed separately as a diagnostic check, but it is not the primary release journey.

## Before the test

- [ ] Record the candidate branch, commit SHA, application configuration profile, tester, and UTC start time.
- [ ] Confirm the patient is synthetic and approved for sandbox testing.
- [ ] Confirm the Oracle Health registration is Patient/Online with intended user Individual/Caregiver and purpose Access Their EHI.
- [ ] Start from the deployed CareConnect website, sign into CareConnect, and select Oracle Health Connect. Do not begin the primary release smoke from Code Console.
- [ ] Confirm the OAuth registration redirect URI exactly matches the client request.
- [ ] Use S256 PKCE and a new unpredictable `state`; do not save the code verifier or authorization code as evidence.
- [ ] Request only approved read scopes for the five-resource workflow. Do not request create, update, delete, or wildcard write scopes.
- [ ] Confirm the authorization endpoint, token endpoint host segment, `aud`, and FHIR base belong to the same persona/host pair.
- [ ] Confirm successful authorization returns through the backend callback with `status=ok`, the UI reports Connected, and reopening the connection view still reports the expected state.
- [ ] Prepare a sanitized evidence location. Disable or redact verbose network/header capture.

## Resource checks

Record HTTP status, FHIR `resourceType`, Bundle type/count, next-link presence, application result summary, and pass/fail. Use server-controlled patient context in the application; the patterns below describe the Oracle Health boundary.

| Resource | Read-only request pattern | Check |
|---|---|---|
| Patient | `GET {base}/Patient/{id}` | Correct synthetic Patient is returned; identity/provenance are retained; no demographic matching is inferred. |
| AllergyIntolerance | `GET {base}/AllergyIntolerance?patient={id}` | Valid records and empty results behave correctly; entered-in-error/missing reaction follow approved rules. |
| Condition | `GET {base}/Condition?patient={id}` | Status/category/code/date fields follow approved rules; paging is handled when present. |
| Encounter | `GET {base}/Encounter?patient={id}` | Status/class/type/period fields follow approved rules; paging is handled when present. |
| Appointment (provisional) | `GET {base}/Appointment?patient={id}&date=gt{start}&date=le{end}` or approved bounded `-date-or-req-period` equivalent | Search is bounded and read-only; proposed/no-time records are not represented as confirmed bookings. |

When a Bundle includes `link.relation = next`, verify the application follows the complete next URL on the same approved source and stops at the configured page limit. Do not manually splice or rewrite the continuation URL.

## Authorization and failure checks

- [ ] Direct patient authorization begins from deployed CareConnect without an EHR-provided `launch` token.
- [ ] A valid short-lived bearer token returns the expected successful resource response.
- [ ] An expired/invalid token produces a source-authorization outcome, not an empty clinical result.
- [ ] Insufficient scope is distinguishable from expired token and from CareConnect patient-access denial.
- [ ] Refresh is tested only if the registered client and approved application policy support it; attempts are bounded and tokens never appear in logs.
- [ ] No raw exception, bearer token, authorization code, cookie, verifier, or clinical payload is exposed in user-facing errors.

## Evidence record

```text
UTC date/time:
Tester:
Branch and commit SHA:
Application build/CI link:
Entry workflow: deployed CareConnect direct patient connection
Sandbox persona and base alias: Patient/Online; fhir-myrecord
Synthetic patient alias (no stable identifier):
SMART scopes requested (no token):
Resources checked:
Request-pattern summary:
HTTP/application-result summary:
Pagination observed and result:
Pass/fail by resource:
Sanitized evidence link:
Defect IDs:
Confirmed no write-back: yes/no
Confirmed secrets and stable identifiers removed: yes/no
```

## Completion

The smoke is complete only when the direct patient connection and each in-scope resource have a recorded outcome, disconnect/reconnect is assessed, any differences from fixtures are triaged, secrets and identifiers are removed from evidence, defects are linked, and the traceability matrix is updated. A Postman-only request or provider/Code Console launch proves only its tested boundary; neither replaces the deployed patient journey, contract, frontend, or automated regression evidence.
