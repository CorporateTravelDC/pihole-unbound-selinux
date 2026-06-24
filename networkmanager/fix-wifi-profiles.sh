#!/bin/bash
# networkmanager/fix-wifi-profiles.sh
#
# PURPOSE:
#   Fixes all WiFi connection profiles to correctly accept DHCP-provided
#   routes and gateways. The harden.sh script previously set
#   ipv4.ignore-auto-routes=yes on some profiles, which caused DHCP to
#   assign an IP but discard the default gateway -- breaking all outbound
#   routing after reboot.
#
#   Sets route-metric=200 so WiFi is lower priority than Tailscale (100)
#   but still provides a working default route when Tailscale is the
#   primary path.
#
# DEPLOY:
#   sudo bash networkmanager/fix-wifi-profiles.sh

set -e

echo "[INFO] Fixing all WiFi NM profiles..."
ALL_WIFI=$(nmcli -t -f NAME,TYPE connection show | grep ':wifi$' | cut -d: -f1)

if [ -z "$ALL_WIFI" ]; then
    echo "[WARN] No WiFi profiles found"
    exit 0
fi

while IFS= read -r PROFILE; do
    nmcli connection modify "$PROFILE" ipv4.ignore-auto-routes no
    nmcli connection modify "$PROFILE" ipv4.never-default no
    nmcli connection modify "$PROFILE" ipv4.route-metric 200
    echo "[OK] Fixed: $PROFILE"
done <<< "$ALL_WIFI"

echo "[INFO] Done. Changes take effect on next connection or reboot."
echo "[WARN] Do NOT run 'nmcli networking off/on' or 'systemctl restart NetworkManager'"
echo "       as this will drop SSH sessions and trigger Unbound race conditions."
