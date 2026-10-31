#!/bin/sh
# USB stick launcher. rc.local calls this once after USB and DNS are up.
. "$(dirname "$0")/usb-env.sh"
cd "$USB" || exit 1

for f in supervisor.pid watchdog.pid; do
  if [ -f "$f" ]; then
    kill "$(cat "$f")" 2>/dev/null || true
  fi
done
sleep 1
pid=$(ps w | awk '/yun-tailssh-bridge --state/ {print $1; exit}')
if [ -n "$pid" ]; then
  kill "$pid" 2>/dev/null || true
  sleep 1
  kill -9 "$pid" 2>/dev/null || true
fi

setsid sh -c "echo \$\$ > $USB/supervisor.pid; exec sh $USB/supervise.sh" >/dev/null 2>&1 &
setsid sh -c "echo \$\$ > $USB/watchdog.pid; exec sh $USB/watchdog.sh" >/dev/null 2>&1 &
echo $!
