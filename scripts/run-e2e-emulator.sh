#!/usr/bin/env bash
# Runs Team B's E2E integration tests on the Android emulator in CI.
#
# Extracted from .github/workflows/team-b-ci.yml: the android-emulator-runner
# action executes each `script:` line as a separate `sh -c` command, so
# multi-line if/for constructs written inline never parse (they fail with
# "Syntax error: end of file unexpected"). Keeping the logic in this file
# lets the workflow invoke it as a single line.
#
# Requires: STAGING_BACKEND_URL env var, a booted emulator (emulator-5554),
# and must be run from the repo root.
set -u

cd frontend

if [ -z "${STAGING_BACKEND_URL:-}" ]; then
  echo "STAGING_BACKEND_URL not set — skipping E2E tests."
  exit 0
fi
echo "Running E2E tests against: $STAGING_BACKEND_URL"

if [ ! -d integration_test ]; then
  echo "No integration_test/ directory found — skipping E2E."
  exit 0
fi

BLOCKED_LIST=/tmp/blocked_tests.txt
EXIT_CODE=0

ALL_TESTS=$(find integration_test -name "*_test.dart" | sort)
if [ -z "$ALL_TESTS" ]; then
  echo "No integration test files found — skipping E2E."
  exit 0
fi

for test_file in $ALL_TESTS; do
  if [ -f "$BLOCKED_LIST" ] && grep -q "$test_file" "$BLOCKED_LIST"; then
    echo "SKIP (// BLOCKED:): $test_file"
  else
    echo "RUN: $test_file"
    flutter test "$test_file" \
      -d emulator-5554 \
      --dart-define=STAGING_BACKEND_URL="$STAGING_BACKEND_URL" \
      --reporter expanded || EXIT_CODE=$?
  fi
done
exit $EXIT_CODE
