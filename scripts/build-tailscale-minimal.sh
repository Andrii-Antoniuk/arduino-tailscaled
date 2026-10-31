#!/usr/bin/env bash
# Reproducibly build the smallest upstream-supported Linux TUN variant.
set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE="$ROOT/upstream-tailscale"
readonly OUT="$ROOT/dist"
readonly REVISION="v1.104.4"
readonly GO_IMAGE="golang@sha256:d9b6a1beb9474adc2a1ce842573639b44b2a0dd49b6669f51d3821baf9ec37c9"

command -v docker >/dev/null
if [[ ! -d "$SOURCE/.git" ]]; then
  git clone https://github.com/tailscale/tailscale.git "$SOURCE"
fi
git -C "$SOURCE" fetch --tags origin "$REVISION"
git -C "$SOURCE" checkout --detach "$REVISION"
test "$(git -C "$SOURCE" rev-parse HEAD)" = \
  27047635f237d1f3e0b08c0f487674757f30d2f7

mkdir -p "$OUT"
build() {
  local goarch=$1 out=$2
  docker run --rm \
    -v "$SOURCE:/src:ro" -v "$OUT:/out" \
    -v tailscale-go-build-cache:/root/.cache/go-build \
    -v tailscale-go-mod-cache:/go/pkg/mod \
    -w /src -e CGO_ENABLED=0 -e GOOS=linux -e GOARCH="$goarch" -e GOMIPS=softfloat \
    "$GO_IMAGE" sh -ec '
      git config --global --add safe.directory /src
      ./build_dist.sh --extra-small --box -o "/out/$0" ./cmd/tailscaled
    ' "$out"
}

# Arduino Yún Rev2's installed mips_24kc firmware is big-endian.
build mips tailscaled.mips
# Built solely for ABI comparison; do not deploy it to this device.
build mipsle tailscaled.mipsle

sha256sum "$OUT"/tailscaled.mips "$OUT"/tailscaled.mipsle | tee "$OUT/SHA256SUMS"
file "$OUT"/tailscaled.mips "$OUT"/tailscaled.mipsle
readelf -h "$OUT/tailscaled.mips" | sed -n '1,24p'
readelf -d "$OUT/tailscaled.mips"
