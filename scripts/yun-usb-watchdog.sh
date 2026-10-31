#!/bin/sh
# Keep the supervisor up. Reboot on a crash loop or a long-dead bridge.
# Cooldown on USB prevents a reboot storm.
. "$(dirname "$0")/usb-env.sh"
cd "$USB" || exit 1

REBOOT_WINDOW=600
REBOOT_MIN=5
REBOOT_COOLDOWN=900
missing=0

bridge_pid() {
  ps w | awk '/yun-tailssh-bridge --state/ {print $1; exit}'
}

supervisor_alive() {
  [ -f supervisor.pid ] && kill -0 "$(cat supervisor.pid)" 2>/dev/null
}

crash_count() {
  now=$(date +%s)
  cutoff=$((now - REBOOT_WINDOW))
  [ -f crash.times ] || { echo 0; return; }
  awk -v c="$cutoff" '$1+0 >= c {n++} END {print n+0}' crash.times
}

maybe_reboot() {
  reason=$1
  now=$(date +%s)
  if [ -f last-reboot ]; then
    last=$(cat last-reboot)
    if [ $((now - last)) -lt "$REBOOT_COOLDOWN" ]; then
      sh ./notify.sh "$(date) reboot skipped (cooldown): $reason" || true
      return
    fi
  fi
  echo "$now" > last-reboot
  sh ./notify.sh "$(date) REBOOT: $reason" || true
  sync
  sleep 1
  reboot
}

while :; do
  sleep 30
  sh ./notify.sh || true

  if ! supervisor_alive; then
    sh ./notify.sh "$(date) supervisor dead, respawning" || true
    setsid sh -c "echo \$\$ > $USB/supervisor.pid; exec sh $USB/supervise.sh" >/dev/null 2>&1 &
    sleep 4
  fi

  if [ -n "$(bridge_pid)" ]; then
    missing=0
  else
    missing=$((missing + 1))
  fi

  if [ "$missing" -ge 4 ]; then
    maybe_reboot "bridge missing for $((missing * 30))s"
    missing=0
  fi

  n=$(crash_count)
  if [ "$n" -ge "$REBOOT_MIN" ]; then
    maybe_reboot "crash loop: $n exits in ${REBOOT_WINDOW}s"
  fi
done
