# INSTALL.md
# pihole-unbound-selinux -- step-by-step install guide
# Fedora 44 -- x86_64, aarch64, armhfp

## Prerequisites

- Fedora 44 installed and booted
- SSH key-based access confirmed (harden.sh disables password auth)
- Tailscale installed and connected (`tailscale up`)
- Note your Tailscale IP: `tailscale ip -4`

## 0. Replace placeholders

Before deploying any file from this repo, substitute:

| Placeholder | Value |
|---|---|
| `YOUR_TAILSCALE_IP` | Output of `tailscale ip -4` |
| `YOUR_TAILSCALE_IFACE` | Usually `tailscale0` (confirm: `ip link show`) |
| `YOUR_HOSTNAME` | `hostname -s` |
| `YOUR_ADMIN_USER` | Your non-root admin user |

## 1. Install Fedora packages

```bash
sudo dnf install -y \
  unbound \
  policycoreutils-python-utils \
  checkpolicy \
  firewalld \
  fail2ban
```

## 2. Relax SELinux for install

At the GRUB menu, press `e`, find the `linux` line, append `enforcing=0`,
then press `Ctrl+X` to boot. This is a one-time-boot parameter.

Or if already booted into an enforcing system:

```bash
sudo setenforce 0
```

## 3. Install georou/pihole-selinux

Required before Pi-hole installer runs:

```
https://github.com/georou/pihole-selinux
```

Follow that repo's instructions. Confirm the module loads:

```bash
sudo semodule -l | grep -i pihole
```

## 4. Install Pi-hole

```bash
curl -sSL https://install.pi-hole.net | bash
```

During the interactive installer:
- Select `Custom` DNS and enter `127.0.0.1#5335` (Unbound)
- Select the Tailscale interface (`YOUR_TAILSCALE_IFACE`) as the listening interface

## 5. Deploy configs

```bash
sudo cp pihole/pihole.toml /etc/pihole/pihole.toml
sudo cp unbound/unbound.conf /etc/unbound/unbound.conf
```

Initialize Unbound root trust anchor and hints:

```bash
sudo unbound-anchor -a /var/lib/unbound/root.key
sudo curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
sudo chown unbound:unbound /var/lib/unbound/root.key /var/lib/unbound/root.hints
```

Enable and start Unbound:

```bash
sudo systemctl enable --now unbound
```

Restart Pi-hole FTL:

```bash
sudo systemctl restart pihole-FTL
```

## 6. Apply SELinux policy

```bash
sudo bash selinux/apply-selinux-policy.sh
sudo bash selinux/label-dns-port.sh
```

Verify Unbound can bind port 5335:

```bash
sudo systemctl status unbound
dig @127.0.0.1 -p 5335 google.com
```

## 7. Harden the host

Confirm SSH key access works in a separate session before running this step.

```bash
sudo bash scripts/harden.sh
```

Review the flags:

```bash
sudo bash scripts/harden.sh --help   # lists flags
sudo bash scripts/harden.sh --dry-run  # preview without applying
```

## 8. Restore SELinux enforcing + relabel

```bash
sudo setenforce 1
sudo touch /.autorelabel
sudo reboot
```

After reboot, verify:

```bash
getenforce
# Expected: Enforcing

dig @127.0.0.1 google.com
# Expected: valid answer via Pi-hole -> Unbound

sudo systemctl status pihole-FTL unbound
# Expected: both active (running)
```

## 9. Verify DNS chain

```bash
# Test Pi-hole (port 53)
dig @YOUR_TAILSCALE_IP google.com

# Test Unbound directly (port 5335)
dig @127.0.0.1 -p 5335 google.com +dnssec

# Confirm DNSSEC validation
dig @127.0.0.1 -p 5335 dnssec-failed.org
# Expected: SERVFAIL (DNSSEC validation failure -- correct behavior)
```

## Troubleshooting

### Unbound fails to start -- permission denied on port 5335

```bash
sudo semanage port -l | grep 5335
# If missing, re-run: sudo bash selinux/label-dns-port.sh
```

### Pi-hole FTL crashes at start

Check that georou/pihole-selinux module is loaded:

```bash
sudo semodule -l | grep -i pihole
```

If not, install it and restart:

```bash
sudo systemctl restart pihole-FTL
```

### resolv.conf reverted

resolv.conf is set immutable by harden.sh. If something reverted it:

```bash
sudo chattr +i /etc/resolv.conf
```

Ensure systemd-resolved is still masked:

```bash
systemctl status systemd-resolved
# Expected: masked
```

### AVC denials after relabel

```bash
sudo ausearch -m avc -ts recent | audit2allow
```

If denials relate to Pi-hole or Unbound, check the georou/pihole-selinux module version
and the `.te` files in `selinux/` in this repo.
