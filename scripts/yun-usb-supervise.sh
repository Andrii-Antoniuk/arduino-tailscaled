#!/bin/sh
. "$(dirname "$0")/usb-env.sh"
cd "$USB" || exit 1
[ -n "${TS_HOSTNAME:-}" ] && export TS_HOSTNAME
while :; do
  ./yun-tailssh-bridge --state ./state >>./bridge.log 2>&1 </dev/null
  st=$?
  now=$(date)
  ts=$(date +%s)
  msg="$now yun-tailssh-bridge exited $st"
  printf '%s, restarting\n' "$msg" >> ./bridge.log
  printf '%s\n' "$ts" >> ./crash.times
  sh ./notify.sh "CRASH $msg" || true
  sleep 3
done
