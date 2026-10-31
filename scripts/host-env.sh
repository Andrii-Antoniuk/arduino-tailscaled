# Host-side loader. Source from bash scripts in this directory.
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "$_script_dir/.." && pwd)"
if [[ -f "$_repo_root/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$_repo_root/.env"
  set +a
fi
: "${YUN_USER:=root}"
: "${ALERT_LISTEN_PORT:=7422}"
: "${YUN_USB:=/mnt/tailscale-usb}"
: "${YUN_NFS_MOUNT:=/mnt/yun-tailscale-test}"
: "${NFS_EXPORT_FILE:=/etc/exports.d/yun-tailscale-test.exports}"
: "${OWNER_UID:=1000}"
: "${OWNER_GID:=1000}"
: "${TS_HOSTNAME:=yun}"
: "${NOTIFY_APP:=yun-bridge}"
: "${SOUND_DEBOUNCE_SECS:=60}"
: "${YUN_ALERTS_SCRIPT:=$_script_dir/watch-yun-alerts-host.sh}"
YUN="${YUN_USER}@${YUN_HOST:-}"
SOUND_FILE="${SOUND_FILE:-$_script_dir/yun-crash.wav}"
unset _script_dir _repo_root
