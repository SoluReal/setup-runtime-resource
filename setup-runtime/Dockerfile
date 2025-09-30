ARG base_image=quay.io/buildah/stable:latest

FROM ${base_image} AS resource

RUN dnf -y install jq bash && dnf clean all && rm -rf /var/cache/dnf

COPY assets /opt/resource/
RUN chmod +x /opt/resource/*
