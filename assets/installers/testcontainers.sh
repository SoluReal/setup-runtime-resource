#!/bin/bash

function testcontainers_get_dependencies() {
  local shared="curl gawk iproute2 jq shadow"

  if [ "$testcontainers_enabled" = "true" ]; then
    if [ "$testcontainers_rootless" = "true" ]; then
      # No podman-docker in Wolfi: the hook links `docker` to podman. slirp4netns is the rootless
      # network backend, as passt is not packaged.
      echo "$shared podman fuse-overlayfs slirp4netns just-newuidmap-newgidmap nftables"
    else
      echo "$shared mount dockerd docker-cli docker-cli-buildx containerd"
    fi
  else
    echo ""
  fi
}
