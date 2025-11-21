FROM anchore/grype:v0.103.0-nonroot as grype

FROM debian:trixie-slim AS resource

COPY --from=grype /grype /usr/local/bin/grype

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mmdebstrap jq bash ca-certificates gnupg curl fakechroot fakeroot unzip zip \
    && \
    rm -rf /var/lib/apt/lists/*

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
