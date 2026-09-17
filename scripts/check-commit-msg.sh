#!/usr/bin/env bash
# scripts/check-commit-msg.sh
# Enforces conventional commit message format.
#
# Allowed format:  <type>: <description>
# Allowed types:   feat, feature, fix, hotfix, chore, docs, test
#
# Examples:
#   feat: add athenahealth patient fetch service
#   feature: add athenahealth patient fetch service
#   fix: resolve null pointer in dashboard
#   hotfix: patch auth token expiry bug
#   chore: update dependencies
#   docs: update API guide
#   test: add unit tests for vitals service

set -euo pipefail

COMMIT_MSG_FILE="$1"
COMMIT_MSG="$(cat "$COMMIT_MSG_FILE")"

# Ignore merge commits, fixup commits, and squash commits
if echo "$COMMIT_MSG" | grep -qE "^(Merge|fixup!|squash!)"; then
  exit 0
fi

ALLOWED_TYPES="feat|feature|fix|hotfix|chore|docs|test"

# Pattern: <type>: <non-empty description>
if echo "$COMMIT_MSG" | grep -qE "^($ALLOWED_TYPES): .+"; then
  exit 0
fi

echo ""
echo "  ⚠️  WARNING: Commit message does not follow the recommended format."
echo ""
echo "  Recommended format:  <type>: <description>"
echo ""
echo "  Allowed types:  feat, feature, fix, hotfix, chore, docs, test"
echo ""
echo "  Examples:"
echo "    feat: add athenahealth patient fetch service"
echo "    fix: resolve null pointer in dashboard"
echo "    hotfix: patch auth token expiry bug"
echo "    chore: update dependencies"
echo "    docs: update API guide"
echo "    test: add unit tests for vitals service"
echo ""
echo "  Your message: \"$COMMIT_MSG\""
echo "  Commit will proceed — please follow the convention going forward."
echo ""
exit 0
