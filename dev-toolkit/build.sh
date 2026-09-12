#!/bin/sh
set -eu

cd "$(dirname "$0")"
mkdir -p dist

build_one() {
  goos="$1"
  goarch="$2"
  suffix="$3"
  out="dist/careconnect-dev-toolkit-${suffix}"
  if [ "$goos" = "windows" ]; then
    out="${out}.exe"
  fi
  echo "building ${out}"
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -trimpath -ldflags="-s -w" -o "$out" ./cmd/careconnect-dev
}

build_one linux amd64 linux-amd64
build_one linux arm64 linux-arm64
build_one darwin amd64 darwin-amd64
build_one darwin arm64 darwin-arm64
build_one windows amd64 windows-amd64
build_one windows arm64 windows-arm64

sh ./bootstrap.sh

echo "done. outputs are in dev-toolkit/dist/"
