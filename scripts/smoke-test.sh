#!/usr/bin/env bash
#
# Post-deploy smoke test for a CareConnect backend.
#
# Checks the things that only break once the app is deployed — configuration,
# routing, CORS, and the public base URL baked into outbound links. Unit and
# integration tests cannot catch these, because locally every one of them is
# trivially correct.
#
# Written for bash 3.2 so it runs on stock macOS as well as CI. That means no
# `mapfile`, no `${var,,}`, and no associative arrays.
#
# THIS SCRIPT LEAVES STATE BEHIND. Step 3 registers a PATIENT account and step 5
# verifies it, and there is no account-deletion endpoint to undo that -- the API
# exposes no DELETE for users. Every run therefore leaves one verified and one
# rejected account in the target database. That is acceptable on a scratch
# environment and is not acceptable on anything carrying real data.
#
#   - The address is `smoke-<timestamp>@example.com`. `example.com` is reserved
#     by RFC 2606 and can never be registered, so a prod-profile run that
#     actually sends mail cannot reach a real person. Override with
#     --email-domain only if you own the domain.
#   - The password is generated fresh per run and printed once in the summary.
#     Nothing reusable is committed to this repository.
#   - The summary at the end lists exactly what was created, with the SQL to
#     remove it.
#
# Usage:
#   ./scripts/smoke-test.sh --backend-url https://abc123.execute-api.us-east-1.amazonaws.com
#   ./scripts/smoke-test.sh -u "$BACKEND_URL" --log-group /ecs/careconnect-backend-cfdemo
#
# Exit codes: 0 = all hard checks passed, 1 = at least one hard check failed.
#
# What this leaves behind: every run registers two PATIENT accounts,
# smoke-<stamp>@example.com and smoke-noaddr-<stamp>@example.com, and verifies
# the first. Nothing deletes them. CareConnect has no account-deletion endpoint:
# removal is a manual request to careconnect.support@gmail.com with a 30-day SLA,
# and HIPAA retention keeps the underlying records for six years regardless.
# Passwords are generated per run and never recorded, so the accounts are inert,
# but the user table grows by two rows every time this runs. Do not point it at
# an environment where that matters.

set -uo pipefail

# Seed from the environment so `BACKEND_URL=... ./smoke-test.sh` works; flags
# below take precedence.
BACKEND_URL="${BACKEND_URL:-}"
LOG_GROUP="${LOG_GROUP:-}"
PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-us-east-1}"
FRONTEND_ORIGIN="http://localhost:3000"
LOG_WAIT_SECONDS=90
# RFC 2606 reserves example.com, so it can never be registered and a run that
# really sends mail cannot reach a stranger.
EMAIL_DOMAIN="${SMOKE_EMAIL_DOMAIN:-example.com}"

# Under `set -u`, a bare `shift 2` on a flag given without its value aborts with
# bash's own unbound-variable message before the parser can say anything useful.
need_value() {
  if [[ $# -lt 2 ]]; then
    echo "Missing value for $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--backend-url)   need_value "$@"; BACKEND_URL="$2"; shift 2 ;;
    -g|--log-group)     need_value "$@"; LOG_GROUP="$2"; shift 2 ;;
    -p|--profile)       need_value "$@"; PROFILE="$2"; shift 2 ;;
    -r|--region)        need_value "$@"; REGION="$2"; shift 2 ;;
    -o|--origin)        need_value "$@"; FRONTEND_ORIGIN="$2"; shift 2 ;;
    -w|--log-wait)      need_value "$@"; LOG_WAIT_SECONDS="$2"; shift 2 ;;
    -d|--email-domain)  need_value "$@"; EMAIL_DOMAIN="$2"; shift 2 ;;
    -h|--help)
      # Print the leading comment block, whatever its length, rather than a
      # hardcoded line range that drifts every time the header is edited.
      awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$BACKEND_URL" ]]; then
  echo "Missing --backend-url (or set BACKEND_URL)." >&2
  exit 1
fi

# Normalise: no trailing slash, and never a /v1 suffix — the app builds those
# paths itself, so a doubled prefix produces confusing 404s.
BACKEND_URL="$(printf '%s' "$BACKEND_URL" | sed -e 's#/*$##' -e 's#/v1$##')"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

