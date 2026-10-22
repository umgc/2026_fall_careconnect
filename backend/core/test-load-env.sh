#!/bin/bash

# load-env.sh test harness (Test Plan TC-ENV-001…007)
# Usage: ./test-load-env.sh [path/to/load-env.sh]
#
# Runs the loader in a temporary directory against a synthetic .env, with a
# stub command in place of the backend. Each run is under env -i, so nothing
# in the caller's environment can stand in for a variable the .env leaves out.
# The loader runs under the same bash as this script. Not run by CI.

set -u

loader_arg="${1:-./load-env.sh}"
LOADER="$(cd "$(dirname "$loader_arg")" && pwd)/$(basename "$loader_arg")"
SAMPLE="$(cd "$(dirname "$0")" && pwd)/sampleDotEnv.txt"
BASH_BIN="${BASH:-bash}"

if [ ! -f "$LOADER" ]; then
    echo "Loader not found: $loader_arg"
    exit 2
fi

required_vars=(
    "JDBC_URI"
    "DB_USER"
    "DB_PASSWORD"
    "SECURITY_JWT_SECRET"
    "FIREBASE_PROJECT_ID"
    "FIREBASE_SENDER_ID"
)

# Same order as load-env.sh
optional_vars=(
    "STRIPE_SECRET_KEY"
    "DEEPSEEK_API_KEY"
    "DEEPSEEK_OPENROUTER_API_KEY"
    "OPENAI_API_KEY"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "S3_BUCKET_NAME"
    "FITBIT_AUTHORIZATION_URI"
    "FITBIT_TOKEN_URI"
    "FITBIT_USERINFO_URI"
    "STRIPE_API_URL"
    "GOOGLE_CLIENT_ID"
    "GOOGLE_CLIENT_SECRET"
    "APPLE_SHARED_SECRET"
    "GOOGLE_ACCESS_TOKEN"
    "GOOGLE_SERVICE_ACCOUNT_FILE"
)

SYNTHETIC_JDBC_URI="jdbc:postgresql://localhost:5433/tc_env_synthetic"

# Stands in for the backend: records its arguments and the JDBC_URI it was
# given, then exits with its first argument.
stub=("$BASH_BIN" -c 'printf "%s\n" "$@" > stub.out; printenv JDBC_URI > stub.env; exit "$1"' stub)

passed=0
failed=0
case_failures=()

# write_env <dir> <required vars to leave out, space-separated> <optional vars to set, space-separated>
write_env() {
    local dir="$1" skip=" $2 " set_optional="$3" var
    : > "$dir/.env"
    for var in "${required_vars[@]}"; do
        case "$skip" in *" $var "*) continue ;; esac
        if [ "$var" = "JDBC_URI" ]; then
            echo "JDBC_URI=$SYNTHETIC_JDBC_URI" >> "$dir/.env"
        else
            echo "$var=synthetic-$var" >> "$dir/.env"
        fi
    done
    for var in $set_optional; do
        echo "$var=synthetic-$var" >> "$dir/.env"
    done
}

# run_loader <dir> <command args...>: sets rc and out
run_loader() {
    local dir="$1"
    shift
    out="$(cd "$dir" && env -i PATH="$PATH" "$BASH_BIN" "$LOADER" "$@" 2>&1)"
    rc=$?
}

fail() {
    case_failures+=("$1")
}

expect_rc() {
    [ "$rc" -eq "$1" ] || fail "exit code $rc, expected $1"
}

expect_line() {
    printf '%s\n' "$out" | grep -qxF -- "$1" || fail "missing line: $1"
}

expect_no_line() {
    ! printf '%s\n' "$out" | grep -qxF -- "$1" || fail "unexpected line: $1"
}

expect_stub_ran() {
    [ -f "$1/stub.out" ] || fail "stub command did not run"
}

expect_stub_not_run() {
    [ ! -f "$1/stub.out" ] || fail "stub command ran"
}

