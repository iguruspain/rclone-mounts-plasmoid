#!/usr/bin/env bash
# ============================================================
# install.sh – Rclone Mounts Plasmoid Installer (Plasma 6)
# Run WITHOUT sudo: bash install.sh
# ============================================================
set -euo pipefail

# ── Protection: don't run as root ────────────────────────────────────────────
if [ "$EUID" -eq 0 ]; then
    echo "❌ Don't run this script as root / sudo!"
    echo "   Run normally: bash install.sh"
    echo ""
    echo "   NM dispatcher (WiFi reconnect) will be installed automatically"
    echo "   and will only ask for sudo password once for that command."
    exit 1
fi

PLASMOID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_ID="org.kde.plasma.rclone-mounts"
REAL_USER="$USER"
REAL_HOME="$HOME"
REAL_UID="$(id -u)"

echo "================================================="
echo "  Rclone Mounts Plasmoid - Installer"
echo "================================================="
echo ""

# Check for rclone
if ! command -v rclone &>/dev/null; then
    echo "❌ rclone not found! Install it from: https://rclone.org/install/"
    exit 1
fi
echo "✅ $(rclone --version | head -1)"

# ── Plasmoid installation / upgrade ────────────────────────────────────────────
echo ""
echo "📦 Installing plasmoid..."
if kpackagetool6 --list --type Plasma/Applet 2>/dev/null | grep -q "$PLASMOID_ID"; then
    kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID_DIR"
    echo "   ♻️  Plasmoid upgraded (settings preserved)"
else
    kpackagetool6 --type Plasma/Applet --install "$PLASMOID_DIR"
    echo "   ✅ Plasmoid installed"
fi

# ── Mount directory ────────────────────────────────────────────────────────
#MOUNT_BASE="$REAL_HOME/mnt/rclone"
#mkdir -p "$MOUNT_BASE"
#echo "   📁 Mount directory: $MOUNT_BASE"

# ── Systemd user service for RC daemon ──────────────────────────────────────
echo ""
echo "🔧 Configuring rclone RC daemon autostart..."

SYSTEMD_DIR="$REAL_HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

cat > "$SYSTEMD_DIR/rclone-rc.service" << 'EOF'
[Unit]
Description=Rclone RC Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone rcd --rc-addr=localhost:5572 --rc-no-auth
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable rclone-rc.service
systemctl --user start rclone-rc.service

if systemctl --user is-active --quiet rclone-rc.service; then
    echo "   ✅ RC daemon started and enabled at login"
else
    echo "   ⚠️  Daemon failed to start - check: systemctl --user status rclone-rc"
fi

# ── Auto-mount on network connect ────────────────────────────────────────────
echo ""
echo "🔧 Configuring auto-mount on network connect..."

AM_CONF_DIR="$REAL_HOME/.config/rclone-plasmoid"
AM_CONF="$AM_CONF_DIR/automount.conf"
AM_SCRIPT="$REAL_HOME/.local/bin/rclone-automount.sh"

mkdir -p "$AM_CONF_DIR"
mkdir -p "$REAL_HOME/.local/bin"

# Configuration file with list of remotes (if it doesn't exist yet)
if [ ! -f "$AM_CONF" ]; then
    cat > "$AM_CONF" << 'CONF'
# Rclone Auto-Mount – list of remotes to mount on network startup
# One remote per line, exactly as returned by "rclone listremotes"
# Example:
#   gdrive:
#   dropbox:
#   mysftp:
CONF
    echo "   📄 Config created: $AM_CONF"
else
    echo "   📄 Config exists: $AM_CONF"
fi

# Mount script
cat > "$AM_SCRIPT" << 'SCRIPT'
#!/usr/bin/env bash
# rclone-automount.sh – mounts remotes from the list once RC daemon is available
set -euo pipefail

CONF="$HOME/.config/rclone-plasmoid/automount.conf"
RC_ADDR="localhost:5572"

# Read mountBase from widget config file; fallback to default
WIDGET_CONF="$HOME/.config/rclone-plasmoid/config"
MOUNT_BASE="$HOME/mnt/rclone"
if [ -f "$WIDGET_CONF" ]; then
    _val="$(grep '^mountBase=' "$WIDGET_CONF" 2>/dev/null | cut -d= -f2- | tr -d '\n')"
    [ -n "$_val" ] && MOUNT_BASE="$_val"
fi
echo "[rclone-automount] Mount base: $MOUNT_BASE"

