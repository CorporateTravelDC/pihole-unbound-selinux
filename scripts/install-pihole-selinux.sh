set -uo pipefail
cd ~
if [ -d pihole-selinux ]; then
  cd pihole-selinux && git pull
else
  git clone https://github.com/georou/pihole-selinux.git
  cd pihole-selinux
fi

echo "== repo contents =="
ls -la

echo "== README (first 60 lines) =="
cat README.md 2>/dev/null | head -60
