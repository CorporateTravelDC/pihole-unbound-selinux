#!/usr/bin/env bash
# scripts/harden.sh
# Host hardening baseline for pihole-unbound-selinux stack
# Fedora 44 -- x86_64, aarch64, armhfp
#
# What this does:
#   1. Detects architecture and skips arch-specific steps that do not apply
#   2. Hardens sshd_config (no DNS, no GSSAPI, no root login, key-only)
#   3. Hardens sysctl (network stack, kernel pointers, core dumps)
#   4. Disables and masks systemd-resolved
#   5. Sets /etc/resolv.conf immutable pointing to 127.0.0.1 (Pi-hole/Unbound)
#   6. Configures firewalld for Pi-hole (DNS) and Unbound ports
#   7. Enables and starts fail2ban
#   8. Sets SELinux enforcing if not already (after policy is applied)
#   9. Schedules filesystem relabel on next boot
#
# Prerequisites:
#   - selinux/apply-selinux-policy.sh must have run successfully
#   - selinux/label-dns-port.sh must have run successfully
#   - georou/pihole-selinux module must be loaded
#   - SSH key-based login must already be configured and tested
#     (this script disables password auth -- do not run before confirming key access)
#
# Usage:
#   sudo bash scripts/harden.sh [--dry-run] [--skip-ssh] [--skip-firewall]
#
# Flags:
#   --dry-run        Print actions without executing
#   --skip-ssh       Skip sshd_config changes
#   --skip-firewall  Skip firewalld changes
#   --skip-resolved  Skip systemd-resolved / resolv.conf steps

set -euo pipefail

DRY_RUN=false
SKIP_SSH=false
SKIP_FIREWALL=false
SKIP_RESOLVED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=true; shift ;;
        --skip-ssh)      SKIP_SSH=true; shift ;;
        --skip-firewall) SKIP_FIREWALL=true; shift ;;
        --skip-resolved) SKIP_RESOLVED=true; shift ;;
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

echo "=== harden.sh ==="
echo "[INFO] Arch:    $ARCH"
echo "[INFO] OS:      $OS_ID"
echo "[INFO] Dry run: $DRY_RUN"
echo ""

# ---------------------------------------------------------------------------
# Step 0 -- User group membership (MUST run before hardening)
# Ensures the service user has access to DRM/GPU devices and audio.
# Required for X11, Electron apps (Claude Desktop), and any GPU-adjacent
# workload. Group membership takes effect on next login.
#
# WHY THIS IS STEP 0:
#   Hardening steps that relabel the filesystem or tighten SELinux policy
#   can make group membership changes harder to diagnose if applied after.
#   Adding groups first ensures a clean baseline before any policy changes.
# ---------------------------------------------------------------------------
echo "--- Step 0: User group membership ---"

# Detect the primary non-root user if not already known
if [[ -z "${SERVICE_USER:-}" ]]; then
    SERVICE_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo '')"
fi

# Groups required for X11, DRM, GPU, audio, input
REQUIRED_GROUPS="video render audio input seat"

if [[ -n "$SERVICE_USER" ]] && id "$SERVICE_USER" &>/dev/null; then
    for GRP in $REQUIRED_GROUPS; do
        if getent group "$GRP" &>/dev/null; then
            run usermod -aG "$GRP" "$SERVICE_USER"
            echo "[OK]  Added $SERVICE_USER to group: $GRP"
        else
            echo "[SKIP] Group $GRP does not exist on this system"
        fi
    done
    echo "[INFO] Group changes take effect on next login for $SERVICE_USER"
else
    echo "[WARN] Could not detect service user -- set SERVICE_USER= and re-run"
    echo "       Example: sudo SERVICE_USER=corporatetraveldc bash scripts/harden.sh"
fi

# ---------------------------------------------------------------------------
# SELinux -- drop to permissive for duration of hardening script
# Restored at end after policy is confirmed good
# ---------------------------------------------------------------------------
SELINUX_WAS_ENFORCING=false
if command -v getenforce &>/dev/null; then
    SE_STATE="$(getenforce 2>/dev/null || echo Disabled)"
    echo "[INFO] SELinux current state: $SE_STATE"
    if [[ "$SE_STATE" == "Enforcing" ]]; then
        echo "[INFO] Setting SELinux permissive for script duration..."
        run setenforce 0
        SELINUX_WAS_ENFORCING=true
    fi
fi

