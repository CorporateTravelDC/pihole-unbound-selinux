#!/bin/bash
# scripts/unbound-cache-warmup.sh
# Pre-populates Unbound's cache right after boot so the first real client
# queries (nginx vhosts, cloudflared, chrony, tailscaled) don't pay for a
# cold recursive walk from the root. Queries Unbound directly on 127.0.0.1
# :5335, bypassing Pi-hole -- Pi-hole's own cache miss is sub-ms local
# regardless; the slow part is Unbound's recursion, which this avoids.
#
# Run by systemd/unbound-cache-warmup.service, after the anchor-refresh
# unit's restart (see that unit for why: it restarts Unbound once early in
# boot, which would otherwise wipe anything warmed before it).
#
# ASCII output only

set -uo pipefail

RESOLVER="127.0.0.1"
PORT="5335"

# Cloudflare Tunnel vhosts (cloudflared/config.yml) -- these are what the
# public-facing tunnel and internal nginx reverse proxy resolve on every
# request.
DOMAINS=(
    csexecutiveservices.com
    www.csexecutiveservices.com
    dispatch.csexecutiveservices.com
    ops.csexecutiveservices.com
    openwebui.csexecutiveservices.com
    ollama.csexecutiveservices.com
    adsb.csexecutiveservices.com
    acars.csexecutiveservices.com
    ntfy.csexecutiveservices.com
    pihole.csexecutiveservices.com
    # chrony (/etc/chrony.conf: pool 2.fedora.pool.ntp.org)
    2.fedora.pool.ntp.org
    # tailscaled control plane
    controlplane.tailscale.com
)

for d in "${DOMAINS[@]}"; do
    dig @"${RESOLVER}" -p "${PORT}" "${d}" A +short +time=3 +tries=1 >/dev/null 2>&1
done

echo "[OK] unbound-cache-warmup: queried ${#DOMAINS[@]} domains"
