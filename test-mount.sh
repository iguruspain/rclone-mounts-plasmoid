#!/usr/bin/env bash
set -euo pipefail

# 1️⃣ Stop previous daemon
systemctl --user stop rclone-rc.service || true
pkill -f "rclone rcd" || true

# 2️⃣ Start new daemon (no auth)
systemctl --user start rclone-rc.service
sleep 3   # give the daemon time to start

# 3️⃣ Test mount via RC API (same as the plasmoid)
REMOTE="onedrive:"               # <--- change here
REMOTE_NAME="${REMOTE%:}"        # strip trailing ':' for paths

MOUNTPOINT="$HOME/mnt/rclone/$REMOTE_NAME"
CACHE_DIR="$HOME/.cache/rclone-mounts/$REMOTE_NAME"

mkdir -p "$MOUNTPOINT" "$CACHE_DIR"

# Build JSON for rclone rc mount/mount (format used by the plasmoid)
JSON='{
  "fs": "'"$REMOTE"'",
  "mountPoint": "'"$MOUNTPOINT"'",
  "mountOpt": {
    "vfs-cache-mode": "writes",
    "vfs-write-back": "1s",
    "attr-timeout": "1s",
    "dir-cache-time": "5s",
    "cache-dir": "'"$CACHE_DIR"'"
  }
}'

echo "Mounting $REMOTE at $MOUNTPOINT via RC API..."
rclone rc mount/mount --json "$JSON" --rc-addr=localhost:5572

echo "✅ Mount completed at $MOUNTPOINT"
echo ""
echo "Verify active mount:"
rclone rc mount/listmounts --rc-addr=localhost:5572
echo ""
echo "To unmount:"
echo "  rclone rc mount/unmount mountPoint='$MOUNTPOINT' --rc-addr=localhost:5572"