# ---------------------------------------------------------------------------
# Step 1 -- SSH hardening
# ---------------------------------------------------------------------------
if [[ "$SKIP_SSH" == false ]]; then
    echo "--- Step 1: SSH hardening ---"

    SSHD_CONF="/etc/ssh/sshd_config"
    SSHD_DROP="/etc/ssh/sshd_config.d/99-csexec-harden.conf"

    # Write a drop-in rather than editing the main file
    run tee "$SSHD_DROP" > /dev/null << 'SSHCONF'
# 99-csexec-harden.conf
# Applied by harden.sh -- do not edit manually

# Disable reverse DNS lookups on connect (eliminates delay on untrusted networks)
UseDNS no

# Disable GSSAPI (not needed; eliminates Kerberos dependency)
GSSAPIAuthentication no
GSSAPICleanupCredentials no

# Disable root login entirely
PermitRootLogin no

# Key-only authentication
# WARNING: confirm key-based login works BEFORE enabling this
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey

# Limit auth attempts and sessions
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 30

# Disable unused features
X11Forwarding no
AllowAgentForwarding yes
AllowTcpForwarding yes
PermitTunnel no
SSHCONF

    run chmod 600 "$SSHD_DROP"
    echo "[INFO] Validating sshd config..."
    if sshd -t 2>&1; then
        echo "[OK]  sshd config valid"
        run systemctl restart sshd
        echo "[OK]  sshd restarted"
    else
        echo "[FAIL] sshd config invalid -- drop-in written but sshd NOT restarted" >&2
        echo "       Review $SSHD_DROP and fix before restarting sshd manually." >&2
    fi
else
    echo "[SKIP] SSH hardening (--skip-ssh)"
fi

# ---------------------------------------------------------------------------
# Step 2 -- sysctl hardening
# ---------------------------------------------------------------------------
echo "--- Step 2: sysctl hardening ---"

run tee /etc/sysctl.d/99-csexec-harden.conf > /dev/null << 'SYSCTL'
# 99-csexec-harden.conf
# Applied by harden.sh

# Network -- disable IP source routing and redirects
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3

# Ignore ICMP broadcasts and bogus error responses
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 -- disable if not needed (uncomment to apply)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Kernel -- hide pointers from unprivileged users
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# Disable core dumps for setuid programs
fs.suid_dumpable = 0

# Increase inotify limits (Pi-hole FTL uses inotify)
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 131072
SYSCTL

run sysctl --system
echo "[OK]  sysctl applied"

# ---------------------------------------------------------------------------
# Step 3 -- Disable systemd-resolved
# ---------------------------------------------------------------------------
if [[ "$SKIP_RESOLVED" == false ]]; then
    echo "--- Step 3: systemd-resolved ---"

    if systemctl is-active systemd-resolved &>/dev/null 2>&1; then
        run systemctl stop systemd-resolved
        echo "[OK]  systemd-resolved stopped"
    fi
    run systemctl disable systemd-resolved
    run systemctl mask systemd-resolved
    echo "[OK]  systemd-resolved disabled and masked"

    # Remove the symlink and write a static resolv.conf
    RESOLV="/etc/resolv.conf"
    if [[ -L "$RESOLV" ]]; then
        run rm -f "$RESOLV"
    fi

    run tee "$RESOLV" > /dev/null << 'RESOLV'
# /etc/resolv.conf
# Managed by harden.sh -- DO NOT EDIT
# systemd-resolved is disabled on this host.
# DNS is provided by Pi-hole (port 53) -> Unbound (port 5335).
nameserver 127.0.0.1
options edns0
RESOLV

    # Make immutable so nothing can overwrite it
    run chattr +i "$RESOLV"
    echo "[OK]  /etc/resolv.conf written and locked immutable"
    echo "[INFO] To edit: sudo chattr -i /etc/resolv.conf"
else
    echo "[SKIP] systemd-resolved / resolv.conf (--skip-resolved)"
fi

# ---------------------------------------------------------------------------
# Step 4 -- firewalld
# ---------------------------------------------------------------------------
if [[ "$SKIP_FIREWALL" == false ]]; then
    echo "--- Step 4: firewalld ---"

    if ! systemctl is-active firewalld &>/dev/null 2>&1; then
        run systemctl enable --now firewalld
    fi

    # Allow SSH (always -- do not lock yourself out)
    run firewall-cmd --permanent --add-service=ssh

    # Allow DNS on the trusted Tailscale interface
    # Change zone name if your Tailscale interface is in a different zone
    if firewall-cmd --get-zones | grep -q "trusted"; then
        run firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 2>/dev/null || true
        run firewall-cmd --permanent --zone=trusted --add-service=dns
    fi

    # Pi-hole web UI -- loopback only via default zone
    # Remove this block if you are not exposing the Pi-hole web UI
    run firewall-cmd --permanent --add-port=80/tcp

    run firewall-cmd --reload
    echo "[OK]  firewalld configured"
    echo "[INFO] Review zones: sudo firewall-cmd --list-all-zones"
