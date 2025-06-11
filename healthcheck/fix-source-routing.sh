#!/bin/bash

set -e

# ensure CloudflareWARP interface exists
if ! ip link show CloudflareWARP >/dev/null 2>&1; then
    echo "[fix-source-routing] CloudflareWARP not started, skip."
    exit 0
fi

# also ensure packets sourced from our non-WARP interfaces use table main
addresses=$(ip --json address | jq -r '
  .[] |
  select((.ifname != "lo") and (.ifname != "CloudflareWARP")) |
  .addr_info[] |
  select(.family == "inet") |
  "\(.local)/\(.prefixlen)"')

for addr in $addresses; do
  if ! ip rule list | grep -q "from $addr lookup main"; then
    echo "[fix-source-routing] Adding source routing rule for $addr."
    sudo ip rule add from $addr lookup main priority 10
  fi
done
