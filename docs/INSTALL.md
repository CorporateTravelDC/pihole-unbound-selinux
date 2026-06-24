# Installation Guide -- pihole-unbound-selinux-internal

## Prerequisites

- Fedora 43+ aarch64 (Pi 5) or x86_64
- SELinux enforcing
- SSH key-based login configured and tested
- Pi-hole v6.x installed
- Tailscale installed and authenticated

## Install Order

Run these steps in order. Each step depends on the previous.

### 1. Apply SELinux policies

```bash
sudo bash selinux/apply-selinux-policy.sh
sudo bash selinux/label-dns-port.sh
```

### 2. Deploy Unbound config

```bash
sudo cp unbound/unbound.conf /etc/unbound/unbound.conf
sudo systemctl enable --now unbound-anchor.timer
sudo unbound-anchor -a /var/lib/unbound/root.key
sudo systemctl enable --now unbound
```

### 3. Deploy systemd units

```bash
sudo mkdir -p /etc/systemd/system/unbound.service.d
sudo cp systemd/unbound.service.d-10-tailscale.conf \
     /etc/systemd/system/unbound.service.d/10-tailscale.conf
sudo cp systemd/unbound-anchor-refresh.service \
     /etc/systemd/system/unbound-anchor-refresh.service
sudo systemctl daemon-reload
sudo systemctl enable unbound-anchor-refresh.service
```

### 4. Deploy NetworkManager fixes

```bash
sudo cp networkmanager/no-connectivity-check.conf \
     /etc/NetworkManager/conf.d/no-connectivity-check.conf
sudo bash networkmanager/fix-wifi-profiles.sh
```

**WARNING:** Do NOT restart NetworkManager manually after this step.
Changes apply on next reboot. Restarting NM drops SSH sessions and
triggers Unbound race conditions.

### 5. Deploy GDM config (desktop hosts only)

```bash
sudo cp gdm/custom.conf /etc/gdm/custom.conf
```

### 6. Run harden.sh

```bash
sudo bash scripts/harden.sh
```

### 7. Reboot and verify

```bash
sudo reboot
# After boot -- wait 30 seconds for anchor refresh to settle
ping -c3 google.com
systemctl status unbound pihole-FTL tailscaled
ip route show
```

Expected: all three services active, default gateway present, DNS resolving.

## Known Issues and Fixes

### Unbound SERVFAIL after boot

Caused by DNSSEC trust anchor loading before internet is available.
Fixed by `unbound-anchor-refresh.service` which fires 5 seconds after
boot, refreshes the anchor, and restarts Unbound. Takes ~30 seconds
from boot to full DNS resolution. This is expected and normal.

### NM marks WiFi "limited" / browsers show offline

Caused by NM connectivity check firing before Pi-hole/Unbound are ready.
Fixed by `no-connectivity-check.conf`. If browsers still show offline
after this fix is applied, reboot -- do not cycle NM manually.

### WiFi gets IP but no default gateway after reboot

Caused by `ipv4.ignore-auto-routes=yes` on NM WiFi profiles.
Fixed by `fix-wifi-profiles.sh`. Run once per new WiFi network added.

### Claude Desktop blank grey window on Pi 5

Caused by Electron's Wayland backend failing on BCM2712 aarch64.
Fixed by `WaylandEnable=false` in `/etc/gdm/custom.conf`.
Requires reboot to take effect.

### Unbound fails to bind: "cannot assign requested address"

Caused by `interface: 100.94.80.100` in unbound.conf -- Tailscale IP
is not assigned at Unbound start time. Fixed by removing that interface
line. Unbound now binds to loopback only.
