ARG base_image=quay.io/buildah/stable:latest

FROM ghcr.io/sigstore/cosign/cosign:v2.6.1 as cosign-bin

FROM ${base_image} AS resource

# Cosign is required to install grype with the -v option (verify signature).
COPY --from=cosign-bin /ko-app/cosign /usr/local/bin/cosign

RUN dnf -y install jq bash && dnf clean all && rm -rf /var/cache/dnf

RUN curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin -v

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
