#!/usr/bin/env bash
# Run only after a successful preflight on a device with adequate RAM/storage.
# It makes no persistent changes; it samples the specified running PID.
set -euo pipefail
host=${1:?usage: $0 root@tailscale-or-lan-host PID}
pid=${2:?usage: $0 root@tailscale-or-lan-host PID}
ssh -o BatchMode=yes "$host" "
  test -r /proc/$pid/status
  date -Is
  awk '/^(VmRSS|VmSize|RssAnon|RssFile|Threads):/ {print}' /proc/$pid/status
  awk '/^(MemAvailable|MemFree|Cached|SReclaimable):/ {print}' /proc/meminfo
"
