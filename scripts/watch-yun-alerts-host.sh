#!/usr/bin/env bash
# Run on the LAN PC (systemd --user yun-alerts-host.service).
# Listens for Yun crash notes, writes the alert log, desktop-notifies with
# sound, and restarts the USB launcher if SSH shows the bridge is gone.
# Reboot stays on the Yun watchdog.
#
#   --test-sound   play the crash notification + sound once, then exit
#   --notify TEXT  used by the listener; not for interactive use
set -euo pipefail

# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"

readonly ALERT_LOG=${EXPORT_DIR:-}/yun-alerts.log
readonly ALERT_FILE=${EXPORT_DIR:-}/YUN-ALERT.txt
readonly SOUND_DEBOUNCE_FILE=${XDG_RUNTIME_DIR:-/tmp}/yun-alerts-host.sound

notify_yun() {
  local body=$1
  local mode=${2:-alert}
  local summary=$NOTIFY_APP

  [[ -n "$body" ]] || return 0
  if [[ "$mode" == test ]]; then
    summary="$NOTIFY_APP sound test"
  fi

  notify-send \
    --urgency=critical \
    --app-name="$NOTIFY_APP" \
    --icon=dialog-error \
    --expire-time=0 \
    -- \
    "$summary" \
    "$body" >/dev/null 2>&1 || true

  local play=0 now last=0
  now=$(date +%s)
  if [[ "$mode" == test ]]; then
    play=1
  else
    if [[ -f "$SOUND_DEBOUNCE_FILE" ]]; then
      last=$(cat "$SOUND_DEBOUNCE_FILE" 2>/dev/null || echo 0)
    fi
    if (( now - last >= SOUND_DEBOUNCE_SECS )); then
      play=1
      printf '%s\n' "$now" >"$SOUND_DEBOUNCE_FILE" || true
    fi
  fi

  if (( play )); then
    if command -v canberra-gtk-play >/dev/null 2>&1; then
      canberra-gtk-play --display="${DISPLAY:-:0}" -f "$SOUND_FILE" >/dev/null 2>&1 \
        || pw-play "$SOUND_FILE" >/dev/null 2>&1 \
        || true
    else
      pw-play "$SOUND_FILE" >/dev/null 2>&1 || true
    fi
  fi
}

case "${1:-}" in
  --test-sound)
    notify_yun "This is the sound you will hear if the Yun crashes or reboots." test
    exit 0
    ;;
  --notify)
    notify_yun "${2:-}" alert
    exit 0
    ;;
esac

: "${HOST_LAN_IP:?copy .env.example to .env and set HOST_LAN_IP}"
: "${YUN_HOST:?set YUN_HOST in .env}"
: "${EXPORT_DIR:?set EXPORT_DIR in .env}"
: "${YUN:?set YUN_USER and YUN_HOST in .env}"

mkdir -p "$EXPORT_DIR"
touch "$ALERT_LOG"

fail_streak=0
healthcheck() {
  local out
  if ! out=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$YUN" "
    pid=\$(ps w | awk '/yun-tailssh-bridge --state/ {print \$1; exit}')
    if [ -n \"\$pid\" ]; then echo ok; exit 0; fi
    echo missing
    [ -x '$YUN_USB/start.sh' ] && '$YUN_USB/start.sh'
    sleep 6
    pid=\$(ps w | awk '/yun-tailssh-bridge --state/ {print \$1; exit}')
    if [ -n \"\$pid\" ]; then echo restarted; exit 0; fi
    echo still-missing
  " 2>/dev/null); then
    fail_streak=$((fail_streak + 1))
    printf '%s yun healthcheck: ssh failed (%sx)\n' "$(date -Is)" "$fail_streak"
    if (( fail_streak == 3 )); then
      notify_yun "$NOTIFY_APP SSH failed ${fail_streak} times; board may be down"
    fi
    return
  fi
  fail_streak=0
  printf '%s yun healthcheck: %s\n' "$(date -Is)" "$(printf '%s' "$out" | tr '\n' ' ')"
  case "$out" in
    *still-missing*)
      notify_yun "$NOTIFY_APP bridge still missing after start.sh"
      ;;
  esac
}

python3 - "$0" "$HOST_LAN_IP" "$ALERT_LISTEN_PORT" "$ALERT_LOG" "$ALERT_FILE" <<'PY' &
import pathlib, socket, subprocess, sys

script, listen_ip, port, log_path, alert_path = (
    sys.argv[1],
    sys.argv[2],
    int(sys.argv[3]),
    pathlib.Path(sys.argv[4]),
    pathlib.Path(sys.argv[5]),
)
log_path.parent.mkdir(parents=True, exist_ok=True)

sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind((listen_ip, port))
sock.listen(8)
print(f"listening on {listen_ip}:{port}", flush=True)

while True:
    conn, addr = sock.accept()
    try:
        chunks = []
        while True:
            buf = conn.recv(4096)
            if not buf:
                break
            chunks.append(buf)
        body = b"".join(chunks).decode("utf-8", "replace")
        if not body.strip():
            continue
        if not body.endswith("\n"):
            body += "\n"
        with log_path.open("a", encoding="utf-8") as f:
            f.write(body)
        alert_path.write_text(body, encoding="utf-8")
        sys.stdout.write(body)
        sys.stdout.flush()
        try:
            subprocess.run(
                [script, "--notify", body.strip()[:800]],
                check=False,
                timeout=12,
            )
        except Exception:
            pass
    finally:
        conn.close()
PY
http_pid=$!

(
  while :; do
    healthcheck || true
    sleep 60
  done
) &
health_pid=$!

trap 'kill "$http_pid" "$health_pid" 2>/dev/null || true' EXIT
echo "alerts -> $ALERT_LOG and $ALERT_FILE (ctrl-c to stop)"
wait "$http_pid"
