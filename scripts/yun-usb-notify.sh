#!/bin/sh
# Queue on USB, then push the queue to the LAN PC over TCP.
# busybox nc has no timeout; background + kill so a sleeping PC cannot hang us.
. "$(dirname "$0")/usb-env.sh"
: "${HOST_LAN_IP:?set HOST_LAN_IP in yun.env}"

if [ -n "${1:-}" ]; then
  printf '%s\n' "$1" >> "$USB/alerts.log"
  printf '%s\n' "$1" >> "$USB/alerts.pending"
fi

[ -s "$USB/alerts.pending" ] || exit 0

nc "$HOST_LAN_IP" "$ALERT_LISTEN_PORT" < "$USB/alerts.pending" &
pid=$!
sleep 2
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  exit 0
fi
wait "$pid"
if [ $? -eq 0 ]; then
  rm -f "$USB/alerts.pending"
fi
