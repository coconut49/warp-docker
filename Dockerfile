ARG SSSERVER_IMAGE=ghcr.io/shadowsocks/ssserver-rust:latest

FROM ubuntu:22.04 AS base

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"



ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc zstd gettext-base && \
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && apt-get autoremove -y && \

    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 ./healthcheck /healthcheck

RUN mkdir -p /home/warp/.local/share/warp && echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV SSR_ARGS="--config /etc/shadowsocks-rust/config.json"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=
ENV SHADOWSOCKS_METHOD=2022-blake3-aes-128-gcm
ENV SHADOWSOCKS_PASSWORD=

FROM ${SSSERVER_IMAGE} AS ssserver

FROM base
COPY --from=ssserver /usr/bin/ssserver /usr/bin/ssserver
COPY --from=ssserver /etc/shadowsocks-rust /etc/shadowsocks-rust
COPY ./config/shadowsocks-rust.json /etc/shadowsocks-rust/config.json

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
