#!/usr/bin/env bash
# scripts/athena-discover.sh
#
# Discovery probe against the athenahealth PREVIEW sandbox using 2-legged
# (client_credentials) OAuth. Saves every response under
# backend/core/src/test/resources/athena/ so the output doubles as the test fixture set.
# Run by hand, never in CI. Windows: use athena-discover.ps1.
#
# Facts baked in from a live run against practice 195900:
#   - OAuth lives at /oauth2/v1/*, FHIR R4 at /fhir/r4 (no practice path segment).
#   - ah-practice is a required SEARCH PARAMETER, format a-1.Practice-NNNNNN.
#   - The token endpoint has its own quota, tighter than the API rate limit; three rapid
#     requests returned 429. This script makes exactly ONE token request.
#   - An unconfigured scope fails the whole token request with 400 "Invalid Scope".
#   - Patient search requires one of [_id] [identifier] [name] [family,birthdate]
#     [family,gender] [family,given]; family alone is 403.
#   - A query estimated over 1000 results returns HTTP 200 with a fatal "too-costly"
#     OperationOutcome INSIDE Bundle.entry, so entries must be filtered on search.mode.
#
# Usage:
#   export ATHENA_CLIENT_ID=... ATHENA_CLIENT_SECRET=...
#   export ATHENA_PRACTICE_ID=a-1.Practice-195900   # the preview sandbox practice
#   sh scripts/athena-discover.sh
#
# ATHENA_PRACTICE_ID has no default: ATHENA_ENV=production is allowed, and a sandbox
# fallback would then be sent to production silently.
# Optional: ATHENA_SCOPES, ATHENA_ENV.

set -euo pipefail

: "${ATHENA_CLIENT_ID:?set ATHENA_CLIENT_ID}"
: "${ATHENA_CLIENT_SECRET:?set ATHENA_CLIENT_SECRET}"
: "${ATHENA_PRACTICE_ID:?set ATHENA_PRACTICE_ID (preview sandbox: a-1.Practice-195900)}"

ENVNAME="${ATHENA_ENV:-preview}"
PRACTICE="$ATHENA_PRACTICE_ID"
SCOPES="${ATHENA_SCOPES:-system/Patient.read}"

if [ "$ENVNAME" = "production" ]; then
  HOST="https://api.platform.athenahealth.com"
else
  HOST="https://api.preview.platform.athenahealth.com"
fi
FHIR="$HOST/fhir/r4"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/backend/core/src/test/resources/athena"
mkdir -p "$OUT"
command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)"; exit 1; }

hr() { printf '%s\n' "------------------------------------------------------------"; }

hr; echo "STEP 1: token (ONE request; the endpoint quota is tight)"; hr
curl -sS -o "$OUT/token-response.json" -X POST "$HOST/oauth2/v1/token" \
  -u "$ATHENA_CLIENT_ID:$ATHENA_CLIENT_SECRET" \
  -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
  -d 'grant_type=client_credentials' --data-urlencode "scope=$SCOPES"

TOKEN="$(jq -r '.access_token // empty' "$OUT/token-response.json")"
if [ -z "$TOKEN" ]; then
  echo "Token request failed:"; jq '.' "$OUT/token-response.json" 2>/dev/null || cat "$OUT/token-response.json"
  echo
  echo '  "Invalid Scope"  -> a scope in ATHENA_SCOPES is not configured on the portal app.'
  echo '  "invalid_client" -> wrong secret, or the app is not enabled for this environment.'
  echo '  "Quota Exceeded" -> token endpoint quota; wait and retry.'
  exit 1
fi
echo "access_token acquired (len ${#TOKEN}), expires_in $(jq -r '.expires_in' "$OUT/token-response.json")s"
echo "GRANTED scope (this, not ATHENA_SCOPES, drives which resource types you can sync):"
jq -r '.scope // "(none returned)"' "$OUT/token-response.json" | tr ' ' '\n' | sed 's/^/  /'
# Never leave a live bearer token in a committed fixture.
jq '.access_token = "REDACTED_FOR_FIXTURE"' "$OUT/token-response.json" > "$OUT/.t" && mv "$OUT/.t" "$OUT/token-response.json"

