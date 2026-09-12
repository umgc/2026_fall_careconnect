#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd "${SCRIPT_DIR}/.." && pwd)"

# Where prebuilt binaries are published. Override to use a fork or pin a tag.
DEV_TOOLKIT_REPO="${DEV_TOOLKIT_REPO:-umgc/2026_fall_careconnect}"
DEV_TOOLKIT_VERSION="${DEV_TOOLKIT_VERSION:-latest}"
# Set to 1 to skip the release download and build from source instead.
DEV_TOOLKIT_OFFLINE="${DEV_TOOLKIT_OFFLINE:-0}"

detect_os() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' darwin
      ;;
    Linux)
      printf '%s\n' linux
      ;;
    MINGW*|MSYS*|CYGWIN*)
      printf '%s\n' windows
      ;;
    *)
      echo "unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf '%s\n' amd64
      ;;
    arm64|aarch64)
      printf '%s\n' arm64
      ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

release_url() {
  asset="$1"

  if [ "$DEV_TOOLKIT_VERSION" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/%s\n' \
      "$DEV_TOOLKIT_REPO" "$asset"
  else
    printf 'https://github.com/%s/releases/download/%s/%s\n' \
      "$DEV_TOOLKIT_REPO" "$DEV_TOOLKIT_VERSION" "$asset"
  fi
}

# Downloads the release asset for this machine. Returns non-zero when the asset
# is missing, the network is unavailable, or no downloader is installed.
download_release() {
  asset="$1"
  dest="$2"
  url="$(release_url "$asset")"
  tmp="${dest}.download.$$"

  if command -v curl >/dev/null 2>&1; then
    downloader=curl
  elif command -v wget >/dev/null 2>&1; then
    downloader=wget
  else
    echo "neither curl nor wget is installed; skipping release download" >&2
    return 1
  fi

  echo "fetching ${asset} from the ${DEV_TOOLKIT_VERSION} release of ${DEV_TOOLKIT_REPO}"
  mkdir -p "$(dirname "$dest")"

  # Errors are silenced: a 404 simply means this platform has no published
  # asset yet, which is an expected fallback path rather than a failure.
  case "$downloader" in
    curl)
      curl -fsSL --retry 2 -o "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
      ;;
    wget)
      wget -q -O "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; return 1; }
      ;;
  esac

  # A zero-length file means the redirect resolved but the asset did not.
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$dest"
  chmod +x "$dest"
  echo "downloaded: dev-toolkit/dist/${asset}"
}

build_from_source() {
  goos="$1"
  goarch="$2"
  dest="$3"

  echo "building ${goos}/${goarch} from source"
  mkdir -p "$(dirname "$dest")"
  (
    cd "$SCRIPT_DIR" &&
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
      go build -trimpath -ldflags="-s -w" -o "$dest" ./cmd/careconnect-dev
  ) || return 1

  echo "built: dev-toolkit/dist/$(basename "$dest")"
}

no_binary_available() {
  asset="$1"

  cat >&2 <<MSG

No dev-toolkit binary is available for ${GOOS}/${GOARCH}, and one could not be
obtained automatically:

  - not found locally at dev-toolkit/dist/${asset}
  - not published in the ${DEV_TOOLKIT_VERSION} release of ${DEV_TOOLKIT_REPO}
  - Go is not installed, so it cannot be built from source

Do one of the following, then rerun this script:

  1. Install Go 1.22 or newer (https://go.dev/dl/) and rerun bootstrap. It will
     build just the binary for this machine.
  2. Download ${asset} from
     https://github.com/${DEV_TOOLKIT_REPO}/releases
     and place it in dev-toolkit/dist/.
MSG
  exit 1
}

# Resolution order: an existing local binary wins so that build.sh, which calls
# this script after building, never re-downloads what it just produced.
resolve_binary() {
  asset="$1"
  dest="$2"

  if [ -f "$dest" ]; then
    echo "using existing binary: dev-toolkit/dist/${asset}"
    return 0
  fi

  if [ "$DEV_TOOLKIT_OFFLINE" != "1" ]; then
    if download_release "$asset" "$dest"; then
      return 0
    fi
    echo "no release asset available; falling back to a local build" >&2
  fi

  if ! command -v go >/dev/null 2>&1; then
    no_binary_available "$asset"
  fi

  if build_from_source "$GOOS" "$GOARCH" "$dest"; then
    return 0
  fi

  echo "go build failed for ${GOOS}/${GOARCH}" >&2
  exit 1
}

write_windows_cmd_launcher() {
  binary_name="$1"
  cmd_path="${REPO_ROOT}/dev-tool.cmd"

  {
    printf '@echo off\r\n'
    printf 'set SCRIPT_DIR=%%~dp0\r\n'
    printf '"%%SCRIPT_DIR%%dev-toolkit\\dist\\%s" %%*\r\n' "$binary_name"
  } > "$cmd_path"

  echo "windows launcher: dev-tool.cmd -> dev-toolkit/dist/${binary_name}"
}

create_symlink() {
  target="$1"
  link="$2"

  if [ -L "$link" ]; then
    rm "$link"
  elif [ -e "$link" ]; then
    echo "cannot create launcher: ${link} already exists and is not a symlink" >&2
    exit 1
  fi

  ln -s "$target" "$link"
  echo "launcher: dev-tool -> ${target}"
}

GOOS="$(detect_os)"
GOARCH="$(detect_arch)"

case "${GOOS}/${GOARCH}" in
  linux/amd64|linux/arm64|darwin/amd64|darwin/arm64|windows/amd64|windows/arm64)
    ;;
  *)
    echo "unsupported binary target: ${GOOS}/${GOARCH}" >&2
    exit 1
    ;;
esac

BINARY_NAME="careconnect-dev-toolkit-${GOOS}-${GOARCH}"
if [ "$GOOS" = "windows" ]; then
  BINARY_NAME="${BINARY_NAME}.exe"
fi

TARGET_REL="dev-toolkit/dist/${BINARY_NAME}"
TARGET_ABS="${REPO_ROOT}/${TARGET_REL}"

resolve_binary "$BINARY_NAME" "$TARGET_ABS"

if [ "$GOOS" = "windows" ]; then
  write_windows_cmd_launcher "$BINARY_NAME"
  if create_symlink "$TARGET_REL" "${REPO_ROOT}/dev-tool" 2>/dev/null; then
    :
  else
    echo "windows symlink was not created; use dev-tool.cmd instead." >&2
  fi
else
  create_symlink "$TARGET_REL" "${REPO_ROOT}/dev-tool"
fi
