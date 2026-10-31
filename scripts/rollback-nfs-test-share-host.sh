#!/usr/bin/env bash
# Remove only the temporary Yun NFS export and its files from the LAN PC.
set -euo pipefail
# shellcheck source=host-env.sh
. "$(cd "$(dirname "$0")" && pwd)/host-env.sh"
: "${EXPORT_DIR:?set EXPORT_DIR in .env}"
sudo rm -f "$NFS_EXPORT_FILE"
sudo exportfs -ra
sudo rm -rf "$EXPORT_DIR"
