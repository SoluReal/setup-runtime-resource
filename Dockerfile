# The base rootfs, built at image build so `in` only has to add the dependencies.
FROM cgr.dev/chainguard/wolfi-base AS base

RUN apk add --no-cache zstd gnutar
RUN apk add --root /base --initdb --no-cache \
      --keys-dir /etc/apk/keys --repositories-file /etc/apk/repositories \
      wolfi-baselayout busybox bash ca-certificates-bundle glibc \
      coreutils gnutar grep sed findutils gzip && \
    mkdir -p /base/etc/apk/keys && cp /etc/apk/repositories /base/etc/apk/ && cp /etc/apk/keys/* /base/etc/apk/keys/ && \
    rm -rf /base/var/cache/apk /base/dev/* && \
    # Hooks install tools into /usr/local like on any FHS distro; Wolfi's layout leaves it out.
    mkdir -p /base/usr/local/bin /base/usr/local/sbin /base/usr/local/lib /base/usr/local/share && \
    tar -C /base -c . | zstd -19 -T0 -o /base.tar.zst

FROM cgr.dev/chainguard/wolfi-base AS resource

# The runtime installers run rootfs binaries on this host, so it needs the same glibc and libstdc++/libatomic.
RUN apk add --no-cache bash jq curl unzip zip zstd libatomic libstdc++ coreutils gnutar findutils grep sed gzip

COPY assets /opt/resource/
RUN chmod +x /opt/resource/* /opt/resource/hooks/*
# Last, so no chmod layer stores the tar twice.
COPY --from=base /base.tar.zst /opt/resource/base.tar.zst
