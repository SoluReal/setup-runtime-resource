FROM debian:trixie-slim AS resource

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mmdebstrap jq bash ca-certificates gnupg curl fakechroot fakeroot unzip zip \
    && \
    rm -rf /var/lib/apt/lists/*

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
