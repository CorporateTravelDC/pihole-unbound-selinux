#!/bin/bash
# brave/install-brave.sh
#
# PURPOSE:
#   Installs Brave Browser on Fedora 43+ aarch64 and deploys
#   Wayland launch flags for Pi 5 BCM2712.
#
# DEPLOY:
#   sudo bash brave/install-brave.sh
#
# POST-INSTALL:
#   1. Launch Brave: brave-browser
#   2. Install Claude extension from Chrome Web Store
#   3. In Claude Desktop: Settings -> Claude in Chrome -> Allow extension

set -e

echo "[1/3] Adding Brave repo..."
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo \
    https://brave-keybase-repo.s3.brave.com/brave-core.repo
echo "[OK]  Brave repo added"

echo "[2/3] Installing Brave..."
sudo dnf install -y brave-browser
echo "[OK]  Brave installed"

echo "[3/3] Deploying Wayland flags..."
cp "$(dirname "$0")/brave-flags.conf" ~/.config/brave-flags.conf
echo "[OK]  ~/.config/brave-flags.conf deployed"

echo ""
echo "-- Done."
echo "-- Launch: brave-browser"
echo "-- Install Claude extension from Chrome Web Store"
echo "-- Then: Claude Desktop -> Settings -> Claude in Chrome -> Allow extension"
