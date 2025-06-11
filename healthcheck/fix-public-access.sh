#!/bin/bash

# exit when any command fails
set -e

interfaces=$(ip --json address | jq -r '
    .[] |
    select(.ifname != "lo") |
    .ifname
    ')

# if CloudflareWARP not started, abort
if [[ ! "$interfaces" =~ "CloudflareWARP" ]]; then
    echo "[fix-public-access] CloudflareWARP not started, skip."
    exit 0
fi

# ensure table exists
if ! sudo nft list table inet cloudflare-warp >/dev/null 2>&1; then
    echo "[fix-public-access] WARNING: Table cloudflare-warp not found, skip."
    exit 0
fi

# ensure port 1080 is allowed in input chain
if ! sudo nft list table inet cloudflare-warp | grep -q 'iifname "eth0" tcp dport 1080 accept'; then
    echo "[fix-public-access] Allowing TCP port 1080 from eth0"
    sudo nft add rule inet cloudflare-warp input iifname "eth0" tcp dport 1080 accept
fi
if ! sudo nft list table inet cloudflare-warp | grep -q 'iifname "eth0" udp dport 1080 accept'; then
    echo "[fix-public-access] Allowing UDP port 1080 from eth0"
    sudo nft add rule inet cloudflare-warp input iifname "eth0" udp dport 1080 accept
fi

# ensure responses can go out via eth0
if ! sudo nft list table inet cloudflare-warp | grep -q 'oifname "eth0" tcp sport 1080 accept'; then
    echo "[fix-public-access] Allowing TCP responses on port 1080 to eth0"
    sudo nft add rule inet cloudflare-warp output oifname "eth0" tcp sport 1080 accept
fi
if ! sudo nft list table inet cloudflare-warp | grep -q 'oifname "eth0" udp sport 1080 accept'; then
    echo "[fix-public-access] Allowing UDP responses on port 1080 to eth0"
    sudo nft add rule inet cloudflare-warp output oifname "eth0" udp sport 1080 accept
fi

# also ensure packets sourced from non-WARP interfaces use table main
addresses=$(ip --json address | jq -r '
  .[] |
  select((.ifname != "lo") and (.ifname != "CloudflareWARP")) |
  .addr_info[] |
  select(.family == "inet") |
  "\(.local)/\(.prefixlen)"')

for addr in $addresses; do
  if ! ip rule list | grep -q "from $addr lookup main"; then
    echo "[fix-public-access] Adding source routing rule for $addr."
    sudo ip rule add from $addr lookup main priority 10
  fi
done
