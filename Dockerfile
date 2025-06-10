FROM ubuntu:22.04

ARG WARP_VERSION
ARG SSGO_VERSION
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL SSGO_VERSION=${SSGO_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck
COPY ./config/shadowsocks-go.json /etc/shadowsocks-go/config.json

# install dependencies
RUN case ${TARGETPLATFORM} in \
      "linux/amd64")   export ARCH="amd64" ;; \
      "linux/arm64")   export ARCH="armv8" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    echo "Building for ${TARGETPLATFORM} with shadowsocks-go ${SSGO_VERSION}" &&\
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc zstd && \
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && \
    apt-get autoremove -y && \
    case ${TARGETPLATFORM} in \
      "linux/amd64") FILE_ARCH="x86-64-v3" ;; \
      "linux/arm64") FILE_ARCH="arm64" ;; \
    esac && \
    FILE_NAME="shadowsocks-go-v${SSGO_VERSION}-linux-${FILE_ARCH}.tar.zst" && \
    echo "File name: ${FILE_NAME}" && \
    curl -LO https://github.com/database64128/shadowsocks-go/releases/download/v${SSGO_VERSION}/${FILE_NAME} && \
    tar --use-compress-program=unzstd -xf ${FILE_NAME} -C /usr/bin/ shadowsocks-go && \
    chmod +x /usr/bin/shadowsocks-go && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV SSGO_ARGS="--confPath /etc/shadowsocks-go/config.json"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
