FROM debian:trixie-slim AS resource

# renovate: datasource=github-tags depName=ilikenwf/apt-fast
ARG APT_FAST_VERSION=v1.7.6

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mmdebstrap jq bash ca-certificates gnupg curl fakechroot fakeroot unzip zip libatomic1 aria2 lockfile-progs \
    && \
    curl -fsSL "https://raw.githubusercontent.com/ilikenwf/apt-fast/${APT_FAST_VERSION}/apt-fast" -o /usr/local/sbin/apt-fast && \
    chmod +x /usr/local/sbin/apt-fast && \
    rm -rf /var/lib/apt/lists/*

COPY apt-fast.conf /etc/apt-fast.conf
COPY assets /opt/resource/
RUN chmod +x /opt/resource/* /opt/resource/hooks/*
