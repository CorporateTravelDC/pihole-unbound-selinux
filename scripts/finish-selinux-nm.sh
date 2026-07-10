set -uo pipefail
cd ~/pihole-unbound-selinux || { echo "[FAIL] repo dir not found at ~/pihole-unbound-selinux"; exit 1; }

echo "== NM WiFi routing =="
WIFI_PROFILE=$(nmcli -t -f NAME,TYPE connection show | grep -E ':(wifi|802-11-wireless)$' | head -1 | cut -d: -f1)
echo "detected profile: ${WIFI_PROFILE:-<none found>}"
if [ -n "${WIFI_PROFILE:-}" ]; then
  sudo nmcli connection modify "$WIFI_PROFILE" ipv4.ignore-auto-routes no ipv4.route-metric 200
  echo "after: $(nmcli -g ipv4.ignore-auto-routes,ipv4.route-metric connection show "$WIFI_PROFILE" 2>/dev/null)"
fi

echo "== tailscaled_t / module state =="
sudo seinfo -t 2>/dev/null | grep tailscaled_t && echo "[INFO] upstream tailscaled_t exists" || echo "[INFO] no upstream tailscaled_t"
sudo semodule -l | grep -i pihole && echo "[INFO] pihole module present" || echo "[INFO] no pihole module"
sudo semodule -l | grep -i tailscale && echo "[INFO] tailscale module already loaded" || echo "[INFO] no tailscale module yet"

echo "== running repo's official policy apply (idempotent) =="
sudo bash selinux/apply-selinux-policy.sh

echo "== installing tailscale-ssh-login.te (embedded, no external file needed) =="
if sudo semodule -l | grep -q "^tailscale-ssh-login$"; then
  echo "[OK] already installed"
else
  WORKDIR=$(mktemp -d)
  cat > "$WORKDIR/tailscale-ssh-login.te" <<'TEFILE'
module tailscale-ssh-login 1.0;

require {
	type unconfined_service_t;
	type unconfined_t;
	class process transition;
}

allow unconfined_service_t unconfined_t:process transition;
TEFILE
  sudo dnf install -y policycoreutils-python-utils checkpolicy
  checkmodule -M -m -o "$WORKDIR/tailscale-ssh-login.mod" "$WORKDIR/tailscale-ssh-login.te"
  semodule_package -o "$WORKDIR/tailscale-ssh-login.pp" -m "$WORKDIR/tailscale-ssh-login.mod"
  sudo semodule -i "$WORKDIR/tailscale-ssh-login.pp"
  rm -rf "$WORKDIR"
fi

echo "== final module list =="
sudo semodule -l | grep -iE "pihole|tailscale"

echo "== port label check =="
sudo semanage port -l | grep 5335

echo "== DONE. If everything above looks sane, proceed with:"
echo "   sudo setenforce 1 && sudo touch /.autorelabel && sudo reboot"
