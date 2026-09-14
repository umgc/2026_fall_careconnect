#!/usr/bin/env bash
# scripts/check-branch-name.sh
# Enforces CareConnect branch naming convention on push.
# Allowed patterns: <type>/<team>-<description>
#
# Allowed types: feature, fix, hotfix, chore, docs, test
# Allowed teams: a, b, c, d, e
#
# Shared/integration branches (team-*-develop, develop, main) are allowed through.

set -euo pipefail

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"

if [[ -z "$BRANCH" ]]; then
  echo "Could not determine current branch name; skipping check."
  exit 0
fi

# Allow pushes from shared/integration branches directly
ALLOWED_EXACT=("develop" "main")
for allowed in "${ALLOWED_EXACT[@]}"; do
  if [[ "$BRANCH" == "$allowed" ]]; then
    exit 0
  fi
done

# Allow any team integration branch: team-a-develop, team-b-develop, etc.
if [[ "$BRANCH" =~ ^team-[a-e]-develop$ ]]; then
  exit 0
fi

# Enforce naming pattern for all other branches
# Allowed types: feature, fix, hotfix, chore, docs, test
# Allowed teams: a, b, c, d, e
if [[ "$BRANCH" =~ ^(feature|fix|hotfix|chore|docs|test)/[a-e]-.+ ]]; then
  echo "Branch name OK: $BRANCH"
  exit 0
fi

echo ""
echo "  ERROR: Branch name '$BRANCH' does not follow the required naming rules."
echo ""
echo "  Required pattern:  <type>/<team>-<description>"
echo ""
echo "  Allowed types:  feature, fix, hotfix, chore, docs, test"
echo "  Allowed teams:  a, b, c, d, e"
echo ""
echo "  Examples:"
echo "    feature/b-athena-patient-fetch"
echo "    fix/a-dashboard-null-pointer"
echo "    hotfix/c-auth-token-refresh"
echo "    chore/d-update-dependencies"
echo "    docs/e-update-api-guide"
echo "    test/b-add-coverage-for-vitals"
echo ""
echo "  Rename your branch:"
echo "    git branch -m $BRANCH <type>/<team>-<your-description>"
echo ""
exit 1
