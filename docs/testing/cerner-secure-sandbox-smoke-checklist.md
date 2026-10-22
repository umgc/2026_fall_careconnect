# Cerner Secure Sandbox Smoke Checklist

**Owner:** Team C QA Lead
**Frequency:** Weekly while integration is active and once within the week before sign-off
**Boundary:** Synthetic data, read-only retrieval, sanitized evidence, no write-back

## Verified environment references

- Oracle Health service-root documentation: <https://docs.oracle.com/en/industries/health/millennium-platform-apis/mfrap/srv_root_url.html>
- Provider FHIR base: `https://fhir-ehr-code.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d`
- Patient FHIR base: `https://fhir-myrecord.cerner.com/r4/ec2458f2-1e24-41c8-b71b-0e701af7583d`
- Provider SMART discovery: `{providerBase}/.well-known/smart-configuration`
- Provider authorization endpoint: `https://authorization.cerner.com/tenants/ec2458f2-1e24-41c8-b71b-0e701af7583d/protocols/oauth2/profiles/smart-v1/personas/provider/authorize`
- Provider token endpoint: `https://authorization.cerner.com/tenants/ec2458f2-1e24-41c8-b71b-0e701af7583d/hosts/fhir-ehr-code.cerner.com/protocols/oauth2/profiles/smart-v1/token`

If the patient persona is tested, discover and use the patient authorization/token endpoints and keep the `fhir-myrecord.cerner.com` audience/base consistent. Never mix a provider token with the patient FHIR host or the reverse.

## Before the test

- [ ] Record the candidate branch, commit SHA, application configuration profile, tester, and UTC start time.
- [ ] Confirm the patient is synthetic and approved for sandbox testing.
- [ ] Confirm the OAuth registration redirect URI exactly matches the client request.
- [ ] Use S256 PKCE and a new unpredictable `state`; do not save the code verifier or authorization code as evidence.
- [ ] Request only approved read scopes for the five-resource workflow. Do not request create, update, delete, or wildcard write scopes.
- [ ] Confirm the authorization endpoint, token endpoint host segment, `aud`, and FHIR base belong to the same persona/host pair.
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
Sandbox persona and base alias:
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

The smoke is complete only when each in-scope resource has a recorded outcome, any differences from fixtures are triaged, secrets and identifiers are removed from evidence, defects are linked, and the traceability matrix is updated. A Postman-only request proves Oracle Health availability; it does not replace application integration, contract, frontend, or automated regression evidence.
