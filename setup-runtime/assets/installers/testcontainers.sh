#!/bin/bash

function testcontainers_get_dependencies() {
  local config="${1}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [ "$testcontainers" = "true" ]; then
    echo "jq curl iptables uidmap slirp4netns kmod iproute2 net-tools fuse-overlayfs util-linux"
  else
    echo ""
  fi
}

function testcontainers_install() {
  local ctr="${1}"
  local config="${2}"
  testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [[ "$testcontainers" = "true" ]]; then
    info "installing docker..."
    log_on_error buildah copy "$ctr" "$ROOT_DIR/includes/docker-lib.sh" "$RUNTIME_DIR/docker-lib.sh"
    log_on_error buildah copy "$ctr" "$ROOT_DIR/includes/docker-cache.sh" "$RUNTIME_DIR/docker-cache.sh"
    log_on_error buildah run "$ctr" -- bash -lc "
      set -e
      curl -sSL https://get.docker.com/ | bash
      echo 'source $RUNTIME_DIR/docker-lib.sh' >> /root/.bashrc
      echo 'source $RUNTIME_DIR/docker-cache.sh' >> /root/.bashrc
    "
    info "docker installed"
  fi
}

function testcontainers_finalize() {
    local ctr="${1}"
    local config="${2}"
    testcontainers=$(jq -r '(.source.testcontainers.enabled // "")' <<< "$config")

  if [[ "$testcontainers" = "true" ]]; then
    log_on_error buildah run "$ctr" -- bash -lc "
    echo 'start_docker' >> /root/.bashrc
    echo 'await_docker' >> /root/.bashrc
    echo 'trap teardown_docker EXIT' >> /root/.bashrc
    echo 'docker_load_cache' >> /root/.bashrc
    echo 'START_TIME=\$(date +%s)' >> /root/.bashrc
    echo 'unset BASH_ENV' >> /root/.bashrc
    echo 'unset ENV' >> /root/.bashrc
    "
  fi
}
