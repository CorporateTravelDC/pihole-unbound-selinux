# pihole-unbound-selinux

Pi-hole v6 + Unbound recursive resolver + SELinux enforcing -- Fedora 43+.

Tested on:

| Arch | Hardware |
|---|---|
| `aarch64` | Raspberry Pi 5 (BCM2712) -- primary target |
| `aarch64` | Raspberry Pi 4, ARM cloud instances |
| `x86_64` | Standard PC / server / VM |

---

> ALL Public Commits are GPG signed by key (pubkey included in this repo): ABD3976FCC006E0F3FE559177286B3118BA4EFB2 


## Hardening script variants

This repo ships two hardening scripts. Choose the one that matches your
network setup. They are not interchangeable.

### `scripts/harden.sh` -- Wired (Ethernet) hosts

Use this when the Pi or server connects via **Ethernet**.

- Assumes a stable, always-present wired network interface
- Does not include NetworkManager WiFi profile fixes
- Does not include NM connectivity check workaround
- Boot-to-DNS is fast and deterministic
- Recommended for any host with a reliable wired connection

### `scripts/harden-wifi.sh` -- WiFi hosts (or wired with WiFi fallback)

Use this when the Pi or server connects via **WiFi**, either exclusively
or as a fallback when wired is unavailable.

- Includes everything in `harden.sh`
- Adds NM WiFi profile routing fixes (`ipv4.ignore-auto-routes=no`,
  `ipv4.route-metric=200`)
- Disables NM connectivity check (prevents false browser offline state
  caused by probe firing before Pi-hole/Unbound are ready)
- Adds `unbound-anchor-refresh.service` for DNSSEC anchor stability
  post-boot on networks that may not be immediately available
- Disables Wayland in GDM (fixes blank Electron/Claude Desktop window
  on aarch64 Pi 5 BCM2712 -- Electron Wayland backend broken)
- Enables `NetworkManager-wait-online` for deterministic boot ordering

**WiFi tradeoffs vs wired:**
- Boot-to-DNS takes ~30s longer (WiFi auth + DHCP + DNSSEC anchor refresh)
- NM is retained as network manager -- required for enterprise/802.1X WiFi
  (e.g. community hotspots, PEAP/MSCHAPv2 networks)
- Do NOT run `nmcli networking off/on` or `systemctl restart NetworkManager`
  while SSH is active -- drops session and races Unbound start

**WiFi credentials:**
This script does NOT configure WiFi credentials. Connect to your network
first via `nmcli device wifi connect` or GNOME Settings, then run
`harden-wifi.sh` to harden the resulting NM profile.

---

## What this stack is

A tested, reproducible configuration for:

- **Pi-hole v6** as a local DNS sinkhole (ad-block + LAN DNS)
- **Unbound** as a self-hosted recursive upstream resolver (no third-party
  DNS, full DNSSEC validation)
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
  pihole.toml                    Pi-hole v6 config (placeholder values)
unbound/
  unbound.conf                   Unbound recursive resolver config
selinux/
  apply-selinux-policy.sh        Policy compiler + labeler (idempotent)
  label-dns-port.sh              semanage dns_port_t for port 5335
  csexec-logind-userns.te        systemd-logind userns allow
  csexec-tailscaled.te           Tailscale AVC allows
  csexec-virtqemud.te            virt-qemud home dir access
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
  custom.conf                    GDM config (Wayland disabled, YOUR_USERNAME)
docs/
  INSTALL.md                     Step-by-step install guide + known issues
```

---

## Placeholder substitutions

Before use, replace these values in the relevant config files:

| Placeholder | Replace with |
|---|---|
| `YOUR_TAILSCALE_IP` | Your Tailscale node IP (`100.x.y.z`) |
| `YOUR_USERNAME` | Your non-root admin/service user |
| `YOUR_HOSTNAME` | Your machine hostname |
| `tailscale0` | Your Tailscale interface name (usually `tailscale0`) |

---

## Related

- [georou/pihole-selinux](https://github.com/georou/pihole-selinux) -- required SELinux policy for Pi-hole
- [CorporateTravelDC/ctdi-dispatch](https://github.com/CorporateTravelDC/ctdi-dispatch) -- dispatch stack built on this DNS foundation
