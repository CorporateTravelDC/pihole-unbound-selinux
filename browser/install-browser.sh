#!/bin/bash
# browser/install-browser.sh
#
# PURPOSE:
#   Installs a Chromium-based browser on Fedora 43+ aarch64 and deploys
#   Wayland launch flags for Pi 5 BCM2712.
#
# USAGE:
#   sudo BROWSER=chromium bash browser/install-browser.sh
#
# BROWSER options:
#   chromium   -- sudo dnf install -y chromium
#   brave      -- add Brave repo, then dnf install brave-browser
#   chrome     -- download .rpm from https://www.google.com/chrome/
#
# Replace this script with your preferred browser's install method.
# The flags file (browser-flags.conf) applies to all Chromium-based
# browsers -- just copy it to the correct location for your browser.

set -e

BROWSER="${BROWSER:-chromium}"

echo "[INFO] Selected browser: $BROWSER"
echo "[INFO] Replace this script with your preferred browser's install method."
echo ""

case "$BROWSER" in
    chromium)
        echo "[1/2] Installing Chromium..."
        sudo dnf install -y chromium
        echo "[OK]  Chromium installed"
        FLAGS_DEST="$HOME/.config/chromium-flags.conf"
        ;;
    *)
        echo "[INFO] Add your browser's install steps here."
        echo "       See browser/browser-flags.conf for the Wayland flags."
        exit 0
        ;;
esac

echo "[2/2] Deploying Wayland flags to $FLAGS_DEST..."
cp "$(dirname "$0")/browser-flags.conf" "$FLAGS_DEST"
echo "[OK]  Flags deployed"

echo ""
echo "-- Done. Launch your browser and install the Claude extension"
echo "   from the Chrome Web Store, then connect via:"
echo "   Claude Desktop -> Settings -> Claude in Chrome -> Allow extension"