pass() { echo "  PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo "  WARN  $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
skip() { echo "  SKIP  $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
step() { echo; echo "==> $1"; }

aws_cli() {
  if [[ -n "$PROFILE" ]]; then
    aws --profile "$PROFILE" --region "$REGION" "$@"
  else
    aws --region "$REGION" "$@"
  fi
}

# Scheme + host + port, which is what has to match between the backend we asked
# and the links it hands out.
url_origin() {
  printf '%s' "$1" | sed -e 's#\(https\{0,1\}://[^/]*\).*#\1#'
}

echo "CareConnect smoke test"
echo "  backend:  $BACKEND_URL"
echo "  origin:   $FRONTEND_ORIGIN"
[[ -n "$LOG_GROUP" ]] && echo "  logs:     $LOG_GROUP"

# ---------------------------------------------------------------------------
step "1. Health"

# One request, not two: -w appends the status code to the body, so a flaky
# endpoint cannot report healthy on one call and 503 on the next.
HEALTH_RAW="$(curl -s -w '\n%{http_code}' --max-time 30 "$BACKEND_URL/v1/api/test/health")"
HEALTH_CODE="$(printf '%s' "$HEALTH_RAW" | tail -1)"
HEALTH_BODY="$(printf '%s' "$HEALTH_RAW" | sed '$d')"

if [[ "$HEALTH_CODE" == "200" ]]; then
  pass "GET /v1/api/test/health -> 200"
else
  fail "GET /v1/api/test/health -> $HEALTH_CODE (expected 200)"
fi

if printf '%s' "$HEALTH_BODY" | grep -q '"status":"healthy"'; then
  pass "health body reports status=healthy"
else
  fail "health body did not report status=healthy: $(printf '%s' "$HEALTH_BODY" | head -c 200)"
fi

# ---------------------------------------------------------------------------
step "2. CORS"
# Plain curl sends no Origin, so it passes even when a browser would be blocked.
# Spring enforces CORS_ALLOWED_LIST on the container, and an app-only redeploy
# can silently reset it from the checked-in parameter file.

CORS_HEADERS="$(curl -s -D - -o /dev/null --max-time 30 \
  -X OPTIONS "$BACKEND_URL/v1/api/test/health" \
  -H "Origin: $FRONTEND_ORIGIN" \
  -H "Access-Control-Request-Method: GET")"

if printf '%s' "$CORS_HEADERS" | grep -qi '^access-control-allow-origin'; then
  pass "preflight from $FRONTEND_ORIGIN returns access-control-allow-origin"
else
  fail "preflight from $FRONTEND_ORIGIN has no access-control-allow-origin header"
fi

# ---------------------------------------------------------------------------
step "3. Registration"

STAMP="$(date +%Y%m%d%H%M%S)"
TEST_EMAIL="smoke-${STAMP}@${EMAIL_DOMAIN}"
BAD_EMAIL="smoke-noaddr-${STAMP}@${EMAIL_DOMAIN}"
START_MS=$(( ( $(date +%s) - 30 ) * 1000 ))

# Generated per run rather than committed. A fixed password in a public repo is
# a working credential for every account this script has ever left behind.
# The suffix guarantees the upper/lower/digit/symbol mix the app expects.
random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 12
  else
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 24
  fi
}
TEST_PASSWORD="Sm0ke!$(random_secret)Aa1"
if [[ ${#TEST_PASSWORD} -lt 16 ]]; then
  echo "Could not generate a random password (no openssl, no /dev/urandom)." >&2
  exit 1
fi

# Deliberately omits `verificationBaseUrl`. That field lets a client override
# the link host, which would mask a misconfigured server-side base URL — the
# precise failure this test exists to detect.
REGISTER_BODY="$(cat <<JSON
{
  "role": "PATIENT",
  "name": "Smoke Test",
  "email": "$TEST_EMAIL",
  "password": "$TEST_PASSWORD",
  "firstName": "Smoke",
  "lastName": "Test",
  "phone": "555-0100",
  "dob": "1990-01-01",
  "gender": "MALE",
  "address": {
    "line1": "1 Test St", "line2": "", "city": "Adelphi",
    "state": "MD", "zip": "20783", "phone": "555-0100"
  }
}
JSON
)"

REG_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
  -X POST "$BACKEND_URL/v1/api/auth/register" \
  -H "Content-Type: application/json" -d "$REGISTER_BODY")"

if [[ "$REG_CODE" == "200" ]]; then
  pass "POST /v1/api/auth/register -> 200 ($TEST_EMAIL)"
else
  fail "POST /v1/api/auth/register -> $REG_CODE (expected 200)"
fi

# ---------------------------------------------------------------------------
step "4. Verification link"
# The dev profile logs email to the container instead of sending it, so the
# link is only observable in CloudWatch.

VERIFY_LINK=""

if [[ "$REG_CODE" != "200" ]]; then
  skip "registration failed, cannot check the verification link"
elif [[ -z "$LOG_GROUP" ]]; then
  skip "no --log-group given, cannot read the emailed link"
  echo "        (pass --log-group /ecs/careconnect-backend-<env> to enable this check)"
else
  WAITED=0
  while [[ $WAITED -lt $LOG_WAIT_SECONDS ]]; do
    VERIFY_LINK="$(aws_cli logs filter-log-events \
      --log-group-name "$LOG_GROUP" \
      --start-time "$START_MS" \
      --filter-pattern '"auth/verify/"' \
      --query 'events[-1].message' --output text 2>/dev/null \
      | grep -o 'https\{0,1\}://[^[:space:]]*/v1/api/auth/verify/[A-Za-z0-9-]*' | tail -1)"
    [[ -n "$VERIFY_LINK" ]] && break
    sleep 5
    WAITED=$((WAITED + 5))
  done

  if [[ -z "$VERIFY_LINK" ]]; then
    fail "no verification link found in $LOG_GROUP within ${LOG_WAIT_SECONDS}s"
  else
    pass "verification link found in logs"

    # The assertion that matters. A link pointing anywhere other than the
    # backend we just called means the server's public base URL is wrong, and
    # every verification email it sends is unusable.
    LINK_ORIGIN="$(url_origin "$VERIFY_LINK")"
    BACKEND_ORIGIN="$(url_origin "$BACKEND_URL")"

    if [[ "$LINK_ORIGIN" == "$BACKEND_ORIGIN" ]]; then
      pass "link origin matches backend ($LINK_ORIGIN)"
    else
      fail "link origin is $LINK_ORIGIN but backend is $BACKEND_ORIGIN"
      echo "        careconnect.baseurl is not set to this environment's public URL."
      echo "        Check BASE_URL in the ECS task definition."
    fi

    case "$BACKEND_ORIGIN" in
      https://*)
        case "$LINK_ORIGIN" in
          https://*) pass "link uses https" ;;
          *)         fail "backend is https but the link is not: $LINK_ORIGIN" ;;
        esac ;;
      *) skip "backend is not https, no scheme assertion" ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
