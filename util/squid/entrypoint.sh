#!/bin/bash
set -euo pipefail

CA_DIR=/etc/squid/ca
SSL_DB=/var/lib/squid/ssl_db

# The CA lives in a volume: a new one would change every test resource's source, so every rootfs is rebuilt.
if [[ ! -s "$CA_DIR/ca.pem" ]]; then
  echo "Generating the proxy CA in $CA_DIR"
  mkdir -p "$CA_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -subj "/CN=setup-runtime local caching proxy CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "$CA_DIR/ca.key" -out "$CA_DIR/ca.pem.tmp"
  # Written last: build-and-test.sh waits for ca.pem.
  mv "$CA_DIR/ca.pem.tmp" "$CA_DIR/ca.pem"
fi
chown root:proxy "$CA_DIR/ca.key"
chmod 640 "$CA_DIR/ca.key"

# Minted leaf certificates are cheap to recreate from the CA.
rm -rf "$SSL_DB"
mkdir -p "$(dirname "$SSL_DB")"
/usr/lib/squid/security_file_certgen -c -s "$SSL_DB" -M 16MB
chown -R proxy:proxy "$SSL_DB"

chown proxy:proxy /var/spool/squid
rm -f /run/squid.pid
# Squid opens its logs as the proxy user, and without a TTY stdout/stderr are root-owned pipes.
chmod 0666 /dev/stdout /dev/stderr
squid -N -z
exec squid -N -d 1
