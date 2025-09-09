FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq bash coreutils findutils \
    && rm -rf /var/lib/apt/lists/*

# 按架构下载 azcopy（buildx 会注入 TARGETARCH）
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) AZ_URL="https://aka.ms/downloadazcopy-v10-linux" ;; \
      arm64) AZ_URL="https://aka.ms/downloadazcopy-v10-linux-arm64" ;; \
      *) echo "unsupported arch: $TARGETARCH"; exit 1 ;; \
    esac; \
    curl -fsSL "$AZ_URL" -o /tmp/azcopy.tgz; \
    mkdir -p /tmp/azcopy && tar -xzf /tmp/azcopy.tgz -C /tmp/azcopy --strip-components=1; \
    mv /tmp/azcopy/azcopy /usr/local/bin/azcopy; \
    chmod +x /usr/local/bin/azcopy; \
    rm -rf /tmp/azcopy /tmp/azcopy.tgz; \
    azcopy --version

WORKDIR /work
COPY fetch-blob.sh /usr/local/bin/fetch-blob
RUN chmod +x /usr/local/bin/fetch-blob

ENTRYPOINT ["/usr/local/bin/fetch-blob"]