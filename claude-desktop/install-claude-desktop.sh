#!/bin/bash
# claude-desktop/install-claude-desktop.sh
#
# PURPOSE:
#   Deploys Claude Desktop launch flags and GNOME autostart entry
#   for aarch64 Pi 5 (BCM2712) under GNOME Wayland.
#
# DEPLOY:
#   bash claude-desktop/install-claude-desktop.sh
#
# NOTE:
#   Run as the desktop user (corporatetraveldc), NOT as root.
#   These are user-level configs, not system-wide.

set -e

if [[ "$EUID" -eq 0 ]]; then
    echo "[FAIL] Run as the desktop user, not root." >&2
    exit 1
fi

echo "[1/2] Installing Claude Desktop launch flags..."
mkdir -p ~/.config/claude
cp "$(dirname "$0")/claude-desktop-flags.conf" ~/.config/claude/claude-desktop-flags.conf
echo "[OK]  ~/.config/claude/claude-desktop-flags.conf deployed"

echo "[2/2] Installing GNOME autostart entry..."
mkdir -p ~/.config/autostart
cp "$(dirname "$0")/claude-desktop.desktop" ~/.config/autostart/claude-desktop.desktop
echo "[OK]  ~/.config/autostart/claude-desktop.desktop deployed"

echo ""
echo "-- Done. Claude Desktop will auto-launch on next GNOME session start."
echo "-- To test now: claude-desktop --ozone-platform=wayland --enable-features=WaylandWindowDecorations &"
