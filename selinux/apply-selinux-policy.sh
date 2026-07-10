#!/usr/bin/env bash
# selinux/apply-selinux-policy.sh
# SELinux policy compilation + directory labeling for pihole-unbound-selinux stack
# Fedora 44 -- all architectures
#
# Run as root before starting Pi-hole or Unbound.
# Idempotent -- safe to re-run after package updates or migrations.
#
# Prerequisites:
#   - georou/pihole-selinux loaded (https://github.com/georou/pihole-selinux)
#   - policycoreutils-python-utils, checkpolicy installed
#
# Usage:
#   sudo bash selinux/apply-selinux-policy.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "[FAIL] Must be run as root." >&2; exit 1
    fi
}

check_deps() {
    local missing=()
    for cmd in semodule checkmodule semanage restorecon semodule_package; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[INFO] Installing missing tools: ${missing[*]}"
        run dnf install -y policycoreutils-python-utils checkpolicy
    fi
}

build_and_load_module() {
    local name="$1"
    local te_src="${SCRIPT_DIR}/${name}.te"
    [[ -f "$te_src" ]] || { echo "[SKIP] No .te file for ${name} -- skipping"; return 0; }

    local work_dir
    work_dir="$(mktemp -d /tmp/selinux-${name}-XXXXXX)"
    trap "rm -rf ${work_dir}" RETURN

    cp "${te_src}" "${work_dir}/${name}.te"
    echo "[INFO] Compiling: ${name}"
    run checkmodule -M -m -o "${work_dir}/${name}.mod" "${work_dir}/${name}.te"
    run semodule_package -o "${work_dir}/${name}.pp" -m "${work_dir}/${name}.mod"

    if semodule -l 2>/dev/null | grep -q "^${name}$"; then
        run semodule -u "${work_dir}/${name}.pp"
    else
        run semodule -i "${work_dir}/${name}.pp"
    fi
    echo "[OK]  ${name}"
}

require_root
check_deps

echo "=== pihole-unbound-selinux -- SELinux Policy Apply ==="
echo "[INFO] Dry run: ${DRY_RUN}"
echo ""

# ---------------------------------------------------------------------------
# Step 1 -- Tailscale policy
# ---------------------------------------------------------------------------
echo "--- Step 1: tailscaled policy ---"
if seinfo -t 2>/dev/null | grep -q "tailscaled_t"; then
    echo "[OK]  upstream tailscaled_t present"
    if semodule -l 2>/dev/null | grep -q "^corporatetraveldc-tailscaled$"; then
        run semodule -r corporatetraveldc-tailscaled
    fi
else
    if dnf info tailscale-selinux &>/dev/null 2>&1; then
        run dnf install -y tailscale-selinux
        run restorecon -v "$(command -v tailscaled 2>/dev/null || echo /usr/sbin/tailscaled)"
    else
        build_and_load_module "corporatetraveldc-tailscaled"
    fi
fi

# ---------------------------------------------------------------------------
# Step 2 -- TE modules
# ---------------------------------------------------------------------------
echo "--- Step 2: TE modules ---"
build_and_load_module "corporatetraveldc-logind-userns"
build_and_load_module "corporatetraveldc-virtqemud"
build_and_load_module "corporatetraveldc-pihole-local"
build_and_load_module "corporatetraveldc-tailscale-ssh-login"

# ---------------------------------------------------------------------------
# Step 3 -- Relabel Pi-hole and Unbound paths
# ---------------------------------------------------------------------------
echo "--- Step 3: restorecon on service paths ---"
for path in /etc/pihole /var/lib/pihole /etc/unbound /var/lib/unbound; do
    if [[ -d "$path" ]]; then
        run restorecon -Rv "$path"
        echo "[OK]  restorecon: $path"
    else
        echo "[SKIP] $path -- not present"
    fi
done

# ---------------------------------------------------------------------------
# Step 4 -- Check pihole-selinux module (georou) is loaded
# ---------------------------------------------------------------------------
echo "--- Step 4: pihole-selinux check ---"
if semodule -l 2>/dev/null | grep -qi "pihole"; then
    echo "[OK]  pihole SELinux module found"
else
    echo "[WARN] pihole SELinux module not found."
    echo "       Install from: https://github.com/georou/pihole-selinux"
    echo "       Then re-run this script."
fi

# ---------------------------------------------------------------------------
# Step 5 -- Port labels (DNS)
# Port 80 itself is covered by the httpd_t allow in corporatetraveldc-pihole-local.te
# (Step 2), since nginx fronts it directly. Port 5335 (Unbound) needs an
# explicit port label, done here. Pi-hole's own webserver port (8091) and
# every other nginx proxy_pass target are labeled by
# ctdi-dispatch-internal/selinux/label-nginx-backend-ports.sh -- that repo
# owns the vhost list (nginx/conf.d/), so it's the source of truth for which
# backend ports exist. Run that script too before re-enabling enforcing.
# ---------------------------------------------------------------------------
echo "--- Step 5: port labels ---"
run bash "${SCRIPT_DIR}/label-dns-port.sh" $([[ "$DRY_RUN" == true ]] && echo --dry-run)

# ---------------------------------------------------------------------------
# Step 6 -- Verify
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 6: Verify ---"
for mod in corporatetraveldc-logind-userns corporatetraveldc-pihole-local corporatetraveldc-tailscale-ssh-login; do
    semodule -l 2>/dev/null | grep -q "^${mod}$" \
        && echo "[OK]  module: ${mod}" \
        || echo "[WARN] module: ${mod} -- not loaded (may not apply to this host)"
done

echo ""
echo "[OK]  Apply complete."
echo "[INFO] Also run ctdi-dispatch-internal/selinux/apply-selinux-policy.sh on this"
echo "       host -- it fixes the dumpvdl2/readsb USB-SDR denials that hit the same"
echo "       enforcing boot. Both must be applied before re-enabling enforcing."
echo "[INFO] Then: sudo setenforce 1 && sudo touch /.autorelabel && sudo reboot"
