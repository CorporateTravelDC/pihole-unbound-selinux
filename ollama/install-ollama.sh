#!/bin/bash
# ollama/install-ollama.sh
#
# PURPOSE:
#   Installs Ollama on Fedora 43+ aarch64 (Pi 5) and configures it
#   as a Tailscale-only API endpoint.
#
# ARCHITECTURE:
#   Ollama API is machine-facing only -- never exposed via CF tunnel.
#   Access paths:
#     Tailscale: http://YOUR_TAILSCALE_IP:11434  (Claude Code, dispatch tasks)
#     Local:     http://127.0.0.1:11434
#
#   OpenWebUI (separate service) provides the human-facing browser UI
#   and calls Ollama internally via 127.0.0.1:11434.
#
# MODEL:
#   This script does NOT pull models. Pull Qwen3:8b manually or as
#   part of the full stack deploy:
#     ollama pull qwen3:8b
#
# USAGE:
#   sudo bash ollama/install-ollama.sh
#
# IDEMPOTENT: yes -- safe to re-run

set -e

echo "=== install-ollama.sh ==="

# Skip if already installed
if command -v ollama &>/dev/null; then
    echo "[OK]  Ollama already installed: $(ollama --version 2>/dev/null || echo 'version unknown')"
    echo "[INFO] To update: curl -fsSL https://ollama.com/install.sh | sh"
else
    echo "[1/1] Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    echo "[OK]  Ollama installed"
fi

# Configure Ollama to bind Tailscale + loopback only
echo "[INFO] Configuring Ollama host binding..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/10-binding.conf > /dev/null << 'EOF'
# /etc/systemd/system/ollama.service.d/10-binding.conf
#
# Binds Ollama to loopback only at the service level.
# OpenWebUI reaches it via 127.0.0.1:11434.
# Claude Code and dispatch tasks reach it via Tailscale IP
# which routes to loopback on the Pi itself.
#
# NEVER set OLLAMA_HOST to 0.0.0.0 -- exposes raw API publicly.
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
EOF

sudo systemctl daemon-reload

# Enable and start
if ! systemctl is-active ollama &>/dev/null; then
    sudo systemctl enable --now ollama
    echo "[OK]  Ollama service enabled and started"
else
    sudo systemctl restart ollama
    echo "[OK]  Ollama service restarted with new config"
fi

# Firewall -- allow Tailscale peers to reach port 11434
if command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --permanent --zone=trusted --add-port=11434/tcp 2>/dev/null || true
    sudo firewall-cmd --reload
    echo "[OK]  firewalld: port 11434 open on trusted zone (Tailscale)"
fi

echo ""
echo "-- Ollama ready at http://127.0.0.1:11434"
echo "-- Via Tailscale:  http://YOUR_TAILSCALE_IP:11434"
echo ""
echo "-- Pull models when ready:"
echo "     ollama pull qwen3:8b"
echo ""
echo "-- Set as Claude Code default:"
echo "     echo 'export OLLAMA_HOST=http://127.0.0.1:11434' >> ~/.bashrc"
