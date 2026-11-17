# The essential rootfs plus apt and apt-fast, bootstrapped once at image build so `in` skips it.
# fakechroot mode is the one that works inside `docker build` (no user namespaces, no mounts).
FROM debian:trixie-slim AS base

# renovate: datasource=github-tags depName=ilikenwf/apt-fast
ARG APT_FAST_VERSION=v1.7.6

RUN apt-get update && \
    apt-get install -y --no-install-recommends mmdebstrap fakechroot fakeroot ca-certificates curl zstd && \
    curl -fsSL "https://raw.githubusercontent.com/ilikenwf/apt-fast/${APT_FAST_VERSION}/apt-fast" -o /apt-fast && \
    rm -rf /var/lib/apt/lists/*

COPY base /base
RUN mmdebstrap --variant=essential --mode=fakechroot \
      --include=apt,aria2,lockfile-progs,ca-certificates \
      --aptopt=/base/apt.conf --dpkgopt=/base/dpkg.cfg \
      --essential-hook='/base/hook.sh essential "$1"' \
      --customize-hook='/base/hook.sh customize "$1"' \
      --customize-hook='copy-in /apt-fast /usr/local/sbin' \
      --customize-hook='copy-in /base/apt-fast.conf /etc' \
      --customize-hook='copy-in /base/apt.conf /etc/apt/apt.conf.d' \
      --customize-hook='copy-in /base/dpkg.cfg /etc/dpkg/dpkg.cfg.d' \
      --skip=output/dev --format=tar trixie - | zstd -19 -T0 -o /base.tar.zst

FROM debian:trixie-slim AS resource

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mmdebstrap jq bash ca-certificates gnupg curl fakechroot fakeroot unzip zip libatomic1 zstd \
    && \
    rm -rf /var/lib/apt/lists/*

COPY assets /opt/resource/
RUN chmod +x /opt/resource/* /opt/resource/hooks/*
# Last, so no chmod layer stores the tar twice.
COPY --from=base /base.tar.zst /opt/resource/base.tar.zst
