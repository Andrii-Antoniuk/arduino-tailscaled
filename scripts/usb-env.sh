# busybox; source from USB copies of these scripts.
_usb_env_dir=$(dirname "$0")
if [ -f "$_usb_env_dir/yun.env" ]; then
  . "$_usb_env_dir/yun.env"
fi
USB=${YUN_USB:-${USB:-/mnt/tailscale-usb}}
ALERT_LISTEN_PORT=${ALERT_LISTEN_PORT:-7422}
TS_HOSTNAME=${TS_HOSTNAME:-yun}
unset _usb_env_dir
