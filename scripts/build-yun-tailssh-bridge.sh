#!/usr/bin/env bash
# Cross-build the Dropbear SSH bridge for OpenWrt mips_24kc (AR9330, soft-float).
# Uses the official OpenWrt 25.12.6 ath79 SDK as linker/CC so the C runtime is
# soft-float. rustc's bundled MIPS crt1.o is hard-float and must not be linked.
set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BRIDGE="$ROOT/rust-dropbear-bridge"
readonly OUT="$ROOT/dist/rust"
readonly SDK_TAR="$ROOT/dist/sdk/openwrt-sdk-25.12.6-ath79-generic_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
readonly SDK_DIR="$ROOT/dist/sdk/openwrt-sdk-25.12.6-ath79-generic_gcc-14.3.0_musl.Linux-x86_64"
readonly SDK_URL="https://downloads.openwrt.org/releases/25.12.6/targets/ath79/generic/openwrt-sdk-25.12.6-ath79-generic_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
readonly SDK_SHA256="941c19d4787944e569bc0ca7fb4b6d0f4387ba24d188900bf0ffb6787fee31c6"
readonly RUST_IMAGE="messense/rust-musl-cross@sha256:0833536207ae001bb2cc7d064518feeed1a29c700d8ebcee72179c4aa5f7efb6"
readonly TOOLCHAIN_REL="staging_dir/toolchain-mips_24kc_gcc-14.3.0_musl"

command -v docker >/dev/null
mkdir -p "$ROOT/dist/sdk" "$OUT"

if [[ ! -d "$SDK_DIR/$TOOLCHAIN_REL" ]]; then
  if [[ ! -f "$SDK_TAR" ]]; then
    wget -c --progress=dot:giga -O "$SDK_TAR" "$SDK_URL"
  fi
  echo "$SDK_SHA256  $SDK_TAR" | sha256sum -c
  tar --zstd -xf "$SDK_TAR" -C "$ROOT/dist/sdk"
fi

docker run --rm --entrypoint sh \
  -v "$ROOT:/workspace" \
  -v "$SDK_DIR:/sdk:ro" \
  -v tailscale-rs-cargo-cache:/root/.cargo/registry \
  -v tailscale-rs-git-cache:/root/.cargo/git \
  -v tailscale-rs-rust-target-sf:/out \
  -w /workspace/rust-dropbear-bridge \
  -e CARGO_TARGET_DIR=/out \
  -e CARGO_HOME=/root/.cargo \
  -e RUSTUP_TOOLCHAIN=nightly \
  -e STAGING_DIR=/sdk/staging_dir \
  -e PATH="/workspace/scripts:/sdk/${TOOLCHAIN_REL}/bin:/root/.cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -e CC_mips_unknown_linux_musl="mips-openwrt-linux-musl-gcc" \
  -e CXX_mips_unknown_linux_musl="mips-openwrt-linux-musl-g++" \
  -e AR_mips_unknown_linux_musl="mips-openwrt-linux-musl-ar" \
  -e CFLAGS_mips_unknown_linux_musl="-Os -pipe -mno-branch-likely -mips32r2 -mtune=24kc -msoft-float -fno-plt" \
  -e CARGO_TARGET_MIPS_UNKNOWN_LINUX_MUSL_LINKER="mips-openwrt-rust-linker.sh" \
  -e CARGO_TARGET_MIPS_UNKNOWN_LINUX_MUSL_RUSTFLAGS="" \
  "$RUST_IMAGE" -ec '
    set -eu
    rustc --version
    mips-openwrt-linux-musl-gcc -dumpmachine
    cargo build --release --target mips-unknown-linux-musl \
      -Z build-std=std,panic_abort
    install -m 0755 /out/mips-unknown-linux-musl/release/yun-tailssh-bridge \
      /workspace/dist/rust/yun-tailssh-bridge.mips
  '

file "$OUT/yun-tailssh-bridge.mips"
readelf -h "$OUT/yun-tailssh-bridge.mips" | sed -n "1,24p"
abi=$(readelf -A "$OUT/yun-tailssh-bridge.mips")
printf '%s\n' "$abi" | grep -E "FP|ISA|float" || true
if ! printf '%s\n' "$abi" | grep -F "Soft float" >/dev/null; then
  echo "refusing to keep a non-soft-float MIPS binary" >&2
  exit 1
fi
ident=$(file "$OUT/yun-tailssh-bridge.mips")
if ! printf '%s\n' "$ident" | grep -F "MSB" >/dev/null; then
  echo "refusing to keep a little-endian MIPS binary" >&2
  exit 1
fi
phdr=$(readelf -l "$OUT/yun-tailssh-bridge.mips")
if printf '%s\n' "$phdr" | grep -F INTERP >/dev/null; then
  echo "refusing to keep a dynamically linked binary" >&2
  exit 1
fi
sha256sum "$OUT/yun-tailssh-bridge.mips"
stat -c "%n %s bytes" "$OUT/yun-tailssh-bridge.mips"
