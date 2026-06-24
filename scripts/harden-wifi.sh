#!/usr/bin/env bash
# scripts/harden-wifi.sh
# Host hardening baseline -- WiFi variant
# Fedora 43+ -- aarch64 (Pi 5), x86_64
#
# PURPOSE:
#   This is the WiFi variant of harden.sh. It is functionally identical
#   to harden.sh with the addition of NetworkManager WiFi profile fixes
#   required for wireless-only or wireless-primary hosts.
#
# WHEN TO USE THIS SCRIPT:
#   - Your Pi (or server) connects to the network via WiFi only
#   - Your Pi uses WiFi as a fallback when wired is unavailable
#   - You are on a community/enterprise WiFi network (e.g. Xfinity hotspot,
#     802.1X PEAP/MSCHAPv2) where NetworkManager handles authentication
#
# WHEN TO USE harden.sh INSTEAD:
#   - Your Pi is wired (Ethernet) -- use harden.sh directly
#   - You manage WiFi credentials outside of NetworkManager
#
# WHAT THIS ADDS OVER harden.sh:
#   1. Disables NM connectivity check (prevents browser offline false-positive)
#   2. Fixes all WiFi NM profiles: ipv4.ignore-auto-routes=no,
#      ipv4.never-default=no, ipv4.route-metric=200
#   3. Disables Wayland in GDM (Electron apps blank on aarch64 under Wayland)
#   4. Enables NetworkManager-wait-online.service for deterministic boot
#
# KNOWN WIFI TRADEOFFS vs WIRED:
#   - Boot-to-DNS takes ~30s longer (WiFi auth + DHCP + anchor refresh)
#   - NM is retained as the network manager (wpa_supplicant underneath)
#   - Enterprise/hotspot WiFi (802.1X) session timeouts may drop connectivity
#     intermittently -- this is an upstream issue, not fixable here
#   - Do NOT run 'nmcli networking off/on' or 'systemctl restart NetworkManager'
#     while SSH is active -- it will drop the session and race Unbound
#
# PREREQUISITES:
#   - selinux/apply-selinux-policy.sh must have run successfully
#   - selinux/label-dns-port.sh must have run successfully
#   - SSH key-based login must already be configured and tested
#   - Pi-hole and Unbound must be installed
#   - Tailscale must be installed and authenticated
#   - WiFi must already be connected (NM profile must exist)
#
# WIFI CREDENTIALS:
#   This script does NOT configure WiFi credentials.
#   Connect to WiFi first via 'nmcli device wifi connect' or GNOME Settings,
#   then run this script to harden the resulting NM profile.
#   For 802.1X/PEAP enterprise WiFi, configure via GNOME Settings or
#   nmcli before running this script.
#
# Usage:
#   sudo bash scripts/harden-wifi.sh [--dry-run] [--skip-ssh] [--skip-firewall]
#
# Flags:
#   --dry-run        Print actions without executing
#   --skip-ssh       Skip sshd_config changes
#   --skip-firewall  Skip firewalld changes
#   --skip-resolved  Skip systemd-resolved / resolv.conf steps
#   --skip-wayland   Skip GDM Wayland disable (wired-display or headless hosts)

set -euo pipefail

DRY_RUN=false
SKIP_SSH=false
SKIP_FIREWALL=false
SKIP_RESOLVED=false
SKIP_WAYLAND=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=true; shift ;;
        --skip-ssh)      SKIP_SSH=true; shift ;;
        --skip-firewall) SKIP_FIREWALL=true; shift ;;
        --skip-resolved) SKIP_RESOLVED=true; shift ;;
        --skip-wayland)  SKIP_WAYLAND=true; shift ;;
        *) echo "[FAIL] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

run() {
    if [[ "$DRY_RUN" == true ]]; then echo "[DRY]  $*"; else "$@"; fi
}

if [[ "$EUID" -ne 0 ]]; then
    echo "[FAIL] Must be run as root." >&2; exit 1
