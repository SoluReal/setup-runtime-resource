FROM debian:trixie-slim AS resource

# Skip docs/man/locale for packages installed in this image - nothing here reads them.
RUN echo 'path-exclude /usr/share/doc/*' > /etc/dpkg/dpkg.cfg.d/01_nodoc && \
    echo 'path-exclude /usr/share/man/*' >> /etc/dpkg/dpkg.cfg.d/01_nodoc && \
    echo 'path-exclude /usr/share/locale/*' >> /etc/dpkg/dpkg.cfg.d/01_nodoc

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      mmdebstrap jq bash ca-certificates gnupg curl fakechroot fakeroot unzip zip \
    && \
    rm -rf /var/lib/apt/lists/*

COPY assets /opt/resource/
RUN chmod +x /opt/resource/* /opt/resource/hooks/*
