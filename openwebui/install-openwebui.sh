#!/bin/bash
# openwebui/install-openwebui.sh
#
# PURPOSE:
#   Deploys OpenWebUI as a rootless Podman Quadlet under the
#   corporatetraveldc user. Requires Ollama to be installed first.
#
# PREREQUISITES:
#   - Ollama installed and running (bash ollama/install-ollama.sh)
#   - Podman installed
#   - corporatetraveldc user with linger enabled
#
# USAGE:
#   bash openwebui/install-openwebui.sh
#   (run as corporatetraveldc, not root)
#
# IDEMPOTENT: yes -- safe to re-run

set -e

if [[ "$EUID" -eq 0 ]]; then
    echo "[FAIL] Run as corporatetraveldc, not root." >&2
    exit 1
fi

echo "=== install-openwebui.sh ==="

# Ensure linger is enabled
if ! loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
    sudo loginctl enable-linger "$USER"
    echo "[OK]  Linger enabled for $USER"
fi

# Data directory
sudo mkdir -p /var/lib/openwebui
sudo chown "$USER:$USER" /var/lib/openwebui
echo "[OK]  Data directory: /var/lib/openwebui"

# Deploy Quadlet
QUADLET_DIR="$HOME/.config/containers/systemd"
mkdir -p "$QUADLET_DIR"
cp "$(dirname "$0")/openwebui.container" "$QUADLET_DIR/openwebui.container"
echo "[OK]  Quadlet deployed: $QUADLET_DIR/openwebui.container"

# Reload and start
systemctl --user daemon-reload
systemctl --user enable --now openwebui.container
echo "[OK]  OpenWebUI service enabled and started"

# Firewall -- allow Tailscale peers to reach port 3000
if command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --permanent --zone=trusted --add-port=3000/tcp 2>/dev/null || true
    sudo firewall-cmd --reload
    echo "[OK]  firewalld: port 3000 open on trusted zone (Tailscale)"
fi

echo ""
echo "-- OpenWebUI starting (may take 30-60s for first pull)..."
echo "-- Tailscale: http://YOUR_TAILSCALE_IP:3000"
echo "-- CF tunnel stub: https://openwebui.YOUR_DOMAIN (wire when CF deployed)"
echo ""
echo "-- Check status: systemctl --user status openwebui.container"
