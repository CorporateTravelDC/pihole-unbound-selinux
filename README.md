# pihole-unbound-selinux-internal

> **INTERNAL** -- Real values pre-applied. This repo is private.
> Do not push to a public remote or share credentials from this file.

Pi-hole v6 + Unbound recursive resolver + SELinux enforcing -- Fedora 43+.

Tested on:

| Arch | Hardware |
|---|---|
| `aarch64` | Raspberry Pi 5 (BCM2712) -- primary target |
| `aarch64` | Raspberry Pi 4, ARM cloud instances |
| `x86_64` | Standard PC / server / VM |

---

## Hardening script variants

This repo ships two hardening scripts. Choose the one that matches your
network setup. They are not interchangeable.

### `scripts/harden.sh` -- Wired (Ethernet) hosts

Use this when the Pi or server connects via Ethernet.

- Assumes a stable, always-present network interface
- Does not include NetworkManager WiFi profile fixes
- Does not include NM connectivity check workaround
- Boot-to-DNS is fast and deterministic

### `scripts/harden-wifi.sh` -- WiFi hosts (or wired with WiFi fallback)

Use this when the Pi or server connects via WiFi, either exclusively or
as a fallback when wired is unavailable.

- Includes everything in `harden.sh`
- Adds NM WiFi profile routing fixes (`ipv4.ignore-auto-routes=no`)
- Disables NM connectivity check (prevents false browser offline state)
- Adds `unbound-anchor-refresh.service` for DNSSEC stability post-boot
- Disables Wayland in GDM (fixes blank Electron window on aarch64)
- Enables `NetworkManager-wait-online` for deterministic boot ordering

**WiFi tradeoffs vs wired:**
- Boot-to-DNS takes ~30s longer (WiFi auth + DHCP + DNSSEC anchor refresh)
- NM is retained as network manager -- do not replace with systemd-networkd
  on enterprise/802.1X WiFi (e.g. Xfinity community hotspot)
- Do NOT run `nmcli networking off/on` or `systemctl restart NetworkManager`
  while SSH is active -- drops session and races Unbound

---

## What this stack is

A tested, reproducible configuration for:

- **Pi-hole v6** as a local DNS sinkhole (ad-block + LAN DNS)
- **Unbound** as a self-hosted recursive upstream resolver (no third-party
  DNS, DNSSEC-validated)
- **SELinux enforcing** mode across the full stack on Fedora 43+
- **Hardened host** baseline (SSH, sysctl, firewalld, systemd-resolved replaced)

No cloud resolver dependencies. All DNS resolution is local.
`systemd-resolved` is replaced entirely; Pi-hole owns port 53;
Unbound listens on `127.0.0.1:5335`.

---

## SELinux installation sequence -- critical

### Required: pihole-selinux

Before installing Pi-hole, install the community SELinux policy module:

```
https://github.com/georou/pihole-selinux
```

### Kernel boot parameters for install

Add one of these to the kernel command line temporarily at GRUB:

```
selinux=0        # fully disabled for that boot -- cleanest for installs
enforcing=0      # permissive -- AVC denials logged but not blocked
```

### Full install sequence

```
1.  Boot with enforcing=0 (or selinux=0)
2.  Install dependencies:
      sudo dnf install -y unbound policycoreutils-python-utils \
        checkpolicy firewalld fail2ban
3.  Install georou/pihole-selinux .pp module
4.  Install Pi-hole via curl installer
5.  Install Unbound
6.  Deploy configs from this repo (see docs/INSTALL.md)
7.  sudo bash selinux/apply-selinux-policy.sh
8.  sudo bash selinux/label-dns-port.sh
9.  For wired:  sudo bash scripts/harden.sh
    For WiFi:   sudo bash scripts/harden-wifi.sh
10. sudo touch /.autorelabel && sudo reboot
```

---

## Repository layout

```
pihole/
  pihole.toml                    Pi-hole v6 config (TOML)
unbound/
  unbound.conf                   Unbound recursive resolver config
selinux/
  apply-selinux-policy.sh                Policy compiler + labeler (idempotent)
  label-dns-port.sh                      semanage dns_port_t for port 5335
  corporatetraveldc-logind-userns.te     systemd-logind userns allow
  corporatetraveldc-tailscaled.te        Tailscale AVC allows
  corporatetraveldc-virtqemud.te         virt-qemud home dir access
  corporatetraveldc-pihole-local.te      pihole_t local allows + httpd_t -> pihole_port_t (nginx :80)
  corporatetraveldc-tailscale-ssh-login.te  Tailscale SSH login session allows
```
Pi-hole's own webserver port (8091) and every other nginx `proxy_pass`
target are labeled by `ctdi-dispatch-internal/selinux/label-nginx-backend-ports.sh`,
not by this repo -- that repo owns the vhost list, so it's the single source
of truth for which backend ports nginx is allowed to reach. Run it too
before re-enabling enforcing.
```
scripts/
  harden.sh                      Wired host hardening baseline
  harden-wifi.sh                 WiFi host hardening (superset of harden.sh)
systemd/
  unbound.service.d-10-tailscale.conf   Unbound boot ordering drop-in
  unbound-anchor-refresh.service        DNSSEC anchor post-boot refresh
networkmanager/
  no-connectivity-check.conf     Disable NM connectivity probe
  fix-wifi-profiles.sh           Fix routing on all WiFi NM profiles
gdm/
  custom.conf                    GDM config (Wayland disabled)
docs/
  INSTALL.md                     Step-by-step install guide + known issues
```

---

## Placeholder substitutions (internal -- real values pre-applied)

| Placeholder | Value |
|---|---|
| `100.94.80.100` | Tailscale node IP |
| `tailscale0` | Tailscale interface name |
| `corporatetraveldc-dispatch` | Hostname |
| `corporatetraveldc` | Service/admin user |

---

## Related

- [georou/pihole-selinux](https://github.com/georou/pihole-selinux) -- required SELinux policy for Pi-hole
- [CorporateTravelDC/ctdi-dispatch](https://github.com/CorporateTravelDC/ctdi-dispatch) -- dispatch stack built on this DNS foundation