finish_case() {
    local id="$1" title="$2" reason
    if [ ${#case_failures[@]} -eq 0 ]; then
        echo "$id PASS  $title"
        passed=$((passed + 1))
    else
        echo "$id FAIL  $title"
        for reason in "${case_failures[@]}"; do
            echo "    - $reason"
        done
        echo "    loader output:"
        printf '%s\n' "$out" | sed -e 's/^Database: .*/Database: <not shown>/' -e 's/^/      | /'
        failed=$((failed + 1))
    fi
    case_failures=()
}

new_dir() {
    mktemp -d "${TMPDIR:-/tmp}/tc-env.XXXXXX"
}

echo "Loader: $LOADER"
echo "Bash:   $("$BASH_BIN" -c 'echo $BASH_VERSION')"
echo ""

# TC-ENV-001: every required variable, no optional ones (DEF-ENV-01)
d="$(new_dir)"
write_env "$d" "" ""
run_loader "$d" "${stub[@]}" 0
expect_rc 0
expect_stub_ran "$d"
expect_line "Database: $SYNTHETIC_JDBC_URI"
for var in "${optional_vars[@]}"; do
    expect_line "  - $var"
done
expect_no_line "  (All optional variables are set)"
expect_line "Starting CareConnect Backend..."
[ "$(cat "$d/stub.env" 2>/dev/null)" = "$SYNTHETIC_JDBC_URI" ] || fail "the command did not get JDBC_URI from .env"
finish_case "TC-ENV-001" "required set, no optional: lists all 16 and starts the command"
rm -rf "$d"

# TC-ENV-002: every required and every optional variable
d="$(new_dir)"
write_env "$d" "" "${optional_vars[*]}"
run_loader "$d" "${stub[@]}" 0
expect_rc 0
expect_stub_ran "$d"
expect_line "  (All optional variables are set)"
printf '%s\n' "$out" | grep -q '^  - ' && fail "an optional variable is listed as unset"
expect_line "Starting CareConnect Backend..."
finish_case "TC-ENV-002" "required and optional all set: none listed, starts the command"
rm -rf "$d"

# TC-ENV-003: the first two optional variables set, the rest unset
d="$(new_dir)"
write_env "$d" "" "STRIPE_SECRET_KEY DEEPSEEK_API_KEY"
run_loader "$d" "${stub[@]}" 0
expect_rc 0
expect_stub_ran "$d"
expect_no_line "  - STRIPE_SECRET_KEY"
expect_no_line "  - DEEPSEEK_API_KEY"
for var in "${optional_vars[@]:2}"; do
    expect_line "  - $var"
done
listed="$(printf '%s\n' "$out" | grep -c '^  - ')"
[ "$listed" -eq 14 ] || fail "$listed optional variables listed, expected 14"
expect_line "Starting CareConnect Backend..."
finish_case "TC-ENV-003" "some optional set: lists only the 14 unset, starts the command"
rm -rf "$d"

# TC-ENV-004: the repository template, sampleDotEnv.txt, copied as .env
d="$(new_dir)"
if [ -f "$SAMPLE" ]; then
    cp "$SAMPLE" "$d/.env"
    run_loader "$d" "${stub[@]}" 0
    expect_rc 0
    expect_stub_ran "$d"
    expect_no_line "  - STRIPE_SECRET_KEY"
    expect_line "  - FITBIT_AUTHORIZATION_URI"
    expect_line "Starting CareConnect Backend..."
else
    out=""
    fail "sampleDotEnv.txt not found next to this script"
fi
finish_case "TC-ENV-004" "sampleDotEnv.txt as .env: starts the command"
rm -rf "$d"

# TC-ENV-005: a required variable missing, no optional ones
d="$(new_dir)"
write_env "$d" "SECURITY_JWT_SECRET" ""
run_loader "$d" "${stub[@]}" 0
expect_rc 1
expect_stub_not_run "$d"
expect_line "Warning: The following critical environment variables are not set:"
expect_line "SECURITY_JWT_SECRET"
expect_no_line "Starting CareConnect Backend..."
expect_line "Please set the missing environment variables before starting the application"
finish_case "TC-ENV-005" "required variable missing: names it, exits 1, does not start"
rm -rf "$d"

# TC-ENV-006: no .env file
d="$(new_dir)"
run_loader "$d" "${stub[@]}" 0
expect_rc 1
expect_stub_not_run "$d"
expect_line "Error: .env file not found in current directory"
expect_no_line "Starting CareConnect Backend..."
finish_case "TC-ENV-006" "no .env: exits 1, does not start"
rm -rf "$d"

# TC-ENV-007: arguments reach the command intact and its exit code comes back
d="$(new_dir)"
write_env "$d" "" ""
run_loader "$d" "${stub[@]}" 7 "two words" "-Dspring.profiles.active=dev"
expect_rc 7
expect_stub_ran "$d"
expected_args="$(printf '%s\n' 7 "two words" "-Dspring.profiles.active=dev")"
[ "$(cat "$d/stub.out" 2>/dev/null)" = "$expected_args" ] || fail "the command did not get its arguments intact"
finish_case "TC-ENV-007" "arguments passed intact, command's exit code returned"
rm -rf "$d"

echo ""
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
