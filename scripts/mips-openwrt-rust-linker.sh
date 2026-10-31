#!/usr/bin/env bash
# rustc always passes -lunwind on this musl target. OpenWrt's 24Kc toolchain has
# no libunwind; libgcc_eh.a provides the same unwinder and is soft-float.
set -euo pipefail
args=()
for arg in "$@"; do
  if [[ "$arg" == "-lunwind" ]]; then
    args+=("-lgcc_eh")
  else
    args+=("$arg")
  fi
done
exec mips-openwrt-linux-musl-gcc "${args[@]}"
