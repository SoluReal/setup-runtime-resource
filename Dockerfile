ARG base_image=quay.io/buildah/stable:latest

FROM anchore/grype:v0.103.0-nonroot as grype

FROM ${base_image} AS resource

COPY --from=grype /grype /usr/local/bin/grype

RUN dnf -y install jq bash && dnf clean all && rm -rf /var/cache/dnf

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
