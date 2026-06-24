#!/bin/bash
# scripts/check-idempotency.sh
#
# PURPOSE:
#   Checks current system state against expected post-install state.
#   Reports what is configured correctly, what is missing, and what
#   needs attention. Does NOT make changes -- read-only audit.
#
# USAGE:
#   bash scripts/check-idempotency.sh
#
# Use this after any reboot, rebuild, or partial install to know
# exactly what still needs to be run.

set -e

PASS=0
FAIL=0
WARN=0

ok()   { echo "[OK]   $*"; ((PASS++)) || true; }
fail() { echo "[FAIL] $*"; ((FAIL++)) || true; }
warn() { echo "[WARN] $*"; ((WARN++)) || true; }

echo "=== Idempotency Check ==="
echo "[INFO] $(date)"
echo "[INFO] Host: $(hostname)"
echo "[INFO] Arch: $(uname -m)"
echo ""

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
echo "--- User groups ---"
for GRP in video render audio input; do
    if id YOUR_USERNAME 2>/dev/null | grep -q "$GRP"; then
        ok "YOUR_USERNAME in group: $GRP"
    else
        fail "YOUR_USERNAME NOT in group: $GRP -- run: sudo usermod -aG $GRP YOUR_USERNAME"
    fi
done

# ---------------------------------------------------------------------------
# DNS stack
# ---------------------------------------------------------------------------
echo ""
echo "--- DNS stack ---"

systemctl is-active pihole-FTL &>/dev/null && ok "pihole-FTL active" || fail "pihole-FTL not active"
systemctl is-active unbound &>/dev/null && ok "unbound active" || fail "unbound not active"
systemctl is-enabled unbound-anchor.timer &>/dev/null && ok "unbound-anchor.timer enabled" || fail "unbound-anchor.timer not enabled"
systemctl is-enabled unbound-anchor-refresh.service &>/dev/null && ok "unbound-anchor-refresh enabled" || fail "unbound-anchor-refresh not enabled"

# resolv.conf
if grep -q "nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null; then
    ok "resolv.conf points to 127.0.0.1"
else
    fail "resolv.conf not pointing to 127.0.0.1"
fi

# resolv.conf immutable
if lsattr /etc/resolv.conf 2>/dev/null | grep -q "\-i-"; then
    ok "resolv.conf is immutable"
else
    warn "resolv.conf is NOT immutable -- run: sudo chattr +i /etc/resolv.conf"
fi

# Unbound loopback-only bind
if grep -q "interface: 100\." /etc/unbound/unbound.conf 2>/dev/null; then
    fail "unbound.conf still has Tailscale IP bind -- remove interface: 100.x.x.x"
else
    ok "unbound.conf loopback-only bind"
fi

# DNS resolution test
if dig @127.0.0.1 -p 5335 google.com +short &>/dev/null; then
    ok "Unbound resolves google.com"
else
    fail "Unbound cannot resolve google.com -- check anchor and upstream"
fi

if dig @127.0.0.1 google.com +short &>/dev/null; then
    ok "Pi-hole resolves google.com"
else
    fail "Pi-hole cannot resolve google.com"
fi

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
echo ""
echo "--- Networking ---"

systemctl is-active tailscaled &>/dev/null && ok "tailscaled active" || fail "tailscaled not active"

ip addr show tailscale0 2>/dev/null | grep -q "100\." && ok "tailscale0 has 100.x IP" || fail "tailscale0 missing 100.x IP"

ip route show | grep -q "^default" && ok "default gateway present" || fail "no default gateway -- check NM WiFi profile"

if [ -f /etc/NetworkManager/conf.d/no-connectivity-check.conf ]; then
    ok "NM connectivity check disabled"
else
    fail "NM connectivity check NOT disabled -- run: networkmanager/fix-wifi-profiles.sh"
fi

ALL_WIFI=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep ':wifi$' | cut -d: -f1 || true)
if [ -n "$ALL_WIFI" ]; then
    while IFS= read -r PROFILE; do
        IGNORE=$(nmcli connection show "$PROFILE" 2>/dev/null | grep "ipv4.ignore-auto-routes" | awk '{print $2}')
        if [ "$IGNORE" = "no" ]; then
            ok "NM profile '$PROFILE': ignore-auto-routes=no"
        else
            fail "NM profile '$PROFILE': ignore-auto-routes=$IGNORE -- run: networkmanager/fix-wifi-profiles.sh"
        fi
    done <<< "$ALL_WIFI"
fi

# ---------------------------------------------------------------------------
# Systemd drop-ins
# ---------------------------------------------------------------------------
echo ""
echo "--- Systemd drop-ins ---"

[ -f /etc/systemd/system/unbound.service.d/10-tailscale.conf ] && \
    ok "unbound drop-in present" || \
    fail "unbound drop-in missing -- deploy systemd/unbound.service.d-10-tailscale.conf"

[ -f /etc/systemd/system/unbound-anchor-refresh.service ] && \
    ok "unbound-anchor-refresh.service present" || \
    fail "unbound-anchor-refresh.service missing"

# ---------------------------------------------------------------------------
# SELinux
# ---------------------------------------------------------------------------
echo ""
echo "--- SELinux ---"

SESTATE=$(getenforce 2>/dev/null || echo "N/A")
[ "$SESTATE" = "Enforcing" ] && ok "SELinux: Enforcing" || fail "SELinux: $SESTATE (expected Enforcing)"

semanage port -l 2>/dev/null | grep -q "5335.*dns_port_t" && \
    ok "Port 5335 labeled dns_port_t" || \
    fail "Port 5335 not labeled -- run: selinux/label-dns-port.sh"

# ---------------------------------------------------------------------------
# Display / Desktop
# ---------------------------------------------------------------------------
echo ""
echo "--- Display stack ---"

grep -q "WaylandEnable=false" /etc/gdm/custom.conf 2>/dev/null && \
    ok "GDM WaylandEnable=false" || \
    warn "GDM WaylandEnable not set (may be intentional on headless)"

[ -f "$HOME/.config/claude/claude-desktop-flags.conf" ] && \
    ok "Claude Desktop Wayland flags present" || \
    warn "Claude Desktop flags missing -- run: bash claude-desktop/install-claude-desktop.sh"

[ -f "$HOME/.config/autostart/claude-desktop.desktop" ] && \
    ok "Claude Desktop autostart present" || \
    warn "Claude Desktop autostart missing -- run: bash claude-desktop/install-claude-desktop.sh"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "  Pass: $PASS"
echo "  Warn: $WARN"
echo "  Fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "  [ACTION REQUIRED] Fix FAIL items above before proceeding."
elif [ "$WARN" -gt 0 ]; then
    echo "  [REVIEW] Check WARN items -- may be intentional."
else
    echo "  [ALL CLEAR] System matches expected post-install state."
fi
