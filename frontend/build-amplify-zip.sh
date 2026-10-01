#!/usr/bin/env bash
# Builds the Flutter web app and zips build/web's *contents* (not the folder
# itself) into manual-amplify.zip, one level above the git repo — matching
# the existing manual Amplify drag-and-drop upload flow documented in
# frontend/README.md and cloudformation-fargate/DEPLOY_2026_SUMMER.md §5.
#
# All three --dart-define values are optional. Leave them blank to reproduce
# the plain `flutter build web` documented in frontend/README.md (falls back
# to http://localhost:8080 at runtime); set BACKEND_URL to point the build at
# a real deployed backend instead.

set -euo pipefail

BACKEND_URL=""
APP_DOMAIN=""
APP_PORT=""
OUTPUT_ZIP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--backend-url)
      BACKEND_URL="$2"
      shift 2
      ;;
    -d|--app-domain)
      APP_DOMAIN="$2"
      shift 2
      ;;
    --app-port)
      APP_PORT="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_ZIP="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./build-amplify-zip.sh [options]

Builds frontend/build/web and zips its contents for manual upload to AWS
Amplify (Amplify console -> app -> branch -> Deploy updates -> drag and drop).

Options:
  -b, --backend-url <url>   --dart-define=BACKEND_URL (blank: falls back to
                              http://localhost:8080 at runtime)
  -d, --app-domain <host>   --dart-define=APP_DOMAIN (hostname only, no
                              https://) — needed alongside --backend-url for
                              a real deployed backend
      --app-port <port>     --dart-define=APP_PORT (typically 443 for a real
                              deployed backend)
  -o, --output <path>       Zip output path (default: ../manual-amplify.zip,
                              i.e. one level above the git repo, matching the
                              existing manual deploy convention)
  -h, --help                Show this help text
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$BACKEND_URL" && ! "$BACKEND_URL" =~ ^https?:// ]]; then
  echo "Warning: --backend-url '$BACKEND_URL' has no http:// or https:// scheme." >&2
  echo "Without one, the compiled app treats it as a relative path and resolves API calls against whatever domain hosts the built app, not the intended backend." >&2
  read -r -p "Add https:// automatically? [Y/n] " reply
  reply="${reply:-Y}"
  if [[ "$reply" =~ ^[Yy] ]]; then
    BACKEND_URL="https://${BACKEND_URL}"
    echo "Using: $BACKEND_URL"
  else
    echo "Proceeding with '$BACKEND_URL' as-is." >&2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$OUTPUT_ZIP" ]]; then
  OUTPUT_ZIP="$(cd "$REPO_ROOT/.." && pwd)/manual-amplify.zip"
fi

cd "$SCRIPT_DIR"

BUILD_ARGS=(build web --release --base-href "/")
if [[ -n "$BACKEND_URL" ]]; then
  BUILD_ARGS+=(--dart-define="BACKEND_URL=${BACKEND_URL}")
fi
if [[ -n "$APP_DOMAIN" ]]; then
  BUILD_ARGS+=(--dart-define="APP_DOMAIN=${APP_DOMAIN}")
fi
if [[ -n "$APP_PORT" ]]; then
  BUILD_ARGS+=(--dart-define="APP_PORT=${APP_PORT}")
fi

echo "Running: flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}"

rm -f "$OUTPUT_ZIP"
(cd build/web && zip -r "$OUTPUT_ZIP" .)

echo "Wrote $OUTPUT_ZIP"
echo "Upload it: Amplify console -> your app -> branch -> Deploy updates -> drag and drop"
