#!/bin/bash

# exit when any command fails
set -e

# Generate random password if not provided
if [ -z "$SHADOWSOCKS_PASSWORD" ]; then
    SHADOWSOCKS_PASSWORD=$(openssl rand -base64 16)
    echo "Generated random shadowsocks password: $SHADOWSOCKS_PASSWORD"
fi

# Set default method if not provided
if [ -z "$SHADOWSOCKS_METHOD" ]; then
    SHADOWSOCKS_METHOD="2022-blake3-aes-128-gcm"
    echo "Using default shadowsocks method: $SHADOWSOCKS_METHOD"
fi

# Replace environment variables in shadowsocks config
envsubst < /etc/shadowsocks-rust/config.json > /tmp/config.json.tmp
sudo mv /tmp/config.json.tmp /etc/shadowsocks-rust/config.json

# create a tun device if not exist
# allow passing device to ensure compatibility with Podman
if [ ! -e /dev/net/tun ]; then
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# start dbus
sudo mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    sudo rm /run/dbus/pid
fi
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# start the daemon
sudo warp-svc --accept-tos &

# wait for the daemon to start with retry mechanism
echo "Waiting for WARP daemon to start..."
for i in $(seq 1 30); do
    if warp-cli --accept-tos status >/dev/null 2>&1; then
        echo "WARP daemon started successfully!"
        break
    fi
    echo "Waiting for daemon... ($i/30)"
    sleep "$WARP_SLEEP"
done

# final check if daemon is ready
if ! warp-cli --accept-tos status >/dev/null 2>&1; then
    echo "ERROR: WARP daemon failed to start after 30 attempts"
    exit 1
fi

# if /var/lib/cloudflare-warp/reg.json not exists, setup new warp client
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    # if /var/lib/cloudflare-warp/mdm.xml not exists or REGISTER_WHEN_MDM_EXISTS not empty, register the warp client
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then
        warp-cli registration new && echo "Warp client registered!"
        # if a license key is provided, register the license
        if [ -n "$WARP_LICENSE_KEY" ]; then
            echo "License key found, registering license..."
            warp-cli registration license "$WARP_LICENSE_KEY" && echo "Warp license registered!"
        fi
    fi
    # connect to the warp server
    warp-cli --accept-tos connect
else
    echo "Warp client already registered, skip registration"
fi

# disable qlog if DEBUG_ENABLE_QLOG is empty
if [ -z "$DEBUG_ENABLE_QLOG" ]; then
    warp-cli --accept-tos debug qlog disable
else
    warp-cli --accept-tos debug qlog enable
fi

# if WARP_ENABLE_NAT is provided, enable NAT and forwarding
if [ -n "$WARP_ENABLE_NAT" ]; then
    # switch to warp mode
    echo "[NAT] Switching to warp mode..."
    warp-cli --accept-tos mode warp
    warp-cli --accept-tos connect

    # wait another seconds for the daemon to reconfigure
    sleep "$WARP_SLEEP"

    # enable NAT
    echo "[NAT] Enabling NAT..."
    sudo nft add table ip nat
    sudo nft add chain ip nat WARP_NAT { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade
    sudo nft add table ip mangle
    sudo nft add chain ip mangle forward { type filter hook forward priority mangle \; }
    sudo nft add rule ip mangle forward tcp flags syn tcp option maxseg size set rt mtu

    sudo nft add table ip6 nat
    sudo nft add chain ip6 nat WARP_NAT { type nat hook postrouting priority 100 \; }
    sudo nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade
    sudo nft add table ip6 mangle
    sudo nft add chain ip6 mangle forward { type filter hook forward priority mangle \; }
    sudo nft add rule ip6 mangle forward tcp flags syn tcp option maxseg size set rt mtu
fi

# start the proxy
ssserver $SSR_ARGS