fi

ARCH="$(uname -m)"
OS_ID="$(. /etc/os-release 2>/dev/null && echo "$ID" || echo unknown)"

echo "=== harden-wifi.sh ==="
echo "[INFO] Arch:    $ARCH"
echo "[INFO] OS:      $OS_ID"
echo "[INFO] Dry run: $DRY_RUN"
echo "[INFO] Mode:    WiFi variant"
echo ""

# ---------------------------------------------------------------------------
# Run harden.sh first -- all base hardening applies
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "--- Running base harden.sh ---"
HARDEN_ARGS=""
[[ "$DRY_RUN" == true ]]        && HARDEN_ARGS="$HARDEN_ARGS --dry-run"
[[ "$SKIP_SSH" == true ]]       && HARDEN_ARGS="$HARDEN_ARGS --skip-ssh"
[[ "$SKIP_FIREWALL" == true ]]  && HARDEN_ARGS="$HARDEN_ARGS --skip-firewall"
[[ "$SKIP_RESOLVED" == true ]]  && HARDEN_ARGS="$HARDEN_ARGS --skip-resolved"

bash "$SCRIPT_DIR/harden.sh" $HARDEN_ARGS
echo "[OK]  Base harden.sh complete"
echo ""

# ---------------------------------------------------------------------------
# WiFi Step 1 -- NetworkManager-wait-online
# ---------------------------------------------------------------------------
echo "--- WiFi Step 1: NetworkManager-wait-online ---"
run systemctl enable NetworkManager-wait-online.service
echo "[OK]  NetworkManager-wait-online enabled"

# ---------------------------------------------------------------------------
# WiFi Step 2 -- Disable NM connectivity check
# ---------------------------------------------------------------------------
echo "--- WiFi Step 2: NM connectivity check ---"
run mkdir -p /etc/NetworkManager/conf.d
run tee /etc/NetworkManager/conf.d/no-connectivity-check.conf > /dev/null << 'EOF'
# /etc/NetworkManager/conf.d/no-connectivity-check.conf
# Disables NM HTTP connectivity probe.
# On Pi-hole/Unbound hosts this probe fires before DNS is ready,
# marks the connection "limited", and causes browsers to show offline.
# Applied by harden-wifi.sh -- do not remove.
[connectivity]
enabled=false
EOF
echo "[OK]  NM connectivity check disabled"

# ---------------------------------------------------------------------------
# WiFi Step 3 -- Fix all WiFi NM profiles
# ---------------------------------------------------------------------------
echo "--- WiFi Step 3: Fix WiFi NM profiles ---"
ALL_WIFI=$(nmcli -t -f NAME,TYPE connection show | grep ':wifi$' | cut -d: -f1 2>/dev/null || true)
if [ -n "$ALL_WIFI" ]; then
    while IFS= read -r PROFILE; do
        run nmcli connection modify "$PROFILE" ipv4.ignore-auto-routes no
        run nmcli connection modify "$PROFILE" ipv4.never-default no
        run nmcli connection modify "$PROFILE" ipv4.route-metric 200
        echo "[OK]  Fixed NM profile: $PROFILE"
    done <<< "$ALL_WIFI"
    echo ""
    echo "[WARN] Do NOT restart NetworkManager after this step."
    echo "       Changes apply on next reboot or reconnect."
    echo "       Restarting NM drops SSH sessions and races Unbound."
else
    echo "[WARN] No WiFi profiles found."
    echo "       Connect to WiFi first, then run this script."
fi

# ---------------------------------------------------------------------------
# WiFi Step 4 -- Deploy Unbound systemd drop-in
# ---------------------------------------------------------------------------
echo "--- WiFi Step 4: Unbound systemd drop-in ---"
run mkdir -p /etc/systemd/system/unbound.service.d
run tee /etc/systemd/system/unbound.service.d/10-tailscale.conf > /dev/null << 'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=-/usr/sbin/unbound-anchor -a /var/lib/unbound/root.key
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=120
StartLimitBurst=5
EOF
echo "[OK]  Unbound drop-in written"