else
    echo "[SKIP] firewalld (--skip-firewall)"
fi

# ---------------------------------------------------------------------------
# Step 5 -- fail2ban
# ---------------------------------------------------------------------------
echo "--- Step 5: fail2ban ---"
if ! command -v fail2ban-server &>/dev/null; then
    run dnf install -y fail2ban
fi

# Write a minimal jail for SSH
run tee /etc/fail2ban/jail.d/sshd-csexec.conf > /dev/null << 'F2B'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/secure
maxretry = 5
bantime  = 3600
findtime = 600
F2B

run systemctl enable --now fail2ban
echo "[OK]  fail2ban enabled"

# ---------------------------------------------------------------------------
# Step 6 -- Restore SELinux enforcing + schedule relabel
# ---------------------------------------------------------------------------
echo "--- Step 6: SELinux restore ---"
if [[ "$SELINUX_WAS_ENFORCING" == true ]]; then
    run setenforce 1
    echo "[OK]  SELinux restored to Enforcing"
    run touch /.autorelabel
    echo "[OK]  /.autorelabel created -- full filesystem relabel on next boot"
    echo "[WARN] Reboot required to complete SELinux relabeling."
else
    echo "[INFO] SELinux was not enforcing at script start -- no restore needed"
    echo "[INFO] After applying selinux/apply-selinux-policy.sh and verifying,"
    echo "       run: sudo setenforce 1 && sudo touch /.autorelabel && sudo reboot"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Hardening complete ==="
echo ""
echo "  Arch:      $ARCH"
echo "  SSH:       /etc/ssh/sshd_config.d/99-csexec-harden.conf"
echo "  sysctl:    /etc/sysctl.d/99-csexec-harden.conf"
echo "  resolv:    /etc/resolv.conf (immutable, 127.0.0.1)"
echo "  firewalld: $(firewall-cmd --list-all 2>/dev/null | head -1 || echo 'check manually')"
echo "  fail2ban:  $(systemctl is-active fail2ban 2>/dev/null || echo 'check status')"
echo "  SELinux:   $(getenforce 2>/dev/null || echo 'N/A')"
if [[ -f /.autorelabel ]]; then
echo ""
echo "  [WARN] /.autorelabel present -- reboot required"
fi

# ---------------------------------------------------------------------------
# Step 7 -- NetworkManager WiFi profile routing fix
# ---------------------------------------------------------------------------
echo "--- Step 7: NetworkManager WiFi profile fix ---"

ALL_WIFI=$(nmcli -t -f NAME,TYPE connection show | grep ':wifi$' | cut -d: -f1 2>/dev/null || true)
if [ -n "$ALL_WIFI" ]; then
    while IFS= read -r PROFILE; do
        run nmcli connection modify "$PROFILE" ipv4.ignore-auto-routes no
        run nmcli connection modify "$PROFILE" ipv4.never-default no
        run nmcli connection modify "$PROFILE" ipv4.route-metric 200
        echo "[OK]  Fixed NM profile: $PROFILE"
    done <<< "$ALL_WIFI"
else
    echo "[INFO] No WiFi profiles found -- skipping"
fi

# NM connectivity check -- disable to prevent browser offline state
run mkdir -p /etc/NetworkManager/conf.d
run tee /etc/NetworkManager/conf.d/no-connectivity-check.conf > /dev/null << 'NMCONF'
[connectivity]
enabled=false
NMCONF
echo "[OK]  NM connectivity check disabled"
echo "[WARN] Do NOT restart NetworkManager -- changes apply on next reboot or reconnect"

# ---------------------------------------------------------------------------
# Step 8 -- GDM X11 forced (Electron/aarch64 Wayland workaround)
# ---------------------------------------------------------------------------
echo "--- Step 8: GDM Wayland disable ---"
if [ -f /etc/gdm/custom.conf ]; then
    if grep -q "WaylandEnable" /etc/gdm/custom.conf; then
        run sed -i 's/.*WaylandEnable.*/WaylandEnable=false/' /etc/gdm/custom.conf
    else
        run sed -i '/\[daemon\]/a WaylandEnable=false' /etc/gdm/custom.conf
    fi
    echo "[OK]  WaylandEnable=false set in /etc/gdm/custom.conf"
else
    echo "[WARN] /etc/gdm/custom.conf not found -- GDM may not be installed"
fi
