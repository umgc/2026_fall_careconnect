#!/usr/bin/env bash
# Sync React Care Circle preview into Flutter web/ui-preview.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRONTEND_DIR/.." && pwd)"
MOBILE_APP="$REPO_ROOT/ui-integration/mobile-app"
DEST="$FRONTEND_DIR/web/ui-preview"

echo "Building React UI preview from $MOBILE_APP"
cd "$MOBILE_APP"
npm ci
npm run build

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R dist/. "$DEST/"

cat > "$DEST/README.txt" <<'EOF'
Generated files — do not edit by hand.
Built from ui-integration/mobile-app via frontend/scripts/sync_ui_preview.ps1 (or sync_ui_preview.sh).
Amplify also rebuilds these during frontend/amplify.yml before flutter build web.
EOF

echo "Synced UI preview to $DEST"