# ---------------------------------------------------------------------------
# WiFi Step 5 -- unbound-anchor-refresh.service
# ---------------------------------------------------------------------------
echo "--- WiFi Step 5: unbound-anchor-refresh service ---"
run tee /etc/systemd/system/unbound-anchor-refresh.service > /dev/null << 'EOF'
[Unit]
Description=Refresh Unbound DNSSEC anchor after network is up
After=network-online.target unbound.service
Wants=network-online.target
Requires=unbound.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 5 && /usr/sbin/unbound-anchor -a /var/lib/unbound/root.key; /usr/bin/systemctl restart unbound'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
run systemctl daemon-reload
run systemctl enable unbound-anchor-refresh.service
run systemctl enable --now unbound-anchor.timer
echo "[OK]  unbound-anchor-refresh.service enabled"

# ---------------------------------------------------------------------------
# WiFi Step 6 -- GDM Wayland disable (aarch64 Electron fix)
# ---------------------------------------------------------------------------
if [[ "$SKIP_WAYLAND" == false ]]; then
    echo "--- WiFi Step 6: GDM Wayland disable ---"
    if [ -f /etc/gdm/custom.conf ]; then
        if grep -q "WaylandEnable" /etc/gdm/custom.conf; then
            run sed -i 's/.*WaylandEnable.*/WaylandEnable=false/' /etc/gdm/custom.conf
        else
            run sed -i '/\[daemon\]/a WaylandEnable=false' /etc/gdm/custom.conf
        fi
        echo "[OK]  WaylandEnable=false set in /etc/gdm/custom.conf"
        echo "[INFO] Fixes blank Electron window on aarch64 (Pi 5 BCM2712)"
        echo "[INFO] Requires reboot to take effect"
    else
        echo "[WARN] /etc/gdm/custom.conf not found -- GDM may not be installed"
        echo "[INFO] Skip with --skip-wayland on headless hosts"
    fi
else
    echo "[SKIP] GDM Wayland disable (--skip-wayland)"
fi

# ---------------------------------------------------------------------------
# WiFi Step 7 -- Claude Desktop Wayland flags + autostart
# ---------------------------------------------------------------------------
echo "--- WiFi Step 7: Claude Desktop config ---"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_INSTALL="$SCRIPT_DIR/../claude-desktop/install-claude-desktop.sh"

if [[ -f "$CLAUDE_INSTALL" ]]; then
    # Run as the service user, not root
    if [[ -n "${SERVICE_USER:-}" ]] && id "$SERVICE_USER" &>/dev/null; then
        run sudo -u "$SERVICE_USER" bash "$CLAUDE_INSTALL"
        echo "[OK]  Claude Desktop config deployed for $SERVICE_USER"
    else
        echo "[WARN] SERVICE_USER not set -- run manually as desktop user:"
        echo "       bash claude-desktop/install-claude-desktop.sh"
    fi
else
    echo "[WARN] claude-desktop/install-claude-desktop.sh not found -- skipping"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== harden-wifi.sh complete ==="
echo ""
echo "  Base hardening:    harden.sh complete"
echo "  NM connectivity:   check disabled"
echo "  NM WiFi profiles:  routing fixed"
echo "  Unbound ordering:  drop-in + anchor refresh service"
echo "  GDM Wayland:       $(grep WaylandEnable /etc/gdm/custom.conf 2>/dev/null || echo 'N/A')"
echo "  Anchor timer:      $(systemctl is-active unbound-anchor.timer 2>/dev/null || echo 'check')"
echo ""
echo "  Next: sudo reboot"
echo "  After reboot, wait 30s then: ping -c3 google.com"
echo "  Expected: resolves without any manual intervention"
