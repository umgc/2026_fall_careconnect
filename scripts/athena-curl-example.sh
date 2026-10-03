#!/usr/bin/env bash
# Minimal working athenahealth PREVIEW example: 2-legged token, then a Patient search.
# Fill in the two values below. Requires curl and jq.
set -euo pipefail

CLIENT_ID='PASTE_CLIENT_ID_HERE'
CLIENT_SECRET='PASTE_CLIENT_SECRET_HERE'

HOST='https://api.preview.platform.athenahealth.com'
PRACTICE='a-1.Practice-195900'   # preview practice 195900, in athena's prefixed id format

# --- 1. token -------------------------------------------------------------
# Credentials go in the Basic header via -u, never in the body. Request only the
# scopes the portal app is configured for; an unconfigured scope returns
# 400 "Invalid Scope" and kills the whole request.
TOKEN="$(curl -sS -X POST "$HOST/oauth2/v1/token" \
  -u "$CLIENT_ID:$CLIENT_SECRET" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -d 'grant_type=client_credentials' \
  --data-urlencode 'scope=system/Patient.read' \
  | jq -r '.access_token')"

[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "token request failed"; exit 1; }

# --- 2. query -------------------------------------------------------------
# ah-practice is REQUIRED on every call. Patient search also requires one of
# [_id] [identifier] [name] [family,birthdate] [family,gender] [family,given];
# family alone returns 403. -G + --data-urlencode keeps the dotted practice id safe.
curl -sS -G "$HOST/fhir/r4/Patient" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/json' \
  --data-urlencode "ah-practice=$PRACTICE" \
  --data-urlencode 'family=Smith' \
  --data-urlencode 'gender=female' \
  --data-urlencode '_count=5' \
  | jq '[.entry[] | select(.search.mode != "outcome") | .resource
         | {id, name: (.name[0].family + ", " + .name[0].given[0]), birthDate, gender}]'
