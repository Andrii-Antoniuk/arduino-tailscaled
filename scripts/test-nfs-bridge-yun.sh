#!/usr/bin/env bash
# No auth key, state, service, or persistent config. It only proves that the
# uncompressed MIPS Rust binary executes from the mounted PC share.
set -euo pipefail
# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"
: "${YUN:?set YUN_USER and YUN_HOST in .env}"
ssh -o BatchMode=yes "$YUN" "
  set -eu
  test -x '$YUN_NFS_MOUNT/yun-tailssh-bridge'
  '$YUN_NFS_MOUNT/yun-tailssh-bridge' --help 2>&1 || rc=\$?
  test \"\${rc:-0}\" -eq 2
  awk '/^(MemAvailable|MemFree):/ {print}' /proc/meminfo
"
