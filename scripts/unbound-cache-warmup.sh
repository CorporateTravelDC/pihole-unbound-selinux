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
    example.com
    www.example.com
    dispatch.example.com
    ops.example.com
    openwebui.example.com
    ollama.example.com
    adsb.example.com
    acars.example.com
    ntfy.example.com
    pihole.example.com
    # chrony (/etc/chrony.conf: pool 2.fedora.pool.ntp.org)
    2.fedora.pool.ntp.org
    # tailscaled control plane
    controlplane.tailscale.com

    # 2026-08-05: external operational data-source domains -- the dispatch
    # platform's own poller/fetchers/skills depend on these for real work
    # (weather, FAA feeds, ACARS/airframes aggregator, Amtrak, AAM trade
    # press), but until now nothing ever warmed them, so the FIRST poll
    # after a cold cache (boot, or just an expired/never-cached entry) paid
    # the full recursive-walk cost -- this is what was actually timing out
    # in direct dig tests. Extracted from real fetcher/skill source
    # (grep for http(s):// across src/poller/fetchers, src/poller/skills,
    # src/acars_watcher, src/shared/rss_catalog.py), not guessed. Scoped to
    # the operational/data-feed domains that actually gate dispatch
    # functionality -- NOT the long tail of general travel/aviation trade-
    # press RSS blogs (aviationsourcenews.com, crankyflier.com, etc.) also
    # present in rss_catalog.py, which are lower-value background churn,
    # not latency-sensitive.
    aviationweather.gov
    api.weather.gov
    notams.aim.faa.gov
    tfr.faa.gov
    nasstatus.faa.gov
    registry.faa.gov
    www.faa.gov
    www.fly.faa.gov
    api.faa.gov
    api.amtraker.com
    api.airframes.io
    api.jumpseat.acarsdrama.com
    opensky-network.org
    s3.opensky-network.org
    urbanairmobilitynews.com
    uasweekly.com
    # EUROCONTROL/JASDAT -- awaiting_credentials as of this writing, but
    # cheap to warm now so DNS isn't also cold on the day credentials land.
    www.eurocontrol.int
    www.b2b.opsnetwork.eurocontrol.int
    www.jasdat.go.jp
)

for d in "${DOMAINS[@]}"; do
    dig @"${RESOLVER}" -p "${PORT}" "${d}" A +short +time=3 +tries=1 >/dev/null 2>&1
done

echo "[OK] unbound-cache-warmup: queried ${#DOMAINS[@]} domains"
