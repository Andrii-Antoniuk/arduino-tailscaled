#!/usr/bin/env bash
# Mount the temporary PC NFSv4 share on the Yun; does not modify /etc/fstab.
set -euo pipefail
# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"
: "${YUN:?set YUN_USER and YUN_HOST in .env}"
: "${HOST_LAN_IP:?set HOST_LAN_IP in .env}"
: "${EXPORT_DIR:?set EXPORT_DIR in .env}"

readonly REMOTE=$HOST_LAN_IP:$EXPORT_DIR

ssh -o BatchMode=yes "$YUN" "
  set -eu
  mkdir -p '$YUN_NFS_MOUNT'
  grep -qs \" $YUN_NFS_MOUNT \" /proc/mounts || mount -t nfs4 -o vers=4,proto=tcp,hard,timeo=30,retrans=2 '$REMOTE' '$YUN_NFS_MOUNT'
  mount | grep \" $YUN_NFS_MOUNT \"
  ls -l '$YUN_NFS_MOUNT/yun-tailssh-bridge'
"
