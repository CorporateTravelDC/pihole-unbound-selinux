#!/usr/bin/env bash
# selinux/label-dns-port.sh
# Label port 5335 as dns_port_t so Unbound can bind under SELinux enforcing.
# Fedora 44 -- all architectures
#
# Run as root before starting Unbound.
# Idempotent -- safe to re-run.
#
# Usage:
#   sudo bash selinux/label-dns-port.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "[FAIL] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

run() {
    if [[ "$DRY_RUN" == true ]]; then echo "[DRY]  $*"; else "$@"; fi
}

if [[ "$EUID" -ne 0 ]]; then
    echo "[FAIL] Must be run as root." >&2; exit 1
fi

command -v semanage &>/dev/null || {
    echo "[INFO] Installing policycoreutils-python-utils..."
    run dnf install -y policycoreutils-python-utils
}

echo "=== label-dns-port.sh ==="
echo "[INFO] Dry run: ${DRY_RUN}"

for proto in tcp udp; do
    if semanage port -l | grep -q "dns_port_t.*${proto}.*5335"; then
        echo "[OK]  5335/${proto} already labeled dns_port_t"
    else
        echo "[INFO] Labeling 5335/${proto} as dns_port_t"
        run semanage port -a -t dns_port_t -p "${proto}" 5335
        echo "[OK]  5335/${proto} labeled"
    fi
done

echo ""
echo "[OK]  Done. Verify with: semanage port -l | grep 5335"
