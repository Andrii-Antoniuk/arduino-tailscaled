#!/usr/bin/env bash
# Read-only target audit; uses existing key-only Dropbear access.
set -euo pipefail
# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"
host=${1:-${YUN:?set YUN_USER and YUN_HOST in .env, or pass user@host}}
ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" '
  set -eu
  uname -a
  ubus call system board
  printf "busybox ELF: "; dd if=/bin/busybox bs=1 count=6 2>/dev/null | hexdump -v -e "1/1 \"%02x \""; echo
  df -k /overlay /
  free || cat /proc/meminfo
  ip link show eth0
  apk info 2>/dev/null | grep -Ei "etherwake|wake|wol" || true
'