step "5. Verification round trip"

if [[ -z "$VERIFY_LINK" ]]; then
  skip "no link to follow"
else
  VERIFY_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$VERIFY_LINK")"
  if [[ "$VERIFY_CODE" == "200" ]]; then
    pass "following the emailed link -> 200"
  else
    fail "following the emailed link -> $VERIFY_CODE (expected 200)"
  fi

  CHECK="$(curl -s --max-time 30 \
    "$BACKEND_URL/v1/api/auth/check-verification?email=$TEST_EMAIL")"
  # The endpoint returns exactly {"verified":true|false}, so assert the field.
  # A bare `true` also matches the false body's own field name in other shapes.
  if printf '%s' "$CHECK" | grep -q '"verified":[[:space:]]*true'; then
    pass "check-verification reports the account verified"
  else
    fail "check-verification did not report verified: $(printf '%s' "$CHECK" | head -c 200)"
  fi
fi

# ---------------------------------------------------------------------------
step "6. Validation failure modes"
# Smoke tests that only exercise the happy path miss the case where a bad
# request takes the server down a crash path instead of a validation path.

BAD_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
  -X POST "$BACKEND_URL/v1/api/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"role\":\"PATIENT\",\"name\":\"No Address\",\"email\":\"$BAD_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"firstName\":\"No\",\"lastName\":\"Address\"}")"

case "$BAD_CODE" in
  400)
    pass "register without address -> 400" ;;
  500)
    warn "register without address -> 500, expected 400 (known issue #12)"
    echo "        Promote this to a hard failure once #12 is fixed." ;;
  *)
    fail "register without address -> $BAD_CODE (expected 400)" ;;
esac

# ---------------------------------------------------------------------------
step "Accounts left behind"
# There is no account-deletion endpoint, so this cannot clean up after itself.
# Say plainly what is now in the database and how to remove it.

if [[ "$REG_CODE" != "200" && "$BAD_CODE" != "500" ]]; then
  echo "  Nothing to clean up: no registration succeeded."
else
  echo "  This run created accounts that nothing deletes automatically:"
  [[ "$REG_CODE" == "200" ]] && \
    echo "    $TEST_EMAIL   (registered, and verified if step 5 passed)"
  [[ "$BAD_CODE" == "500" ]] && \
    echo "    $BAD_EMAIL   (validation returned 500, so the row may exist)"
  echo "  Password, generated for this run only:"
  echo "    $TEST_PASSWORD"
  echo
  echo "  To remove them, against the environment's database. The child row goes"
  echo "  first -- patient.user_id is a foreign key, so the users row will not"
  echo "  delete while it is there:"
  echo "    DELETE FROM patient WHERE user_id IN"
  echo "      (SELECT id FROM users WHERE email LIKE 'smoke-%@${EMAIL_DOMAIN}');"
  echo "    DELETE FROM users WHERE email LIKE 'smoke-%@${EMAIL_DOMAIN}';"
  echo "  Run this only on a scratch environment. Never point this script at an"
  echo "  environment holding real user data."
fi

# ---------------------------------------------------------------------------
echo
echo "-----------------------------------------------"
printf 'passed %d   failed %d   warned %d   skipped %d\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "SMOKE TEST FAILED"
  exit 1
fi

echo "SMOKE TEST PASSED"
[[ $SKIP_COUNT -gt 0 ]] && echo "(some checks were skipped — see above)"
exit 0
