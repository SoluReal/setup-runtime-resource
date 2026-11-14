FROM debian:trixie-slim

# squid-openssl, not squid: only the OpenSSL build has ssl-bump and security_file_certgen.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      squid-openssl ca-certificates openssl \
 && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY entrypoint.sh store-id.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/store-id.sh

EXPOSE 3128/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
