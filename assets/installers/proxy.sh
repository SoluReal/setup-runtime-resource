#!/bin/bash

# Same path on the build host, in the rootfs and at task time, so NODE_EXTRA_CA_CERTS holds in all three.
export PROXY_CA_FILE="/usr/local/share/ca-certificates/setup-runtime-proxy.crt"
export SYSTEM_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

# Proxies this build's downloads and exports the proxy to tasks; the CA is trusted on this host.
function proxy_configure() {
  if [[ -n "$proxy_url" ]]; then
    if ! [[ "$proxy_url" =~ ^http://([A-Za-z0-9.-]+):([0-9]+)/?$ ]]; then
      error "proxy.url must look like http://host:port, got '$proxy_url'"
      exit 1
    fi
    local host="${BASH_REMATCH[1]}" port="${BASH_REMATCH[2]}"
    # Values end up unescaped in metadata.json's env list.
    if ! [[ "$proxy_no_proxy" =~ ^[][A-Za-z0-9.,:*/_-]*$ ]]; then
      error "proxy.no_proxy must be a comma-separated list of hosts, got '$proxy_no_proxy'"
      exit 1
    fi

    info "Using proxy: $proxy_url"
    local name
    for name in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
      export "$name=$proxy_url"
      add_task_env_var "$name=$proxy_url"
    done
    for name in no_proxy NO_PROXY; do
      export "$name=$proxy_no_proxy"
      add_task_env_var "$name=$proxy_no_proxy"
    done
    # JVMs ignore *_proxy; gradle.sh and maven.sh configure them from these. Java wants `|` and `*.domain`.
    local non_proxy_hosts
    non_proxy_hosts="$(tr ',' '\n' <<< "$proxy_no_proxy" | sed 's/^\./*./' | paste -sd '|' -)"
    add_task_env_var "SETUP_RUNTIME_PROXY_HOST=$host"
    add_task_env_var "SETUP_RUNTIME_PROXY_PORT=$port"
    add_task_env_var "SETUP_RUNTIME_NON_PROXY_HOSTS=$non_proxy_hosts"
  fi

  if [[ -n "$proxy_ca_certificate" ]]; then
    mkdir -p "$(dirname "$PROXY_CA_FILE")"
    printf '%s\n' "$proxy_ca_certificate" > "$PROXY_CA_FILE"
    if ! openssl x509 -noout -in "$PROXY_CA_FILE"; then
      error "proxy.ca_certificate is not a PEM certificate"
      exit 1
    fi
    log_on_error update-ca-certificates
    export NODE_EXTRA_CA_CERTS="$PROXY_CA_FILE"

    add_task_env_var "SSL_CERT_FILE=$SYSTEM_CA_BUNDLE"
    add_task_env_var "NODE_EXTRA_CA_CERTS=$PROXY_CA_FILE"
    add_task_env_var "REQUESTS_CA_BUNDLE=$SYSTEM_CA_BUNDLE"
    add_task_env_var "PIP_CERT=$SYSTEM_CA_BUNDLE"
  fi
}

# Adds the CA to the rootfs bundle (its dpkg database is gone, so no update-ca-certificates) and every JDK's cacerts.
function proxy_trust_rootfs() {
  local chroot_dir="$1"
  [[ -n "$proxy_ca_certificate" ]] || return 0

  mkdir -p "$chroot_dir$(dirname "$PROXY_CA_FILE")"
  cp "$PROXY_CA_FILE" "$chroot_dir$PROXY_CA_FILE"
  cat "$PROXY_CA_FILE" >> "$chroot_dir$SYSTEM_CA_BUNDLE"

  local java_dir="$chroot_dir$SDKMAN_RUNTIME_DIR/candidates/java" cacerts jdk
  [[ -d "$java_dir" ]] || return 0
  # find skips the `current` symlink, so each JDK is imported once.
  while IFS= read -r cacerts; do
    jdk="$java_dir/$(cut -d/ -f1 <<< "${cacerts#"$java_dir"/}")"
    log_on_error "$jdk/bin/keytool" -importcert -noprompt -alias setup-runtime-proxy \
      -keystore "$cacerts" -storepass changeit -file "$PROXY_CA_FILE"
  done < <(find "$java_dir" -path '*/lib/security/cacerts' -type f)
}
