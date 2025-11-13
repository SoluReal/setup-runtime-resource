FROM anchore/grype:v0.103.0-nonroot as grype

FROM debian:stable-slim AS resource

COPY --from=grype /grype /usr/local/bin/grype

# Install required tooling: mmdebstrap for bootstrapping rootfs, rsync for copying, jq, bash, ca-certificates, gnupg, curl
RUN apt-get update && \
    apt-get install -y --no-install-recommends mmdebstrap rsync jq bash ca-certificates gnupg curl && \
    rm -rf /var/lib/apt/lists/*

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
