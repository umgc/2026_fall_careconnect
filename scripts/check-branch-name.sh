#!/usr/bin/env bash
# scripts/check-branch-name.sh
# Enforces Team B branch naming convention on push.
# Allowed patterns: feature/b-* or hotfix/b-*
#
# Shared/integration branches (team-b-develop, develop, main) are allowed through.

set -euo pipefail

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"

if [[ -z "$BRANCH" ]]; then
  echo "Could not determine current branch name; skipping check."
  exit 0
fi

# Allow pushes from team integration and shared branches directly
ALLOWED_EXACT=("team-b-develop" "develop" "main")
for allowed in "${ALLOWED_EXACT[@]}"; do
  if [[ "$BRANCH" == "$allowed" ]]; then
    exit 0
  fi
done

# Enforce Team B naming pattern for all other branches
if [[ "$BRANCH" =~ ^(feature|hotfix)/b-.+ ]]; then
  echo "Branch name OK: $BRANCH"
  exit 0
fi

echo ""
echo "  ERROR: Branch name '$BRANCH' does not follow Team B naming rules."
echo ""
echo "  Required pattern:  feature/b-<description>"
echo "                     hotfix/b-<description>"
echo ""
echo "  Examples:"
echo "    feature/b-athena-patient-fetch"
echo "    hotfix/b-fix-auth-token-refresh"
echo ""
echo "  Rename your branch:"
echo "    git branch -m $BRANCH feature/b-<your-description>"
echo ""
exit 1
