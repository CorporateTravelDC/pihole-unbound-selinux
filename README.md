# pihole-unbound-selinux

Pi-hole v6 + Unbound recursive resolver + SELinux enforcing -- Fedora 44.

Tested on all architectures Fedora 44 ships for:

| Arch | Example hardware |
|---|---|
| `x86_64` | Standard PC / server / VM |
| `aarch64` | Raspberry Pi 4/5, ARM cloud instances, Apple Silicon VM |
| `armhfp` | Raspberry Pi 3 and older ARMv7 boards |

## What this is

A tested, reproducible configuration stack for:

- **Pi-hole v6** as a local DNS sinkhole (ad-block + LAN DNS)
- **Unbound** as a self-hosted recursive upstream resolver (no third-party DNS, DNSSEC-validated)
- **SELinux enforcing** mode across the full stack on Fedora 44
- **Hardened host** baseline (SSH, sysctl, firewalld, systemd-resolved replaced)

No cloud resolver dependencies. All DNS resolution is local. `systemd-resolved` is
replaced entirely; Pi-hole owns port 53 on the designated interface; Unbound listens
on `127.0.0.1:5335`.

## SELinux installation sequence -- critical

Installing Pi-hole and Unbound under SELinux enforcing will fail without relaxing
the policy at install time and restoring it after the custom modules are loaded.

### Required: pihole-selinux

Before installing Pi-hole, install the community SELinux policy module:

```
https://github.com/georou/pihole-selinux
```

Follow that repo's instructions to load the Pi-hole `.te`/`.pp` policy before
the Pi-hole installer runs or before first start after install.

### Kernel boot parameters for install

When the system uses SELinux and you need to run the Pi-hole curl installer cleanly,
add one of these to the kernel command line **temporarily** at the GRUB menu:

```
selinux=0
```

Fully disables SELinux for that boot. Cleanest for package installs that touch
systemd units, firewall rules, and /etc directories.

```
enforcing=0
```

Keeps the kernel SELinux-aware but in permissive mode -- denials are logged but
not blocked. Use this if you want AVC audit records during install to build policy
from.

The `scripts/harden.sh` in this repo handles the `setenforce 0` / `setenforce 1`
runtime cycle. Use the kernel boot parameters only when you cannot start a session
to run setenforce first (e.g. remote headless install, firstboot scripts).

### Full install sequence

```
1.  Boot with enforcing=0 (or selinux=0 for cleanest install)
2.  Install Fedora 44 dependencies:
      sudo dnf install -y unbound policycoreutils-python-utils checkpolicy firewalld fail2ban
3.  Install georou/pihole-selinux .pp module (see that repo)
4.  Install Pi-hole via curl installer
5.  Install Unbound
6.  Deploy configs from this repo (see docs/INSTALL.md)
7.  Run:  sudo bash selinux/apply-selinux-policy.sh
8.  Run:  sudo bash selinux/label-dns-port.sh
9.  Restore enforcing:  sudo setenforce 1
10. Trigger filesystem relabel:  sudo touch /.autorelabel && sudo reboot
```

## Repository layout

```
pihole/
  pihole.toml              Pi-hole v6 override-only config (TOML)
unbound/
  unbound.conf             Unbound recursive resolver config
selinux/
  apply-selinux-policy.sh  Policy compiler + directory labeler (idempotent)
  label-dns-port.sh        semanage dns_port_t for port 5335
  csexec-logind-userns.te  systemd-logind userns allow (rootless containers)
  csexec-tailscaled.te     Tailscale runtime AVC allows
  csexec-virtqemud.te      virt-qemud home dir access (image build hosts)
scripts/
  harden.sh                Host hardening baseline (SSH, sysctl, firewalld, resolved)
docs/
  INSTALL.md               Step-by-step install guide
```

## Placeholder substitutions

Replace these throughout before deploying:

| Placeholder | Replace with |
|---|---|
| `YOUR_TAILSCALE_IP` | Your Tailscale node IP (`100.x.y.z`) |
| `YOUR_TAILSCALE_IFACE` | Interface name -- usually `tailscale0` |
| `YOUR_HOSTNAME` | Machine hostname |
| `YOUR_ADMIN_USER` | Non-root service/admin user |

## Fedora 44 packages

```bash
sudo dnf install -y \
  unbound \
  policycoreutils-python-utils \
  checkpolicy \
  firewalld \
  fail2ban
```

Pi-hole installs via its own curl installer -- do not use dnf.

## Related

- [georou/pihole-selinux](https://github.com/georou/pihole-selinux) -- required SELinux policy for Pi-hole
- [CorporateTravelDC/ctdi-dispatch](https://github.com/CorporateTravelDC/ctdi-dispatch) -- dispatch stack that builds on this DNS foundation