AUTH=(-H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')

hr; echo "STEP 2: CapabilityStatement"; hr
curl -sS "${AUTH[@]}" "$FHIR/metadata" | jq '.' > "$OUT/CapabilityStatement.json"
echo "Supported resource types:"
jq -r '[.rest[]?.resource[]?.type]|sort|join(" ")' "$OUT/CapabilityStatement.json" | fold -s -w 72 | sed 's/^/  /'
echo "Required search-param combinations per type:"
jq -r '.rest[]?.resource[]? | select(.extension) | "  \(.type): " +
       ([.extension[]?|select(.url|test("ah-search-parameter-metadata"))
        |.extension[]?|select(.url=="requiredAnySearchParams")|.valueString]|join(" | "))' \
  "$OUT/CapabilityStatement.json" | head -40

hr; echo "STEP 3: SMART configuration"; hr
curl -sS "${AUTH[@]}" "$FHIR/.well-known/smart-configuration" | jq '.' > "$OUT/smart-configuration.json"
jq -r 'to_entries|map(select(.key|test("endpoint")))|from_entries|to_entries[]|"  \(.key): \(.value)"' \
  "$OUT/smart-configuration.json"

hr; echo "STEP 4: patients (search needs a valid param combination)"; hr
printf '  %-34s %-6s %s\n' "QUERY" "HTTP" "PATIENTS"
for Q in 'family=Smith&gender=female' 'name=Testpatient'; do
  code="$(curl -sS -o /tmp/ath-p.json -w '%{http_code}' "${AUTH[@]}" \
    "$FHIR/Patient?ah-practice=$PRACTICE&$Q&_count=5")"
  n="$(jq -r '[.entry[]?|select(.search.mode!="outcome")]|length' /tmp/ath-p.json 2>/dev/null || echo 0)"
  oc="$(jq -r '[.entry[]?|select(.search.mode=="outcome")|.resource.issue[0].code]|join(",")' /tmp/ath-p.json 2>/dev/null)"
  printf '  %-34s %-6s %s%s\n' "$Q" "$code" "$n" "${oc:+  [outcome: $oc]}"
  if [ "${n:-0}" -gt 0 ]; then cp /tmp/ath-p.json "$OUT/Patient-searchset.json"; fi
done

if [ -f "$OUT/Patient-searchset.json" ]; then
  echo
  echo "Patients found:"
  jq -r '.entry[]?|select(.search.mode!="outcome")|.resource
         |"  \(.id)  \(.name[0].family // "?"), \(.name[0].given[0] // "?")  dob=\(.birthDate // "?")  \(.gender // "?")"' \
    "$OUT/Patient-searchset.json"
  PID="$(jq -r '[.entry[]?|select(.search.mode!="outcome")|.resource.id][0]' "$OUT/Patient-searchset.json")"

  hr; echo "STEP 5: per-resource pull for $PID (403 = scope not granted)"; hr
  printf '  %-22s %-6s %s\n' "RESOURCE" "HTTP" "ENTRIES"
  for RT in Condition Observation AllergyIntolerance MedicationRequest MedicationStatement \
            Immunization Procedure DocumentReference DiagnosticReport Encounter; do
    f="$OUT/${RT}-searchset.json"
    code="$(curl -sS -o "$f" -w '%{http_code}' "${AUTH[@]}" \
      "$FHIR/$RT?ah-practice=$PRACTICE&patient=$PID&_count=5")"
    if [ "$code" = "200" ]; then
      n="$(jq -r '[.entry[]?|select(.search.mode!="outcome")]|length' "$f" 2>/dev/null || echo '?')"
      [ "$n" = "0" ] && rm -f "$f"
    else
      n="(not saved)"; rm -f "$f"
    fi
    printf '  %-22s %-6s %s\n' "$RT" "$code" "$n"
  done
fi

hr; echo "Fixtures in $OUT:"; ls -1 "$OUT" | sed 's/^/  /'
echo "Scrub before committing. Never point this at production."
