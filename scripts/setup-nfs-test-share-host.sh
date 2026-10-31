#!/usr/bin/env bash
# Run on the LAN PC in a normal terminal, once.
# Creates a temporary NFSv4 test export accessible only to the Yun.
set -euo pipefail
# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"
: "${YUN_HOST:?set YUN_HOST in .env}"
: "${EXPORT_DIR:?set EXPORT_DIR in .env}"

readonly BRIDGE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/dist/rust/yun-tailssh-bridge.mips"

test -x "$BRIDGE"
sudo apt-get update
sudo apt-get install -y nfs-kernel-server
sudo install -d -o "$OWNER_UID" -g "$OWNER_GID" -m 0750 "$EXPORT_DIR"
sudo install -d -o root -g root -m 0755 /etc/exports.d
install -o "$OWNER_UID" -g "$OWNER_GID" -m 0755 "$BRIDGE" "$EXPORT_DIR/yun-tailssh-bridge"

tmp=$(mktemp)
printf '%s %s(rw,sync,no_subtree_check,all_squash,anonuid=%s,anongid=%s,sec=sys)\n' \
  "$EXPORT_DIR" "$YUN_HOST" "$OWNER_UID" "$OWNER_GID" > "$tmp"
sudo install -o root -g root -m 0644 "$tmp" "$NFS_EXPORT_FILE"
rm -f "$tmp"
sudo exportfs -ra
sudo systemctl start nfs-server
sudo exportfs -v
