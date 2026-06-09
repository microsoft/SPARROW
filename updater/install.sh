#!/usr/bin/env bash
###############################################################################
# install.sh — idempotent installer for the SPARROW auto-updater.
#
# Run from anywhere with sudo. Defaults assume this lives at
# <DEPLOY_DIR>/updater/install.sh; the script auto-detects DEPLOY_DIR from its
# own location.
#
# What it does:
#   1. apt-get install -y jq (the only host-side dep not already present)
#   2. Copies sparrow-update.sh -> /usr/local/sbin/ (root-owned, mode 0750)
#   3. Writes /etc/systemd/system/sparrow-update.{service,timer}
#   4. Writes /etc/logrotate.d/sparrow-update
#   5. systemctl daemon-reload && enable --now sparrow-update.timer
#
# Re-running is safe: each write is checked or overwrites with the same content.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/sparrow-update.sh"
TARGET_SCRIPT="/usr/local/sbin/sparrow-update.sh"
SERVICE_FILE="/etc/systemd/system/sparrow-update.service"
TIMER_FILE="/etc/systemd/system/sparrow-update.timer"
LOGROTATE_FILE="/etc/logrotate.d/sparrow-update"
CONFIG_FILE="/etc/sparrow-update.conf"
STATE_DIR="/var/lib/sparrow-update"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (try: sudo $0)" >&2
    exit 1
fi

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
    echo "ERROR: cannot find sparrow-update.sh at $SOURCE_SCRIPT" >&2
    exit 1
fi

# The auto-updater works without any config for public repos. If the repo is
# still private, set UPDATER_GITHUB_TOKEN before running this installer and we
# will persist it to $CONFIG_FILE (mode 0600). An existing $CONFIG_FILE is
# never overwritten — operators can edit it directly.
if [[ -n "${UPDATER_GITHUB_TOKEN:-}" && ! -f "$CONFIG_FILE" ]]; then
    echo "[install] writing $CONFIG_FILE from UPDATER_GITHUB_TOKEN (mode 0600)"
    umask 077
    cat > "$CONFIG_FILE" <<EOF
# /etc/sparrow-update.conf — optional overrides for the SPARROW auto-updater.
# Sourced by /usr/local/sbin/sparrow-update.sh. Treat as a secret.
GITHUB_TOKEN="${UPDATER_GITHUB_TOKEN}"
EOF
    chmod 0600 "$CONFIG_FILE"
elif [[ -f "$CONFIG_FILE" ]]; then
    echo "[install] $CONFIG_FILE already exists; leaving in place"
else
    echo "[install] no $CONFIG_FILE created (public repo / anonymous access)"
fi

echo "[install] ensuring jq is installed"
if ! command -v jq >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y jq
fi

echo "[install] preparing state directory at $STATE_DIR"
install -d -m 0750 "$STATE_DIR"
install -d -m 0750 "$STATE_DIR/staging" "$STATE_DIR/backup" "$STATE_DIR/log"

echo "[install] copying $SOURCE_SCRIPT -> $TARGET_SCRIPT"
install -m 0750 -o root -g root "$SOURCE_SCRIPT" "$TARGET_SCRIPT"

echo "[install] writing $SERVICE_FILE"
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=SPARROW automated tag-based self-update
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sparrow-update.sh
# The script handles its own logging; let stdout/stderr flow into journal
StandardOutput=journal
StandardError=journal
# Generous timeout so a full rebuild + recreate + health-check fits
TimeoutStartSec=30min
EOF

echo "[install] writing $TIMER_FILE"
cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=SPARROW auto-update — fires every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
RandomizedDelaySec=120
Persistent=true
Unit=sparrow-update.service

[Install]
WantedBy=timers.target
EOF

echo "[install] writing $LOGROTATE_FILE"
cat > "$LOGROTATE_FILE" <<'EOF'
/var/lib/sparrow-update/log/sparrow-update.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "[install] reloading systemd and enabling timer"
systemctl daemon-reload
systemctl enable --now sparrow-update.timer

echo
echo "[install] done. Status:"
systemctl --no-pager status sparrow-update.timer || true
echo
echo "Useful commands:"
echo "  sudo systemctl start sparrow-update.service           # fire one update tick now"
echo "  sudo journalctl -u sparrow-update.service -f          # tail update activity"
echo "  sudo cat /var/lib/sparrow-update/current_tag          # what's deployed"
echo "  sudo cat /var/lib/sparrow-update/log/sparrow-update.log"