# Wait up to 60s for RC daemon
echo "[rclone-automount] Waiting for RC daemon on $RC_ADDR..."
for i in $(seq 60); do
    rclone rc mount/listmounts --rc-addr="$RC_ADDR" --rc-no-auth &>/dev/null && break
    sleep 1
done

if ! rclone rc mount/listmounts --rc-addr="$RC_ADDR" --rc-no-auth &>/dev/null; then
    echo "[rclone-automount] ⚠️  RC daemon unavailable after 60s, skipping."
    exit 0
fi

[ ! -f "$CONF" ] && { echo "[rclone-automount] No config ($CONF), skipping."; exit 0; }

while IFS= read -r remote; do
    [[ -z "$remote" || "$remote" =~ ^[[:space:]]*# ]] && continue
    remote="${remote// /}"
    name="${remote%%:}"
    mp="$MOUNT_BASE/$name"

    # Check if already mounted
    if rclone rc mount/listmounts --rc-addr="$RC_ADDR" --rc-no-auth 2>/dev/null \
        | python3 -c "import sys,json; mps=[m['MountPoint'] for m in json.load(sys.stdin).get('mountPoints',[])]; exit(0 if '$mp' in mps else 1)" 2>/dev/null; then
        echo "[rclone-automount] ✓ Skipping $remote – already mounted"
        continue
    fi

    mkdir -p "$mp"
    if rclone rc mount/mount fs="$remote" mountPoint="$mp" \
        --rc-addr="$RC_ADDR" --rc-no-auth 2>/dev/null; then
        echo "[rclone-automount] ✅ $remote → $mp"
    else
        echo "[rclone-automount] ❌ Failed: $remote"
    fi
done < "$CONF"
SCRIPT

chmod +x "$AM_SCRIPT"

# systemd user service
cat > "$SYSTEMD_DIR/rclone-automount.service" << 'EOF'
[Unit]
Description=Rclone Auto-Mount (on network)
After=network.target rclone-rc.service
Wants=rclone-rc.service

[Service]
Type=oneshot
ExecStart=%h/.local/bin/rclone-automount.sh
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable rclone-automount.service
echo "   ✅ Auto-mount service enabled (runs at login)"

# NetworkManager dispatcher – only calls sudo for one file, the rest runs as user
NM_DISPATCHER_DIR="/etc/NetworkManager/dispatcher.d"
NM_SCRIPT="$NM_DISPATCHER_DIR/99-rclone-automount"

if [ -d "$NM_DISPATCHER_DIR" ]; then
    echo ""
    echo "🌐 Setting up NM dispatcher (auto-mount on WiFi reconnect)..."
    echo "   (sudo password will be required to write to /etc/NetworkManager/)"

    sudo bash -c "cat > '$NM_SCRIPT'" << NMSCRIPT
#!/usr/bin/env bash
# Run rclone-automount on every network / VPN connection
[ "\$2" = "up" ] || [ "\$2" = "vpn-up" ] || exit 0
sleep 2
XDG_RUNTIME_DIR=/run/user/${REAL_UID} \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${REAL_UID}/bus \
HOME=${REAL_HOME} \
su -s /bin/bash -c "${REAL_HOME}/.local/bin/rclone-automount.sh" ${REAL_USER} &
NMSCRIPT

    sudo chmod +x "$NM_SCRIPT"
    echo "   ✅ NetworkManager dispatcher configured – auto-mount on every WiFi/VPN connection"
else
    echo "   ℹ️  NetworkManager dispatcher skipped (directory $NM_DISPATCHER_DIR does not exist)"
fi

# ── Restart Plasma shell ──────────────────────────────────────────────────────
echo ""
echo "🔄 Restarting Plasma shell..."
kquitapp6 plasmashell 2>/dev/null || true
sleep 1
kstart6 plasmashell &>/dev/null &
systemctl --user restart plasma-plasmashell.service 2>/dev/null || true

echo ""
echo "================================================="
echo "✅ Done!"
echo "================================================="
echo ""
echo "Add widget: right-click desktop -> Add Widgets -> 'Rclone'"
echo ""
echo "RC daemon status:    systemctl --user status rclone-rc"
echo "Auto-mount config:   ~/.config/rclone-plasmoid/automount.conf"
echo "Auto-mount log:      journalctl --user -u rclone-automount"
echo ""
echo "💡 Tip: In the plasmoid, click the network icon next to a remote to enable auto-mount"
echo ""
