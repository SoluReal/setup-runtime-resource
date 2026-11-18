# The base rootfs, built at image build so `in` only has to add the dependencies.
FROM debian:trixie-slim AS base

# renovate: datasource=github-tags depName=ilikenwf/apt-fast
ARG APT_FAST_VERSION=v1.7.6

COPY base/apt-fast.conf /etc/apt-fast.conf
COPY base/apt.conf /etc/apt/apt.conf.d/90setup-runtime
# docker-clean deletes downloaded debs after every dpkg run, before apt-fast's install can use them.
# aria2 and lockfile-progs only serve apt-fast, so `in` autoremoves them with apt.
RUN rm /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates aria2 lockfile-progs && \
    apt-mark auto aria2 lockfile-progs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
ADD --chmod=755 https://raw.githubusercontent.com/ilikenwf/apt-fast/${APT_FAST_VERSION}/apt-fast /usr/local/sbin/apt-fast

FROM cgr.dev/chainguard/wolfi-base AS tar
RUN --mount=type=bind,from=base,target=/base apk add --no-cache gnutar && \
    tar -C /base --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* -cf /base.tar .

FROM cgr.dev/chainguard/wolfi-base AS resource

# The runtime installers run rootfs binaries on this host, so it needs glibc and libstdc++/libatomic.
RUN apk add --no-cache bash jq curl unzip zip libatomic libstdc++ coreutils gnutar findutils grep sed gzip

COPY assets /opt/resource/
RUN chmod +x /opt/resource/* /opt/resource/hooks/*
# Last, so no chmod layer stores the tar twice.
COPY --from=tar /base.tar /opt/resource/base.tar
