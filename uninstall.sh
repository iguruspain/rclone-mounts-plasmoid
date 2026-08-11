#!/usr/bin/env bash
# ============================================================
# uninstall.sh – Rclone Mounts Plasmoid Uninstaller (Plasma 6)
# Run WITHOUT sudo: bash uninstall.sh
# ------------------------------------------------------------
# This script reverses the changes made by install.sh:
#   * Stops and disables systemd user services for RC daemon & auto‑mount.
#   * Removes the plasmoid from Plasma.
#   * Deletes configuration files, mount directory (optional) and NM dispatcher entry.
# ============================================================

set -euo pipefail

echo "🔧 Uninstalling Rclone Mounts Plasmoid..."

# ── Protection: don't run as root ───────────────────────────────────────
if [ "$EUID" -eq 0 ]; then
    echo "❌ Don't run this script as root / sudo!"
    exit 1
fi

REAL_USER="$USER"
REAL_HOME="$HOME"
REAL_UID="$(id -u)"
PLASMOID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_ID="org.kde.plasma.rclone-mounts"

# ── Stop RC daemon service ───────────────────────────────────────
echo ""
echo "🛑 Stopping rclone‑rc.service..."
systemctl --user stop rclone-rc.service || true

# ── Disable & remove systemd user services ─────────────────────────
for svc in rclone-rc.service rclone-automount.service; do
    if [ -f "$HOME/.config/systemd/user/$svc" ]; then
        echo "   📦 Disabling $svc..."
        systemctl --user disable "$svc"
        rm -f "$HOME/.config/systemd/user/$svc"
    fi
done

# Reload daemon to apply removals
systemctl --user daemon-reload 2>/dev/null || true

# ── Remove the plasmoid from Plasma ───────────────────────────────
echo ""
if kpackagetool6 --list --type Plasma/Applet 2>/dev/null | grep -q "$PLASMOID_ID"; then
    echo "🗑️  Removing plasmoid $PLASMOID_ID..."
    kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_DIR"
else
    echo "⚠️  Plasmoid not found – maybe already removed."
fi

# ── Clean up configuration files & mount directory (optional) ───────
echo ""
CONF_DIR="$REAL_HOME/.config/rclone-plasmoid"
if [ -d "$CONF_DIR" ]; then
    echo "🗑️  Removing config directory $CONF_DIR..."
    rm -rf "$CONF_DIR"
fi

MOUNT_BASE="$REAL_HOME/mnt/rclone"
if [ -d "$MOUNT_BASE" ]; then
    # Keep the mount dir if it contains other data; otherwise remove.
    echo "🗑️  Removing default mount directory $MOUNT_BASE..."
    rm -rf "$MOUNT_BASE"
fi

# ── Remove NM dispatcher script (if present) ───────────────────────
NM_DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"
DISP_SCRIPT="$NM_DISPATCHER_DIR/99-rclone-automount"

if [ -f "$DISP_SCRIPT" ]; then
    echo ""
    echo "🗑️  Removing NetworkManager dispatcher script $DISP_SCRIPT..."
    sudo rm -f "$DISP_SCRIPT"
fi

# ── Restart Plasma shell (optional) ───────────────────────────────
echo ""
read -rp "Do you want to restart the Plasma shell now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "🔄 Restarting plasma‑shell..."
    kquitapp6 plasmashell 2>/dev/null || true
    sleep 1
    kstart6 plasmashell &>/dev/null &
    systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
fi

echo ""
echo "✅ Uninstallation complete."
echo "If you need to reinstall, run: bash install.sh"