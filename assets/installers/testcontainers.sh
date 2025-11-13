#!/bin/bash

function testcontainers_get_dependencies() {
  local config="${1}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [ "$testcontainers" = "true" ]; then
    echo "ca-certificates curl ca-certificates"
  else
    echo ""
  fi
}

function testcontainers_install() {
  local ctr="${1}"
  local config="${2}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [[ "$testcontainers" = "true" ]]; then
    info "Setting up testcontainers"

    log_on_error chroot_exec "$ctr" "
      set -e
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc

      # Add the repository to Apt sources:
      tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: \$(. /etc/os-release && echo \"\$VERSION_CODENAME\")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
      apt-get update
      apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io iproute2 jq gzip
      mkdir -p $RUNTIME_DIR/docker
      "

    log_on_error rootfs_copy "$ctr" "$ROOT_DIR/includes/docker-functions.sh" "$RUNTIME_DIR/docker/docker-functions.sh"
    log_on_error rootfs_copy "$ctr" "$ROOT_DIR/includes/docker-cache.sh" "$RUNTIME_DIR/docker/docker-cache.sh"
    log_on_error rootfs_copy "$ctr" "$ROOT_DIR/includes/docker.sh" "$RUNTIME_DIR/docker/docker.sh"

    add_metadata "testcontainers" "true"
    info "Testcontainers setup completed (docker installed)..."
  fi
}

function finalize_testcontainers() {
  local ctr="${1}"
  local config="${2}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [[ "$testcontainers" = "true" ]]; then
    log_on_error chroot_exec "$ctr" "
      echo 'source $RUNTIME_DIR/docker/docker.sh' >> /root/.bashrc
    "
  fi
}
