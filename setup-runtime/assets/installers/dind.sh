#!/bin/bash

function dind_get_dependencies() {
  local pkg_mgr="${1}"
  local config="${2}"
  dind=$(jq -r '(.source.docker.enabled // "")' <<< "$config")

  if [ "$dind" = "true" ]; then
    case "$pkg_mgr" in
      apk)
        echo "jq curl iptables slirp4netns" ;;
      apt)
        echo "jq curl iptables uidmap slirp4netns kmod iproute2 net-tools fuse-overlayfs util-linux  " ;;
      dnf|yum)
        echo "jq curl iptables slirp4netns" ;;
      *)
        echo "" ;;
    esac
  else
    echo ""
  fi
}

function dind_install() {
  local ctr="${1}"
  local config="${2}"
  dind=$(jq -r '(.source.docker.enabled // "")' <<< "$config")

  if [[ "$dind" = "true" ]]; then
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
